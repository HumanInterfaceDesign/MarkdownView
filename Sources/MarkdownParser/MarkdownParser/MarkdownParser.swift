//
//  MarkdownParser.swift
//  FlowMarkdownView
//
//  Created by 秋星桥 on 2025/1/2.
//

import cmark_gfm
import cmark_gfm_extensions
import Foundation

public class MarkdownParser {
    public init() {}

    func withParser<T>(_ block: (UnsafeMutablePointer<cmark_parser>) -> T) -> T {
        let parser = cmark_parser_new(CMARK_OPT_DEFAULT)!
        cmark_gfm_core_extensions_ensure_registered()
        let extensionNames = [
            "autolink",
            "strikethrough",
            "tagfilter",
            "tasklist",
            "table",
        ]
        for extensionName in extensionNames {
            guard let syntaxExtension = cmark_find_syntax_extension(extensionName) else {
                assertionFailure()
                continue
            }
            cmark_parser_attach_syntax_extension(parser, syntaxExtension)
        }
        defer { cmark_parser_free(parser) }
        return block(parser)
    }

    public struct ParseResult {
        public let document: [MarkdownBlockNode]
        public let mathContext: [Int: String]
    }

    public func parse(_ markdown: String) -> ParseResult {
        let math = MathContext(preprocessText: markdown)
        math.process()
        let markdown = math.indexedContent ?? markdown
        let nodes = withParser { parser in
            markdown.withCString { str in
                cmark_parser_feed(parser, str, strlen(str))
                return cmark_parser_finish(parser)
            }
        }
        var blocks = dumpBlocks(root: nodes)
        blocks = finalizeMathBlocks(blocks, mathContext: math)
        return .init(document: blocks, mathContext: math.contents)
    }

    public struct RootBlockRange {
        public let type: MarkdownNodeType
        public let startIndex: String.Index
        public let endIndex: String.Index
        public let outputBlockCount: Int
    }

    public struct IncrementalParseResult {
        public let stablePrefixBlockCount: Int
        public let tailResult: ParseResult
        public let blockRanges: [RootBlockRange]
    }

    public func parseBlockRange(_ markdown: String) -> [RootBlockRange] {
        var ranges = [RootBlockRange]()

        let root = withParser { parser in
            markdown.withCString { str in
                cmark_parser_feed(parser, str, strlen(str))
                return cmark_parser_finish(parser)
            }
        }
        guard let root else {
            assertionFailure()
            return ranges
        }

        assert(root.pointee.type == CMARK_NODE_DOCUMENT.rawValue)
        for block in root.children {
            let node = block.pointee

            let startLine = Int(node.start_line)
            let startColumn = Int(node.start_column)
            let endLine = Int(node.end_line)
            let endColumn = Int(node.end_column)

            guard let startIndex = getIndex(forLine: startLine, column: startColumn, in: markdown),
                  let endIndex = getIndex(forLine: endLine, column: endColumn, in: markdown)
            else {
                assertionFailure()
                continue
            }
            let outputBlockCount = transformedOutputBlockCount(for: block)
            let content = RootBlockRange(
                type: block.nodeType,
                startIndex: startIndex,
                endIndex: endIndex,
                outputBlockCount: outputBlockCount
            )
            ranges.append(content)
        }
        return ranges
    }

    public func parseIncremental(
        previousMarkdown: String,
        newMarkdown: String,
        previousBlocks: [MarkdownBlockNode],
        previousRanges: [RootBlockRange]? = nil
    ) -> IncrementalParseResult? {
        guard !previousMarkdown.isEmpty else { return nil }
        guard newMarkdown.count > previousMarkdown.count else { return nil }

        let ranges = previousRanges ?? parseBlockRange(previousMarkdown)
        guard !ranges.isEmpty else { return nil }

        let tailRootBlockCount = preferredTailRootBlockCount(
            previousMarkdown: previousMarkdown,
            previousBlocks: previousBlocks,
            ranges: ranges
        )
        let stableRootBlockCount = max(ranges.count - tailRootBlockCount, 0)
        guard stableRootBlockCount > 0 else { return nil }
        let stablePrefixBlockCount = ranges
            .prefix(stableRootBlockCount)
            .reduce(into: 0) { $0 += $1.outputBlockCount }

        let stablePrefixStartIndex: String.Index = if let boundary = ranges[safe: stableRootBlockCount]?.startIndex {
            boundary
        } else {
            previousMarkdown.endIndex
        }

        let stablePrefixText = previousMarkdown[..<stablePrefixStartIndex]
        guard newMarkdown.starts(with: stablePrefixText) else {
            return nil
        }

        let tailMarkdown = String(newMarkdown[stablePrefixStartIndex...])
        let mathIdentifierOffset = maxMathIdentifier(in: previousBlocks.prefix(stablePrefixBlockCount)) + 1
        let tailResult = shiftMathIdentifiers(in: parse(tailMarkdown), by: mathIdentifierOffset)
        let tailRanges = parseBlockRange(tailMarkdown)
        let shiftedTailRanges = shiftRanges(
            tailRanges,
            from: tailMarkdown,
            into: newMarkdown,
            at: stablePrefixStartIndex
        )

        return .init(
            stablePrefixBlockCount: min(stablePrefixBlockCount, previousBlocks.count),
            tailResult: tailResult,
            blockRanges: Array(ranges.prefix(stableRootBlockCount)) + shiftedTailRanges
        )
    }
}

