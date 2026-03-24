import Litext

private enum DiffDisplayRows {
    case unified([DiffPresentation.UnifiedRow])
    case sideBySide(rows: [DiffPresentation.SideBySideRow], maxOldUTF16Length: Int)

    static func make(
        for block: DiffRenderBlock,
        theme: MarkdownTheme
    ) -> DiffDisplayRows {
        switch theme.diff.displayMode {
        case .unified:
            return .unified(
                DiffPresentation.unifiedRows(from: block, configuration: theme.diff)
            )
        case .sideBySide:
            let rows = DiffPresentation.sideBySideRows(from: block, configuration: theme.diff)
            return .sideBySide(
                rows: rows,
                maxOldUTF16Length: DiffPresentation.sideBySideMaxOldUTF16Length(rows: rows)
            )
        }
    }

    var count: Int {
        switch self {
        case let .unified(rows):
            rows.count
        case let .sideBySide(rows, _):
            rows.count
        }
    }

    var effectiveCount: Int {
        max(count, 1)
    }

    var isEmpty: Bool {
        count == 0
    }
}

private struct DiffSideBySideTextMetrics {
    let maxOldUTF16Length: Int
    let oldTextWidth: CGFloat
    let separatorTextWidth: CGFloat

    static func make(
        maxOldUTF16Length: Int,
        font: Any
    ) -> DiffSideBySideTextMetrics {
        let oldPaddingWidth = String(repeating: " ", count: maxOldUTF16Length)
            .size(withAttributes: [.font: font]).width
        let separatorTextWidth = DiffPresentation.sideBySideSeparatorText
            .size(withAttributes: [.font: font]).width
        return .init(
            maxOldUTF16Length: maxOldUTF16Length,
            oldTextWidth: oldPaddingWidth,
            separatorTextWidth: separatorTextWidth
        )
    }
}

private struct DiffGutterMetrics {
    let oldColumnWidth: CGFloat
    let newColumnWidth: CGFloat
    let markerColumnWidth: CGFloat

    var showsOldColumn: Bool {
        oldColumnWidth > 0
    }

    var showsNewColumn: Bool {
        newColumnWidth > 0
    }

    var showsMarkerColumn: Bool {
        markerColumnWidth > 0
    }

    var totalWidth: CGFloat {
        let visibleColumns = [showsOldColumn, showsNewColumn, showsMarkerColumn].filter { $0 }.count
        let internalSeparatorCount = max(visibleColumns - 1, 0)
        let trailingSeparatorCount = visibleColumns > 0 ? 1 : 0
        return oldColumnWidth
            + newColumnWidth
            + markerColumnWidth
            + DiffViewConfiguration.separatorWidth * CGFloat(internalSeparatorCount + trailingSeparatorCount)
    }
}

private struct DiffSideBySideContentRects {
    let dividerX: CGFloat
    let dividerRect: CGRect
    let oldRect: CGRect
    let newRect: CGRect
}

private struct DiffGutterRowRects {
    let oldRect: CGRect?
    let newRect: CGRect?
    let markerRect: CGRect?
}

private func diffBlockTitle(for block: DiffRenderBlock) -> String {
    if let language = block.language, !language.isEmpty {
        return "diff \(language)"
    }
    return "diff"
}

private func rawDiffSelectionText(from block: DiffRenderBlock) -> String {
    block.rows
        .map(diffSelectionText(for:))
        .joined(separator: "\n")
}

private func diffSelectionText(for row: DiffRenderBlock.Row) -> String {
    switch row.kind {
    case .fileHeader, .fileMetadata, .hunkHeader, .annotation:
        row.text
    case .context:
        " " + row.text
    case .removed:
        "-" + row.text
    case .added:
        "+" + row.text
    }
}

private func makeDiffParagraphStyle() -> NSMutableParagraphStyle {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineSpacing = CodeViewConfiguration.codeLineSpacing
    return paragraphStyle
}

private func makeDiffAttributes(
    font: Any,
    color: PlatformColor,
    paragraphStyle: NSParagraphStyle
) -> [NSAttributedString.Key: Any] {
    [
        .font: font,
        .paragraphStyle: paragraphStyle,
        .foregroundColor: color,
    ]
}

private func diffRowRect(
    index: Int,
    rowCount: Int,
    contentHeight: CGFloat,
    bounds: CGRect
) -> CGRect {
    let lineHeight = contentHeight / CGFloat(max(rowCount, 1))
    return CGRect(
        x: bounds.minX,
        y: DiffViewConfiguration.verticalPadding + CGFloat(index) * lineHeight,
        width: bounds.width,
        height: lineHeight
    )
}

private func paddedToUTF16Length(
    _ text: String,
    targetLength: Int
) -> String {
    let delta = targetLength - text.utf16.count
    guard delta > 0 else { return text }
    return text + String(repeating: " ", count: delta)
}

private func applySyntaxHighlights(
    _ highlights: CodeHighlighter.HighlightMap,
    to result: NSMutableAttributedString,
    baseLocation: Int,
    rowLength: Int
) {
    for (range, color) in highlights {
        guard range.location >= 0, range.upperBound <= rowLength else { continue }
        let shifted = NSRange(location: baseLocation + range.location, length: range.length)
        result.addAttribute(.foregroundColor, value: color, range: shifted)
    }
}

private func applyEmphasis(
    _ ranges: [NSRange],
    color: PlatformColor?,
    to result: NSMutableAttributedString,
    baseLocation: Int,
    rowLength: Int
) {
    guard let color else { return }
    for range in ranges {
        guard range.location >= 0, range.upperBound <= rowLength else { continue }
        let shifted = NSRange(location: baseLocation + range.location, length: range.length)
        result.addAttribute(.backgroundColor, value: color, range: shifted)
    }
}

private func showsLineChangeHighlights(
    in theme: MarkdownTheme
) -> Bool {
    switch theme.diff.changeHighlightStyle {
    case .lineOnly, .both:
        true
    case .inlineOnly:
        false
    }
}

private func showsInlineChangeHighlights(
    in theme: MarkdownTheme
) -> Bool {
    switch theme.diff.changeHighlightStyle {
    case .inlineOnly, .both:
        true
    case .lineOnly:
        false
    }
}

private func unifiedTextColor(
    for kind: DiffPresentation.UnifiedRow.Kind,
    theme: MarkdownTheme
) -> PlatformColor {
    switch kind {
    case .fileHeader:
        theme.diff.fileHeaderText
    case .fileMetadata:
        theme.diff.fileMetadataText
    case .hunkHeader:
        theme.diff.hunkHeaderText
    case .annotation:
        theme.diff.annotationText
    case .collapsedContext:
        theme.diff.collapsedContextText
    case .context, .removed, .added:
        theme.colors.code
    }
}

