//
//  PreprocessedContent.swift
//  MarkdownView
//
//  Created by 秋星桥 on 7/5/25.
//

import Foundation
import MarkdownParser

public extension MarkdownTextView {
    final class PreprocessedContent {
        public let blocks: [MarkdownBlockNode]
        public let rendered: RenderedTextContent.Map
        public let highlightMaps: [Int: CodeHighlighter.HighlightMap]

        public init(
            blocks: [MarkdownBlockNode],
            rendered: RenderedTextContent.Map,
            highlightMaps: [Int: CodeHighlighter.HighlightMap]
        ) {
            self.blocks = blocks
            self.rendered = rendered
            self.highlightMaps = highlightMaps
        }

        public init(parserResult: MarkdownParser.ParseResult, theme: MarkdownTheme) {
            blocks = parserResult.document
            rendered = parserResult.render(theme: theme)
            highlightMaps = parserResult.render(theme: theme)
        }

        public init() {
            blocks = .init()
            rendered = .init()
            highlightMaps = .init()
        }
    }
}

public extension MarkdownParser.ParseResult {
    fileprivate func renderMathContent(_ theme: MarkdownTheme, _ renderedContexts: inout [String: RenderedTextContent]) {
        for (key, value) in mathContext {
            var image = MathRenderer.renderToImage(
                latex: value,
                fontSize: theme.fonts.body.pointSize,
                textColor: theme.colors.body
            )
            #if canImport(UIKit)
                image = image?.withRenderingMode(.alwaysTemplate)
            #endif
            let renderedContext = RenderedTextContent(
                image: image,
                text: value
            )
            let replacementText = MarkdownParser.replacementText(for: .math, identifier: .init(key))
            renderedContexts[replacementText] = renderedContext
        }
    }

    func render(theme: MarkdownTheme) -> RenderedTextContent.Map {
        var renderedContexts: [String: RenderedTextContent] = [:]
        renderMathContent(theme, &renderedContexts)
        return renderedContexts
    }
}

private func visitCodeBlocks(
    in blocks: [MarkdownBlockNode],
    visitor: (String?, String) -> Void
) {
    var queue = blocks
    var index = 0
    while index < queue.count {
        let node = queue[index]
        index += 1
        if case let .codeBlock(fenceInfo, content) = node {
            visitor(fenceInfo, content)
        }
        queue.append(contentsOf: node.children)
    }
}

public extension MarkdownParser.ParseResult {
    func render(theme: MarkdownTheme) -> [Int: CodeHighlighter.HighlightMap] {
        var highlightMaps = [Int: CodeHighlighter.HighlightMap]()
        visitCodeBlocks(in: document) { fenceInfo, content in
            let key = CodeHighlighter.current.key(for: content, language: fenceInfo)
            let map = CodeHighlighter.current.highlight(key: key, content: content, language: fenceInfo)
            highlightMaps[key] = map
        }
        return highlightMaps
    }
}
