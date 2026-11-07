//
//  MarkdownTextView+Private.swift
//  MarkdownView
//
//  Created by 秋星桥 on 7/9/25.
//

import Combine
import Foundation
import Litext
import MarkdownParser

extension MarkdownTextView {
    // Flows through the background preprocessing queue, so both the context and the
    // pipeline's update enum are nonisolated immutable snapshots.
    nonisolated struct IncrementalParsingContext {
        let previousRawMarkdown: String
        let previousContent: PreprocessedContent
        let previousRanges: [MarkdownParser.RootBlockRange]?
    }

    // Immutable snapshots cross the serial worker boundary. Background processing
    // reads AST data and builds new content; UI rendering stays on the main actor.
    // Platform colors/images in these snapshots lack checked Sendable conformance.
    nonisolated enum RawMarkdownUpdate: @unchecked Sendable {
        case ready(content: PreprocessedContent, rawMarkdown: String)
        case parse(markdown: String, theme: MarkdownTheme, incrementalContext: IncrementalParsingContext?)
        case parsedFull(
            result: MarkdownParser.ParseResult,
            ranges: [MarkdownParser.RootBlockRange],
            content: PreprocessedContent,
            theme: MarkdownTheme,
            rawMarkdown: String
        )
        case parsedIncremental(
            result: MarkdownParser.IncrementalParseResult,
            tailContent: PreprocessedContent,
            context: IncrementalParsingContext,
            theme: MarkdownTheme,
            rawMarkdown: String
        )
    }

    static let preprocessingQueue = DispatchQueue(
        label: "com.markdownview.preprocessing",
        qos: .userInitiated
    )

    /// Heavy parsing + background-safe preprocessing (code highlighting, diff blocks).
    /// Deliberately `nonisolated` because it executes on `preprocessingQueue`; math
    /// rendering is deferred to the main actor in the downstream `.sink`.
    nonisolated static func processOnPreprocessingQueue(_ update: RawMarkdownUpdate) -> RawMarkdownUpdate {
        switch update {
        case .ready:
            return update
        case let .parse(markdown, theme, incrementalContext):
            let parser = MarkdownParser()
            if let incrementalContext,
               let result = parser.parseIncremental(
                   previousMarkdown: incrementalContext.previousRawMarkdown,
                   newMarkdown: markdown,
                   previousBlocks: incrementalContext.previousContent.blocks,
                   previousRanges: incrementalContext.previousRanges
               ) {
                let tailContent = PreprocessedContent(
                    parserResult: result.tailResult,
                    theme: theme,
                    backgroundSafe: true
                )
                return .parsedIncremental(
                    result: result,
                    tailContent: tailContent,
                    context: incrementalContext,
                    theme: theme,
                    rawMarkdown: markdown
                )
            }

            let parsed = parser.parseWithBlockRanges(markdown)
            let result = parsed.result
            // Code highlighting runs on background; math rendering deferred to main
            let content = PreprocessedContent(parserResult: result, theme: theme, backgroundSafe: true)
            return .parsedFull(
                result: result,
                ranges: parsed.blockRanges,
                content: content,
                theme: theme,
                rawMarkdown: markdown
            )
        case .parsedFull, .parsedIncremental:
            return update
        }
    }

    private static let disallowedPlainTextAppendScalars = CharacterSet(
        charactersIn: "\n\r`*_[]()!$<>|~\\"
    )

    func resetCombine() {
        rawPipelineGeneration &+= 1
        pendingRawMarkdown = nil
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
        contentPipelineMode = .none
    }

    func setupCombine() {
        resetCombine()
        contentPipelineMode = .preprocessed
        if let throttleInterval {
            contentSubject
                .throttle(for: .seconds(throttleInterval), scheduler: DispatchQueue.main, latest: true)
                .sink { [weak self] content in self?.use(content) }
                .store(in: &cancellables)
        } else {
            contentSubject
                .sink { [weak self] content in self?.use(content) }
                .store(in: &cancellables)
        }
    }

    func setupRawCombine() {
        resetCombine()
        contentPipelineMode = .raw

        let pipeline: AnyPublisher<String, Never>
        if let throttleInterval {
            pipeline = rawContentSubject
                .throttle(for: .seconds(throttleInterval), scheduler: DispatchQueue.main, latest: true)
                .eraseToAnyPublisher()
        } else {
            pipeline = rawContentSubject.eraseToAnyPublisher()
        }

        pipeline
            .sink { [weak self] markdown in
                guard let self else { return }
                self.pendingRawMarkdown = markdown
                self.processPendingRawMarkdown()
            }
            .store(in: &cancellables)
    }