private func unifiedRowBackgroundColor(
    for kind: DiffPresentation.UnifiedRow.Kind,
    theme: MarkdownTheme
) -> PlatformColor? {
    switch kind {
    case .fileHeader, .fileMetadata:
        theme.diff.fileHeaderBackground
    case .hunkHeader:
        theme.diff.hunkHeaderBackground
    case .removed:
        showsLineChangeHighlights(in: theme) ? theme.diff.removedLineBackground : nil
    case .added:
        showsLineChangeHighlights(in: theme) ? theme.diff.addedLineBackground : nil
    case .collapsedContext:
        theme.diff.collapsedContextBackground
    case .context, .annotation:
        nil
    }
}

private func unifiedContentRowBackgroundColor(
    for kind: DiffPresentation.UnifiedRow.Kind,
    theme: MarkdownTheme
) -> PlatformColor? {
    switch kind {
    case .removed, .added:
        return nil
    case .fileHeader, .fileMetadata, .hunkHeader, .context, .annotation, .collapsedContext:
        return unifiedRowBackgroundColor(for: kind, theme: theme)
    }
}

private func unifiedEmphasisColor(
    for kind: DiffPresentation.UnifiedRow.Kind,
    theme: MarkdownTheme
) -> PlatformColor? {
    guard showsInlineChangeHighlights(in: theme) else { return nil }
    switch kind {
    case .removed:
        return theme.diff.removedHighlightBackground
    case .added:
        return theme.diff.addedHighlightBackground
    case .fileHeader, .fileMetadata, .hunkHeader, .context, .annotation, .collapsedContext:
        return nil
    }
}

private func unifiedLineBackgroundColor(
    for kind: DiffPresentation.UnifiedRow.Kind,
    theme: MarkdownTheme
) -> PlatformColor? {
    guard showsLineChangeHighlights(in: theme) else { return nil }
    switch kind {
    case .removed:
        return theme.diff.removedLineBackground
    case .added:
        return theme.diff.addedLineBackground
    case .fileHeader, .fileMetadata, .hunkHeader, .context, .annotation, .collapsedContext:
        return nil
    }
}

private func makeFullWidthLineBackgroundAction(
    color: PlatformColor
) -> LTXLineDrawingAction {
    LTXLineDrawingAction { context, line, lineOrigin in
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        CTLineGetTypographicBounds(line, &ascent, &descent, &leading)

        let lineSpacing = CodeViewConfiguration.codeLineSpacing
        let clipBounds = context.boundingBoxOfClipPath
        let rect = CGRect(
            x: clipBounds.minX,
            y: lineOrigin.y - descent - lineSpacing / 2,
            width: clipBounds.width,
            height: ascent + descent + leading + lineSpacing
        )

        context.saveGState()
        context.setFillColor(color.cgColor)
        context.fill(rect)
        context.restoreGState()
    }
}

private func sideBySideRowTextColor(
    for kind: DiffPresentation.SideBySideRow.Kind,
    theme: MarkdownTheme
) -> PlatformColor {
    switch kind {
    case .fileHeader:
        theme.diff.fileHeaderText
    case .fileMetadata:
        theme.diff.fileMetadataText
    case .hunkHeader:
        theme.diff.hunkHeaderText
    case .annotation:
        theme.diff.annotationText
    case .collapsedContext:
        theme.diff.collapsedContextText
    case .content:
        theme.colors.code
    }
}

private func sideBySideRowBackgroundColor(
    for kind: DiffPresentation.SideBySideRow.Kind,
    theme: MarkdownTheme
) -> PlatformColor? {
    switch kind {
    case .fileHeader, .fileMetadata:
        theme.diff.fileHeaderBackground
    case .hunkHeader:
        theme.diff.hunkHeaderBackground
    case .collapsedContext:
        theme.diff.collapsedContextBackground
    case .annotation, .content:
        nil
    }
}

private func sideBySideCellBackgroundColor(
    for role: DiffPresentation.SideBySideRow.CellRole,
    theme: MarkdownTheme
) -> PlatformColor? {
    guard showsLineChangeHighlights(in: theme) else { return nil }
    switch role {
    case .removed:
        return theme.diff.removedLineBackground
    case .added:
        return theme.diff.addedLineBackground
    case .empty, .context:
        return nil
    }
}

private func sideBySideEmphasisColor(
    for role: DiffPresentation.SideBySideRow.CellRole,
    theme: MarkdownTheme
) -> PlatformColor? {
    guard showsInlineChangeHighlights(in: theme) else { return nil }
    switch role {
    case .removed:
        return theme.diff.removedHighlightBackground
    case .added:
        return theme.diff.addedHighlightBackground
    case .empty, .context:
        return nil
    }
}

private func sideBySideMarkerBackgroundColor(
    for row: DiffPresentation.SideBySideRow,
    theme: MarkdownTheme
) -> PlatformColor? {
    guard showsLineChangeHighlights(in: theme) else { return nil }
    switch sideBySideMarker(for: row) {
    case "-":
        return theme.diff.removedLineBackground
    case "+":
        return theme.diff.addedLineBackground
    default:
        return nil
    }
}

private func sideBySideMarker(
    for row: DiffPresentation.SideBySideRow
) -> String? {
    switch row.kind {
    case .annotation:
        return "\\"
    case .content:
        if row.oldRole == .removed, row.newRole == .empty {
            return "-"
        }
        if row.oldRole == .empty, row.newRole == .added {
            return "+"
        }
        return nil
    case .fileHeader, .fileMetadata, .hunkHeader, .collapsedContext:
        return nil
    }
}

private func sideBySideMarkerColor(
    for row: DiffPresentation.SideBySideRow,
    theme: MarkdownTheme
) -> PlatformColor {
    switch sideBySideMarker(for: row) {
    case "-":
        theme.diff.removedIndicatorText
    case "+":
        theme.diff.addedIndicatorText
    case "\\":
        theme.diff.annotationIndicatorText
    default:
        theme.diff.gutterText
    }
}

private func maxLineNumberText(
    for displayRows: DiffDisplayRows
) -> String {
    let maxLineNumber: Int = switch displayRows {
    case let .unified(rows):
        rows.reduce(into: 0) { partialResult, row in
            partialResult = max(partialResult, row.oldLineNumber ?? 0, row.newLineNumber ?? 0)
        }
    case let .sideBySide(rows, _):
        rows.reduce(into: 0) { partialResult, row in
            partialResult = max(
                partialResult,
                row.oldCell?.lineNumber ?? 0,
                row.newCell?.lineNumber ?? 0
            )
        }
    }
    return "\(max(maxLineNumber, 0))"
}

private func hasOldLineNumbers(
    for displayRows: DiffDisplayRows
) -> Bool {
    switch displayRows {
    case let .unified(rows):
        rows.contains { $0.oldLineNumber != nil }
    case let .sideBySide(rows, _):
        rows.contains { $0.oldCell?.lineNumber != nil }
    }
}

