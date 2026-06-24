//
//  Created by Lakr233 & Helixform on 2025/2/18.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreFoundation
import CoreText
import Foundation
import QuartzCore

public class LTXLabel: LTXPlatformView, Identifiable {
    public let id: UUID = .init()

    // MARK: - Public Properties

    public var attributedText: NSAttributedString = .init() {
        didSet {
            // Rebuilding the layout recreates the CTFramesetter and triggers a
            // full relayout; skip it when the content is unchanged.
            guard !attributedText.isEqual(to: oldValue) else { return }
            textLayout = LTXTextLayout(attributedString: attributedText)
            handleRevealTextChange()
        }
    }

    // MARK: - Streaming reveal

    /// When `true`, characters appended to `attributedText` fade in (left→right as
    /// they arrive) instead of appearing instantly — the streaming "typing" reveal.
    /// Each character fades over `streamingRevealDuration` from when it first
    /// appears, so text flowing across several labels composes into one
    /// continuous stream. Set back to `false` when the stream finishes; in-flight
    /// fades still settle.
    public var streamingReveal: Bool = false {
        didSet { handleStreamingRevealChanged() }
    }

    /// Per-character fade duration for `streamingReveal` (how soft the fade edge is).
    public var streamingRevealDuration: CFTimeInterval = 0.4

    /// How fast the reveal sweeps through characters, in characters per second.
    /// A burst of text that arrives at once is still revealed left→right at this
    /// pace (rather than fading in as one block). Lower = slower / more deliberate.
    public var streamingRevealCharactersPerSecond: CGFloat = 90

    /// Optional group key that sequences the reveal across multiple labels. Labels
    /// sharing a group reveal in append order (block 1, then 2, …) as one
    /// top-to-bottom cascade — set this to the same value on every label that makes
    /// up a single streamed response (e.g. one response split across many cells).
    /// `nil` (default) keeps each label on its own clock.
    public var streamingRevealGroup: String?

    /// Wall-clock appearance time per character index; empty when not revealing.
    /// Times may be scheduled slightly into the future so a bursty arrival reveals
    /// as a paced sweep instead of all at once.
    var revealAppearance: [CFTimeInterval] = []
    /// The scheduled appearance time for the next character — the "typewriter"
    /// cursor that carries pacing across batches.
    var revealCursor: CFTimeInterval = 0
    /// Latest scheduled appearance — the reveal settles `duration` after this.
    var revealLastStamp: CFTimeInterval = 0
    /// True while any character is still mid-fade (drives the per-glyph draw path).
    var revealActive: Bool = false
    #if canImport(UIKit)
        var revealDisplayLink: CADisplayLink?
    #else
        var revealTimer: Timer?
    #endif

    public var preferredMaxLayoutWidth: CGFloat = 0 {
        didSet {
            if preferredMaxLayoutWidth != oldValue {
                invalidateTextLayout()
            }
        }
    }

    override public var frame: CGRect {
        get { super.frame }
        set {
            guard newValue != super.frame else { return }
            super.frame = newValue
            invalidateTextLayout()
        }
    }

    public var isSelectable: Bool = false {
        didSet { if !isSelectable { clearSelection() } }
    }

    public var longPressSelectsWord: Bool = true

    public var selectionBackgroundColor: PlatformColor? {
        didSet { updateSelectionLayer() }
    }

    public internal(set) var isInteractionInProgress = false

    /// Custom menu items shown in the text selection context menu. Maximum 10 items.
    public var customMenuItems: [LTXCustomMenuItem] = [] {
        didSet {
            customMenuItems = Array(customMenuItems.prefix(10))
        }
    }

    /// Controls where custom menu items appear relative to built-in items.
    /// Only affects Mac Catalyst and macOS; iOS UIMenuController always shows built-in items first.
    public var customMenuItemPosition: LTXCustomMenuItemPosition = .afterBuiltIn

    public weak var delegate: LTXLabelDelegate?

