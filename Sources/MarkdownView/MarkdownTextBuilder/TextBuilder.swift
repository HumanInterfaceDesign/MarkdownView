//
//  Created by ktiays on 2025/1/20.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

import CoreText
import Litext
import MarkdownParser
#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

final class TextBuilder {
    private let nodes: [MarkdownBlockNode]
    private let viewProvider: ReusableViewProvider
    private var theme: MarkdownTheme = .default
    private let text: NSMutableAttributedString = .init()
    private let context: MarkdownTextView.PreprocessedContent

    private var bulletDrawing: BulletDrawingCallback?
    private var numberedDrawing: NumberedDrawingCallback?
    private var checkboxDrawing: CheckboxDrawingCallback?
    private var thematicBreakDrawing: DrawingCallback?
    private var codeDrawing: DrawingCallback?
    private var tableDrawing: DrawingCallback?
    private var blockquoteMarking: BlockquoteMarkingCallback?
    private var blockquoteDrawing: BlockquoteDrawingCallback?

    init(
        nodes: [MarkdownBlockNode],
        context: MarkdownTextView.PreprocessedContent,
        viewProvider: ReusableViewProvider
    ) {
        self.nodes = nodes
        self.context = context
        self.viewProvider = viewProvider
    }

    func withTheme(_ theme: MarkdownTheme) -> TextBuilder {
        self.theme = theme
        return self
    }

    func withBulletDrawing(_ drawing: @escaping BulletDrawingCallback) -> TextBuilder {
        bulletDrawing = drawing
        return self
    }

    func withNumberedDrawing(_ drawing: @escaping NumberedDrawingCallback) -> TextBuilder {
        numberedDrawing = drawing
        return self
    }

    func withCheckboxDrawing(_ drawing: @escaping CheckboxDrawingCallback) -> TextBuilder {
        checkboxDrawing = drawing
        return self
    }

    func withThematicBreakDrawing(_ drawing: @escaping DrawingCallback) -> TextBuilder {
        thematicBreakDrawing = drawing
        return self
    }

    func withCodeDrawing(_ drawing: @escaping DrawingCallback) -> TextBuilder {
        codeDrawing = drawing
        return self
    }

    func withTableDrawing(_ drawing: @escaping DrawingCallback) -> TextBuilder {
        tableDrawing = drawing
        return self
    }

    func withBlockquoteMarking(_ marking: @escaping BlockquoteMarkingCallback) -> TextBuilder {
        blockquoteMarking = marking
        return self
    }

    func withBlockquoteDrawing(_ drawing: @escaping BlockquoteDrawingCallback) -> TextBuilder {
        blockquoteDrawing = drawing
        return self
    }

    struct BuildResult {
        let document: NSAttributedString
        let subviews: [PlatformView]
        /// Per-block attributed strings, parallel to the input block array.
        let blockSegments: [NSAttributedString]
    }

    private var previouslyBuilt = false
    func build() -> BuildResult {
        assert(!previouslyBuilt, "TextBuilder can only be built once.")
        previouslyBuilt = true
        var subviewCollector = [PlatformView]()
        var segments = [NSAttributedString]()
        segments.reserveCapacity(nodes.count)
        let processors = makeProcessors()
        for node in nodes {
            let segment = processBlock(
                node,
                context: context,
                blockProcessor: processors.blockProcessor,
                listProcessor: processors.listProcessor,
                subviews: &subviewCollector
            )
            segments.append(segment)
            text.append(segment)
        }
        text.fixAttributes(in: .init(location: 0, length: text.length))
        return .init(document: text, subviews: subviewCollector, blockSegments: segments)
    }