private func hasNewLineNumbers(
    for displayRows: DiffDisplayRows
) -> Bool {
    switch displayRows {
    case let .unified(rows):
        rows.contains { $0.newLineNumber != nil }
    case let .sideBySide(rows, _):
        rows.contains { $0.newCell?.lineNumber != nil }
    }
}

private func hasMarkerColumn(
    for displayRows: DiffDisplayRows
) -> Bool {
    switch displayRows {
    case let .unified(rows):
        rows.contains {
            switch $0.kind {
            case .removed, .added, .annotation:
                true
            case .fileHeader, .fileMetadata, .hunkHeader, .context, .collapsedContext:
                false
            }
        }
    case let .sideBySide(rows, _):
        rows.contains { sideBySideMarker(for: $0) != nil }
    }
}

private func diffGutterMetrics(
    for displayRows: DiffDisplayRows,
    font: Any
) -> DiffGutterMetrics {
    let numberWidth = maxLineNumberText(for: displayRows)
        .size(withAttributes: [.font: font]).width
    let columnWidth = numberWidth + DiffViewConfiguration.gutterPadding * 2
    return .init(
        oldColumnWidth: hasOldLineNumbers(for: displayRows) ? columnWidth : 0,
        newColumnWidth: hasNewLineNumbers(for: displayRows) ? columnWidth : 0,
        markerColumnWidth: hasMarkerColumn(for: displayRows) ? DiffViewConfiguration.markerColumnWidth : 0
    )
}

private func diffGutterRowRects(
    for metrics: DiffGutterMetrics,
    rowRect: CGRect
) -> DiffGutterRowRects {
    var x = rowRect.minX
    var oldRect: CGRect?
    var newRect: CGRect?
    var markerRect: CGRect?

    if metrics.showsOldColumn {
        oldRect = CGRect(x: x, y: rowRect.minY, width: metrics.oldColumnWidth, height: rowRect.height)
        x += metrics.oldColumnWidth
        if metrics.showsNewColumn || metrics.showsMarkerColumn {
            x += DiffViewConfiguration.separatorWidth
        }
    }

    if metrics.showsNewColumn {
        newRect = CGRect(x: x, y: rowRect.minY, width: metrics.newColumnWidth, height: rowRect.height)
        x += metrics.newColumnWidth
        if metrics.showsMarkerColumn {
            x += DiffViewConfiguration.separatorWidth
        }
    }

    if metrics.showsMarkerColumn {
        markerRect = CGRect(x: x, y: rowRect.minY, width: metrics.markerColumnWidth, height: rowRect.height)
    }

    return .init(oldRect: oldRect, newRect: newRect, markerRect: markerRect)
}

private func diffGutterSeparatorPositions(
    for metrics: DiffGutterMetrics
) -> [CGFloat] {
    var x: CGFloat = 0
    var positions: [CGFloat] = []

    if metrics.showsOldColumn {
        x += metrics.oldColumnWidth
        if metrics.showsNewColumn || metrics.showsMarkerColumn {
            positions.append(x)
            x += DiffViewConfiguration.separatorWidth
        }
    }

    if metrics.showsNewColumn {
        x += metrics.newColumnWidth
        if metrics.showsMarkerColumn {
            positions.append(x)
            x += DiffViewConfiguration.separatorWidth
        }
    }

    if metrics.showsMarkerColumn {
        x += metrics.markerColumnWidth
    }

    if metrics.showsOldColumn || metrics.showsNewColumn || metrics.showsMarkerColumn {
        positions.append(x)
    }

    return positions
}

private func diffContentContainerHeight(
    textSize: CGSize,
    scrollBounds: CGSize,
    theme: MarkdownTheme
) -> CGFloat {
    let contentHeight = textSize.height + DiffViewConfiguration.verticalPadding * 2
    switch theme.diff.scrollBehavior {
    case .horizontalOnly:
        return scrollBounds.height
    case .bothAxes:
        return max(scrollBounds.height, contentHeight)
    }
}

private func sideBySideContentRects(
    in bounds: CGRect,
    textMetrics: DiffSideBySideTextMetrics
) -> DiffSideBySideContentRects {
    let dividerX = min(
        max(
            DiffViewConfiguration.horizontalPadding
                + textMetrics.oldTextWidth
                + textMetrics.separatorTextWidth / 2,
            0
        ),
        bounds.width
    )
    let dividerRect = CGRect(
        x: max(dividerX - DiffViewConfiguration.separatorWidth / 2, 0),
        y: bounds.minY,
        width: DiffViewConfiguration.separatorWidth,
        height: bounds.height
    )
    return .init(
        dividerX: dividerX,
        dividerRect: dividerRect,
        oldRect: CGRect(x: bounds.minX, y: bounds.minY, width: dividerX, height: bounds.height),
        newRect: CGRect(x: dividerX, y: bounds.minY, width: max(bounds.width - dividerX, 0), height: bounds.height)
    )
}

private func makeUnifiedAttributedText(
    rows: [DiffPresentation.UnifiedRow],
    font: Any,
    theme: MarkdownTheme
) -> NSAttributedString {
    let paragraphStyle = makeDiffParagraphStyle()
    let result = NSMutableAttributedString()

    for (index, row) in rows.enumerated() {
        let rowStart = result.length
        var attributes = makeDiffAttributes(
            font: font,
            color: unifiedTextColor(for: row.kind, theme: theme),
            paragraphStyle: paragraphStyle
        )
        if let lineBackgroundColor = unifiedLineBackgroundColor(for: row.kind, theme: theme) {
            attributes[.ltxLineDrawingCallback] = makeFullWidthLineBackgroundAction(
                color: lineBackgroundColor
            )
        }
        result.append(.init(string: row.text, attributes: attributes))

        let rowLength = row.text.utf16.count
        applySyntaxHighlights(
            row.syntaxHighlights,
            to: result,
            baseLocation: rowStart,
            rowLength: rowLength
        )
        applyEmphasis(
            row.emphasizedRanges,
            color: unifiedEmphasisColor(for: row.kind, theme: theme),
            to: result,
            baseLocation: rowStart,
            rowLength: rowLength
        )

        if index < rows.count - 1 {
            result.append(
                .init(
                    string: "\n",
                    attributes: makeDiffAttributes(
                        font: font,
                        color: theme.colors.code,
                        paragraphStyle: paragraphStyle
                    )
                )
            )
        }
    }

    return result
}

