//
//  PreprocessedContent.swift
//  MarkdownView
//
//  Created by 秋星桥 on 7/5/25.
//

import Foundation
import MarkdownParser
import os.log

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
            preloadImages(in: blocks)
        }

        /// Creates preprocessed content with code highlighting done on the calling thread
        /// and math rendering deferred. Use this from background queues where UIKit trait
        /// access is unavailable.
        public init(parserResult: MarkdownParser.ParseResult, theme: MarkdownTheme, backgroundSafe: Bool) {
            blocks = parserResult.document
            if backgroundSafe {
                // Code highlighting is thread-safe; math rendering needs main thread context
                highlightMaps = parserResult.render(theme: theme)
                rendered = .init()
            } else {
                rendered = parserResult.render(theme: theme)
                highlightMaps = parserResult.render(theme: theme)
            }
            preloadImages(in: blocks)
        }

        /// Fills in math-rendered content from main thread after background init.
        public func completeMathRendering(parserResult: MarkdownParser.ParseResult, theme: MarkdownTheme) -> PreprocessedContent {
            PreprocessedContent(
                blocks: blocks,
                rendered: parserResult.render(theme: theme),
                highlightMaps: highlightMaps
            )
        }

        public init() {
            blocks = .init()
            rendered = .init()
            highlightMaps = .init()
        }

        private static let log = Logger(subsystem: "MarkdownView", category: "PreprocessedContent")

        /// Kick off async image loading for all image URLs in the document.
        private func preloadImages(in blocks: [MarkdownBlockNode]) {
            var urls = Set<String>()
            visitImageURLs(in: blocks, urls: &urls)
            #if DEBUG
                if !urls.isEmpty {
                    Self.log.info("preloadImages: \(urls.count) image URL(s) found")
                }
            #endif
            for url in urls {
                ImageLoader.shared.loadImage(from: url) { _ in }
            }
        }
    }
}

private func visitImageURLs(in blocks: [MarkdownBlockNode], urls: inout Set<String>) {
    for block in blocks {
        switch block {
        case let .paragraph(inlines):
            visitInlineImages(in: inlines, urls: &urls)
        case let .heading(_, inlines):
            visitInlineImages(in: inlines, urls: &urls)
        case let .blockquote(children):
            visitImageURLs(in: children, urls: &urls)
        case let .bulletedList(_, items):
            for item in items { visitImageURLs(in: item.children, urls: &urls) }
        case let .numberedList(_, _, items):
            for item in items { visitImageURLs(in: item.children, urls: &urls) }
        case let .taskList(_, items):
            for item in items { visitImageURLs(in: item.children, urls: &urls) }
        default:
            break
        }
    }
}

private func visitInlineImages(in inlines: [MarkdownInlineNode], urls: inout Set<String>) {
    for inline in inlines {
        switch inline {
        case let .image(source, _):
            urls.insert(source)
        case let .emphasis(children), let .strong(children), let .strikethrough(children):
            visitInlineImages(in: children, urls: &urls)
        case let .link(_, children):
            visitInlineImages(in: children, urls: &urls)
        default:
            break
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
