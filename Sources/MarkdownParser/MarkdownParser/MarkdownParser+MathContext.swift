//
//  MarkdownParser+MathContext.swift
//  MarkdownView
//
//  Created by 秋星桥 on 6/3/25.
//

import Foundation

private let mathPattern: NSRegularExpression? = {
    let patterns = [
        ###"\$\$([\s\S]*?)\$\$"###, // block formula $$ ... $$
        ###"\\\\\[([\s\S]*?)\\\\\]"###, // escaped block formula \\[ ... \\]
        ###"\\\\\(([\s\S]*?)\\\\\)"###, // escaped inline formula \\( ... \\)
        ###"\\\[ ([\s\S]*?) \\\]"###, // single-backslash block formula \[ ... \], spaces required
        ###"\\\( ([^`\n]*?) \\\)"###, // single-backslash inline formula \( ... \), spaces required, no backticks or newlines inside
    ]
    let pattern = patterns.joined(separator: "|")
    guard let regex = try? NSRegularExpression(
        pattern: pattern,
        options: [
            .caseInsensitive,
            .allowCommentsAndWhitespace,
        ]
    ) else {
        assertionFailure("failed to create regex for math pattern")
        return nil
    }
    return regex
}()

public extension MarkdownParser {
    class MathContext {
        let document: String
        var indexedContent: String?

        public fileprivate(set) var contents: [Int: String] = [:]

        init(preprocessText: String) {
            document = preprocessText
        }

        func process() {
            guard let regex = mathPattern else {
                assertionFailure()
                return
            }

            var document = document

            let matches = regex.matches(
                in: document,
                options: [],
                range: NSRange(location: 0, length: document.count)
            ).reversed()
            if matches.isEmpty { return }

            var indexer = 0
            for match in matches where match.numberOfRanges > 1 {
                var mathContentRange: NSRange?

                // find the longest capture group
                for rangeIndex in 1 ..< match.numberOfRanges {
                    let captureRange = match.range(at: rangeIndex)
                    if captureRange.location != NSNotFound {
                        mathContentRange = captureRange
                        break
                    }
                }

                guard let contentRange = mathContentRange else { continue }

                let fullMatchRange = match.range(at: 0)
                guard let fullRange = Range(fullMatchRange, in: document) else { continue }

                let mathIndex = indexer
                let mathContent = (document as NSString).substring(with: contentRange)

                indexer += 1

                contents[mathIndex] = mathContent

                let replacement = MarkdownParser.replacementText(for: .math, identifier: String(mathIndex))
                document.replaceSubrange(fullRange, with: replacement)
            }

            indexedContent = document
        }
    }
}

private let mathPatternWithinBlock: NSRegularExpression? = {
    // NOTE: `.allowCommentsAndWhitespace` strips unescaped whitespace from the
    // pattern, so do NOT rely on literal spaces inside these regexes. The
    // inline `$...$` pattern uses pandoc-style lookarounds to avoid matching
    // currency amounts like `$73,092.00 ... $73,370.00`:
    //   • opening `$` must be followed by a non-whitespace character
    //   • closing `$` must be preceded by a non-whitespace character
    //   • closing `$` must not be immediately followed by a digit (anti-currency)
    let patterns = [
        ###"\\\(([^\r\n]+?)\\\)"###, // inline formula \(...\)
        ###"\$(?!\s)([^\r\n$]+?)(?<!\s)\$(?!\d)"###, // inline formula $...$, avoids matching currency amounts
    ]
    let pattern = patterns.joined(separator: "|")
    guard let regex = try? NSRegularExpression(
        pattern: pattern,
        options: [
            .caseInsensitive,
            .allowCommentsAndWhitespace,
        ]
    ) else {
        assertionFailure("failed to create regex for math pattern")
        return nil
    }
    return regex
}()

extension MarkdownParser {
    func finalizeMathBlocks(_ nodes: [MarkdownBlockNode], mathContext: MathContext) -> [MarkdownBlockNode] {
        nodes.map { finalizeMathBlocks($0, mathContext: mathContext) }.flatMap(\.self)
    }