private func makeSideBySideAttributedText(
    rows: [DiffPresentation.SideBySideRow],
    textMetrics: DiffSideBySideTextMetrics,
    font: Any,
    theme: MarkdownTheme
) -> NSAttributedString {
    let paragraphStyle = makeDiffParagraphStyle()
    let result = NSMutableAttributedString()

    for (index, row) in rows.enumerated() {
        let rowStart = result.length

        switch row.kind {
        case .fileHeader, .fileMetadata, .hunkHeader, .annotation, .collapsedContext:
            result.append(
                .init(
                    string: row.fullWidthText ?? "",
                    attributes: makeDiffAttributes(
                        font: font,
                        color: sideBySideRowTextColor(for: row.kind, theme: theme),
                        paragraphStyle: paragraphStyle
                    )
                )
            )

        case .content:
            let oldText = row.oldCell?.text ?? ""
            let oldPadded = paddedToUTF16Length(oldText, targetLength: textMetrics.maxOldUTF16Length)
            let separatorText = DiffPresentation.sideBySideSeparatorText
            let newText = row.newCell?.text ?? ""
            let rowText = oldPadded + separatorText + newText

            result.append(
                .init(
                    string: rowText,
                    attributes: makeDiffAttributes(
                        font: font,
                        color: theme.colors.code,
                        paragraphStyle: paragraphStyle
                    )
                )
            )

            let oldRange = NSRange(location: rowStart, length: oldText.utf16.count)
            let newBaseLocation = rowStart + oldPadded.utf16.count + separatorText.utf16.count
            let newRange = NSRange(location: newBaseLocation, length: newText.utf16.count)

            if let oldCell = row.oldCell {
                applySyntaxHighlights(
                    oldCell.syntaxHighlights,
                    to: result,
                    baseLocation: oldRange.location,
                    rowLength: oldRange.length
                )
                applyEmphasis(
                    oldCell.emphasizedRanges,
                    color: sideBySideEmphasisColor(for: row.oldRole, theme: theme),
                    to: result,
                    baseLocation: oldRange.location,
                    rowLength: oldRange.length
                )
            }

            if let newCell = row.newCell {
                applySyntaxHighlights(
                    newCell.syntaxHighlights,
                    to: result,
                    baseLocation: newRange.location,
                    rowLength: newRange.length
                )
                applyEmphasis(
                    newCell.emphasizedRanges,
                    color: sideBySideEmphasisColor(for: row.newRole, theme: theme),
                    to: result,
                    baseLocation: newRange.location,
                    rowLength: newRange.length
                )
            }
        }

        if index < rows.count - 1 {
            result.append(
                .init(
                    string: "\n",
                    attributes: makeDiffAttributes(
                        font: font,
                        color: theme.colors.code,
                        paragraphStyle: paragraphStyle
                    )
                )
            )
        }
    }

    return result
}

