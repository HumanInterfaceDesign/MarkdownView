//
//  Created by ktiays on 2025/1/20.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

import Combine
import CoreText
import Litext
import MarkdownParser

enum ContentPipelineMode {
    case none
    case preprocessed
    case raw
}

#if canImport(UIKit)
    import UIKit

    public final class MarkdownTextView: UIView {
        public var linkHandler: ((LinkPayload, NSRange, CGPoint) -> Void)?
        public var imageTapHandler: ((String, CGPoint) -> Void)?
        public var codePreviewHandler: ((String?, NSAttributedString) -> Void)?
        public var lineSelectionHandler: LineSelectionHandler?
        public var lineSelectionEndedHandler: LineSelectionHandler?
        /// Called whenever the selected character range changes, including
        /// while either selection handle is being dragged.
        public var selectionChangeHandler: ((NSRange?) -> Void)?

        public internal(set) var document: PreprocessedContent = .init()
        public let textView: LTXLabel = .init()
        public var theme: MarkdownTheme = .default {
            didSet {
                textView.selectionBackgroundColor = theme.colors.selectionBackground
                setMarkdown(document)
            }
        }

        public internal(set) weak var trackedScrollView: UIScrollView? // for selection updating

        var contextViews: [UIView] = []
        var cancellables = Set<AnyCancellable>()
        let contentSubject = CurrentValueSubject<PreprocessedContent, Never>(.init())
        let rawContentSubject = PassthroughSubject<String, Never>()
        public var throttleInterval: TimeInterval? = 1 / 20 { // x fps
            didSet { setupCombine() }
        }

        let viewProvider: ReusableViewProvider
        var contentPipelineMode: ContentPipelineMode = .none
        var lastRawMarkdown: String?
        var lastRootBlockRanges: [MarkdownParser.RootBlockRange]?
        var lastRenderedBlocks: [MarkdownBlockNode] = []
        var lastBuildResult: TextBuilder.BuildResult?

        public init(viewProvider: ReusableViewProvider = .init()) {
            self.viewProvider = viewProvider
            super.init(frame: .zero)
            textView.isSelectable = true
            textView.backgroundColor = .clear
            textView.selectionBackgroundColor = theme.colors.selectionBackground
            textView.delegate = self
            textView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(textView)
            NSLayoutConstraint.activate([
                textView.leadingAnchor.constraint(equalTo: leadingAnchor),
                textView.trailingAnchor.constraint(equalTo: trailingAnchor),
                textView.topAnchor.constraint(equalTo: topAnchor),
                textView.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            isAccessibilityElement = false
            accessibilityTraits = .staticText
            setupCombine()
            observeImageLoading()
        }

        /// Handles line selection from a code or diff view, clearing other blocks (exclusive mode)
        /// and forwarding the selection info to the public handler.
        func handleLineSelection(from sourceView: UIView, info: LineSelectionInfo?) {
            // Exclusive mode: clear selection in all other code/diff views
            for view in contextViews {
                guard view !== sourceView else { continue }
                if let codeView = view as? CodeView {
                    codeView.clearLineSelection()
                } else if let diffView = view as? DiffView {
                    diffView.clearLineSelection()
                }
            }
            lineSelectionHandler?(info)
        }

        /// Forwards the end-of-gesture selection info to the public `lineSelectionEndedHandler`.
        func handleLineSelectionEnded(from _: UIView, info: LineSelectionInfo?) {
            lineSelectionEndedHandler?(info)
        }

        @available(*, unavailable)
        public required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        override public func layoutSubviews() {
            super.layoutSubviews()
            textView.preferredMaxLayoutWidth = bounds.width
        }

        override public var intrinsicContentSize: CGSize {
            textView.intrinsicContentSize
        }

        public func boundingSize(for width: CGFloat) -> CGSize {
            textView.preferredMaxLayoutWidth = width
            return textView.intrinsicContentSize
        }

        /// Streaming "typing" reveal — forwards to the text label
        /// (see `LTXLabel.streamingReveal`). Set `true` while a message streams.
        public var streamingReveal: Bool {
            get { textView.streamingReveal }
            set { textView.streamingReveal = newValue }
        }

        /// Per-character fade duration for `streamingReveal` (fade softness).
        public var streamingRevealDuration: CFTimeInterval {
            get { textView.streamingRevealDuration }
            set { textView.streamingRevealDuration = newValue }
        }

        /// How fast the reveal sweeps through characters (characters per second).
        /// Bursty arrivals are still revealed left→right at this pace. Lower = slower.
        public var streamingRevealCharactersPerSecond: CGFloat {
            get { textView.streamingRevealCharactersPerSecond }
            set { textView.streamingRevealCharactersPerSecond = newValue }
        }

        /// Fires on the main thread once the reveal has fully settled to opaque
        /// after `streamingReveal` is set back to `false` — the moment the trailing
        /// fade lands. Use to time post-stream UI (e.g. action buttons) so it waits
        /// for the reveal instead of racing the still-fading tail.
        public var onStreamingRevealComplete: (() -> Void)? {
            get { textView.onStreamingRevealComplete }
            set { textView.onStreamingRevealComplete = newValue }
        }

        /// Fires whenever the reveal animation starts or stops running — `true`
        /// while the frontier is sweeping, `false` the moment it settles, including
        /// mid-stream pauses where the frontier catches up to the text so far.
        public var onStreamingRevealActivityChanged: ((Bool) -> Void)? {
            get { textView.onStreamingRevealActivityChanged }
            set { textView.onStreamingRevealActivityChanged = newValue }
        }

        /// Characters from the end at which the activity signal reports `false`
        /// while the tail keeps animating — an early handoff so follow-on UI can
        /// overlap the last beat of the sweep. 0 (default) reports active until
        /// the frontier fully settles.
        public var streamingRevealHandoffCharacters: Double {
            get { textView.streamingRevealHandoffCharacters }
            set { textView.streamingRevealHandoffCharacters = newValue }
        }

        /// Immediately cancels an in-flight reveal (e.g. on cell reuse).
        public func cancelStreamingReveal() {
            textView.cancelStreamingReveal()
        }

        /// Seeds the reveal frontier so a recycled cell continues an in-progress
        /// reveal instead of restarting (forward-only).
        /// Current reveal frontier — capture before cell reuse, re-seed on return.
        public var streamingRevealFrontier: Double {
            textView.streamingRevealFrontier
        }

        public func seedStreamingRevealFrontier(_ position: Double) {
            textView.seedStreamingRevealFrontier(position)
        }

        public func setMarkdownManually(_ content: PreprocessedContent) {
            assert(Thread.isMainThread)
            resetCombine()
            lastRawMarkdown = nil
            lastRootBlockRanges = nil
            lastRenderedBlocks.removeAll()
            lastBuildResult = nil
            use(content)
        }

        public func setMarkdown(_ content: PreprocessedContent) {
            if contentPipelineMode != .preprocessed {
                setupCombine()
            }
            lastRawMarkdown = nil
            lastRootBlockRanges = nil
            contentSubject.send(content)
        }

        /// Sets raw markdown string. Parsing, syntax highlighting, and math rendering
        /// are performed on a background queue. Cancels any in-flight preprocessing
        /// when new content arrives.
        public func setMarkdown(string: String) {
            if contentPipelineMode != .raw {
                setupRawCombine()
            }
            rawContentSubject.send(string)
        }

        public func reset() {
            assert(Thread.isMainThread)
            lastRawMarkdown = nil
            lastRootBlockRanges = nil
            lastRenderedBlocks.removeAll()
            lastBuildResult = nil
            use(.init())
            setupCombine()
        }

        public func bindContentOffset(from scrollView: UIScrollView?) {
            trackedScrollView = scrollView
        }
    }

#elseif canImport(AppKit)
    import AppKit

    public final class MarkdownTextView: NSView {
        public var linkHandler: ((LinkPayload, NSRange, CGPoint) -> Void)?
        public var imageTapHandler: ((String, CGPoint) -> Void)?
        public var codePreviewHandler: ((String?, NSAttributedString) -> Void)?
        public var lineSelectionHandler: LineSelectionHandler?
        public var lineSelectionEndedHandler: LineSelectionHandler?
        /// Called whenever the selected character range changes.
        public var selectionChangeHandler: ((NSRange?) -> Void)?

        public internal(set) var document: PreprocessedContent = .init()
        public let textView: LTXLabel = .init()
        public var theme: MarkdownTheme = .default {
            didSet {
                textView.selectionBackgroundColor = theme.colors.selectionBackground
                setMarkdown(document)
            }
        }

        public internal(set) weak var trackedScrollView: NSScrollView? // for selection updating

        var contextViews: [NSView] = []
        var cancellables = Set<AnyCancellable>()
        let contentSubject = CurrentValueSubject<PreprocessedContent, Never>(.init())
        let rawContentSubject = PassthroughSubject<String, Never>()
        public var throttleInterval: TimeInterval? = 1 / 20 { // x fps
            didSet { setupCombine() }
        }

        let viewProvider: ReusableViewProvider
        var contentPipelineMode: ContentPipelineMode = .none
        var lastRawMarkdown: String?
        var lastRootBlockRanges: [MarkdownParser.RootBlockRange]?
        var lastRenderedBlocks: [MarkdownBlockNode] = []
        var lastBuildResult: TextBuilder.BuildResult?

        public init(viewProvider: ReusableViewProvider = .init()) {
            self.viewProvider = viewProvider
            super.init(frame: .zero)
            textView.isSelectable = true
            textView.selectionBackgroundColor = theme.colors.selectionBackground
            wantsLayer = true
            layer?.backgroundColor = NSColor.clear.cgColor
            textView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(textView)
            NSLayoutConstraint.activate([
                textView.leadingAnchor.constraint(equalTo: leadingAnchor),
                textView.trailingAnchor.constraint(equalTo: trailingAnchor),
                textView.topAnchor.constraint(equalTo: topAnchor),
                textView.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            setAccessibilityElement(false)
            setAccessibilityRole(.group)
            setupCombine()
            observeImageLoading()
        }

        /// Handles line selection from a code or diff view, clearing other blocks (exclusive mode)
        /// and forwarding the selection info to the public handler.
        func handleLineSelection(from sourceView: NSView, info: LineSelectionInfo?) {
            for view in contextViews {
                guard view !== sourceView else { continue }
                if let codeView = view as? CodeView {
                    codeView.clearLineSelection()
                } else if let diffView = view as? DiffView {
                    diffView.clearLineSelection()
                }
            }
            lineSelectionHandler?(info)
        }

        /// Forwards the end-of-gesture selection info to the public `lineSelectionEndedHandler`.
        func handleLineSelectionEnded(from _: NSView, info: LineSelectionInfo?) {
            lineSelectionEndedHandler?(info)
        }

        @available(*, unavailable)
        public required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        override public var isFlipped: Bool {
            true
        }

        override public func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            setMarkdown(document)
        }

        override public func layout() {
            super.layout()
            textView.preferredMaxLayoutWidth = bounds.width
        }

        override public var intrinsicContentSize: CGSize {
            textView.intrinsicContentSize
        }

        public func boundingSize(for width: CGFloat) -> CGSize {
            textView.preferredMaxLayoutWidth = width
            return textView.intrinsicContentSize
        }

        /// Streaming "typing" reveal — forwards to the text label
        /// (see `LTXLabel.streamingReveal`). Set `true` while a message streams.
        public var streamingReveal: Bool {
            get { textView.streamingReveal }
            set { textView.streamingReveal = newValue }
        }

        /// Per-character fade duration for `streamingReveal` (fade softness).
        public var streamingRevealDuration: CFTimeInterval {
            get { textView.streamingRevealDuration }
            set { textView.streamingRevealDuration = newValue }
        }

        /// How fast the reveal sweeps through characters (characters per second).
        /// Bursty arrivals are still revealed left→right at this pace. Lower = slower.
        public var streamingRevealCharactersPerSecond: CGFloat {
            get { textView.streamingRevealCharactersPerSecond }
            set { textView.streamingRevealCharactersPerSecond = newValue }
        }

        /// Fires on the main thread once the reveal has fully settled to opaque
        /// after `streamingReveal` is set back to `false` — the moment the trailing
        /// fade lands. Use to time post-stream UI (e.g. action buttons) so it waits
        /// for the reveal instead of racing the still-fading tail.
        public var onStreamingRevealComplete: (() -> Void)? {
            get { textView.onStreamingRevealComplete }
            set { textView.onStreamingRevealComplete = newValue }
        }

        /// Fires whenever the reveal animation starts or stops running — `true`
        /// while the frontier is sweeping, `false` the moment it settles, including
        /// mid-stream pauses where the frontier catches up to the text so far.
        public var onStreamingRevealActivityChanged: ((Bool) -> Void)? {
            get { textView.onStreamingRevealActivityChanged }
            set { textView.onStreamingRevealActivityChanged = newValue }
        }

        /// Characters from the end at which the activity signal reports `false`
        /// while the tail keeps animating — an early handoff so follow-on UI can
        /// overlap the last beat of the sweep. 0 (default) reports active until
        /// the frontier fully settles.
        public var streamingRevealHandoffCharacters: Double {
            get { textView.streamingRevealHandoffCharacters }
            set { textView.streamingRevealHandoffCharacters = newValue }
        }

        /// Immediately cancels an in-flight reveal (e.g. on cell reuse).
        public func cancelStreamingReveal() {
            textView.cancelStreamingReveal()
        }

        /// Seeds the reveal frontier so a recycled cell continues an in-progress
        /// reveal instead of restarting (forward-only).
        /// Current reveal frontier — capture before cell reuse, re-seed on return.
        public var streamingRevealFrontier: Double {
            textView.streamingRevealFrontier
        }

        public func seedStreamingRevealFrontier(_ position: Double) {
            textView.seedStreamingRevealFrontier(position)
        }

        public func setMarkdownManually(_ content: PreprocessedContent) {
            assert(Thread.isMainThread)
            resetCombine()
            lastRawMarkdown = nil
            lastRootBlockRanges = nil
            lastRenderedBlocks.removeAll()
            lastBuildResult = nil
            use(content)
        }

        public func setMarkdown(_ content: PreprocessedContent) {
            if contentPipelineMode != .preprocessed {
                setupCombine()
            }
            lastRawMarkdown = nil
            lastRootBlockRanges = nil
            contentSubject.send(content)
        }

        /// Sets raw markdown string. Parsing, syntax highlighting, and math rendering
        /// are performed on a background queue. Cancels any in-flight preprocessing
        /// when new content arrives.
        public func setMarkdown(string: String) {
            if contentPipelineMode != .raw {
                setupRawCombine()
            }
            rawContentSubject.send(string)
        }

        public func reset() {
            assert(Thread.isMainThread)
            lastRawMarkdown = nil
            lastRootBlockRanges = nil
            lastRenderedBlocks.removeAll()
            lastBuildResult = nil
            use(.init())
            setupCombine()
        }

        public func bindContentOffset(from scrollView: NSScrollView?) {
            trackedScrollView = scrollView
        }
    }
#endif