private func getIndex(forLine targetLine: Int, column targetColumn: Int, in text: String) -> String.Index? {
    var currentLine = 1
    var lineStartIndex = text.startIndex

    while currentLine < targetLine {
        guard let newlineIndex = text[lineStartIndex...].firstIndex(of: "\n") else {
            return nil
        }
        lineStartIndex = text.index(after: newlineIndex)
        currentLine += 1
    }

    // cmark 使用 1-based 列号，需要减1转换为 0-based
    let targetOffset = targetColumn - 1

    let lineEndIndex: String.Index = if let newlineIndex = text[lineStartIndex...].firstIndex(of: "\n") {
        newlineIndex
    } else {
        text.endIndex
    }

    let maxOffset = text.distance(from: lineStartIndex, to: lineEndIndex)

    if targetOffset > maxOffset {
        return lineEndIndex
    }

    if targetOffset < 0 {
        return lineStartIndex
    }

    return text.index(lineStartIndex, offsetBy: targetOffset)
}

private extension MarkdownParser {
    func transformedOutputBlockCount(for block: UnsafeNode) -> Int {
        guard let blockNode = MarkdownBlockNode(unsafeNode: block) else { return 0 }
        let specializeContext = SpecializeContext()
        specializeContext.append(blockNode)
        return specializeContext.complete().count
    }

    func preferredTailRootBlockCount(
        previousMarkdown: String,
        previousBlocks: [MarkdownBlockNode],
        ranges: [RootBlockRange]
    ) -> Int {
        var count = min(3, ranges.count)

        let complexTail = previousBlocks.suffix(3).contains { block in
            switch block {
            case .blockquote, .bulletedList, .numberedList, .taskList, .codeBlock, .table:
                return true
            case .paragraph, .heading, .thematicBreak:
                return false
            }
        }
        if complexTail {
            count = min(5, ranges.count)
        }

        let suffix = String(previousMarkdown.suffix(2048))
        if suffixContainsOpenFence(suffix) || suffixContainsContinuationMarkers(suffix) {
            count = min(max(count, 8), ranges.count)
        }

        return max(count, 1)
    }

    func suffixContainsOpenFence(_ suffix: String) -> Bool {
        var fenceCount = 0
        for line in suffix.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = String(line).trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                fenceCount += 1
            }
        }
        return fenceCount % 2 == 1
    }

    func suffixContainsContinuationMarkers(_ suffix: String) -> Bool {
        guard let lastNonEmptyLine = suffix
            .split(separator: "\n", omittingEmptySubsequences: false)
            .reversed()
            .first(where: { !String($0).trimmingCharacters(in: .whitespaces).isEmpty }) else {
            return false
        }

        let trimmed = String(lastNonEmptyLine).trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix(">")
            || trimmed.hasPrefix("- ")
            || trimmed.hasPrefix("* ")
            || trimmed.hasPrefix("+ ")
            || trimmed.hasPrefix("|")
        {
            return true
        }
        return trimmed.range(
            of: #"^\d+\.\s"#,
            options: .regularExpression
        ) != nil
    }

    func maxMathIdentifier<S: Sequence>(in blocks: S) -> Int where S.Element == MarkdownBlockNode {
        var maximum = -1
        for block in blocks {
            _ = block.rewrite { inline -> [MarkdownInlineNode] in
                if case let .math(_, replacementIdentifier) = inline,
                   let identifier = Self.identifierForReplacementText(replacementIdentifier),
                   let value = Int(identifier) {
                    maximum = max(maximum, value)
                }
                return [inline]
            }
        }
        return maximum
    }

    func shiftMathIdentifiers(in result: ParseResult, by offset: Int) -> ParseResult {
        guard offset > 0, !result.mathContext.isEmpty else { return result }

        let shiftedDocument = result.document.rewrite { inline -> [MarkdownInlineNode] in
            guard case let .math(content, replacementIdentifier) = inline,
                  let identifier = Self.identifierForReplacementText(replacementIdentifier),
                  let value = Int(identifier) else {
                return [inline]
            }

            let shiftedIdentifier = String(value + offset)
            return [
                .math(
                    content: content,
                    replacementIdentifier: Self.replacementText(
                        for: .math,
                        identifier: shiftedIdentifier
                    )
                ),
            ]
        }

        let shiftedMathContext = Dictionary(
            uniqueKeysWithValues: result.mathContext.map { key, value in
                (key + offset, value)
            }
        )

        return .init(document: shiftedDocument, mathContext: shiftedMathContext)
    }

    func shiftRanges(
        _ ranges: [RootBlockRange],
        from tailMarkdown: String,
        into fullMarkdown: String,
        at boundary: String.Index
    ) -> [RootBlockRange] {
        ranges.map { range in
            let startOffset = tailMarkdown.distance(from: tailMarkdown.startIndex, to: range.startIndex)
            let endOffset = tailMarkdown.distance(from: tailMarkdown.startIndex, to: range.endIndex)
            return .init(
                type: range.type,
                startIndex: fullMarkdown.index(boundary, offsetBy: startOffset),
                endIndex: fullMarkdown.index(boundary, offsetBy: endOffset),
                outputBlockCount: range.outputBlockCount
            )
        }
    }
}