    func finalizeMathBlocks(_ node: MarkdownBlockNode, mathContext: MathContext) -> [MarkdownBlockNode] {
        switch node {
        case let .blockquote(children):
            return [.blockquote(children: finalizeMathBlocks(children, mathContext: mathContext))]
        case let .bulletedList(isTight, items):
            let processedItems = items.map { item in
                RawListItem(children: finalizeMathBlocks(item.children, mathContext: mathContext))
            }
            return [.bulletedList(isTight: isTight, items: processedItems)]
        case let .numberedList(isTight, start, items):
            let processedItems = items.map { item in
                RawListItem(children: finalizeMathBlocks(item.children, mathContext: mathContext))
            }
            return [.numberedList(isTight: isTight, start: start, items: processedItems)]
        case let .taskList(isTight, items):
            let processedItems = items.map { item in
                RawTaskListItem(isCompleted: item.isCompleted, children: finalizeMathBlocks(item.children, mathContext: mathContext))
            }
            return [.taskList(isTight: isTight, items: processedItems)]
        case let .paragraph(content):
            let processedContent = finalizeInlineMathInNodes(content, mathContext: mathContext)
            return [.paragraph(content: processedContent)]
        case let .table(columnAlignments, rows):
            let processedRows = rows.map { row in
                let processedCells = row.cells.map { cell in
                    RawTableCell(content: finalizeInlineMathInNodes(cell.content, mathContext: mathContext))
                }
                return RawTableRow(cells: processedCells)
            }
            return [.table(columnAlignments: columnAlignments, rows: processedRows)]
        case let .codeBlock(language, content):
            // restore replacement content in code blocks if found, we dont want bad links in code blocks
            return [.codeBlock(fenceInfo: language, content: restore(content: content, mathContext: mathContext))]
        case let .heading(level: level, content: content):
            return [.heading(level: level, content: finalizeInlineMathInNodes(content, mathContext: mathContext))]
        default:
            return [node]
        }
    }

    private func restore(content: String, mathContext: MathContext) -> String {
        var content = content
        for (index, mathContent) in mathContext.contents.sorted(by: { $0.key < $1.key }) {
            let placeholder = Self.replacementText(for: .math, identifier: .init(index))
            content = content.replacingOccurrences(of: placeholder, with: mathContent)
        }
        return content
    }

    private func finalizeInlineMathInNodes(_ nodes: [MarkdownInlineNode], mathContext: MathContext) -> [MarkdownInlineNode] {
        var result: [MarkdownInlineNode] = []

        for node in nodes {
            switch node {
            case let .text(text):
                result.append(contentsOf: processInlineMath(text, mathContext: mathContext))
            case let .code(content):
                if Self.typeForReplacementText(content) == .math,
                   let identifier = Self.identifierForReplacementText(content),
                   let value = Int(identifier),
                   let content = mathContext.contents[value]
                {
                    result.append(.math(
                        content: content,
                        replacementIdentifier: Self.replacementText(
                            for: .math,
                            identifier: identifier
                        )
                    ))
                } else {
                    result.append(node)
                }
            default:
                result.append(node)
            }
        }

        return result
    }

    private func processInlineMath(_ text: String, mathContext: MathContext) -> [MarkdownInlineNode] {
        let blocks = processInlineMathInTextWithRegExMather(text, mathContext: mathContext).map { [$0] }
        return blocks.flatMap(\.self)
    }

    // thought that adding ` to enclosing replacement string is not robust
    // but it works on my machine

    private func processInlineMathInTextWithRegExMather(_ text: String, mathContext: MathContext) -> [MarkdownInlineNode] {
        guard let regex = mathPatternWithinBlock else { return [.text(text)] }

        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.count))
        if matches.isEmpty { return [.text(text)] }

        var result: [MarkdownInlineNode] = []
        var lastEnd = 0

        for match in matches {
            let fullMatchRange = match.range(at: 0)
            guard fullMatchRange.location != NSNotFound else { continue }

            // find the first valid capture group (the math content)
            var mathContent: String?
            for groupIndex in 1 ..< match.numberOfRanges {
                let captureRange = match.range(at: groupIndex)
                if captureRange.location != NSNotFound {
                    mathContent = (text as NSString).substring(with: captureRange)
                    break
                }
            }

            guard let content = mathContent else { continue }

            if fullMatchRange.location > lastEnd {
                let beforeText = (text as NSString).substring(
                    with: NSRange(location: lastEnd, length: fullMatchRange.location - lastEnd)
                )
                if !beforeText.isEmpty { result.append(.text(beforeText)) }
            }

            let mathIndex = mathContext.contents.count
            mathContext.contents[mathIndex] = content
            let placeholder = Self.replacementText(for: .math, identifier: .init(mathIndex))
            result.append(.math(content: content, replacementIdentifier: placeholder))

            lastEnd = fullMatchRange.location + fullMatchRange.length
        }

        if lastEnd < text.count {
            let remainingText = (text as NSString).substring(from: lastEnd)
            if !remainingText.isEmpty {
                result.append(.text(remainingText))
            }
        }

        return result
    }
}