    /// Build only specific block indices, reusing cached segments for unchanged blocks.
    func buildIncremental(
        changes: [ASTDiff.Change],
        cachedSegments: [NSAttributedString]
    ) -> BuildResult {
        assert(!previouslyBuilt, "TextBuilder can only be built once.")
        previouslyBuilt = true

        var subviewCollector = [PlatformView]()
        var segments = [NSAttributedString]()
        segments.reserveCapacity(nodes.count)
        let processors = makeProcessors()

        for change in changes {
            switch change {
            case let .keep(oldIndex, newIndex):
                // Reuse the previous segment for the matching old block.
                if oldIndex < cachedSegments.count {
                    let segment = cachedSegments[oldIndex]
                    segments.append(segment)
                    text.append(segment)
                    // Also collect any subviews from the cached segment
                    collectSubviews(from: segment, into: &subviewCollector)
                } else {
                    // Index out of range for cache — rebuild
                    let segment = processBlock(
                        nodes[newIndex],
                        context: context,
                        blockProcessor: processors.blockProcessor,
                        listProcessor: processors.listProcessor,
                        subviews: &subviewCollector
                    )
                    segments.append(segment)
                    text.append(segment)
                }
            case let .rebuild(newIndex):
                let segment = processBlock(
                    nodes[newIndex],
                    context: context,
                    blockProcessor: processors.blockProcessor,
                    listProcessor: processors.listProcessor,
                    subviews: &subviewCollector
                )
                segments.append(segment)
                text.append(segment)
            case .remove:
                // Nothing to add — block was removed
                break
            }
        }

        text.fixAttributes(in: .init(location: 0, length: text.length))
        return .init(document: text, subviews: subviewCollector, blockSegments: segments)
    }

    /// Extract context views (CodeView, TableView) embedded in an attributed string.
    private func collectSubviews(from segment: NSAttributedString, into collector: inout [PlatformView]) {
        collector.append(contentsOf: Self.contextViews(in: segment))
    }

    static func contextViews(in segment: NSAttributedString) -> [PlatformView] {
        var views = [PlatformView]()
        segment.enumerateAttribute(.contextView, in: NSRange(location: 0, length: segment.length)) { value, _, _ in
            if let view = value as? PlatformView {
                views.append(view)
            }
        }
        return views
    }
}

// MARK: - Block Processing

extension TextBuilder {
    private func makeProcessors() -> (blockProcessor: BlockProcessor, listProcessor: ListProcessor) {
        (
            BlockProcessor(
                theme: theme,
                viewProvider: viewProvider,
                context: context,
                thematicBreakDrawing: thematicBreakDrawing,
                codeDrawing: codeDrawing,
                tableDrawing: tableDrawing,
                blockquoteMarking: blockquoteMarking,
                blockquoteDrawing: blockquoteDrawing
            ),
            ListProcessor(
                theme: theme,
                viewProvider: viewProvider,
                context: context,
                bulletDrawing: bulletDrawing,
                numberedDrawing: numberedDrawing,
                checkboxDrawing: checkboxDrawing
            )
        )
    }

    private func processBlock(
        _ node: MarkdownBlockNode,
        context: MarkdownTextView.PreprocessedContent,
        blockProcessor: BlockProcessor,
        listProcessor: ListProcessor,
        subviews: inout [PlatformView]
    ) -> NSAttributedString {
        switch node {
        case let .heading(level, contents):
            return blockProcessor.processHeading(level: level, contents: contents)
        case let .paragraph(contents):
            return blockProcessor.processParagraph(contents: contents)
        case let .bulletedList(_, items):
            return listProcessor.processBulletedList(items: items)
        case let .numberedList(_, index, items):
            return listProcessor.processNumberedList(startAt: index, items: items)
        case let .taskList(_, items):
            return listProcessor.processTaskList(items: items)
        case .thematicBreak:
            return blockProcessor.processThematicBreak()
        case let .codeBlock(language, content):
            let highlightKey = CodeHighlighter.current.key(for: content, language: language)
            let highlightMap = context.highlightMaps[highlightKey]
            let result = blockProcessor.processCodeBlock(
                language: language,
                content: content,
                highlightMap: highlightMap ?? .init()
            )
            subviews.append(result.1)
            return result.0
        case let .blockquote(children):
            return blockProcessor.processBlockquote(children)
        case let .table(_, rows):
            let result = blockProcessor.processTable(rows: rows)
            subviews.append(result.1)
            return result.0
        }
    }
}
