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
    struct IncrementalParsingContext {
        let previousRawMarkdown: String
        let previousContent: PreprocessedContent
        let previousRanges: [MarkdownParser.RootBlockRange]?
    }

    enum RawMarkdownUpdate {
        case ready(content: PreprocessedContent, rawMarkdown: String)
        case parse(markdown: String, theme: MarkdownTheme, incrementalContext: IncrementalParsingContext?)
        case parsedFull(
            result: MarkdownParser.ParseResult,
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

    private static let disallowedPlainTextAppendScalars = CharacterSet(
        charactersIn: "\n\r`*_[]()!$<>|~\\"
    )

    func resetCombine() {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }

    func setupCombine() {
        resetCombine()
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

        let pipeline: AnyPublisher<String, Never>
        if let throttleInterval {
            pipeline = rawContentSubject
                .throttle(for: .seconds(throttleInterval), scheduler: DispatchQueue.main, latest: true)
                .eraseToAnyPublisher()
        } else {
            pipeline = rawContentSubject.eraseToAnyPublisher()
        }

        pipeline
            .map { [weak self] markdown -> RawMarkdownUpdate in
                guard let self else {
                    return .parse(markdown: markdown, theme: .default, incrementalContext: nil)
                }
                if let content = self.makePlainTextAppendFastPath(for: markdown) {
                    return .ready(content: content, rawMarkdown: markdown)
                }
                return .parse(
                    markdown: markdown,
                    theme: self.theme,
                    incrementalContext: self.makeIncrementalParsingContext()
                )
            }
            .receive(on: Self.preprocessingQueue)
            .map { update -> RawMarkdownUpdate in
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

                    let result = parser.parse(markdown)
                    // Code highlighting runs on background; math rendering deferred to main
                    let content = PreprocessedContent(parserResult: result, theme: theme, backgroundSafe: true)
                    return .parsedFull(
                        result: result,
                        content: content,
                        theme: theme,
                        rawMarkdown: markdown
                    )
                case .parsedFull, .parsedIncremental:
                    return update
                }
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] update in
                guard let self else { return }
                switch update {
                case let .ready(content, rawMarkdown):
                    self.lastRawMarkdown = rawMarkdown
                    self.lastRootBlockRanges = nil
                    self.use(content)
                case let .parsedFull(result, content, theme, rawMarkdown):
                    // Complete math rendering on main thread where UI context is available
                    let finalContent = content.completeMathRendering(parserResult: result, theme: theme)
                    self.lastRawMarkdown = rawMarkdown
                    self.lastRootBlockRanges = nil
                    self.use(finalContent)
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
                    self.lastRawMarkdown = rawMarkdown
                    self.lastRootBlockRanges = result.blockRanges
                    self.use(mergedContent)
                case .parse:
                    assertionFailure("Unexpected raw markdown parse request on main thread")
                }
            }
            .store(in: &cancellables)
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

    func use(_ content: PreprocessedContent) {
        assert(Thread.isMainThread)
        document = content
        // due to a bug in model gemini-flash
        // there might be a large of unknown empty whitespace inside the table
        // thus we hereby call the autoreleasepool to avoid large memory consumption
        autoreleasepool { updateTextExecute() }

        invalidateIntrinsicContentSize()

        #if canImport(UIKit)
            layoutIfNeeded()
        #elseif canImport(AppKit)
            layoutSubtreeIfNeeded()
        #endif
    }
}