    private func processPendingRawMarkdown() {
        guard !isRawPreprocessing, contentPipelineMode == .raw,
              let rawMarkdown = pendingRawMarkdown else { return }
        pendingRawMarkdown = nil
        let markdown = RawDiffMarkdownNormalizer.normalizeForParsing(rawMarkdown)
        if let content = makePlainTextAppendFastPath(for: markdown) {
            applyRawMarkdownUpdate(.ready(content: content, rawMarkdown: markdown))
            return
        }
        let generation = rawPipelineGeneration
        let request = RawMarkdownUpdate.parse(
            markdown: markdown,
            theme: theme,
            incrementalContext: makeIncrementalParsingContext()
        )
        isRawPreprocessing = true
        // Only one job per view is queued. The main actor retains just the latest
        // pending input, and reset invalidates results without racing the worker.
        Self.preprocessingQueue.async { [weak self] in
            let update = Self.processOnPreprocessingQueue(request)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isRawPreprocessing = false
                if self.rawPipelineGeneration == generation,
                   self.contentPipelineMode == .raw {
                    // Publish progress even while newer input is pending; otherwise
                    // continuous streams can starve rendering until input stops.
                    self.applyRawMarkdownUpdate(update)
                }
                self.processPendingRawMarkdown()
            }
        }
    }

    private func applyRawMarkdownUpdate(_ update: RawMarkdownUpdate) {
        switch update {
        case let .ready(content, rawMarkdown):
            // The plain-text fast path changes only the final paragraph's end.
            // Keep its source map so the next structural token does not reparse
            // the entire previous document just to recover block ranges.
            if var ranges = lastRootBlockRanges, let last = ranges.last,
               last.outputBlockCount == 1, !rawMarkdown.isEmpty {
                ranges[ranges.count - 1] = .init(
                    type: last.type, startIndex: last.startIndex,
                    endIndex: rawMarkdown.index(before: rawMarkdown.endIndex),
                    outputBlockCount: last.outputBlockCount
                )
                lastRootBlockRanges = ranges
            } else {
                lastRootBlockRanges = nil
            }
            lastRawMarkdown = rawMarkdown
            use(content, layoutImmediately: false)
        case let .parsedFull(result, ranges, content, theme, rawMarkdown):
            // Complete math rendering on main thread where UI context is available
            let finalContent = content.completeMathRendering(parserResult: result, theme: theme)
            lastRawMarkdown = rawMarkdown
            lastRootBlockRanges = ranges
            use(finalContent, layoutImmediately: false)
        case let .parsedIncremental(result, tailContent, context, theme, rawMarkdown):
            let completedTailContent = tailContent.completeMathRendering(
                parserResult: result.tailResult,
                theme: theme
            )
            let mergedContent = PreprocessedContent.incrementalMerged(
                prefix: context.previousContent,
                stablePrefixBlockCount: result.stablePrefixBlockCount,
                tail: completedTailContent
            )
            lastRawMarkdown = rawMarkdown
            lastRootBlockRanges = result.blockRanges
            use(mergedContent, layoutImmediately: false)
        case .parse:
            assertionFailure("Unexpected raw markdown parse request on main thread")
        }
    }

    private func makeIncrementalParsingContext() -> IncrementalParsingContext? {
        assert(Thread.isMainThread)
        guard let lastRawMarkdown else { return nil }
        guard !document.blocks.isEmpty else { return nil }
        return .init(
            previousRawMarkdown: lastRawMarkdown,
            previousContent: document,
            previousRanges: lastRootBlockRanges
        )
    }

    func makePlainTextAppendFastPath(for markdown: String) -> PreprocessedContent? {
        assert(Thread.isMainThread)

        guard let lastRawMarkdown else { return nil }
        guard markdown.count > lastRawMarkdown.count else { return nil }
        guard markdown.hasPrefix(lastRawMarkdown) else { return nil }

        let appendedText = String(markdown.dropFirst(lastRawMarkdown.count))
        guard Self.isSafePlainTextAppend(appendedText) else { return nil }
        guard !document.blocks.isEmpty else { return nil }

        var updatedBlocks = document.blocks
        guard let lastBlock = updatedBlocks[safe: updatedBlocks.count - 1],
              case let .paragraph(content) = lastBlock else {
            return nil
        }
        guard let updatedContent = Self.appendingPlainText(appendedText, to: content) else {
            return nil
        }

        let lastIndex = updatedBlocks.count - 1
        updatedBlocks[lastIndex] = .paragraph(content: updatedContent)
        return PreprocessedContent(
            blocks: updatedBlocks,
            rendered: document.rendered,
            highlightMaps: document.highlightMaps,
            imageSources: document.imageSources
        )
    }

    private static func isSafePlainTextAppend(_ appendedText: String) -> Bool {
        guard !appendedText.isEmpty else { return false }
        for scalar in appendedText.unicodeScalars {
            if disallowedPlainTextAppendScalars.contains(scalar) {
                return false
            }
        }
        return true
    }

    private static func appendingPlainText(
        _ appendedText: String,
        to content: [MarkdownInlineNode]
    ) -> [MarkdownInlineNode]? {
        guard content.allSatisfy({
            if case .text = $0 {
                return true
            }
            return false
        }) else {
            return nil
        }

        guard !content.isEmpty else {
            return [.text(appendedText)]
        }

        var updatedContent = content
        let lastIndex = updatedContent.count - 1
        if let lastInline = updatedContent[safe: lastIndex],
           case let .text(existingText) = lastInline {
            updatedContent[lastIndex] = .text(existingText + appendedText)
        } else {
            updatedContent.append(.text(appendedText))
        }
        return updatedContent
    }

    func observeImageLoading() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleImageDidLoad(_:)),
            name: ImageLoader.imageDidLoadNotification,
            object: nil
        )
    }

    @objc func handleImageDidLoad(_ notification: Notification) {
        // Re-render current document so newly cached images appear
        guard !document.blocks.isEmpty else { return }
        if let imageSource = notification.object as? String,
           !document.imageSources.contains(imageSource) {
            return
        }
        use(document)
    }

    func use(_ content: PreprocessedContent, layoutImmediately: Bool = true) {
        assert(Thread.isMainThread)
        document = content
        // due to a bug in model gemini-flash
        // there might be a large of unknown empty whitespace inside the table
        // thus we hereby call the autoreleasepool to avoid large memory consumption
        autoreleasepool { updateTextExecute() }

        invalidateIntrinsicContentSize()

        #if canImport(UIKit)
            setNeedsLayout()
            if layoutImmediately { layoutIfNeeded() }
        #elseif canImport(AppKit)
            needsLayout = true
            if layoutImmediately { layoutSubtreeIfNeeded() }
        #endif
    }
}
