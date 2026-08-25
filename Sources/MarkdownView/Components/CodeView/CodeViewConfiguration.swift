//
//  Created by ktiays on 2025/1/22.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

import Litext

private func offsetCodeLineRects(
    _ lineRects: [CGRect],
    by origin: CGPoint
) -> [CGRect] {
    lineRects.map { $0.offsetBy(dx: origin.x, dy: origin.y) }
}

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

enum CodeViewConfiguration {
    static let barPadding: CGFloat = 8
    static let buttonSize = CGSize(width: 32, height: 32)
    static let codePadding: CGFloat = 8
    static let codeLineSpacing: CGFloat = 4
    static let lineNumberWidth: CGFloat = 40
    static let lineNumberPadding: CGFloat = 8

    /// Count newlines in O(n) without allocating an array of substrings.
    static func lineCount(of string: String) -> Int {
        guard !string.isEmpty else { return 1 }
        var count = 1
        for char in string.utf8 {
            if char == UInt8(ascii: "\n") { count += 1 }
        }
        return count
    }

    static func intrinsicHeight(
        for content: String,
        lineCount: Int? = nil,
        theme: MarkdownTheme = .default
    ) -> CGFloat {
        let barHeight = Self.barHeight(theme: theme)
        let font = theme.fonts.code
        #if canImport(UIKit)
            let lineHeight = font.lineHeight
        #elseif canImport(AppKit)
            let lineHeight = font.ascender + abs(font.descender) + font.leading
        #endif
        let numberOfRows = lineCount ?? Self.lineCount(of: content)
        let codeHeight = lineHeight * CGFloat(numberOfRows)
            + codePadding * 2
            + codeLineSpacing * CGFloat(max(numberOfRows - 1, 0))
        return ceil(barHeight + codeHeight)
    }

    /// Width available for wrapped code text inside a view of `viewWidth`,
    /// after the line-number gutter and horizontal padding.
    static func wrappedTextWidth(forViewWidth viewWidth: CGFloat, lineNumberWidth: CGFloat) -> CGFloat {
        max(viewWidth - lineNumberWidth - codePadding * 2, 40)
    }

    static func barHeight(theme: MarkdownTheme = .default) -> CGFloat {
        guard theme.showsBlockHeaders else { return 0 }
        let font = theme.fonts.code
        #if canImport(UIKit)
            let lineHeight = font.lineHeight
        #elseif canImport(AppKit)
            let lineHeight = font.ascender + abs(font.descender) + font.leading
        #endif
        return max(lineHeight + barPadding * 2, buttonSize.height)
    }
}

