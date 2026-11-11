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

    public struct RangedParseResult {
        public let result: ParseResult
        /// Ranges in the original source, including math before placeholder substitution.
        public let blockRanges: [RootBlockRange]
    }

    public func parse(_ markdown: String) -> ParseResult {
        parseSource(markdown, includingRanges: false).result
    }

    public func parseWithBlockRanges(_ markdown: String) -> RangedParseResult {
        parseSource(markdown, includingRanges: true)
    }

    private func parseSource(_ markdown: String, includingRanges: Bool) -> RangedParseResult {
        let math = MathContext(preprocessText: markdown)
        math.process()
        let source = math.indexedContent ?? markdown
        return withParser { parser in
            source.withCString { cmark_parser_feed(parser, $0, source.utf8.count) }
            guard let root = cmark_parser_finish(parser) else {
                assertionFailure("Unable to finish markdown parsing")
                return .init(result: .init(document: [], mathContext: [:]), blockRanges: [])
            }
            defer { cmark_node_free(root) }
            let sourceLines = includingRanges ? SourceLineIndex(source) : nil
            var blocks: [MarkdownBlockNode] = []
            var ranges: [RootBlockRange] = []
            for child in root.children {
                let context = SpecializeContext()
                if let node = MarkdownBlockNode(unsafeNode: child) { context.append(node) }
                let transformed = finalizeMathBlocks(context.complete(), mathContext: math)
                blocks.append(contentsOf: transformed)
                if let sourceLines,
                   let start = sourceLines.index(line: Int(child.pointee.start_line), column: Int(child.pointee.start_column)),
                   let end = sourceLines.index(line: Int(child.pointee.end_line), column: Int(child.pointee.end_column)) {
                    ranges.append(.init(
                        type: child.nodeType,
                        startIndex: math.originalIndex(for: start, in: source, isEnd: false),
                        endIndex: math.originalIndex(for: end, in: source, isEnd: true),
                        outputBlockCount: transformed.count
                    ))
                }
            }
            return .init(
                result: .init(document: blocks, mathContext: math.contents),
                blockRanges: ranges
            )
        }
    }

    public struct RootBlockRange {
        public let type: MarkdownNodeType
        public let startIndex: String.Index
        public let endIndex: String.Index
        public let outputBlockCount: Int

        public init(type: MarkdownNodeType, startIndex: String.Index, endIndex: String.Index, outputBlockCount: Int) {
            self.type = type
            self.startIndex = startIndex
            self.endIndex = endIndex
            self.outputBlockCount = outputBlockCount
        }
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

        defer { cmark_node_free(root) }
        let sourceLines = SourceLineIndex(markdown)

        assert(root.pointee.type == CMARK_NODE_DOCUMENT.rawValue)
        for block in root.children {
            let node = block.pointee

            let startLine = Int(node.start_line)
            let startColumn = Int(node.start_column)
            let endLine = Int(node.end_line)
            let endColumn = Int(node.end_column)

            guard let startIndex = sourceLines.index(line: startLine, column: startColumn),
                  let endIndex = sourceLines.index(line: endLine, column: endColumn)
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

        let ranges = previousRanges ?? parseWithBlockRanges(previousMarkdown).blockRanges
        guard !ranges.isEmpty else { return nil }

        let tailRootBlockCount = preferredTailRootBlockCount(
            newMarkdown: newMarkdown,
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
        let tail = parseWithBlockRanges(tailMarkdown)
        let tailResult = shiftMathIdentifiers(in: tail.result, by: mathIdentifierOffset)
        let tailRanges = tail.blockRanges
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

private struct SourceLineIndex {
    let text: String
    let lines: [Range<String.UTF8View.Index>]

    init(_ text: String) {
        self.text = text
        let bytes = text.utf8
        var lines: [Range<String.UTF8View.Index>] = []
        var start = bytes.startIndex
        var cursor = start
        while cursor < bytes.endIndex {
            let byte = bytes[cursor]
            if byte == 10 || byte == 13 {
                lines.append(start..<cursor)
                cursor = bytes.index(after: cursor)
                if byte == 13, cursor < bytes.endIndex, bytes[cursor] == 10 {
                    cursor = bytes.index(after: cursor)
                }
                start = cursor
            } else {
                cursor = bytes.index(after: cursor)
            }
        }
        lines.append(start..<bytes.endIndex)
        self.lines = lines
    }

    func index(line: Int, column: Int) -> String.Index? {
        guard line > 0, line <= lines.count else { return nil }
        let range = lines[line - 1]
        let bytes = text.utf8
        let offset = min(max(column - 1, 0), bytes.distance(from: range.lowerBound, to: range.upperBound))
        var position = bytes.index(range.lowerBound, offsetBy: offset)
        // cmark columns are UTF-8 bytes; inclusive ends can land inside a scalar.
        while String.Index(position, within: text) == nil, position > range.lowerBound {
            position = bytes.index(before: position)
        }
        return String.Index(position, within: text)
    }
}

private extension MarkdownParser {
    func transformedOutputBlockCount(for block: UnsafeNode) -> Int {
        guard let blockNode = MarkdownBlockNode(unsafeNode: block) else { return 0 }
        let specializeContext = SpecializeContext()
        specializeContext.append(blockNode)
        return specializeContext.complete().count
    }

    func preferredTailRootBlockCount(
        newMarkdown: String,
        previousBlocks: [MarkdownBlockNode],
        ranges: [RootBlockRange]
    ) -> Int {
        var count = 1

        if let lastBlock = previousBlocks.last {
            switch lastBlock {
            case .blockquote, .bulletedList, .numberedList, .taskList, .codeBlock, .table:
                count = 2
            case .paragraph, .heading, .thematicBreak:
                break
            }
        }

        let suffix = String(newMarkdown.suffix(2048))
        if suffixContainsContinuationMarkers(suffix) {
            count = max(count, 4)
        }
        if suffixContainsOpenFence(suffix) {
            count = max(count, 5)
        }

        return min(max(count, 1), ranges.count)
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
        if suffixContainsOpenTable(suffix) {
            return true
        }

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
        {
            return true
        }
        return trimmed.range(
            of: #"^\d+\.\s"#,
            options: .regularExpression
        ) != nil
    }

    func suffixContainsOpenTable(_ suffix: String) -> Bool {
        let lastBlock = suffix.components(separatedBy: "\n\n").last ?? suffix
        let lines = lastBlock
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard let header = lines.first, header.hasPrefix("|") else {
            return false
        }
        guard lines.count >= 2 else {
            return true
        }
        guard isTableSeparatorLine(lines[1]) else {
            return true
        }

        for line in lines.dropFirst(2) where !line.hasPrefix("|") {
            return true
        }
        return false
    }

    func isTableSeparatorLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("|"), trimmed.hasSuffix("|") else {
            return false
        }

        let cells = trimmed
            .split(separator: "|", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        guard !cells.isEmpty else { return false }

        return cells.allSatisfy { cell in
            let stripped = cell.replacingOccurrences(of: ":", with: "")
            return !stripped.isEmpty && stripped.allSatisfy { $0 == "-" }
        }
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
            let startOffset = tailMarkdown.utf8.distance(from: tailMarkdown.startIndex, to: range.startIndex)
            let endOffset = tailMarkdown.utf8.distance(from: tailMarkdown.startIndex, to: range.endIndex)
            return .init(
                type: range.type,
                startIndex: fullMarkdown.utf8.index(boundary, offsetBy: startOffset),
                endIndex: fullMarkdown.utf8.index(boundary, offsetBy: endOffset),
                outputBlockCount: range.outputBlockCount
            )
        }
    }
}