#if canImport(UIKit)
    import UIKit

    final class DiffView: UIView {
        var theme: MarkdownTheme = .default {
            didSet {
                titleLabel.font = theme.fonts.code
                textView.selectionBackgroundColor = theme.colors.selectionBackground
                applyTheme()
                updateHeaderVisibility()
                applyRenderBlock()
                invalidateIntrinsicContentSize()
            }
        }

        var renderBlock: DiffRenderBlock = .init(language: nil, rows: []) {
            didSet {
                applyRenderBlock()
            }
        }

        private var cachedTextHeight: CGFloat = 0
        private var displayRows: DiffDisplayRows = .unified([])
        private var sideBySideTextMetrics: DiffSideBySideTextMetrics?

        lazy var scrollView: UIScrollView = .init()
        lazy var barView: UIView = .init()
        lazy var titleLabel: UILabel = .init()
        lazy var copyButton: UIButton = .init(type: .system)
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
            let titleWidth = titleLabel.intrinsicContentSize.width
            let textSize = textView.intrinsicContentSize
            let gutterWidth = gutterView.intrinsicContentSize.width
            let headerWidth = theme.showsBlockHeaders
                ? titleWidth + DiffViewConfiguration.buttonSize.width + DiffViewConfiguration.barPadding * 2
                : 0
            return CGSize(
                width: max(
                    gutterWidth + textSize.width + DiffViewConfiguration.horizontalPadding * 2,
                    headerWidth
                ),
                height: DiffViewConfiguration.intrinsicHeight(for: renderBlock, theme: theme)
            )
        }

        private func configureSubviews() {
            layer.cornerRadius = DiffViewConfiguration.cornerRadius
            layer.cornerCurve = .continuous
            clipsToBounds = true

            barView.backgroundColor = .clear
            addSubview(barView)

            titleLabel.font = theme.fonts.code
            barView.addSubview(titleLabel)

            let copyImage = UIImage(
                systemName: "doc.on.doc",
                withConfiguration: UIImage.SymbolConfiguration(scale: .small)
            )
            copyButton.setImage(copyImage, for: .normal)
            copyButton.accessibilityLabel = "Copy diff"
            copyButton.addTarget(self, action: #selector(handleCopy(_:)), for: .touchUpInside)
            barView.addSubview(copyButton)

            gutterView.backgroundColor = .clear
            addSubview(gutterView)

            scrollView.showsHorizontalScrollIndicator = false
            scrollView.showsVerticalScrollIndicator = false
            scrollView.isDirectionalLockEnabled = true
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
            updateHeaderVisibility()
        }

        private func applyTheme() {
            backgroundColor = theme.diff.backgroundColor ?? theme.colors.codeBackground.withAlphaComponent(0.08)
            layer.borderWidth = theme.diff.borderWidth
            layer.borderColor = theme.diff.borderColor.cgColor
            barView.backgroundColor = theme.diff.fileHeaderBackground
            titleLabel.font = theme.fonts.code
            titleLabel.textColor = theme.diff.fileHeaderText
            copyButton.tintColor = theme.diff.fileHeaderText
        }

        private func updateHeaderVisibility() {
            let showsHeader = theme.showsBlockHeaders
            barView.isHidden = !showsHeader
            titleLabel.isHidden = !showsHeader
            copyButton.isHidden = !showsHeader
        }

        @objc private func handleCopy(_: UIButton) {
            UIPasteboard.general.string = rawDiffSelectionText(from: renderBlock)
            #if !os(visionOS)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
        }

        private func applyRenderBlock() {
            displayRows = DiffDisplayRows.make(for: renderBlock, theme: theme)
            titleLabel.text = diffBlockTitle(for: renderBlock)
            if case let .sideBySide(_, maxOldUTF16Length) = displayRows {
                sideBySideTextMetrics = .make(
                    maxOldUTF16Length: maxOldUTF16Length,
                    font: theme.fonts.code
                )
            } else {
                sideBySideTextMetrics = nil
            }

            textView.attributedText = makeDisplayAttributedText()
            cachedTextHeight = textView.intrinsicContentSize.height

            gutterView.configure(
                displayRows: displayRows,
                contentHeight: cachedTextHeight,
                font: theme.fonts.code,
                theme: theme
            )
            backgroundView.configure(
                displayRows: displayRows,
                sideBySideTextMetrics: sideBySideTextMetrics,
                contentHeight: cachedTextHeight,
                theme: theme
            )
            scrollView.setContentOffset(.zero, animated: false)
            setNeedsLayout()
            invalidateIntrinsicContentSize()
        }

        private func makeDisplayAttributedText() -> NSAttributedString {
            switch displayRows {
            case let .unified(rows):
                return makeUnifiedAttributedText(
                    rows: rows,
                    font: theme.fonts.code,
                    theme: theme
                )
            case let .sideBySide(rows, _):
                return makeSideBySideAttributedText(
                    rows: rows,
                    textMetrics: sideBySideTextMetrics ?? .make(maxOldUTF16Length: 0, font: theme.fonts.code),
                    font: theme.fonts.code,
                    theme: theme
                )
            }
        }

        private func performLayout() {
            let barHeight = DiffViewConfiguration.barHeight(theme: theme)

            guard theme.showsBlockHeaders else {
                barView.frame = .zero
                titleLabel.frame = .zero
                copyButton.frame = .zero

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
                let containerHeight = diffContentContainerHeight(
                    textSize: textSize,
                    scrollBounds: scrollView.bounds.size,
                    theme: theme
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
                scrollView.contentSize = CGSize(
                    width: contentContainerView.bounds.width,
                    height: containerHeight
                )
                return
            }

            barView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: barHeight)

            let buttonSize = DiffViewConfiguration.buttonSize
            copyButton.frame = CGRect(
                x: barView.bounds.width - buttonSize.width,
                y: (barView.bounds.height - buttonSize.height) / 2,
                width: buttonSize.width,
                height: buttonSize.height
            )
            let titleSize = titleLabel.intrinsicContentSize
            let availableTitleWidth = max(copyButton.frame.minX - DiffViewConfiguration.barPadding * 2, 0)
            titleLabel.frame = CGRect(
                x: DiffViewConfiguration.barPadding,
                y: DiffViewConfiguration.barPadding,
                width: min(titleSize.width, availableTitleWidth),
                height: titleSize.height
            )

            let gutterWidth = gutterView.intrinsicContentSize.width
            gutterView.frame = CGRect(
                x: 0,
                y: barHeight,
                width: gutterWidth,
                height: max(bounds.height - barHeight, 0)
            )

            scrollView.frame = CGRect(
                x: gutterWidth,
                y: barHeight,
                width: max(bounds.width - gutterWidth, 0),
                height: max(bounds.height - barHeight, 0)
            )

            let textSize = textView.intrinsicContentSize
            let containerWidth = max(
                scrollView.bounds.width,
                textSize.width + DiffViewConfiguration.horizontalPadding * 2
            )
            let containerHeight = diffContentContainerHeight(
                textSize: textSize,
                scrollBounds: scrollView.bounds.size,
                theme: theme
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
            scrollView.contentSize = CGSize(
                width: contentContainerView.bounds.width,
                height: containerHeight
            )
        }
    }

    extension DiffView: LTXAttributeStringRepresentable {
        func attributedStringRepresentation() -> NSAttributedString {
            NSAttributedString(string: rawDiffSelectionText(from: renderBlock))
        }
    }

    private final class DiffContentBackgroundView: UIView {
        private var displayRows: DiffDisplayRows = .unified([])
        private var sideBySideTextMetrics: DiffSideBySideTextMetrics?
        private var contentHeight: CGFloat = 0
        private var theme: MarkdownTheme = .default

        func configure(
            displayRows: DiffDisplayRows,
            sideBySideTextMetrics: DiffSideBySideTextMetrics?,
            contentHeight: CGFloat,
            theme: MarkdownTheme
        ) {
            self.displayRows = displayRows
            self.sideBySideTextMetrics = sideBySideTextMetrics
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
            guard !displayRows.isEmpty, contentHeight > 0 else { return }

            switch displayRows {
            case let .unified(rows):
                for (index, row) in rows.enumerated() {
                    let rect = diffRowRect(
                        index: index,
                        rowCount: rows.count,
                        contentHeight: contentHeight,
                        bounds: bounds
                    )

                    if let fillColor = unifiedContentRowBackgroundColor(for: row.kind, theme: theme) {
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

            case let .sideBySide(rows, _):
                let textMetrics = sideBySideTextMetrics ?? .make(maxOldUTF16Length: 0, font: theme.fonts.code)
                for (index, row) in rows.enumerated() {
                    let rect = diffRowRect(
                        index: index,
                        rowCount: rows.count,
                        contentHeight: contentHeight,
                        bounds: bounds
                    )

                    switch row.kind {
                    case .fileHeader, .fileMetadata, .hunkHeader, .annotation, .collapsedContext:
                        if let fillColor = sideBySideRowBackgroundColor(for: row.kind, theme: theme) {
                            context.setFillColor(fillColor.cgColor)
                            context.fill(rect)
                        }

                    case .content:
                        let columnRects = sideBySideContentRects(in: rect, textMetrics: textMetrics)

                        if let oldColor = sideBySideCellBackgroundColor(for: row.oldRole, theme: theme) {
                            context.setFillColor(oldColor.cgColor)
                            context.fill(columnRects.oldRect)
                        }

                        if let newColor = sideBySideCellBackgroundColor(for: row.newRole, theme: theme) {
                            context.setFillColor(newColor.cgColor)
                            context.fill(columnRects.newRect)
                        }

                        context.setFillColor(theme.diff.separatorColor.cgColor)
                        context.fill(columnRects.dividerRect)
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
        }
    }

    private final class DiffGutterView: UIView {
        private var displayRows: DiffDisplayRows = .unified([])
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
            displayRows: DiffDisplayRows,
            contentHeight: CGFloat,
            font: UIFont,
            theme: MarkdownTheme
        ) {
            self.displayRows = displayRows
            self.contentHeight = contentHeight
            self.font = font
            self.theme = theme
            setNeedsDisplay()
            invalidateIntrinsicContentSize()
        }

        override var intrinsicContentSize: CGSize {
            let metrics = diffGutterMetrics(for: displayRows, font: font)
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

        private func drawRows(in context: CGContext) {
            guard !displayRows.isEmpty, contentHeight > 0 else { return }

            let metrics = diffGutterMetrics(for: displayRows, font: font)
            let textAttributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: theme.diff.gutterText,
            ]

            switch displayRows {
            case let .unified(rows):
                for (index, row) in rows.enumerated() {
                    let rect = diffRowRect(
                        index: index,
                        rowCount: rows.count,
                        contentHeight: contentHeight,
                        bounds: bounds
                    )

                    if let fillColor = unifiedRowBackgroundColor(for: row.kind, theme: theme) {
                        context.setFillColor(fillColor.cgColor)
                        context.fill(rect)
                    } else {
                        context.setFillColor(theme.diff.gutterBackground.cgColor)
                        context.fill(rect)
                    }

                    let markerAttributes: [NSAttributedString.Key: Any] = [
                        .font: font,
                        .foregroundColor: markerColor(for: row.kind),
                    ]
                    let rowRects = diffGutterRowRects(for: metrics, rowRect: rect)

                    drawNumber(
                        row.oldLineNumber,
                        in: rowRects.oldRect,
                        attributes: textAttributes
                    )
                    drawNumber(
                        row.newLineNumber,
                        in: rowRects.newRect,
                        attributes: textAttributes
                    )
                    drawMarker(
                        marker(for: row.kind),
                        in: rowRects.markerRect,
                        attributes: markerAttributes
                    )
                }

            case let .sideBySide(rows, _):
                for (index, row) in rows.enumerated() {
                    let rect = diffRowRect(
                        index: index,
                        rowCount: rows.count,
                        contentHeight: contentHeight,
                        bounds: bounds
                    )

                    let rowRects = diffGutterRowRects(for: metrics, rowRect: rect)

                    switch row.kind {
                    case .fileHeader, .fileMetadata, .hunkHeader, .annotation, .collapsedContext:
                        if let fillColor = sideBySideRowBackgroundColor(for: row.kind, theme: theme) {
                            context.setFillColor(fillColor.cgColor)
                            context.fill(rect)
                        } else {
                            context.setFillColor(theme.diff.gutterBackground.cgColor)
                            context.fill(rect)
                        }

                    case .content:
                        if let oldColor = sideBySideCellBackgroundColor(for: row.oldRole, theme: theme) {
                            context.setFillColor(oldColor.cgColor)
                            if let oldRect = rowRects.oldRect {
                                context.fill(oldRect)
                            }
                        } else if let oldRect = rowRects.oldRect {
                            context.setFillColor(theme.diff.gutterBackground.cgColor)
                            context.fill(oldRect)
                        }

                        if let newColor = sideBySideCellBackgroundColor(for: row.newRole, theme: theme) {
                            context.setFillColor(newColor.cgColor)
                            if let newRect = rowRects.newRect {
                                context.fill(newRect)
                            }
                        } else if let newRect = rowRects.newRect {
                            context.setFillColor(theme.diff.gutterBackground.cgColor)
                            context.fill(newRect)
                        }

                        if let marker = sideBySideMarker(for: row), !marker.isEmpty {
                            if let markerColor = sideBySideMarkerBackgroundColor(for: row, theme: theme) {
                                context.setFillColor(markerColor.cgColor)
                            } else {
                                context.setFillColor(theme.diff.gutterBackground.cgColor)
                            }
                            if let markerRect = rowRects.markerRect {
                                context.fill(markerRect)
                            }
                        } else if let markerRect = rowRects.markerRect {
                            context.setFillColor(theme.diff.gutterBackground.cgColor)
                            context.fill(markerRect)
                        }
                    }

                    let markerAttributes: [NSAttributedString.Key: Any] = [
                        .font: font,
                        .foregroundColor: sideBySideMarkerColor(for: row, theme: theme),
                    ]

                    drawNumber(
                        row.oldCell?.lineNumber,
                        in: rowRects.oldRect,
                        attributes: textAttributes
                    )
                    drawNumber(
                        row.newCell?.lineNumber,
                        in: rowRects.newRect,
                        attributes: textAttributes
                    )
                    drawMarker(
                        sideBySideMarker(for: row),
                        in: rowRects.markerRect,
                        attributes: markerAttributes
                    )
                }
            }
        }

        private func drawNumber(
            _ number: Int?,
            in rect: CGRect?,
            attributes: [NSAttributedString.Key: Any]
        ) {
            guard let number, let rect else { return }
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
            in rect: CGRect?,
            attributes: [NSAttributedString.Key: Any]
        ) {
            guard let marker, let rect else { return }
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
            let metrics = diffGutterMetrics(for: displayRows, font: font)
            context.setFillColor(theme.diff.separatorColor.cgColor)
            for x in diffGutterSeparatorPositions(for: metrics) {
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

        private func marker(for kind: DiffPresentation.UnifiedRow.Kind) -> String? {
            switch kind {
            case .removed:
                "-"
            case .added:
                "+"
            case .annotation:
                "\\"
            case .fileHeader, .fileMetadata, .hunkHeader, .context, .collapsedContext:
                nil
            }
        }

        private func markerColor(for kind: DiffPresentation.UnifiedRow.Kind) -> UIColor {
            switch kind {
            case .removed:
                theme.diff.removedIndicatorText
            case .added:
                theme.diff.addedIndicatorText
            case .annotation:
                theme.diff.annotationIndicatorText
            case .fileHeader, .fileMetadata, .hunkHeader, .context, .collapsedContext:
                theme.diff.gutterText
            }
        }
    }

#elseif canImport(AppKit)
    import AppKit

    final class DiffView: NSView {
        var theme: MarkdownTheme = .default {
            didSet {
                titleLabel.font = theme.fonts.code
                textView.selectionBackgroundColor = theme.colors.selectionBackground
                applyTheme()
                updateHeaderVisibility()
                applyRenderBlock()
                invalidateIntrinsicContentSize()
            }
        }

        var renderBlock: DiffRenderBlock = .init(language: nil, rows: []) {
            didSet {
                applyRenderBlock()
            }
        }

        private var cachedTextHeight: CGFloat = 0
        private var displayRows: DiffDisplayRows = .unified([])
        private var sideBySideTextMetrics: DiffSideBySideTextMetrics?

        lazy var scrollView: NSScrollView = {
            let scrollView = NSScrollView()
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            scrollView.drawsBackground = false
            scrollView.automaticallyAdjustsContentInsets = false
            return scrollView
        }()

        lazy var barView: NSView = .init()
        lazy var titleLabel: NSTextField = {
            let label = NSTextField(labelWithString: "")
            label.isEditable = false
            label.isBordered = false
            label.backgroundColor = .clear
            return label
        }()
        lazy var copyButton: NSButton = .init(title: "", target: nil, action: nil)
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
            let titleWidth = titleLabel.intrinsicContentSize.width
            let textSize = textView.intrinsicContentSize
            let gutterWidth = gutterView.intrinsicContentSize.width
            let headerWidth = theme.showsBlockHeaders
                ? titleWidth + DiffViewConfiguration.buttonSize.width + DiffViewConfiguration.barPadding * 2
                : 0
            return CGSize(
                width: max(
                    gutterWidth + textSize.width + DiffViewConfiguration.horizontalPadding * 2,
                    headerWidth
                ),
                height: DiffViewConfiguration.intrinsicHeight(for: renderBlock, theme: theme)
            )
        }

        private func configureSubviews() {
            wantsLayer = true
            layer?.cornerRadius = DiffViewConfiguration.cornerRadius

            barView.wantsLayer = true
            addSubview(barView)
            barView.addSubview(titleLabel)

            if let copyImage = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy diff") {
                copyButton.image = copyImage
            }
            copyButton.target = self
            copyButton.action = #selector(handleCopy(_:))
            copyButton.bezelStyle = .inline
            copyButton.isBordered = false
            barView.addSubview(copyButton)

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
            updateHeaderVisibility()
        }

        private func applyTheme() {
            layer?.backgroundColor = (theme.diff.backgroundColor ?? theme.colors.codeBackground.withAlphaComponent(0.08)).cgColor
            layer?.borderWidth = theme.diff.borderWidth
            layer?.borderColor = theme.diff.borderColor.cgColor
            barView.layer?.backgroundColor = theme.diff.fileHeaderBackground.cgColor
            titleLabel.font = theme.fonts.code
            titleLabel.textColor = theme.diff.fileHeaderText
            copyButton.contentTintColor = theme.diff.fileHeaderText
            scrollView.verticalScrollElasticity = theme.diff.scrollBehavior == .bothAxes ? .automatic : .none
        }

        private func updateHeaderVisibility() {
            let showsHeader = theme.showsBlockHeaders
            barView.isHidden = !showsHeader
            titleLabel.isHidden = !showsHeader
            copyButton.isHidden = !showsHeader
        }

        @objc private func handleCopy(_: Any?) {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(rawDiffSelectionText(from: renderBlock), forType: .string)
        }

        private func applyRenderBlock() {
            displayRows = DiffDisplayRows.make(for: renderBlock, theme: theme)
            titleLabel.stringValue = diffBlockTitle(for: renderBlock)
            if case let .sideBySide(_, maxOldUTF16Length) = displayRows {
                sideBySideTextMetrics = .make(
                    maxOldUTF16Length: maxOldUTF16Length,
                    font: theme.fonts.code
                )
            } else {
                sideBySideTextMetrics = nil
            }

            textView.attributedText = makeDisplayAttributedText()
            cachedTextHeight = textView.intrinsicContentSize.height

            gutterView.configure(
                displayRows: displayRows,
                contentHeight: cachedTextHeight,
                font: theme.fonts.code,
                theme: theme
            )
            backgroundView.configure(
                displayRows: displayRows,
                sideBySideTextMetrics: sideBySideTextMetrics,
                contentHeight: cachedTextHeight,
                theme: theme
            )
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
            needsLayout = true
            invalidateIntrinsicContentSize()
        }

        private func makeDisplayAttributedText() -> NSAttributedString {
            switch displayRows {
            case let .unified(rows):
                return makeUnifiedAttributedText(
                    rows: rows,
                    font: theme.fonts.code,
                    theme: theme
                )
            case let .sideBySide(rows, _):
                return makeSideBySideAttributedText(
                    rows: rows,
                    textMetrics: sideBySideTextMetrics ?? .make(maxOldUTF16Length: 0, font: theme.fonts.code),
                    font: theme.fonts.code,
                    theme: theme
                )
            }
        }

        private func performLayout() {
            let barHeight = DiffViewConfiguration.barHeight(theme: theme)

            guard theme.showsBlockHeaders else {
                barView.frame = .zero
                titleLabel.frame = .zero
                copyButton.frame = .zero

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
                let containerHeight = diffContentContainerHeight(
                    textSize: textSize,
                    scrollBounds: scrollView.bounds.size,
                    theme: theme
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
                scrollView.documentView?.frame = contentContainerView.frame
                return
            }

            barView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: barHeight)

            let buttonSize = DiffViewConfiguration.buttonSize
            copyButton.frame = CGRect(
                x: barView.bounds.width - buttonSize.width,
                y: (barView.bounds.height - buttonSize.height) / 2,
                width: buttonSize.width,
                height: buttonSize.height
            )
            let titleSize = titleLabel.intrinsicContentSize
            let availableTitleWidth = max(copyButton.frame.minX - DiffViewConfiguration.barPadding * 2, 0)
            titleLabel.frame = CGRect(
                x: DiffViewConfiguration.barPadding,
                y: DiffViewConfiguration.barPadding,
                width: min(titleSize.width, availableTitleWidth),
                height: titleSize.height
            )

            let gutterWidth = gutterView.intrinsicContentSize.width
            gutterView.frame = CGRect(
                x: 0,
                y: barHeight,
                width: gutterWidth,
                height: max(bounds.height - barHeight, 0)
            )

            scrollView.frame = CGRect(
                x: gutterWidth,
                y: barHeight,
                width: max(bounds.width - gutterWidth, 0),
                height: max(bounds.height - barHeight, 0)
            )

            let textSize = textView.intrinsicContentSize
            let containerWidth = max(
                scrollView.bounds.width,
                textSize.width + DiffViewConfiguration.horizontalPadding * 2
            )
            let containerHeight = diffContentContainerHeight(
                textSize: textSize,
                scrollBounds: scrollView.bounds.size,
                theme: theme
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
            scrollView.documentView?.frame = contentContainerView.frame
        }
    }

    extension DiffView: LTXAttributeStringRepresentable {
        func attributedStringRepresentation() -> NSAttributedString {
            NSAttributedString(string: rawDiffSelectionText(from: renderBlock))
        }
    }

    private final class DiffContainerView: NSView {
        override var isFlipped: Bool {
            true
        }
    }

    private final class DiffContentBackgroundView: NSView {
        private var displayRows: DiffDisplayRows = .unified([])
        private var sideBySideTextMetrics: DiffSideBySideTextMetrics?
        private var contentHeight: CGFloat = 0
        private var theme: MarkdownTheme = .default

        override var isFlipped: Bool {
            true
        }

        func configure(
            displayRows: DiffDisplayRows,
            sideBySideTextMetrics: DiffSideBySideTextMetrics?,
            contentHeight: CGFloat,
            theme: MarkdownTheme
        ) {
            self.displayRows = displayRows
            self.sideBySideTextMetrics = sideBySideTextMetrics
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
            guard !displayRows.isEmpty, contentHeight > 0 else { return }

            switch displayRows {
            case let .unified(rows):
                for (index, row) in rows.enumerated() {
                    let rect = diffRowRect(
                        index: index,
                        rowCount: rows.count,
                        contentHeight: contentHeight,
                        bounds: bounds
                    )

                    if let fillColor = unifiedContentRowBackgroundColor(for: row.kind, theme: theme) {
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

            case let .sideBySide(rows, _):
                let textMetrics = sideBySideTextMetrics ?? .make(maxOldUTF16Length: 0, font: theme.fonts.code)
                for (index, row) in rows.enumerated() {
                    let rect = diffRowRect(
                        index: index,
                        rowCount: rows.count,
                        contentHeight: contentHeight,
                        bounds: bounds
                    )

                    switch row.kind {
                    case .fileHeader, .fileMetadata, .hunkHeader, .annotation, .collapsedContext:
                        if let fillColor = sideBySideRowBackgroundColor(for: row.kind, theme: theme) {
                            context.setFillColor(fillColor.cgColor)
                            context.fill(rect)
                        }

                    case .content:
                        let columnRects = sideBySideContentRects(in: rect, textMetrics: textMetrics)

                        if let oldColor = sideBySideCellBackgroundColor(for: row.oldRole, theme: theme) {
                            context.setFillColor(oldColor.cgColor)
                            context.fill(columnRects.oldRect)
                        }

                        if let newColor = sideBySideCellBackgroundColor(for: row.newRole, theme: theme) {
                            context.setFillColor(newColor.cgColor)
                            context.fill(columnRects.newRect)
                        }

                        context.setFillColor(theme.diff.separatorColor.cgColor)
                        context.fill(columnRects.dividerRect)
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
        }
    }

    private final class DiffGutterView: NSView {
        private var displayRows: DiffDisplayRows = .unified([])
        private var font: NSFont = .monospacedSystemFont(ofSize: 12, weight: .regular)
        private var theme: MarkdownTheme = .default
        private var contentHeight: CGFloat = 0

        override var isFlipped: Bool {
            true
        }

        func configure(
            displayRows: DiffDisplayRows,
            contentHeight: CGFloat,
            font: NSFont,
            theme: MarkdownTheme
        ) {
            self.displayRows = displayRows
            self.contentHeight = contentHeight
            self.font = font
            self.theme = theme
            needsDisplay = true
            invalidateIntrinsicContentSize()
        }

        override var intrinsicContentSize: CGSize {
            let metrics = diffGutterMetrics(for: displayRows, font: font)
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

        private func drawRows(in context: CGContext) {
            guard !displayRows.isEmpty, contentHeight > 0 else { return }

            let metrics = diffGutterMetrics(for: displayRows, font: font)
            let textAttributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: theme.diff.gutterText,
            ]

            switch displayRows {
            case let .unified(rows):
                for (index, row) in rows.enumerated() {
                    let rect = diffRowRect(
                        index: index,
                        rowCount: rows.count,
                        contentHeight: contentHeight,
                        bounds: bounds
                    )

                    if let fillColor = unifiedRowBackgroundColor(for: row.kind, theme: theme) {
                        context.setFillColor(fillColor.cgColor)
                        context.fill(rect)
                    } else {
                        context.setFillColor(theme.diff.gutterBackground.cgColor)
                        context.fill(rect)
                    }

                    let markerAttributes: [NSAttributedString.Key: Any] = [
                        .font: font,
                        .foregroundColor: markerColor(for: row.kind),
                    ]
                    let rowRects = diffGutterRowRects(for: metrics, rowRect: rect)

                    drawNumber(
                        row.oldLineNumber,
                        in: rowRects.oldRect,
                        attributes: textAttributes
                    )
                    drawNumber(
                        row.newLineNumber,
                        in: rowRects.newRect,
                        attributes: textAttributes
                    )
                    drawMarker(
                        marker(for: row.kind),
                        in: rowRects.markerRect,
                        attributes: markerAttributes
                    )
                }

            case let .sideBySide(rows, _):
                for (index, row) in rows.enumerated() {
                    let rect = diffRowRect(
                        index: index,
                        rowCount: rows.count,
                        contentHeight: contentHeight,
                        bounds: bounds
                    )

                    let rowRects = diffGutterRowRects(for: metrics, rowRect: rect)

                    switch row.kind {
                    case .fileHeader, .fileMetadata, .hunkHeader, .annotation, .collapsedContext:
                        if let fillColor = sideBySideRowBackgroundColor(for: row.kind, theme: theme) {
                            context.setFillColor(fillColor.cgColor)
                            context.fill(rect)
                        } else {
                            context.setFillColor(theme.diff.gutterBackground.cgColor)
                            context.fill(rect)
                        }

                    case .content:
                        if let oldColor = sideBySideCellBackgroundColor(for: row.oldRole, theme: theme) {
                            context.setFillColor(oldColor.cgColor)
                            if let oldRect = rowRects.oldRect {
                                context.fill(oldRect)
                            }
                        } else if let oldRect = rowRects.oldRect {
                            context.setFillColor(theme.diff.gutterBackground.cgColor)
                            context.fill(oldRect)
                        }

                        if let newColor = sideBySideCellBackgroundColor(for: row.newRole, theme: theme) {
                            context.setFillColor(newColor.cgColor)
                            if let newRect = rowRects.newRect {
                                context.fill(newRect)
                            }
                        } else if let newRect = rowRects.newRect {
                            context.setFillColor(theme.diff.gutterBackground.cgColor)
                            context.fill(newRect)
                        }

                        if let marker = sideBySideMarker(for: row), !marker.isEmpty {
                            if let markerColor = sideBySideMarkerBackgroundColor(for: row, theme: theme) {
                                context.setFillColor(markerColor.cgColor)
                            } else {
                                context.setFillColor(theme.diff.gutterBackground.cgColor)
                            }
                            if let markerRect = rowRects.markerRect {
                                context.fill(markerRect)
                            }
                        } else if let markerRect = rowRects.markerRect {
                            context.setFillColor(theme.diff.gutterBackground.cgColor)
                            context.fill(markerRect)
                        }
                    }

                    let markerAttributes: [NSAttributedString.Key: Any] = [
                        .font: font,
                        .foregroundColor: sideBySideMarkerColor(for: row, theme: theme),
                    ]

                    drawNumber(
                        row.oldCell?.lineNumber,
                        in: rowRects.oldRect,
                        attributes: textAttributes
                    )
                    drawNumber(
                        row.newCell?.lineNumber,
                        in: rowRects.newRect,
                        attributes: textAttributes
                    )
                    drawMarker(
                        sideBySideMarker(for: row),
                        in: rowRects.markerRect,
                        attributes: markerAttributes
                    )
                }
            }
        }

        private func drawNumber(
            _ number: Int?,
            in rect: CGRect?,
            attributes: [NSAttributedString.Key: Any]
        ) {
            guard let number, let rect else { return }
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
            in rect: CGRect?,
            attributes: [NSAttributedString.Key: Any]
        ) {
            guard let marker, let rect else { return }
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
            let metrics = diffGutterMetrics(for: displayRows, font: font)
            context.setFillColor(theme.diff.separatorColor.cgColor)
            for x in diffGutterSeparatorPositions(for: metrics) {
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

        private func marker(for kind: DiffPresentation.UnifiedRow.Kind) -> String? {
            switch kind {
            case .removed:
                "-"
            case .added:
                "+"
            case .annotation:
                "\\"
            case .fileHeader, .fileMetadata, .hunkHeader, .context, .collapsedContext:
                nil
            }
        }

        private func markerColor(for kind: DiffPresentation.UnifiedRow.Kind) -> NSColor {
            switch kind {
            case .removed:
                theme.diff.removedIndicatorText
            case .added:
                theme.diff.addedIndicatorText
            case .annotation:
                theme.diff.annotationIndicatorText
            case .fileHeader, .fileMetadata, .hunkHeader, .context, .collapsedContext:
                theme.diff.gutterText
            }
        }
    }
#endif