#if canImport(UIKit)
    extension CodeView {
        func configureSubviews() {
            setupViewAppearance()
            setupBarView()
            setupButtons()
            setupScrollView()
            setupTextView()
            setupLineNumberView()
            setupSelectionOverlay()
            updateHeaderVisibility()
        }

        private func setupViewAppearance() {
            layer.cornerRadius = 8
            layer.cornerCurve = .continuous
            clipsToBounds = true
            backgroundColor = .gray.withAlphaComponent(0.05)
        }

        private func setupBarView() {
            barView.backgroundColor = .gray.withAlphaComponent(0.05)
            languageLabel.textColor = theme.colors.body
            addSubview(barView)
            barView.addSubview(languageLabel)
        }

        private func setupButtons() {
            setupPreviewButton()
            setupCopyButton()
        }

        private func setupPreviewButton() {
            let previewImage = UIImage(
                systemName: "eye",
                withConfiguration: UIImage.SymbolConfiguration(scale: .small)
            )
            previewButton.setImage(previewImage, for: .normal)
            previewButton.tintColor = theme.colors.body
            previewButton.addTarget(self, action: #selector(handlePreview(_:)), for: .touchUpInside)
            barView.addSubview(previewButton)
        }

        private func setupCopyButton() {
            copyButton.tintColor = theme.colors.body
            copyButton.onTap { [weak self] in
                self?.handleCopy()
            }
            barView.addSubview(copyButton)
        }

        private func setupScrollView() {
            scrollView.showsVerticalScrollIndicator = false
            scrollView.showsHorizontalScrollIndicator = false
            scrollView.alwaysBounceVertical = false
            scrollView.alwaysBounceHorizontal = false
            addSubview(scrollView)
        }

        private func setupTextView() {
            textView.backgroundColor = .clear
            textView.preferredMaxLayoutWidth = .infinity
            textView.isSelectable = true
            textView.selectionBackgroundColor = theme.colors.selectionBackground
            scrollView.addSubview(textView)
        }

        private func setupLineNumberView() {
            lineNumberView.backgroundColor = .clear
            addSubview(lineNumberView)
            updateLineNumberView()
        }

        private func setupSelectionOverlay() {
            selectionOverlay.isUserInteractionEnabled = false
            let selectionColor = theme.colors.lineSelectionBackground
                ?? theme.colors.selectionTint.withAlphaComponent(0.15)
            selectionOverlay.selectionColor = selectionColor
            scrollView.addSubview(selectionOverlay)
        }

        func performLayout() {
            let labelSize = languageLabel.intrinsicContentSize
            let barHeight = CodeViewConfiguration.barHeight(theme: theme)

            layoutBarView(barHeight: barHeight, labelSize: labelSize)
            layoutButtons()
            layoutLineNumberView(barHeight: barHeight)
            layoutScrollViewAndTextView(barHeight: barHeight)
        }

        private func layoutButtons() {
            guard theme.showsBlockHeaders else {
                copyButton.isHidden = true
                previewButton.isHidden = true
                return
            }

            let buttonSize = CodeViewConfiguration.buttonSize
            let hasPreview = previewAction != nil

            if hasPreview {
                copyButton.frame = CGRect(
                    x: barView.bounds.width - buttonSize.width,
                    y: (barView.bounds.height - buttonSize.height) / 2,
                    width: buttonSize.width,
                    height: buttonSize.height
                )
                previewButton.isHidden = false
                previewButton.frame = CGRect(
                    x: copyButton.frame.minX - buttonSize.width,
                    y: (barView.bounds.height - buttonSize.height) / 2,
                    width: buttonSize.width,
                    height: buttonSize.height
                )
            } else {
                copyButton.frame = CGRect(
                    x: barView.bounds.width - buttonSize.width,
                    y: (barView.bounds.height - buttonSize.height) / 2,
                    width: buttonSize.width,
                    height: buttonSize.height
                )
                previewButton.isHidden = true
            }
        }

        private func layoutBarView(barHeight: CGFloat, labelSize: CGSize) {
            guard theme.showsBlockHeaders else {
                barView.frame = .zero
                languageLabel.frame = .zero
                return
            }

            barView.frame = CGRect(origin: .zero, size: CGSize(width: bounds.width, height: barHeight))
            languageLabel.frame = CGRect(
                origin: CGPoint(x: CodeViewConfiguration.barPadding, y: CodeViewConfiguration.barPadding),
                size: labelSize
            )
        }

        private func layoutLineNumberView(barHeight: CGFloat) {
            let lineNumberSize = lineNumberView.intrinsicContentSize
            lineNumberView.frame = CGRect(
                x: 0,
                y: barHeight,
                width: lineNumberSize.width,
                height: bounds.height - barHeight
            )
        }

        private func layoutScrollViewAndTextView(barHeight: CGFloat) {
            let lineNumberWidth = lineNumberView.intrinsicContentSize.width

            scrollView.frame = CGRect(
                x: lineNumberWidth,
                y: barHeight,
                width: bounds.width - lineNumberWidth,
                height: bounds.height - barHeight
            )

            let availableTextWidth = scrollView.bounds.width - CodeViewConfiguration.codePadding * 2
            textView.preferredMaxLayoutWidth = theme.wrapsCodeBlockLines
                ? max(availableTextWidth, 40)
                : .infinity
            let textContentSize = textView.intrinsicContentSize

            textView.frame = CGRect(
                x: CodeViewConfiguration.codePadding,
                y: CodeViewConfiguration.codePadding,
                width: theme.wrapsCodeBlockLines
                    ? max(availableTextWidth, 40)
                    : max(availableTextWidth, textContentSize.width),
                height: textContentSize.height
            )

            scrollView.contentSize = CGSize(
                width: theme.wrapsCodeBlockLines
                    ? scrollView.bounds.width
                    : textView.frame.width + CodeViewConfiguration.codePadding * 2,
                height: 0
            )

            textView.setNeedsLayout()
            textView.layoutIfNeeded()
            let resolvedLineRects = offsetCodeLineRects(
                textView.lineRects(),
                by: textView.frame.origin
            )
            lineNumberView.updateLineRects(logicalLineStartRects(from: resolvedLineRects))

            selectionOverlay.frame = CGRect(
                origin: .zero,
                size: CGSize(
                    width: scrollView.contentSize.width,
                    height: max(textView.frame.maxY + CodeViewConfiguration.codePadding, scrollView.bounds.height)
                )
            )
            selectionOverlay.updateLineRects(resolvedLineRects)

            let selectionColor = theme.colors.lineSelectionBackground
                ?? theme.colors.selectionTint.withAlphaComponent(0.15)
            selectionOverlay.selectionColor = selectionColor
        }

        /// With soft wrapping a logical line spans several visual rows; the
        /// gutter should number only the row each logical line starts on.
        func logicalLineStartRects(from visualRects: [CGRect]) -> [CGRect] {
            guard theme.wrapsCodeBlockLines else { return visualRects }
            let ranges = textView.lineStringRanges()
            guard ranges.count == visualRects.count else { return visualRects }
            let text = content as NSString
            var starts: [CGRect] = []
            starts.reserveCapacity(ranges.count)
            for (index, range) in ranges.enumerated() {
                let location = range.location
                if location == 0
                    || (location - 1 < text.length && text.character(at: location - 1) == 0x0A)
                {
                    starts.append(visualRects[index])
                }
            }
            return starts
        }
    }

#elseif canImport(AppKit)
    extension CodeView {
        func configureSubviews() {
            setupViewAppearance()
            setupBarView()
            setupButtons()
            setupScrollView()
            setupTextView()
            setupLineNumberView()
            setupLineSelectionOverlay()
            updateHeaderVisibility()
        }

        private func setupViewAppearance() {
            wantsLayer = true
            layer?.cornerRadius = 8
            layer?.backgroundColor = NSColor.gray.withAlphaComponent(0.05).cgColor
        }

        private func setupBarView() {
            barView.wantsLayer = true
            barView.layer?.backgroundColor = NSColor.gray.withAlphaComponent(0.05).cgColor
            languageLabel.textColor = theme.colors.body
            addSubview(barView)
            barView.addSubview(languageLabel)
        }

        private func setupButtons() {
            setupPreviewButton()
            setupCopyButton()
        }

        private func setupPreviewButton() {
            if let previewImage = NSImage(systemSymbolName: "eye", accessibilityDescription: nil) {
                previewButton.image = previewImage
            }
            previewButton.target = self
            previewButton.action = #selector(handlePreview(_:))
            previewButton.bezelStyle = .inline
            previewButton.isBordered = false
            previewButton.contentTintColor = theme.colors.body
            barView.addSubview(previewButton)
        }

        private func setupCopyButton() {
            if let copyImage = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil) {
                copyButton.image = copyImage
            }
            copyButton.target = self
            copyButton.action = #selector(handleCopy(_:))
            copyButton.bezelStyle = .inline
            copyButton.isBordered = false
            copyButton.contentTintColor = theme.colors.body
            barView.addSubview(copyButton)
        }

        private func setupScrollView() {
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            scrollView.drawsBackground = false
            scrollView.automaticallyAdjustsContentInsets = false
            scrollView.contentInsets = NSEdgeInsets(
                top: CodeViewConfiguration.codePadding,
                left: CodeViewConfiguration.codePadding,
                bottom: CodeViewConfiguration.codePadding,
                right: CodeViewConfiguration.codePadding
            )
            addSubview(scrollView)
        }

        private func setupTextView() {
            textView.wantsLayer = true
            textView.layer?.backgroundColor = NSColor.clear.cgColor
            textView.preferredMaxLayoutWidth = .infinity
            textView.isSelectable = true
            textView.selectionBackgroundColor = theme.colors.selectionBackground
            scrollView.documentView = textView
        }

        private func setupLineNumberView() {
            lineNumberView.wantsLayer = true
            lineNumberView.layer?.backgroundColor = NSColor.clear.cgColor
            addSubview(lineNumberView)
            updateLineNumberView()
        }

        private func setupLineSelectionOverlay() {
            let selectionColor = theme.colors.lineSelectionBackground
                ?? theme.colors.selectionTint.withAlphaComponent(0.15)
            selectionOverlay.selectionColor = selectionColor
            scrollView.documentView?.addSubview(selectionOverlay, positioned: .below, relativeTo: textView)
        }

        func performLayout() {
            let labelSize = languageLabel.intrinsicContentSize
            let barHeight = CodeViewConfiguration.barHeight(theme: theme)

            layoutBarView(barHeight: barHeight, labelSize: labelSize)
            layoutButtons()
            layoutLineNumberView(barHeight: barHeight)
            layoutScrollViewAndTextView(barHeight: barHeight)
        }

        private func layoutButtons() {
            guard theme.showsBlockHeaders else {
                copyButton.isHidden = true
                previewButton.isHidden = true
                return
            }

            let buttonSize = CodeViewConfiguration.buttonSize
            let hasPreview = previewAction != nil

            if hasPreview {
                copyButton.frame = CGRect(
                    x: barView.bounds.width - buttonSize.width,
                    y: (barView.bounds.height - buttonSize.height) / 2,
                    width: buttonSize.width,
                    height: buttonSize.height
                )
                previewButton.isHidden = false
                previewButton.frame = CGRect(
                    x: copyButton.frame.minX - buttonSize.width,
                    y: (barView.bounds.height - buttonSize.height) / 2,
                    width: buttonSize.width,
                    height: buttonSize.height
                )
            } else {
                copyButton.frame = CGRect(
                    x: barView.bounds.width - buttonSize.width,
                    y: (barView.bounds.height - buttonSize.height) / 2,
                    width: buttonSize.width,
                    height: buttonSize.height
                )
                previewButton.isHidden = true
            }
        }

        private func layoutBarView(barHeight: CGFloat, labelSize: CGSize) {
            guard theme.showsBlockHeaders else {
                barView.frame = .zero
                languageLabel.frame = .zero
                return
            }

            barView.frame = CGRect(origin: .zero, size: CGSize(width: bounds.width, height: barHeight))
            languageLabel.frame = CGRect(
                origin: CGPoint(x: CodeViewConfiguration.barPadding, y: CodeViewConfiguration.barPadding),
                size: labelSize
            )
        }

        private func layoutLineNumberView(barHeight: CGFloat) {
            let lineNumberSize = lineNumberView.intrinsicContentSize
            lineNumberView.frame = CGRect(
                x: 0,
                y: barHeight,
                width: lineNumberSize.width,
                height: bounds.height - barHeight
            )
        }

        private func layoutScrollViewAndTextView(barHeight: CGFloat) {
            let lineNumberWidth = lineNumberView.intrinsicContentSize.width

            scrollView.frame = CGRect(
                x: lineNumberWidth,
                y: barHeight,
                width: bounds.width - lineNumberWidth,
                height: bounds.height - barHeight
            )

            let availableTextWidth = scrollView.bounds.width - CodeViewConfiguration.codePadding * 2
            textView.preferredMaxLayoutWidth = theme.wrapsCodeBlockLines
                ? max(availableTextWidth, 40)
                : .infinity
            let textContentSize = textView.intrinsicContentSize

            textView.frame = CGRect(
                x: 0,
                y: 0,
                width: theme.wrapsCodeBlockLines
                    ? max(availableTextWidth, 40)
                    : max(availableTextWidth, textContentSize.width),
                height: textContentSize.height
            )

            textView.needsLayout = true
            textView.layoutSubtreeIfNeeded()
            let resolvedLineRects = offsetCodeLineRects(
                textView.lineRects(),
                by: textView.frame.origin
            )
            lineNumberView.updateLineRects(logicalLineStartRects(from: resolvedLineRects))

            selectionOverlay.frame = CGRect(
                origin: .zero,
                size: CGSize(
                    width: max(scrollView.bounds.width - CodeViewConfiguration.codePadding * 2, textView.frame.width),
                    height: max(textView.frame.maxY + CodeViewConfiguration.codePadding, scrollView.bounds.height)
                )
            )
            selectionOverlay.updateLineRects(resolvedLineRects)

            let selectionColor = theme.colors.lineSelectionBackground
                ?? theme.colors.selectionTint.withAlphaComponent(0.15)
            selectionOverlay.selectionColor = selectionColor
        }

        /// With soft wrapping a logical line spans several visual rows; the
        /// gutter should number only the row each logical line starts on.
        func logicalLineStartRects(from visualRects: [CGRect]) -> [CGRect] {
            guard theme.wrapsCodeBlockLines else { return visualRects }
            let ranges = textView.lineStringRanges()
            guard ranges.count == visualRects.count else { return visualRects }
            let text = content as NSString
            var starts: [CGRect] = []
            starts.reserveCapacity(ranges.count)
            for (index, range) in ranges.enumerated() {
                let location = range.location
                if location == 0
                    || (location - 1 < text.length && text.character(at: location - 1) == 0x0A)
                {
                    starts.append(visualRects[index])
                }
            }
            return starts
        }
    }
#endif
