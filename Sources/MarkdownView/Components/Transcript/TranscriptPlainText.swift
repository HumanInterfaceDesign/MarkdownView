import Foundation
import MarkdownParser

/// Flattens markdown into one continuous run of plain text for the collapsed
/// transcript preview. Inline styling is dropped and block boundaries become
/// single spaces, so the teaser reads as spoken prose instead of spending its
/// few lines on structure.
enum TranscriptPlainText {
    static func flatten(markdown: String) -> String {
        let blocks = MarkdownParser().parse(markdown).document
        return blocks
            .compactMap(text(for:))
            .joined(separator: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func text(for block: MarkdownBlockNode) -> String? {
        switch block {
        case let .paragraph(content):
            return text(for: content)
        case let .heading(_, content):
            return text(for: content)
        case let .blockquote(children):
            return text(for: children)
        case let .bulletedList(_, items):
            return text(forItems: items.map(\.children))
        case let .numberedList(_, _, items):
            return text(forItems: items.map(\.children))
        case let .taskList(_, items):
            return text(forItems: items.map(\.children))
        case let .codeBlock(_, content):
            return content
        case let .table(_, rows):
            return rows
                .flatMap(\.cells)
                .map { text(for: $0.content) }
                .joined(separator: " ")
        case .thematicBreak:
            return nil
        }
    }

    private static func text(for blocks: [MarkdownBlockNode]) -> String {
        blocks.compactMap(text(for:)).joined(separator: " ")
    }

    private static func text(forItems items: [[MarkdownBlockNode]]) -> String {
        items.map(text(for:)).joined(separator: " ")
    }

    private static func text(for inlines: [MarkdownInlineNode]) -> String {
        inlines.collect { node -> [String] in
            switch node {
            case let .text(string):
                return [string]
            case .softBreak, .lineBreak:
                return [" "]
            case let .code(string):
                return [string]
            case let .math(content, _):
                return [content]
            default:
                return []
            }
        }.joined()
    }
}
