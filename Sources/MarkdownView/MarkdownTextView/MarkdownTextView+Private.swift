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
    static let preprocessingQueue = DispatchQueue(
        label: "com.markdownview.preprocessing",
        qos: .userInitiated
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
            .map { [weak self] markdown -> (String, MarkdownTheme) in
                (markdown, self?.theme ?? .default)
            }
            .receive(on: Self.preprocessingQueue)
            .map { markdown, theme -> (MarkdownParser.ParseResult, PreprocessedContent, MarkdownTheme) in
                let parser = MarkdownParser()
                let result = parser.parse(markdown)
                // Code highlighting runs on background; math rendering deferred to main
                let content = PreprocessedContent(parserResult: result, theme: theme, backgroundSafe: true)
                return (result, content, theme)
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] result, content, theme in
                // Complete math rendering on main thread where UI context is available
                let finalContent = content.completeMathRendering(parserResult: result, theme: theme)
                self?.use(finalContent)
            }
            .store(in: &cancellables)
    }

    func use(_ content: PreprocessedContent) {
        assert(Thread.isMainThread)
        document = content
        // due to a bug in model gemini-flash
        // there might be a large of unknown empty whitespace inside the table
        // thus we hereby call the autoreleasepool to avoid large memory consumption
        autoreleasepool { updateTextExecute() }

        #if canImport(UIKit)
            layoutIfNeeded()
        #elseif canImport(AppKit)
            layoutSubtreeIfNeeded()
        #endif
    }
}
