import Litext

#if canImport(UIKit)
    import UIKit

    final class DiffView: UIView {
        var theme: MarkdownTheme = .default {
            didSet {
                textView.selectionBackgroundColor = theme.colors.selectionBackground
                applyTheme()
                applyRenderBlock()
            }
        }

        var renderBlock: DiffRenderBlock = .init(language: nil, rows: []) {
            didSet {
                guard oldValue.rows.count != renderBlock.rows.count || oldValue.language != renderBlock.language else {
                    applyRenderBlock()
                    return
                }
                applyRenderBlock()
            }
        }

        private var cachedTextHeight: CGFloat = 0

        lazy var scrollView: UIScrollView = .init()
        private lazy var contentContainerView: UIView = .init()
        private lazy var backgroundView: DiffContentBackgroundView = .init()
        lazy var textView: LTXLabel = .init()
        private lazy var gutterView: DiffGutterView = .init()

        override init(frame: CGRect) {
            super.init(frame: frame)
            configureSubviews()
            applyTheme()
            applyRenderBlock()
            isAccessibilityElement = false
            accessibilityElements = []
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var accessibilityLabel: String? {
            get { "Diff block" }
            set { /* read-only */ }
        }

        override var accessibilityValue: String? {
            get { attributedStringRepresentation().string }
            set { /* read-only */ }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            performLayout()
        }

        override var intrinsicContentSize: CGSize {
            let textSize = textView.intrinsicContentSize
            let gutterWidth = gutterView.intrinsicContentSize.width
            return CGSize(
                width: gutterWidth + textSize.width + DiffViewConfiguration.horizontalPadding * 2,
                height: DiffViewConfiguration.intrinsicHeight(for: renderBlock, theme: theme)
            )
        }

        private func configureSubviews() {
            layer.cornerRadius = DiffViewConfiguration.cornerRadius
            layer.cornerCurve = .continuous
            clipsToBounds = true

            gutterView.backgroundColor = .clear
            addSubview(gutterView)

            scrollView.showsHorizontalScrollIndicator = false
            scrollView.showsVerticalScrollIndicator = false
            scrollView.alwaysBounceHorizontal = false
            scrollView.alwaysBounceVertical = false
            addSubview(scrollView)

            contentContainerView.backgroundColor = .clear
            scrollView.addSubview(contentContainerView)

            backgroundView.backgroundColor = .clear
            contentContainerView.addSubview(backgroundView)

            textView.backgroundColor = .clear
            textView.preferredMaxLayoutWidth = .infinity
            textView.isSelectable = true
            textView.selectionBackgroundColor = theme.colors.selectionBackground
            contentContainerView.addSubview(textView)
        }

        private func applyTheme() {
            backgroundColor = theme.colors.codeBackground.withAlphaComponent(0.08)
        }

        private func applyRenderBlock() {
            textView.attributedText = makeDisplayAttributedText()
            cachedTextHeight = textView.intrinsicContentSize.height
            gutterView.configure(
                rows: renderBlock.rows,
                contentHeight: cachedTextHeight,
                font: theme.fonts.code,
                theme: theme
            )
            backgroundView.configure(
                rows: renderBlock.rows,
                contentHeight: cachedTextHeight,
                theme: theme
            )
            setNeedsLayout()
            invalidateIntrinsicContentSize()
        }

        private func makeDisplayAttributedText() -> NSAttributedString {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = CodeViewConfiguration.codeLineSpacing

            let result = NSMutableAttributedString()
            for (index, row) in renderBlock.rows.enumerated() {
                let rowRange = NSRange(location: result.length, length: row.text.utf16.count)
                let baseColor: UIColor = switch row.kind {
                case .hunkHeader:
                    theme.diff.hunkHeaderText
                case .annotation:
                    theme.diff.annotationText
                case .context, .removed, .added:
                    theme.colors.code
                }

                result.append(
                    .init(
                        string: row.text,
                        attributes: [
                            .font: theme.fonts.code,
                            .paragraphStyle: paragraphStyle,
                            .foregroundColor: baseColor,
                        ]
                    )
                )

                for (range, color) in row.syntaxHighlights {
                    guard range.location >= 0, range.upperBound <= rowRange.length else { continue }
                    let shifted = NSRange(location: rowRange.location + range.location, length: range.length)
                    result.addAttribute(.foregroundColor, value: color, range: shifted)
                }

                let emphasisColor: UIColor? = switch row.kind {
                case .removed:
                    theme.diff.removedHighlightBackground
                case .added:
                    theme.diff.addedHighlightBackground
                case .hunkHeader, .context, .annotation:
                    nil
                }

                if let emphasisColor {
                    for range in row.emphasizedRanges {
                        guard range.location >= 0, range.upperBound <= rowRange.length else { continue }
                        let shifted = NSRange(location: rowRange.location + range.location, length: range.length)
                        result.addAttribute(.backgroundColor, value: emphasisColor, range: shifted)
                    }
                }

                if index < renderBlock.rows.count - 1 {
                    result.append(
                        .init(
                            string: "\n",
                            attributes: [
                                .font: theme.fonts.code,
                                .paragraphStyle: paragraphStyle,
                                .foregroundColor: theme.colors.code,
                            ]
                        )
                    )
                }
            }
            return result
        }

        private func performLayout() {
            let gutterWidth = gutterView.intrinsicContentSize.width
            gutterView.frame = CGRect(
                x: 0,
                y: 0,
                width: gutterWidth,
                height: bounds.height
            )

            scrollView.frame = CGRect(
                x: gutterWidth,
                y: 0,
                width: max(bounds.width - gutterWidth, 0),
                height: bounds.height
            )

            let textSize = textView.intrinsicContentSize
            let containerWidth = max(
                scrollView.bounds.width,
                textSize.width + DiffViewConfiguration.horizontalPadding * 2
            )
            let containerHeight = max(
                bounds.height,
                textSize.height + DiffViewConfiguration.verticalPadding * 2
            )

            contentContainerView.frame = CGRect(origin: .zero, size: CGSize(width: containerWidth, height: containerHeight))
            backgroundView.frame = contentContainerView.bounds
            textView.frame = CGRect(
                x: DiffViewConfiguration.horizontalPadding,
                y: DiffViewConfiguration.verticalPadding,
                width: max(
                    scrollView.bounds.width - DiffViewConfiguration.horizontalPadding * 2,
                    textSize.width
                ),
                height: textSize.height
            )
            scrollView.contentSize = contentContainerView.bounds.size
        }
    }

    extension DiffView: LTXAttributeStringRepresentable {
        func attributedStringRepresentation() -> NSAttributedString {
            let content = renderBlock.rows
                .map(Self.selectionText(for:))
                .joined(separator: "\n")
            return NSAttributedString(string: content)
        }

        private static func selectionText(for row: DiffRenderBlock.Row) -> String {
            switch row.kind {
            case .hunkHeader, .annotation:
                row.text
            case .context:
                " " + row.text
            case .removed:
                "-" + row.text
            case .added:
                "+" + row.text
            }
        }
    }

    private final class DiffContentBackgroundView: UIView {
        private var rows: [DiffRenderBlock.Row] = []
        private var contentHeight: CGFloat = 0
        private var theme: MarkdownTheme = .default

        func configure(
            rows: [DiffRenderBlock.Row],
            contentHeight: CGFloat,
            theme: MarkdownTheme
        ) {
            self.rows = rows
            self.contentHeight = contentHeight
            self.theme = theme
            setNeedsDisplay()
        }

        override func draw(_ rect: CGRect) {
            guard let context = UIGraphicsGetCurrentContext() else { return }
            context.clear(rect)
            drawRows(in: context)
        }

        private func drawRows(in context: CGContext) {
            guard !rows.isEmpty, contentHeight > 0 else { return }

            let availableHeight = contentHeight
            let lineSpacing = availableHeight / CGFloat(rows.count)
            let startY = DiffViewConfiguration.verticalPadding

            for (index, row) in rows.enumerated() {
                let rect = CGRect(
                    x: 0,
                    y: startY + CGFloat(index) * lineSpacing,
                    width: bounds.width,
                    height: lineSpacing
                )

                if let fillColor = rowBackgroundColor(for: row.kind) {
                    context.setFillColor(fillColor.cgColor)
                    context.fill(rect)
                }

                context.setFillColor(theme.diff.separatorColor.cgColor)
                context.fill(
                    CGRect(
                        x: 0,
                        y: rect.maxY - DiffViewConfiguration.separatorWidth,
                        width: bounds.width,
                        height: DiffViewConfiguration.separatorWidth
                    )
                )
            }
        }

        private func rowBackgroundColor(for kind: DiffRenderBlock.RowKind) -> UIColor? {
            switch kind {
            case .hunkHeader:
                theme.diff.hunkHeaderBackground
            case .removed:
                theme.diff.removedLineBackground
            case .added:
                theme.diff.addedLineBackground
            case .context, .annotation:
                nil
            }
        }
    }

    private final class DiffGutterView: UIView {
        private struct Metrics {
            let oldColumnWidth: CGFloat
            let newColumnWidth: CGFloat
            let markerColumnWidth: CGFloat

            var totalWidth: CGFloat {
                oldColumnWidth + newColumnWidth + markerColumnWidth + DiffViewConfiguration.separatorWidth * 3
            }
        }

        private var suppressInvalidation = false
        private var rows: [DiffRenderBlock.Row] = []
        private var font: UIFont = .monospacedSystemFont(ofSize: 12, weight: .regular)
        private var theme: MarkdownTheme = .default
        private var contentHeight: CGFloat = 0

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isOpaque = false
            contentMode = .redraw
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func configure(
            rows: [DiffRenderBlock.Row],
            contentHeight: CGFloat,
            font: UIFont,
            theme: MarkdownTheme
        ) {
            suppressInvalidation = true
            self.rows = rows
            self.contentHeight = contentHeight
            self.font = font
            self.theme = theme
            suppressInvalidation = false
            setNeedsDisplay()
            invalidateIntrinsicContentSize()
        }

        override var intrinsicContentSize: CGSize {
            let metrics = layoutMetrics()
            let maxHeight = max(
                contentHeight + DiffViewConfiguration.verticalPadding * 2,
                font.lineHeight + DiffViewConfiguration.verticalPadding * 2
            )
            return CGSize(width: metrics.totalWidth, height: maxHeight)
        }

        override func draw(_ rect: CGRect) {
            guard let context = UIGraphicsGetCurrentContext() else { return }
            context.clear(rect)
            drawRows(in: context)
            drawSeparators(in: context)
        }

        private func layoutMetrics() -> Metrics {
            let numberWidth = maxLineNumberText().size(withAttributes: [.font: font]).width
            let columnWidth = numberWidth + DiffViewConfiguration.gutterPadding * 2
            return .init(
                oldColumnWidth: columnWidth,
                newColumnWidth: columnWidth,
                markerColumnWidth: DiffViewConfiguration.markerColumnWidth
            )
        }

        private func maxLineNumberText() -> String {
            let maxLineNumber = rows.reduce(into: 0) { partialResult, row in
                partialResult = max(partialResult, row.oldLineNumber ?? 0, row.newLineNumber ?? 0)
            }
            return "\(max(maxLineNumber, 0))"
        }

        private func drawRows(in context: CGContext) {
            guard !rows.isEmpty, contentHeight > 0 else { return }

            let metrics = layoutMetrics()
            let availableHeight = contentHeight
            let lineSpacing = availableHeight / CGFloat(rows.count)
            let startY = DiffViewConfiguration.verticalPadding

            for (index, row) in rows.enumerated() {
                let rect = CGRect(
                    x: 0,
                    y: startY + CGFloat(index) * lineSpacing,
                    width: bounds.width,
                    height: lineSpacing
                )

                if let fillColor = rowBackgroundColor(for: row.kind) {
                    context.setFillColor(fillColor.cgColor)
                    context.fill(rect)
                } else {
                    context.setFillColor(theme.diff.gutterBackground.cgColor)
                    context.fill(rect)
                }

                let textAttributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: theme.diff.gutterText,
                ]

                drawNumber(
                    row.oldLineNumber,
                    in: CGRect(x: 0, y: rect.minY, width: metrics.oldColumnWidth, height: rect.height),
                    attributes: textAttributes
                )
                drawNumber(
                    row.newLineNumber,
                    in: CGRect(
                        x: metrics.oldColumnWidth + DiffViewConfiguration.separatorWidth,
                        y: rect.minY,
                        width: metrics.newColumnWidth,
                        height: rect.height
                    ),
                    attributes: textAttributes
                )
                drawMarker(
                    marker(for: row.kind),
                    in: CGRect(
                        x: metrics.oldColumnWidth + metrics.newColumnWidth + DiffViewConfiguration.separatorWidth * 2,
                        y: rect.minY,
                        width: metrics.markerColumnWidth,
                        height: rect.height
                    ),
                    attributes: textAttributes
                )
            }
        }

        private func drawNumber(
            _ number: Int?,
            in rect: CGRect,
            attributes: [NSAttributedString.Key: Any]
        ) {
            guard let number else { return }
            let string = "\(number)"
            let size = string.size(withAttributes: attributes)
            let target = CGRect(
                x: rect.maxX - DiffViewConfiguration.gutterPadding - size.width,
                y: rect.minY + (rect.height - size.height) / 2,
                width: size.width,
                height: size.height
            )
            string.draw(in: target, withAttributes: attributes)
        }

        private func drawMarker(
            _ marker: String?,
            in rect: CGRect,
            attributes: [NSAttributedString.Key: Any]
        ) {
            guard let marker else { return }
            let size = marker.size(withAttributes: attributes)
            let target = CGRect(
                x: rect.midX - size.width / 2,
                y: rect.minY + (rect.height - size.height) / 2,
                width: size.width,
                height: size.height
            )
            marker.draw(in: target, withAttributes: attributes)
        }

        private func drawSeparators(in context: CGContext) {
            let metrics = layoutMetrics()
            context.setFillColor(theme.diff.separatorColor.cgColor)

            let firstSeparatorX = metrics.oldColumnWidth
            let secondSeparatorX = metrics.oldColumnWidth + DiffViewConfiguration.separatorWidth + metrics.newColumnWidth
            let finalSeparatorX = bounds.width - DiffViewConfiguration.separatorWidth

            for x in [firstSeparatorX, secondSeparatorX, finalSeparatorX] {
                context.fill(
                    CGRect(
                        x: x,
                        y: 0,
                        width: DiffViewConfiguration.separatorWidth,
                        height: bounds.height
                    )
                )
            }
        }

        private func marker(for kind: DiffRenderBlock.RowKind) -> String? {
            switch kind {
            case .removed:
                "-"
            case .added:
                "+"
            case .annotation:
                "\\"
            case .hunkHeader, .context:
                nil
            }
        }

        private func rowBackgroundColor(for kind: DiffRenderBlock.RowKind) -> UIColor? {
            switch kind {
            case .hunkHeader:
                theme.diff.hunkHeaderBackground
            case .removed:
                theme.diff.removedLineBackground
            case .added:
                theme.diff.addedLineBackground
            case .context, .annotation:
                nil
            }
        }
    }