    // MARK: - Internal Properties

    var textLayout: LTXTextLayout = .init(attributedString: .init()) {
        didSet { invalidateTextLayout() }
    }

    var attachmentViews: Set<LTXPlatformView> = []
    var highlightRegions: [LTXHighlightRegion] {
        textLayout.highlightRegions
    }

    var activeHighlightRegion: LTXHighlightRegion?
    var lastContainerSize: CGSize = .zero

    public internal(set) var selectionRange: NSRange? {
        didSet {
            updateSelectionLayer()
            if selectionRange != oldValue {
                delegate?.ltxLabelSelectionDidChange(self, selection: selectionRange)
            }
        }
    }

    var selectedLinkForMenuAction: URL?
    var selectionLayer: CAShapeLayer?

    #if canImport(UIKit) && !targetEnvironment(macCatalyst) && !os(tvOS) && !os(watchOS)
        var selectionHandleStart: LTXSelectionHandle = .init(type: .start)
        var selectionHandleEnd: LTXSelectionHandle = .init(type: .end)
    #endif

    var interactionState = InteractionState()
    var flags = Flags()

    // MARK: - Initialization

    #if canImport(UIKit)
        override public init(frame: CGRect) {
            super.init(frame: frame)
            registerNotificationCenterForSelectionDeduplicate()
            configureAccessibility()

            backgroundColor = .clear
            #if !os(tvOS) && !os(watchOS)
                installContextMenuInteraction()
                installTextPointerInteraction()
            #endif

            #if !os(tvOS)
                isMultipleTouchEnabled = false
                isExclusiveTouch = true
            #endif

            #if !targetEnvironment(macCatalyst) && !os(tvOS) && !os(watchOS)
                clipsToBounds = false // for selection handle
                selectionHandleStart.isHidden = true
                selectionHandleStart.delegate = self
                addSubview(selectionHandleStart)
                selectionHandleEnd.isHidden = true
                selectionHandleEnd.delegate = self
                addSubview(selectionHandleEnd)
            #endif
        }

    #elseif canImport(AppKit)
        override public init(frame: CGRect) {
            super.init(frame: frame)
            registerNotificationCenterForSelectionDeduplicate()
            configureAccessibility()
            wantsLayer = true
            layer?.backgroundColor = NSColor.clear.cgColor
        }
    #endif

    public convenience init(frame: CGRect = .zero, attributedText: NSAttributedString) {
        self.init(frame: frame)
        self.attributedText = attributedText
    }

    @available(*, unavailable)
    public required init?(coder _: NSCoder) {
        fatalError()
    }

    deinit {
        stopRevealDriver()
        cancelLongPressTimer()
        attributedText = .init()
        attachmentViews = []
        clearSelection()
        deactivateHighlightRegion()
        NotificationCenter.default.removeObserver(self)
    }

    #if canImport(UIKit)
        override public func didMoveToWindow() {
            super.didMoveToWindow()
            clearSelection()
            invalidateTextLayout()
        }

    #elseif canImport(AppKit)
        override public func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            clearSelection()
            invalidateTextLayout()
        }

        public var backgroundColor: NSColor? {
            get {
                guard let cgColor = layer?.backgroundColor else { return nil }
                return NSColor(cgColor: cgColor)
            }
            set {
                wantsLayer = true
                layer?.backgroundColor = newValue?.cgColor
            }
        }
    #endif
}

extension LTXLabel {
    struct InteractionState {
        var initialTouchLocation: CGPoint = .zero
        var clickCount: Int = 1
        var lastClickTime: TimeInterval = 0
        var isFirstMove: Bool = false
        var longPressWorkItem: DispatchWorkItem?
        #if canImport(UIKit) && !os(tvOS) && !os(watchOS)
            var feedbackGenerator: UIImpactFeedbackGenerator?
        #endif
    }

    struct Flags {
        var layoutIsDirty: Bool = false
        var needsUpdateHighlightRegions: Bool = false
    }
}
