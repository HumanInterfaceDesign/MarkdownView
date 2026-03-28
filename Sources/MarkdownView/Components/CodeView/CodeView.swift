//
//  Created by ktiays on 2025/1/22.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

import Litext

#if canImport(UIKit)
    import UIKit

    final class CodeView: UIView {
        // MARK: - CONTENT

        var theme: MarkdownTheme = .default {
            didSet {
                languageLabel.font = theme.fonts.code
                languageLabel.textColor = theme.colors.body
                copyButton.tintColor = theme.colors.body
                previewButton.tintColor = theme.colors.body
                textView.selectionBackgroundColor = theme.colors.selectionBackground
                updateHeaderVisibility()
                setNeedsLayout()
                invalidateIntrinsicContentSize()
                updateLineNumberView()
            }
        }

        var language: String = "" {
            didSet {
                languageLabel.text = language.isEmpty ? "</>" : language
            }
        }

        var highlightMap: CodeHighlighter.HighlightMap = .init()

        private var cachedLineCount: Int = 1

        var content: String = "" {
            didSet {
                guard oldValue != content else { return }
                cachedLineCount = CodeViewConfiguration.lineCount(of: content)
                textView.attributedText = highlightMap.apply(to: content, with: theme)
                lineNumberView.updateForContent(content)
                updateLineNumberView()
                clearLineSelection()
            }
        }

        // MARK: CONTENT -

        var previewAction: ((String?, NSAttributedString) -> Void)? {
            didSet {
                updateHeaderVisibility()
                invalidateIntrinsicContentSize()
                setNeedsLayout()
            }
        }

        // MARK: - LINE SELECTION

        var isLineSelectionEnabled = false {
            didSet {
                guard isLineSelectionEnabled != oldValue else { return }
                textView.isSelectable = !isLineSelectionEnabled
                if isLineSelectionEnabled {
                    let tap = UITapGestureRecognizer(target: self, action: #selector(handleLineTap(_:)))
                    addGestureRecognizer(tap)
                    lineTapGesture = tap

                    let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLineLongPress(_:)))
                    longPress.minimumPressDuration = 0.15
                    addGestureRecognizer(longPress)
                    lineLongPressGesture = longPress
                } else {
                    if let g = lineTapGesture { removeGestureRecognizer(g); lineTapGesture = nil }
                    if let g = lineLongPressGesture { removeGestureRecognizer(g); lineLongPressGesture = nil }
                }
            }
        }

        var lineSelectionHandler: LineSelectionHandler?
        private(set) var selectedLineRange: ClosedRange<Int>?
        lazy var selectionOverlay: LineSelectionOverlayView = .init()
        private var dragAnchorLine: Int?
        private var lineTapGesture: UITapGestureRecognizer?
        private var lineLongPressGesture: UILongPressGestureRecognizer?

        func clearLineSelection() {
            guard selectedLineRange != nil else { return }
            selectedLineRange = nil
            selectionOverlay.clearSelection()
        }

        private func lineIndex(at point: CGPoint) -> Int? {
            let localPoint = scrollView.convert(point, from: self)
            let contentPoint = CGPoint(
                x: localPoint.x + scrollView.contentOffset.x,
                y: localPoint.y + scrollView.contentOffset.y
            )
            let font = theme.fonts.code
            let lineHeight = font.lineHeight
            let rowAdvance = lineHeight + CodeViewConfiguration.codeLineSpacing
            let barHeight = CodeViewConfiguration.barHeight(theme: theme)
            let adjustedY = contentPoint.y
            guard adjustedY >= CodeViewConfiguration.codePadding else { return nil }
            let line = Int((adjustedY - CodeViewConfiguration.codePadding) / rowAdvance) + 1
            guard line >= 1, line <= cachedLineCount else { return nil }
            return line
        }

        private func updateLineSelection(_ range: ClosedRange<Int>?) {
            selectedLineRange = range
            selectionOverlay.selectedRange = range
            if let range = range {
                let lines = content.components(separatedBy: .newlines)
                let contents = (range.lowerBound...range.upperBound).compactMap { idx -> String? in
                    let arrayIdx = idx - 1
                    guard arrayIdx >= 0, arrayIdx < lines.count else { return nil }
                    return lines[arrayIdx]
                }
                let info = LineSelectionInfo(
                    lineRange: range,
                    contents: contents,
                    language: language.isEmpty ? nil : language
                )
                lineSelectionHandler?(info)
            } else {
                lineSelectionHandler?(nil)
            }
        }

        @objc func handleLineTap(_ gesture: UITapGestureRecognizer) {
            let point = gesture.location(in: self)
            guard let line = lineIndex(at: point) else { return }
            if selectedLineRange == line...line {
                updateLineSelection(nil)
            } else {
                updateLineSelection(line...line)
            }
            #if !os(visionOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        }

        @objc func handleLineLongPress(_ gesture: UILongPressGestureRecognizer) {
            let point = gesture.location(in: self)
            switch gesture.state {
            case .began:
                guard let line = lineIndex(at: point) else { return }
                dragAnchorLine = line
                updateLineSelection(line...line)
                #if !os(visionOS)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
            case .changed:
                guard let anchor = dragAnchorLine,
                      let line = lineIndex(at: point) else { return }
                let newRange = min(anchor, line)...max(anchor, line)
                if newRange != selectedLineRange {
                    updateLineSelection(newRange)
                    #if !os(visionOS)
                        UISelectionFeedbackGenerator().selectionChanged()
                    #endif
                }
            case .ended, .cancelled, .failed:
                dragAnchorLine = nil
            default:
                break
            }
        }

        // MARK: LINE SELECTION -

        private let callerIdentifier = UUID()
        private var currentTaskIdentifier: UUID?

        lazy var barView: UIView = .init()
        lazy var scrollView: UIScrollView = .init()
        lazy var languageLabel: UILabel = .init()
        lazy var textView: LTXLabel = .init()
        lazy var copyButton: UIButton = .init()
        lazy var previewButton: UIButton = .init()
        lazy var lineNumberView: LineNumberView = .init()

        override init(frame: CGRect) {
            super.init(frame: frame)
            configureSubviews()
            updateLineNumberView()
            isAccessibilityElement = false
            accessibilityElements = []
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        static func intrinsicHeight(for content: String, theme: MarkdownTheme = .default) -> CGFloat {
            CodeViewConfiguration.intrinsicHeight(for: content, theme: theme)
        }

        override var accessibilityLabel: String? {
            get {
                let lang = language.isEmpty ? "Code" : language
                return "\(lang) code block"
            }
            set { /* read-only */ }
        }

        override var accessibilityValue: String? {
            get { content }
            set { /* read-only */ }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            performLayout()
            updateLineNumberView()
        }

        override var intrinsicContentSize: CGSize {
            let labelSize = languageLabel.intrinsicContentSize
            let barHeight = CodeViewConfiguration.barHeight(theme: theme)
            let textSize = textView.intrinsicContentSize
            let supposedHeight = CodeViewConfiguration.intrinsicHeight(
                for: content, lineCount: cachedLineCount, theme: theme
            )

            let lineNumberWidth = lineNumberView.intrinsicContentSize.width
            let headerWidth = theme.showsBlockHeaders
                ? labelSize.width + CodeViewConfiguration.barPadding * 2
                : 0

            return CGSize(
                width: max(
                    headerWidth,
                    lineNumberWidth + textSize.width + CodeViewConfiguration.codePadding * 2
                ),
                height: max(
                    barHeight + textSize.height + CodeViewConfiguration.codePadding * 2,
                    supposedHeight
                )
            )
        }

        @objc func handleCopy(_: UIButton) {
            UIPasteboard.general.string = content
            #if !os(visionOS)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
        }

        @objc func handlePreview(_: UIButton) {
            #if !os(visionOS)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
            previewAction?(language, textView.attributedText)
        }

        func updateLineNumberView() {
            let font = theme.fonts.code
            lineNumberView.textColor = theme.colors.body.withAlphaComponent(0.5)

            let lineCount = max(cachedLineCount, 1)
            let textViewContentHeight = textView.intrinsicContentSize.height

            lineNumberView.configure(
                lineCount: lineCount,
                contentHeight: textViewContentHeight,
                font: font,
                textColor: .secondaryLabel
            )

            lineNumberView.padding = UIEdgeInsets(
                top: CodeViewConfiguration.codePadding,
                left: CodeViewConfiguration.lineNumberPadding,
                bottom: CodeViewConfiguration.codePadding,
                right: CodeViewConfiguration.lineNumberPadding
            )
        }

        func updateHeaderVisibility() {
            let showsHeader = theme.showsBlockHeaders
            barView.isHidden = !showsHeader
            languageLabel.isHidden = !showsHeader
            copyButton.isHidden = !showsHeader
            previewButton.isHidden = !showsHeader || previewAction == nil
        }
    }

    extension CodeView: LTXAttributeStringRepresentable {
        func attributedStringRepresentation() -> NSAttributedString {
            textView.attributedText
        }
    }

#elseif canImport(AppKit)
    import AppKit

    final class CodeView: NSView {
        var theme: MarkdownTheme = .default {
            didSet {
                languageLabel.font = theme.fonts.code
                languageLabel.textColor = theme.colors.body
                copyButton.contentTintColor = theme.colors.body
                previewButton.contentTintColor = theme.colors.body
                textView.selectionBackgroundColor = theme.colors.selectionBackground
                updateHeaderVisibility()
                needsLayout = true
                invalidateIntrinsicContentSize()
                updateLineNumberView()
            }
        }

        var language: String = "" {
            didSet {
                languageLabel.stringValue = language.isEmpty ? "</>" : language
            }
        }

        var highlightMap: CodeHighlighter.HighlightMap = .init()

        private var cachedLineCount: Int = 1

        var content: String = "" {
            didSet {
                guard oldValue != content else { return }
                cachedLineCount = CodeViewConfiguration.lineCount(of: content)
                textView.attributedText = highlightMap.apply(to: content, with: theme)
                lineNumberView.updateForContent(content)
                updateLineNumberView()
                clearLineSelection()
            }
        }

        var previewAction: ((String?, NSAttributedString) -> Void)? {
            didSet {
                updateHeaderVisibility()
                invalidateIntrinsicContentSize()
                needsLayout = true
            }
        }

        // MARK: - LINE SELECTION

        var isLineSelectionEnabled = false {
            didSet { textView.isSelectable = !isLineSelectionEnabled }
        }

        var lineSelectionHandler: LineSelectionHandler?
        private(set) var selectedLineRange: ClosedRange<Int>?
        lazy var selectionOverlay: LineSelectionOverlayView = .init()
        private var dragAnchorLine: Int?

        func clearLineSelection() {
            guard selectedLineRange != nil else { return }
            selectedLineRange = nil
            selectionOverlay.clearSelection()
        }

        private func lineIndex(at point: CGPoint) -> Int? {
            let localPoint = convert(point, from: nil)
            let font = theme.fonts.code
            let lineHeight = font.ascender + abs(font.descender) + font.leading
            let rowAdvance = lineHeight + CodeViewConfiguration.codeLineSpacing
            let barHeight = CodeViewConfiguration.barHeight(theme: theme)
            let adjustedY = localPoint.y - barHeight
            guard adjustedY >= CodeViewConfiguration.codePadding else { return nil }
            let line = Int((adjustedY - CodeViewConfiguration.codePadding) / rowAdvance) + 1
            guard line >= 1, line <= cachedLineCount else { return nil }
            return line
        }

        private func updateLineSelection(_ range: ClosedRange<Int>?) {
            selectedLineRange = range
            selectionOverlay.selectedRange = range
            if let range = range {
                let lines = content.components(separatedBy: .newlines)
                let contents = (range.lowerBound...range.upperBound).compactMap { idx -> String? in
                    let arrayIdx = idx - 1
                    guard arrayIdx >= 0, arrayIdx < lines.count else { return nil }
                    return lines[arrayIdx]
                }
                let info = LineSelectionInfo(
                    lineRange: range,
                    contents: contents,
                    language: language.isEmpty ? nil : language
                )
                lineSelectionHandler?(info)
            } else {
                lineSelectionHandler?(nil)
            }
        }

        override func mouseDown(with event: NSEvent) {
            guard isLineSelectionEnabled else {
                super.mouseDown(with: event)
                return
            }
            let point = convert(event.locationInWindow, from: nil)
            guard let line = lineIndex(at: point) else {
                super.mouseDown(with: event)
                return
            }
            dragAnchorLine = line
            if selectedLineRange == line...line {
                updateLineSelection(nil)
            } else {
                updateLineSelection(line...line)
            }
        }

        override func mouseDragged(with event: NSEvent) {
            guard isLineSelectionEnabled else {
                super.mouseDragged(with: event)
                return
            }
            let point = convert(event.locationInWindow, from: nil)
            guard let anchor = dragAnchorLine,
                  let line = lineIndex(at: point) else { return }
            let newRange = min(anchor, line)...max(anchor, line)
            if newRange != selectedLineRange {
                updateLineSelection(newRange)
            }
        }

        override func mouseUp(with event: NSEvent) {
            dragAnchorLine = nil
            super.mouseUp(with: event)
        }

        // MARK: LINE SELECTION -

        private let callerIdentifier = UUID()
        private var currentTaskIdentifier: UUID?

        lazy var barView: NSView = .init()
        lazy var scrollView: NSScrollView = {
            let sv = NSScrollView()
            sv.hasVerticalScroller = false
            sv.hasHorizontalScroller = false
            sv.drawsBackground = false
            return sv
        }()

        lazy var languageLabel: NSTextField = {
            let label = NSTextField(labelWithString: "")
            label.isEditable = false
            label.isBordered = false
            label.backgroundColor = .clear
            return label
        }()

        lazy var textView: LTXLabel = .init()
        lazy var copyButton: NSButton = .init(title: "", target: nil, action: nil)
        lazy var previewButton: NSButton = .init(title: "", target: nil, action: nil)
        lazy var lineNumberView: LineNumberView = .init()

        override init(frame: CGRect) {
            super.init(frame: frame)
            configureSubviews()
            updateLineNumberView()
            setAccessibilityElement(false)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var isFlipped: Bool {
            true
        }

        override func accessibilityLabel() -> String? {
            let lang = language.isEmpty ? "Code" : language
            return "\(lang) code block"
        }

        override func accessibilityValue() -> Any? {
            content
        }

        static func intrinsicHeight(for content: String, theme: MarkdownTheme = .default) -> CGFloat {
            CodeViewConfiguration.intrinsicHeight(for: content, theme: theme)
        }

        override func layout() {
            super.layout()
            performLayout()
            updateLineNumberView()
        }

        override var intrinsicContentSize: CGSize {
            let labelSize = languageLabel.intrinsicContentSize
            let barHeight = CodeViewConfiguration.barHeight(theme: theme)
            let textSize = textView.intrinsicContentSize
            let supposedHeight = CodeViewConfiguration.intrinsicHeight(
                for: content, lineCount: cachedLineCount, theme: theme
            )

            let lineNumberWidth = lineNumberView.intrinsicContentSize.width
            let headerWidth = theme.showsBlockHeaders
                ? labelSize.width + CodeViewConfiguration.barPadding * 2
                : 0

            return CGSize(
                width: max(
                    headerWidth,
                    lineNumberWidth + textSize.width + CodeViewConfiguration.codePadding * 2
                ),
                height: max(
                    barHeight + textSize.height + CodeViewConfiguration.codePadding * 2,
                    supposedHeight
                )
            )
        }

        @objc func handleCopy(_: Any?) {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(content, forType: .string)
        }

        @objc func handlePreview(_: Any?) {
            previewAction?(language, textView.attributedText)
        }

        func updateLineNumberView() {
            let font = theme.fonts.code
            lineNumberView.textColor = theme.colors.body.withAlphaComponent(0.5)

            let lineCount = max(cachedLineCount, 1)
            let textViewContentHeight = textView.intrinsicContentSize.height

            lineNumberView.configure(
                lineCount: lineCount,
                contentHeight: textViewContentHeight,
                font: font,
                textColor: .secondaryLabelColor
            )

            lineNumberView.padding = NSEdgeInsets(
                top: CodeViewConfiguration.codePadding,
                left: CodeViewConfiguration.lineNumberPadding,
                bottom: CodeViewConfiguration.codePadding,
                right: CodeViewConfiguration.lineNumberPadding
            )
        }

        func updateHeaderVisibility() {
            let showsHeader = theme.showsBlockHeaders
            barView.isHidden = !showsHeader
            languageLabel.isHidden = !showsHeader
            copyButton.isHidden = !showsHeader
            previewButton.isHidden = !showsHeader || previewAction == nil
        }
    }

    extension CodeView: LTXAttributeStringRepresentable {
        func attributedStringRepresentation() -> NSAttributedString {
            textView.attributedText
        }
    }
#endif
