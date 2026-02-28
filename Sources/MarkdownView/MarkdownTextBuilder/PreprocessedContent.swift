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
        let imageSources: Set<String>

        public init(
            blocks: [MarkdownBlockNode],
            rendered: RenderedTextContent.Map,
            highlightMaps: [Int: CodeHighlighter.HighlightMap],
            imageSources: Set<String> = []
        ) {
            self.blocks = blocks
            self.rendered = rendered
            self.highlightMaps = highlightMaps
            self.imageSources = imageSources
        }

        public init(parserResult: MarkdownParser.ParseResult, theme: MarkdownTheme) {
            blocks = parserResult.document
            rendered = parserResult.render(theme: theme)
            highlightMaps = parserResult.render(theme: theme)
            imageSources = Self.collectImageSources(in: blocks)
            preloadImages()
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
            imageSources = Self.collectImageSources(in: blocks)
            preloadImages()
        }

        /// Fills in math-rendered content from main thread after background init.
        public func completeMathRendering(parserResult: MarkdownParser.ParseResult, theme: MarkdownTheme) -> PreprocessedContent {
            PreprocessedContent(
                blocks: blocks,
                rendered: parserResult.render(theme: theme),
                highlightMaps: highlightMaps,
                imageSources: imageSources
            )
        }

        public init() {
            blocks = .init()
            rendered = .init()
            highlightMaps = .init()
            imageSources = []
        }

        static func incrementalMerged(
            prefix: PreprocessedContent,
            stablePrefixBlockCount: Int,
            tail: PreprocessedContent
        ) -> PreprocessedContent {
            let clampedPrefixBlockCount = min(stablePrefixBlockCount, prefix.blocks.count)
            let stablePrefixBlocks = Array(prefix.blocks.prefix(clampedPrefixBlockCount))
            let mergedBlocks = stablePrefixBlocks + tail.blocks

            var rendered = retainedRenderedContexts(
                from: stablePrefixBlocks,
                available: prefix.rendered
            )
            for (key, value) in tail.rendered {
                rendered[key] = value
            }

            var highlightMaps = retainedHighlightMaps(
                from: stablePrefixBlocks,
                available: prefix.highlightMaps
            )
            for (key, value) in tail.highlightMaps {
                highlightMaps[key] = value
            }

            let content = PreprocessedContent(
                blocks: mergedBlocks,
                rendered: rendered,
                highlightMaps: highlightMaps,
                imageSources: collectImageSources(in: mergedBlocks)
            )
            content.preloadImages()
            return content
        }

        private static let log = Logger(subsystem: "MarkdownView", category: "PreprocessedContent")

        static func collectImageSources(in blocks: [MarkdownBlockNode]) -> Set<String> {
            var urls = Set<String>()
            visitImageURLs(in: blocks, urls: &urls)
            return urls
        }

        /// Kick off async image loading for all image URLs in the document.
        private func preloadImages() {
            #if DEBUG
                if !imageSources.isEmpty {
                    Self.log.info("preloadImages: \(self.imageSources.count) image URL(s) found")
                }
            #endif
            for url in imageSources {
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

private func retainedHighlightMaps(
    from blocks: [MarkdownBlockNode],
    available: [Int: CodeHighlighter.HighlightMap]
) -> [Int: CodeHighlighter.HighlightMap] {
    var retained = [Int: CodeHighlighter.HighlightMap]()
    visitCodeBlocks(in: blocks) { fenceInfo, content in
        let key = CodeHighlighter.current.key(for: content, language: fenceInfo)
        if let existing = available[key] {
            retained[key] = existing
        }
    }
    return retained
}

private func retainedRenderedContexts(
    from blocks: [MarkdownBlockNode],
    available: RenderedTextContent.Map
) -> RenderedTextContent.Map {
    let usedIdentifiers = collectMathReplacementIdentifiers(in: blocks)
    return available.filter { usedIdentifiers.contains($0.key) }
}

private func collectMathReplacementIdentifiers(in blocks: [MarkdownBlockNode]) -> Set<String> {
    var identifiers = Set<String>()
    for block in blocks {
        switch block {
        case let .paragraph(content), let .heading(_, content):
            collectMathReplacementIdentifiers(in: content, identifiers: &identifiers)
        case let .blockquote(children):
            identifiers.formUnion(collectMathReplacementIdentifiers(in: children))
        case let .bulletedList(_, items):
            for item in items {
                identifiers.formUnion(collectMathReplacementIdentifiers(in: item.children))
            }
        case let .numberedList(_, _, items):
            for item in items {
                identifiers.formUnion(collectMathReplacementIdentifiers(in: item.children))
            }
        case let .taskList(_, items):
            for item in items {
                identifiers.formUnion(collectMathReplacementIdentifiers(in: item.children))
            }
        case let .table(_, rows):
            for row in rows {
                for cell in row.cells {
                    collectMathReplacementIdentifiers(in: cell.content, identifiers: &identifiers)
                }
            }
        case .codeBlock, .thematicBreak:
            break
        }
    }
    return identifiers
}

private func collectMathReplacementIdentifiers(
    in inlines: [MarkdownInlineNode],
    identifiers: inout Set<String>
) {
    for inline in inlines {
        switch inline {
        case let .math(_, replacementIdentifier):
            identifiers.insert(replacementIdentifier)
        case let .emphasis(children), let .strong(children), let .strikethrough(children):
            collectMathReplacementIdentifiers(in: children, identifiers: &identifiers)
        case let .link(_, children), let .image(_, children):
            collectMathReplacementIdentifiers(in: children, identifiers: &identifiers)
        default:
            break
        }
    }
}