#elseif canImport(AppKit)
    import AppKit

    final class DiffView: NSView {
        var theme: MarkdownTheme = .default {
            didSet {
                textView.selectionBackgroundColor = theme.colors.selectionBackground
                applyTheme()
                applyRenderBlock()
            }
        }

        var renderBlock: DiffRenderBlock = .init(language: nil, rows: []) {
            didSet {
                guard oldValue.rows.count != renderBlock.rows.count || oldValue.language != renderBlock.language else {
                    applyRenderBlock()
                    return
                }
                applyRenderBlock()
            }
        }

        private var cachedTextHeight: CGFloat = 0

        lazy var scrollView: NSScrollView = {
            let scrollView = NSScrollView()
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            scrollView.drawsBackground = false
            scrollView.automaticallyAdjustsContentInsets = false
            return scrollView
        }()

        private lazy var contentContainerView: DiffContainerView = .init()
        private lazy var backgroundView: DiffContentBackgroundView = .init()
        lazy var textView: LTXLabel = .init()
        private lazy var gutterView: DiffGutterView = .init()

        override init(frame: CGRect) {
            super.init(frame: frame)
            configureSubviews()
            applyTheme()
            applyRenderBlock()
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
            "Diff block"
        }

        override func accessibilityValue() -> Any? {
            attributedStringRepresentation().string
        }

        override func layout() {
            super.layout()
            performLayout()
        }

        override var intrinsicContentSize: CGSize {
            let textSize = textView.intrinsicContentSize
            let gutterWidth = gutterView.intrinsicContentSize.width
            return CGSize(
                width: gutterWidth + textSize.width + DiffViewConfiguration.horizontalPadding * 2,
                height: DiffViewConfiguration.intrinsicHeight(for: renderBlock, theme: theme)
            )
        }

        private func configureSubviews() {
            wantsLayer = true
            layer?.cornerRadius = DiffViewConfiguration.cornerRadius

            gutterView.wantsLayer = true
            gutterView.layer?.backgroundColor = NSColor.clear.cgColor
            addSubview(gutterView)

            addSubview(scrollView)

            contentContainerView.wantsLayer = true
            contentContainerView.layer?.backgroundColor = NSColor.clear.cgColor
            scrollView.documentView = contentContainerView

            backgroundView.wantsLayer = true
            backgroundView.layer?.backgroundColor = NSColor.clear.cgColor
            contentContainerView.addSubview(backgroundView)

            textView.wantsLayer = true
            textView.layer?.backgroundColor = NSColor.clear.cgColor
            textView.preferredMaxLayoutWidth = .infinity
            textView.isSelectable = true
            textView.selectionBackgroundColor = theme.colors.selectionBackground
            contentContainerView.addSubview(textView)
        }

        private func applyTheme() {
            layer?.backgroundColor = theme.colors.codeBackground.withAlphaComponent(0.08).cgColor
        }

        private func applyRenderBlock() {
            textView.attributedText = makeDisplayAttributedText()
            cachedTextHeight = textView.intrinsicContentSize.height
            gutterView.configure(
                rows: renderBlock.rows,
                contentHeight: cachedTextHeight,
                font: theme.fonts.code,
                theme: theme
            )
            backgroundView.configure(
                rows: renderBlock.rows,
                contentHeight: cachedTextHeight,
                theme: theme
            )
            needsLayout = true
            invalidateIntrinsicContentSize()
        }

        private func makeDisplayAttributedText() -> NSAttributedString {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = CodeViewConfiguration.codeLineSpacing

            let result = NSMutableAttributedString()
            for (index, row) in renderBlock.rows.enumerated() {
                let rowRange = NSRange(location: result.length, length: row.text.utf16.count)
                let baseColor: NSColor = switch row.kind {
                case .hunkHeader:
                    theme.diff.hunkHeaderText
                case .annotation:
                    theme.diff.annotationText
                case .context, .removed, .added:
                    theme.colors.code
                }

                result.append(
                    .init(
                        string: row.text,
                        attributes: [
                            .font: theme.fonts.code,
                            .paragraphStyle: paragraphStyle,
                            .foregroundColor: baseColor,
                        ]
                    )
                )

                for (range, color) in row.syntaxHighlights {
                    guard range.location >= 0, range.upperBound <= rowRange.length else { continue }
                    let shifted = NSRange(location: rowRange.location + range.location, length: range.length)
                    result.addAttribute(.foregroundColor, value: color, range: shifted)
                }

                let emphasisColor: NSColor? = switch row.kind {
                case .removed:
                    theme.diff.removedHighlightBackground
                case .added:
                    theme.diff.addedHighlightBackground
                case .hunkHeader, .context, .annotation:
                    nil
                }

                if let emphasisColor {
                    for range in row.emphasizedRanges {
                        guard range.location >= 0, range.upperBound <= rowRange.length else { continue }
                        let shifted = NSRange(location: rowRange.location + range.location, length: range.length)
                        result.addAttribute(.backgroundColor, value: emphasisColor, range: shifted)
                    }
                }

                if index < renderBlock.rows.count - 1 {
                    result.append(
                        .init(
                            string: "\n",
                            attributes: [
                                .font: theme.fonts.code,
                                .paragraphStyle: paragraphStyle,
                                .foregroundColor: theme.colors.code,
                            ]
                        )
                    )
                }
            }
            return result
        }

        private func performLayout() {
            let gutterWidth = gutterView.intrinsicContentSize.width
            gutterView.frame = CGRect(
                x: 0,
                y: 0,
                width: gutterWidth,
                height: bounds.height
            )

            scrollView.frame = CGRect(
                x: gutterWidth,
                y: 0,
                width: max(bounds.width - gutterWidth, 0),
                height: bounds.height
            )

            let textSize = textView.intrinsicContentSize
            let containerWidth = max(
                scrollView.bounds.width,
                textSize.width + DiffViewConfiguration.horizontalPadding * 2
            )
            let containerHeight = max(
                bounds.height,
                textSize.height + DiffViewConfiguration.verticalPadding * 2
            )

            contentContainerView.frame = CGRect(origin: .zero, size: CGSize(width: containerWidth, height: containerHeight))
            backgroundView.frame = contentContainerView.bounds
            textView.frame = CGRect(
                x: DiffViewConfiguration.horizontalPadding,
                y: DiffViewConfiguration.verticalPadding,
                width: max(
                    scrollView.bounds.width - DiffViewConfiguration.horizontalPadding * 2,
                    textSize.width
                ),
                height: textSize.height
            )
        }
    }

    extension DiffView: LTXAttributeStringRepresentable {
        func attributedStringRepresentation() -> NSAttributedString {
            let content = renderBlock.rows
                .map(Self.selectionText(for:))
                .joined(separator: "\n")
            return NSAttributedString(string: content)
        }

        private static func selectionText(for row: DiffRenderBlock.Row) -> String {
            switch row.kind {
            case .hunkHeader, .annotation:
                row.text
            case .context:
                " " + row.text
            case .removed:
                "-" + row.text
            case .added:
                "+" + row.text
            }
        }
    }

    private final class DiffContainerView: NSView {
        override var isFlipped: Bool {
            true
        }
    }

    private final class DiffContentBackgroundView: NSView {
        private var rows: [DiffRenderBlock.Row] = []
        private var contentHeight: CGFloat = 0
        private var theme: MarkdownTheme = .default

        override var isFlipped: Bool {
            true
        }

        func configure(
            rows: [DiffRenderBlock.Row],
            contentHeight: CGFloat,
            theme: MarkdownTheme
        ) {
            self.rows = rows
            self.contentHeight = contentHeight
            self.theme = theme
            needsDisplay = true
        }

        override func draw(_ dirtyRect: NSRect) {
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            context.clear(dirtyRect)
            drawRows(in: context)
        }

        private func drawRows(in context: CGContext) {
            guard !rows.isEmpty, contentHeight > 0 else { return }

            let availableHeight = contentHeight
            let lineSpacing = availableHeight / CGFloat(rows.count)
            let startY = DiffViewConfiguration.verticalPadding

            for (index, row) in rows.enumerated() {
                let rect = CGRect(
                    x: 0,
                    y: startY + CGFloat(index) * lineSpacing,
                    width: bounds.width,
                    height: lineSpacing
                )

                if let fillColor = rowBackgroundColor(for: row.kind) {
                    context.setFillColor(fillColor.cgColor)
                    context.fill(rect)
                }

                context.setFillColor(theme.diff.separatorColor.cgColor)
                context.fill(
                    CGRect(
                        x: 0,
                        y: rect.maxY - DiffViewConfiguration.separatorWidth,
                        width: bounds.width,
                        height: DiffViewConfiguration.separatorWidth
                    )
                )
            }
        }

        private func rowBackgroundColor(for kind: DiffRenderBlock.RowKind) -> NSColor? {
            switch kind {
            case .hunkHeader:
                theme.diff.hunkHeaderBackground
            case .removed:
                theme.diff.removedLineBackground
            case .added:
                theme.diff.addedLineBackground
            case .context, .annotation:
                nil
            }
        }
    }

    private final class DiffGutterView: NSView {
        private struct Metrics {
            let oldColumnWidth: CGFloat
            let newColumnWidth: CGFloat
            let markerColumnWidth: CGFloat

            var totalWidth: CGFloat {
                oldColumnWidth + newColumnWidth + markerColumnWidth + DiffViewConfiguration.separatorWidth * 3
            }
        }

        private var rows: [DiffRenderBlock.Row] = []
        private var font: NSFont = .monospacedSystemFont(ofSize: 12, weight: .regular)
        private var theme: MarkdownTheme = .default
        private var contentHeight: CGFloat = 0

        override var isFlipped: Bool {
            true
        }

        func configure(
            rows: [DiffRenderBlock.Row],
            contentHeight: CGFloat,
            font: NSFont,
            theme: MarkdownTheme
        ) {
            self.rows = rows
            self.contentHeight = contentHeight
            self.font = font
            self.theme = theme
            needsDisplay = true
            invalidateIntrinsicContentSize()
        }

        override var intrinsicContentSize: CGSize {
            let metrics = layoutMetrics()
            let fontHeight = font.ascender + abs(font.descender) + font.leading
            let maxHeight = max(
                contentHeight + DiffViewConfiguration.verticalPadding * 2,
                fontHeight + DiffViewConfiguration.verticalPadding * 2
            )
            return CGSize(width: metrics.totalWidth, height: maxHeight)
        }

        override func draw(_ dirtyRect: NSRect) {
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            context.clear(dirtyRect)
            drawRows(in: context)
            drawSeparators(in: context)
        }

        private func layoutMetrics() -> Metrics {
            let numberWidth = maxLineNumberText().size(withAttributes: [.font: font]).width
            let columnWidth = numberWidth + DiffViewConfiguration.gutterPadding * 2
            return .init(
                oldColumnWidth: columnWidth,
                newColumnWidth: columnWidth,
                markerColumnWidth: DiffViewConfiguration.markerColumnWidth
            )
        }

        private func maxLineNumberText() -> String {
            let maxLineNumber = rows.reduce(into: 0) { partialResult, row in
                partialResult = max(partialResult, row.oldLineNumber ?? 0, row.newLineNumber ?? 0)
            }
            return "\(max(maxLineNumber, 0))"
        }

        private func drawRows(in context: CGContext) {
            guard !rows.isEmpty, contentHeight > 0 else { return }

            let metrics = layoutMetrics()
            let availableHeight = contentHeight
            let lineSpacing = availableHeight / CGFloat(rows.count)
            let startY = DiffViewConfiguration.verticalPadding

            for (index, row) in rows.enumerated() {
                let rect = CGRect(
                    x: 0,
                    y: startY + CGFloat(index) * lineSpacing,
                    width: bounds.width,
                    height: lineSpacing
                )

                if let fillColor = rowBackgroundColor(for: row.kind) {
                    context.setFillColor(fillColor.cgColor)
                    context.fill(rect)
                } else {
                    context.setFillColor(theme.diff.gutterBackground.cgColor)
                    context.fill(rect)
                }

                let textAttributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: theme.diff.gutterText,
                ]

                drawNumber(
                    row.oldLineNumber,
                    in: CGRect(x: 0, y: rect.minY, width: metrics.oldColumnWidth, height: rect.height),
                    attributes: textAttributes
                )
                drawNumber(
                    row.newLineNumber,
                    in: CGRect(
                        x: metrics.oldColumnWidth + DiffViewConfiguration.separatorWidth,
                        y: rect.minY,
                        width: metrics.newColumnWidth,
                        height: rect.height
                    ),
                    attributes: textAttributes
                )
                drawMarker(
                    marker(for: row.kind),
                    in: CGRect(
                        x: metrics.oldColumnWidth + metrics.newColumnWidth + DiffViewConfiguration.separatorWidth * 2,
                        y: rect.minY,
                        width: metrics.markerColumnWidth,
                        height: rect.height
                    ),
                    attributes: textAttributes
                )
            }
        }

        private func drawNumber(
            _ number: Int?,
            in rect: CGRect,
            attributes: [NSAttributedString.Key: Any]
        ) {
            guard let number else { return }
            let string = "\(number)"
            let size = string.size(withAttributes: attributes)
            let target = CGRect(
                x: rect.maxX - DiffViewConfiguration.gutterPadding - size.width,
                y: rect.minY + (rect.height - size.height) / 2,
                width: size.width,
                height: size.height
            )
            string.draw(in: target, withAttributes: attributes)
        }

        private func drawMarker(
            _ marker: String?,
            in rect: CGRect,
            attributes: [NSAttributedString.Key: Any]
        ) {
            guard let marker else { return }
            let size = marker.size(withAttributes: attributes)
            let target = CGRect(
                x: rect.midX - size.width / 2,
                y: rect.minY + (rect.height - size.height) / 2,
                width: size.width,
                height: size.height
            )
            marker.draw(in: target, withAttributes: attributes)
        }

        private func drawSeparators(in context: CGContext) {
            let metrics = layoutMetrics()
            context.setFillColor(theme.diff.separatorColor.cgColor)

            let firstSeparatorX = metrics.oldColumnWidth
            let secondSeparatorX = metrics.oldColumnWidth + DiffViewConfiguration.separatorWidth + metrics.newColumnWidth
            let finalSeparatorX = bounds.width - DiffViewConfiguration.separatorWidth

            for x in [firstSeparatorX, secondSeparatorX, finalSeparatorX] {
                context.fill(
                    CGRect(
                        x: x,
                        y: 0,
                        width: DiffViewConfiguration.separatorWidth,
                        height: bounds.height
                    )
                )
            }
        }

        private func marker(for kind: DiffRenderBlock.RowKind) -> String? {
            switch kind {
            case .removed:
                "-"
            case .added:
                "+"
            case .annotation:
                "\\"
            case .hunkHeader, .context:
                nil
            }
        }

        private func rowBackgroundColor(for kind: DiffRenderBlock.RowKind) -> NSColor? {
            switch kind {
            case .hunkHeader:
                theme.diff.hunkHeaderBackground
            case .removed:
                theme.diff.removedLineBackground
            case .added:
                theme.diff.addedLineBackground
            case .context, .annotation:
                nil
            }
        }
    }
#endif
