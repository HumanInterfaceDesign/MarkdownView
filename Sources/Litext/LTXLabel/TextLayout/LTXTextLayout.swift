//
//  Created by Lakr233 & Helixform on 2025/2/18.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreGraphics
import CoreText
import Foundation
import QuartzCore

private let kTruncationToken = "\u{2026}"

private nonisolated func _hasHighlightAttributes(_ attributes: [NSAttributedString.Key: Any]) -> Bool {
    if attributes[.link] != nil {
        return true
    }
    if attributes[LTXAttachmentAttributeName] != nil {
        return true
    }
    return false
}

/// Nonisolated so a fully built layout can draw from background tile renders
/// (`draw(in:visibleRect:)`). Not internally synchronized: build and mutate on
/// one actor, and once a layout is shared with a background renderer treat it
/// as frozen — swap in a fresh instance instead of mutating `containerSize`.
/// The highlight-region API stays main-actor: it reaches into attachments,
/// which hold views.
public nonisolated class LTXTextLayout: NSObject {
    public private(set) var attributedString: NSAttributedString
    @MainActor public var highlightRegions: [LTXHighlightRegion] {
        Array(_highlightRegions.values)
    }

    public var containerSize: CGSize {
        didSet {
            cachedSuggestedSize = nil
            cachedSuggestedSizeConstraint = nil
            generateLayout()
        }
    }

    var ctFrame: CTFrame?

    private var framesetter: CTFramesetter
    private var lines: [CTLine]?
    private var lineOrigins: [CGPoint]?
    private var lineBands: [LineBand] = []
    private var hasOrderedLineBands = true
    private struct PrefixSnapshot {
        let lines: [CTLine]
        let origins: [CGPoint]
        let size: CGSize
        let anchorLocation: Int
        let anchorOrigin: CGPoint
    }
    private var prefixSnapshot: PrefixSnapshot?
    private(set) var reusedLineCount = 0
    private var _highlightRegions: [Int: LTXHighlightRegion]
    private var cachedSuggestedSize: CGSize?
    private var cachedSuggestedSizeConstraint: CGSize?
    private let hasLineDrawingActions: Bool
    private let hasHighlightAttributes: Bool

    public class func textLayout(
        withAttributedString attributedString: NSAttributedString
    ) -> LTXTextLayout {
        LTXTextLayout(attributedString: attributedString)
    }

    public init(attributedString: NSAttributedString) {
        self.attributedString = attributedString
        containerSize = .zero
        framesetter = CTFramesetterCreateWithAttributedString(
            attributedString
        )
        _highlightRegions = [:]

        let fullRange = NSRange(location: 0, length: attributedString.length)
        var foundDrawingAction = false
        var foundHighlight = false
        if fullRange.length > 0 {
            attributedString.enumerateAttributes(in: fullRange) { attributes, _, stop in
                if attributes[LTXLineDrawingCallbackName] != nil {
                    foundDrawingAction = true
                }
                if _hasHighlightAttributes(attributes) {
                    foundHighlight = true
                }
                if foundDrawingAction, foundHighlight {
                    stop.pointee = true
                }
            }
        }
        hasLineDrawingActions = foundDrawingAction
        hasHighlightAttributes = foundHighlight

        super.init()
    }

    deinit {}

    func reusePrefix(from previous: LTXTextLayout, utf16Length length: Int) {
        guard length > 0, length <= attributedString.length,
              length <= previous.attributedString.length,
              previous.containerSize.width > 0,
              let oldLines = previous.lines, let oldOrigins = previous.lineOrigins else { return }
        let prefixRange = NSRange(location: 0, length: length)
        guard attributedString.attributedSubstring(from: prefixRange).isEqual(
            to: previous.attributedString.attributedSubstring(from: prefixRange)
        ) else { return }
        let source = attributedString.string as NSString
        let anchor = source.paragraphRange(for: NSRange(location: length - 1, length: 0))
        // Re-layout one complete, unchanged paragraph at the join. Its baseline
        // anchors paragraph spacing without independently stacking block heights.
        guard NSMaxRange(anchor) <= length,
              let anchorIndex = oldLines.firstIndex(where: {
                  CTLineGetStringRange($0).location == anchor.location
              }), anchorIndex > 0 else { return }
        prefixSnapshot = PrefixSnapshot(
            lines: Array(oldLines[..<anchorIndex]),
            origins: Array(oldOrigins[..<anchorIndex]),
            size: previous.containerSize,
            anchorLocation: anchor.location,
            anchorOrigin: oldOrigins[anchorIndex]
        )
    }

    public func invalidateLayout() {
        prefixSnapshot = nil
        cachedSuggestedSize = nil
        cachedSuggestedSizeConstraint = nil
        generateLayout()
    }

    public func suggestContainerSize(withSize size: CGSize) -> CGSize {
        if let cachedSuggestedSize,
           let cachedSuggestedSizeConstraint,
           cachedSuggestedSizeConstraint.width == size.width,
           cachedSuggestedSizeConstraint.height == size.height
        {
            return cachedSuggestedSize
        }
        let result = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: 0),
            nil,
            size,
            nil
        )
        cachedSuggestedSize = result
        cachedSuggestedSizeConstraint = size
        return result
    }

    public func draw(in context: CGContext) {
        draw(in: context, glyphAlpha: nil)
    }

    /// Draws the laid-out text. When `glyphAlpha` is supplied, glyphs are drawn
    /// run-by-run with a per-character alpha (used for the streaming fade-in
    /// reveal); otherwise the fast `CTFrameDraw` path is used unchanged.
    public func draw(in context: CGContext, glyphAlpha: ((Int) -> CGFloat)?) {
        context.saveGState()

        context.setAllowsAntialiasing(true)
        context.setShouldSmoothFonts(true)

        context.translateBy(x: 0, y: containerSize.height)
        context.scaleBy(x: 1, y: -1)

        if let glyphAlpha {
            drawGlyphs(in: context, glyphAlpha: glyphAlpha)
        } else if let ctFrame {
            CTFrameDraw(ctFrame, context)
        } else {
            context.textMatrix = .identity
            enumerateLines { line, _, origin in
                context.textPosition = origin
                CTLineDraw(line, context)
            }
        }

        processLineDrawingActions(in: context, glyphAlpha: glyphAlpha)

        context.restoreGState()
    }

    /// Draws only the lines intersecting `visibleRect`, given in the layout's
    /// top-left-origin coordinate space. Backs tiled rendering of oversized
    /// content: each tile pays for its own band of lines instead of the whole
    /// document. Safe to call off the main thread as long as the layout isn't
    /// mutated concurrently (swap in a fresh instance rather than changing
    /// `containerSize` under in-flight draws).
    public func draw(
        in context: CGContext,
        visibleRect: CGRect,
        glyphAlpha: ((Int) -> CGFloat)? = nil
    ) {
        context.saveGState()

        context.setAllowsAntialiasing(true)
        context.setShouldSmoothFonts(true)

        context.translateBy(x: 0, y: containerSize.height)
        context.scaleBy(x: 1, y: -1)

        // The container is flipped for CoreText; convert the band once.
        let band = LineBand(
            minY: containerSize.height - visibleRect.maxY,
            maxY: containerSize.height - visibleRect.minY
        )
        if let glyphAlpha {
            drawGlyphs(in: context, band: band, glyphAlpha: glyphAlpha)
        } else {
            context.textMatrix = .identity
            enumerateLines(intersecting: band) { line, _, lineOrigin in
                context.textPosition = lineOrigin
                CTLineDraw(line, context)
            }
        }

        processLineDrawingActions(in: context, band: band, glyphAlpha: glyphAlpha)

        context.restoreGState()
    }

    /// Vertical slice of the layout in CoreText (bottom-up) coordinates.
    private struct LineBand {
        let minY: CGFloat
        let maxY: CGFloat
    }

    /// Per-run draw that varies alpha by character index. Consecutive glyphs with
    /// near-equal alpha are batched into a single `CTRunDraw` so the cost stays
    /// close to the frame draw while still producing a smooth fade edge.
    private func drawGlyphs(in context: CGContext, band: LineBand? = nil, glyphAlpha: (Int) -> CGFloat) {
        context.textMatrix = .identity
        enumerateLines(intersecting: band) { line, _, lineOrigin in
            let glyphRuns = CTLineGetGlyphRuns(line) as NSArray
            for runIndex in 0 ..< glyphRuns.count {
                guard let run = glyphRuns[runIndex] as! CTRun? else { continue }
                let glyphCount = CTRunGetGlyphCount(run)
                guard glyphCount > 0 else { continue }

                var indices = [CFIndex](repeating: 0, count: glyphCount)
                CTRunGetStringIndices(run, CFRange(location: 0, length: 0), &indices)

                context.textPosition = lineOrigin
                var start = 0
                while start < glyphCount {
                    let alpha = clampAlpha(glyphAlpha(indices[start]))
                    var end = start + 1
                    while end < glyphCount, abs(clampAlpha(glyphAlpha(indices[end])) - alpha) < 0.03 {
                        end += 1
                    }
                    if alpha > 0.001 {
                        context.setAlpha(alpha)
                        CTRunDraw(run, context, CFRange(location: start, length: end - start))
                    }
                    start = end
                }
            }
        }
        context.setAlpha(1)
    }

    private func clampAlpha(_ value: CGFloat) -> CGFloat {
        max(0, min(1, value))
    }

    private func processLineDrawingActions(
        in context: CGContext,
        band: LineBand? = nil,
        glyphAlpha: ((Int) -> CGFloat)? = nil
    ) {
        guard hasLineDrawingActions else { return }
        enumerateLines(intersecting: band) { line, _, lineOrigin in
            let glyphRuns = CTLineGetGlyphRuns(line) as NSArray

            for i in 0 ..< glyphRuns.count {
                guard let glyphRun = glyphRuns[i] as! CTRun?
                else { continue }

                let attributes = CTRunGetAttributes(glyphRun) as! [NSAttributedString.Key: Any]
                if let action = attributes[LTXLineDrawingCallbackName] as? LTXLineDrawingAction {
                    context.saveGState()
                    // Fade line decorations (list bullets, quote bars, …) in step
                    // with the text on their line so they reveal together rather
                    // than popping in ahead of the streaming sweep. Key off the
                    // line's first character index (the marker sits at the item's
                    // start); the run's own glyph indices aren't reliable here.
                    if let glyphAlpha {
                        let lineStart = CTLineGetStringRange(line).location
                        context.setAlpha(clampAlpha(glyphAlpha(lineStart)))
                    }
                    action.action(context, line, lineOrigin)
                    context.restoreGState()
                }
            }
        }
    }

    @MainActor public func updateHighlightRegions() {
        _highlightRegions.removeAll()
        extractHighlightRegions()
    }

    public func rects(for range: NSRange) -> [CGRect] {
        var rects = [CGRect]()
        enumerateTextRects(in: range) { rect in
            rects.append(rect)
        }
        return rects
    }

    public func lineRects() -> [CGRect] {
        guard let lines, let origins = lineOrigins else { return [] }

        let lineCount = lines.count
        var rects: [CGRect] = []
        rects.reserveCapacity(lineCount)

        for i in 0 ..< lineCount {
            let line = lines[i]
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            let width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
            let origin = origins[i]
            rects.append(
                CGRect(
                    x: origin.x,
                    y: origin.y - descent,
                    width: width,
                    height: ascent + descent + leading
                )
            )
        }

        return rects
    }

    /// String range of each laid-out line, parallel to `lineRects()`. With soft
    /// wrapping enabled a single logical line can span several entries.
    public func lineStringRanges() -> [NSRange] {
        guard let lines else { return [] }
        return lines.map { line in
            let range = CTLineGetStringRange(line)
            return NSRange(location: range.location, length: range.length)
        }
    }

    public func enumerateTextRects(in range: NSRange, using block: (CGRect) -> Void) {
        guard let lines, let origins = lineOrigins else { return }

        let lineCount = lines.count

        for i in 0 ..< lineCount {
            let line = lines[i]
            let lineRange = CTLineGetStringRange(line)

            let lineStart = lineRange.location
            let lineEnd = lineStart + lineRange.length
            let selStart = range.location
            let selEnd = selStart + range.length

            // Lines are ordered by string position; once past the range, no
            // later line can overlap it.
            if selEnd < lineStart {
                break
            }
            if selStart > lineEnd {
                continue
            }

            let overlapStart = max(lineStart, selStart)
            let overlapEnd = min(lineEnd, selEnd)

            if overlapStart >= overlapEnd {
                continue
            }

            calculateAndAddTextRect(
                for: line,
                origin: origins[i],
                overlapStart: overlapStart,
                overlapEnd: overlapEnd,
                lineStart: lineStart,
                lineEnd: lineEnd,
                using: block
            )
        }
    }

    private func calculateAndAddTextRect(
        for line: CTLine,
        origin: CGPoint,
        overlapStart: CFIndex,
        overlapEnd: CFIndex,
        lineStart: CFIndex,
        lineEnd: CFIndex,
        using block: (CGRect) -> Void
    ) {
        var startOffset: CGFloat = 0
        var endOffset: CGFloat = 0

        if overlapStart > lineStart {
            startOffset = CTLineGetOffsetForStringIndex(
                line,
                overlapStart,
                nil
            )
        }

        if overlapEnd < lineEnd {
            endOffset = CTLineGetOffsetForStringIndex(
                line,
                overlapEnd,
                nil
            )
        } else {
            endOffset = CTLineGetTypographicBounds(
                line,
                nil,
                nil,
                nil
            )
        }

        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        CTLineGetTypographicBounds(
            line,
            &ascent,
            &descent,
            &leading
        )

        let rect = CGRect(
            x: origin.x + startOffset,
            y: origin.y - descent,
            width: endOffset - startOffset,
            height: ascent + descent + leading
        )

        block(rect)
    }

    // MARK: - Private Methods

    private func generateLayout() {
        lines = nil
        lineOrigins = nil
        ctFrame = nil
        reusedLineCount = 0
        lineBands.removeAll(keepingCapacity: true)
        hasOrderedLineBands = true

        let path = CGPath(rect: CGRect(origin: .zero, size: containerSize), transform: nil)
        if !generateTailLayout(path: path) {
            prefixSnapshot = nil
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
            ctFrame = frame
            let frameLines = CTFrameGetLines(frame) as! [CTLine]
            var origins = [CGPoint](repeating: .zero, count: frameLines.count)
            if !origins.isEmpty { CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins) }
            lines = frameLines
            lineOrigins = origins
        }
        guard let lines, let lineOrigins else { return }
        lineBands.reserveCapacity(lines.count)
        for (index, line) in lines.enumerated() {
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
            let band = LineBand(minY: lineOrigins[index].y - descent, maxY: lineOrigins[index].y + ascent + leading)
            if let previous = lineBands.last,
               band.minY > previous.minY || band.maxY > previous.maxY {
                hasOrderedLineBands = false
            }
            lineBands.append(band)
        }
    }

    private func generateTailLayout(path: CGPath) -> Bool {
        guard let prefix = prefixSnapshot, prefix.size.width == containerSize.width,
              containerSize.height > 0 else { return false }
        let frame = CTFramesetterCreateFrame(
            framesetter, CFRange(location: prefix.anchorLocation, length: 0), path, nil
        )
        let visible = CTFrameGetVisibleStringRange(frame)
        // Finite/truncated containers retain the full-frame implementation.
        guard visible.location + visible.length == attributedString.length,
              let tailLines = CTFrameGetLines(frame) as? [CTLine], !tailLines.isEmpty,
              CTLineGetStringRange(tailLines[0]).location == prefix.anchorLocation else { return false }
        var origins = [CGPoint](repeating: .zero, count: tailLines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        let heightDelta = containerSize.height - prefix.size.height
        let translation = prefix.anchorOrigin.y + heightDelta - origins[0].y
        for index in origins.indices {
            origins[index].y += translation
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            CTLineGetTypographicBounds(tailLines[index], &ascent, &descent, nil)
            guard origins[index].y - descent >= 0,
                  origins[index].y + ascent <= containerSize.height else { return false }
        }
        lines = prefix.lines + tailLines
        lineOrigins = prefix.origins.map { CGPoint(x: $0.x, y: $0.y + heightDelta) } + origins
        reusedLineCount = prefix.lines.count
        return true
    }

    @MainActor private func extractHighlightRegions() {
        guard hasHighlightAttributes else { return }
        enumerateLines { line, _, lineOrigin in
            let glyphRuns = CTLineGetGlyphRuns(line) as NSArray

            for i in 0 ..< glyphRuns.count {
                guard let glyphRun = glyphRuns[i] as! CTRun? else { continue }

                let attributes = CTRunGetAttributes(
                    glyphRun
                ) as! [NSAttributedString.Key: Any]
                if !_hasHighlightAttributes(attributes) {
                    continue
                }

                processHighlightRegionForRun(
                    glyphRun,
                    attributes: attributes,
                    lineOrigin: lineOrigin
                )
            }
        }
    }

    @MainActor private func processHighlightRegionForRun(
        _ glyphRun: CTRun,
        attributes: [NSAttributedString.Key: Any],
        lineOrigin: CGPoint
    ) {
        let cfStringRange = CTRunGetStringRange(glyphRun)
        let stringRange = NSRange(
            location: cfStringRange.location,
            length: cfStringRange.length
        )

        var effectiveRange = NSRange()
        _ = attributedString.attributes(
            at: stringRange.location,
            effectiveRange: &effectiveRange
        )

        let highlightRegion: LTXHighlightRegion
        if let existingRegion = _highlightRegions[
            effectiveRange.location
        ] {
            highlightRegion = existingRegion
        } else {
            highlightRegion = LTXHighlightRegion(
                attributes: attributes,
                stringRange: stringRange
            )
            _highlightRegions[effectiveRange.location] = highlightRegion
        }

        var runBounds = CTRunGetImageBounds(
            glyphRun,
            nil,
            CFRange(location: 0, length: 0)
        )

        if let attachment = attributes[
            LTXAttachmentAttributeName
        ] as? LTXAttachment {
            runBounds.size = attachment.size
            runBounds.origin.y -= attachment.size.height * 0.1
        }

        runBounds.origin.x += lineOrigin.x
        runBounds.origin.y += lineOrigin.y
        highlightRegion.addRect(runBounds)
    }

    private func enumerateLines(
        intersecting band: LineBand? = nil,
        using block: (CTLine, Int, CGPoint) -> Void
    ) {
        guard let lines, let lineOrigins else { return }

        var start = 0
        if let band, hasOrderedLineBands {
            var end = lineBands.count
            while start < end {
                let middle = start + (end - start) / 2
                if lineBands[middle].minY > band.maxY {
                    start = middle + 1
                } else {
                    end = middle
                }
            }
        }
        for i in start ..< lines.count {
            if let band {
                let bounds = lineBands[i]
                if bounds.minY > band.maxY { continue }
                if bounds.maxY < band.minY {
                    if hasOrderedLineBands { break }
                    continue
                }
            }
            block(lines[i], i, lineOrigins[i])
        }
    }

    // MARK: - Text Index Helpers

    public func textIndex(at point: CGPoint) -> Int? {
        if let lineInfo = findLineContainingPoint(point) {
            return findCharacterIndexInLine(point, lineInfo: lineInfo)
        }

        guard let lines, let lineOrigins, !lines.isEmpty else { return nil }

        guard point.y < lineOrigins[lines.count - 1].y else { return nil }
        let lastLine = lines[lines.count - 1]
        let range = CTLineGetStringRange(lastLine)
        return range.location + range.length
    }

    public func nearestTextIndex(at point: CGPoint) -> Int? {
        if let lineInfo = findLineContainingPoint(point) {
            return findCharacterIndexInLine(point, lineInfo: lineInfo)
        }

        guard let lines, let lineOrigins, !lines.isEmpty else { return nil }

        // 如果点在文本上方
        if point.y > lineOrigins[0].y {
            let firstLine = lines[0]
            if point.x < lineOrigins[0].x {
                return CTLineGetStringRange(firstLine).location
            } else {
                let range = CTLineGetStringRange(firstLine)
                let lineWidth = CTLineGetTypographicBounds(firstLine, nil, nil, nil)
                if point.x > lineOrigins[0].x + lineWidth {
                    return range.location + range.length
                } else {
                    return findCharacterIndexInLine(point, lineInfo: (firstLine, lineOrigins[0], 0))
                }
            }
        }

        // 如果点在文本下方
        if point.y < lineOrigins[lines.count - 1].y {
            let lastLine = lines[lines.count - 1]
            if point.x < lineOrigins[lines.count - 1].x {
                return CTLineGetStringRange(lastLine).location
            } else {
                let range = CTLineGetStringRange(lastLine)
                let lineWidth = CTLineGetTypographicBounds(lastLine, nil, nil, nil)
                if point.x > lineOrigins[lines.count - 1].x + lineWidth {
                    return range.location + range.length
                } else {
                    return findCharacterIndexInLine(point, lineInfo: (lastLine, lineOrigins[lines.count - 1], lines.count - 1))
                }
            }
        }

        // 如果点在两行之间，找到最近的行
        var closestLineIndex = 0
        var minDistance = CGFloat.greatestFiniteMagnitude

        for i in 0 ..< lines.count {
            let line = lines[i]
            let origin = lineOrigins[i]
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0

            CTLineGetTypographicBounds(line, &ascent, &descent, &leading)

            let lineMiddleY = origin.y - descent + (ascent + descent) / 2
            let distance = abs(point.y - lineMiddleY)

            if distance < minDistance {
                minDistance = distance
                closestLineIndex = i
            }
        }

        let closestLine = lines[closestLineIndex]
        let closestOrigin = lineOrigins[closestLineIndex]

        return findCharacterIndexInLine(point, lineInfo: (closestLine, closestOrigin, closestLineIndex))
    }

    // MARK: - Private Text Index Helpers

    private func findLineContainingPoint(
        _ point: CGPoint
    ) -> (line: CTLine, origin: CGPoint, index: Int)? {
        guard let lines, let lineOrigins else { return nil }

        for i in 0 ..< lines.count {
            let origin = lineOrigins[i]
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0

            let line = lines[i]
            let lineWidth = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
            let lineHeight = ascent + descent + leading

            let lineRect = CGRect(
                x: origin.x,
                y: origin.y - descent,
                width: lineWidth,
                height: lineHeight
            )

            if point.y >= lineRect.minY, point.y <= lineRect.maxY {
                return (line: line, origin: origin, index: i)
            }
        }

        return nil
    }

    private func findCharacterIndexInLine(
        _ point: CGPoint,
        lineInfo: (line: CTLine, origin: CGPoint, index: Int)
    ) -> Int {
        let line = lineInfo.line
        let lineOrigin = lineInfo.origin
        let lineRange = CTLineGetStringRange(line)

        if point.x <= lineOrigin.x {
            return lineRange.location
        }

        let positionInLine = CGPoint(x: point.x - lineOrigin.x, y: 0)
        let index = CTLineGetStringIndexForPosition(line, positionInLine)
        if index == kCFNotFound {
            return lineRange.location + lineRange.length
        }
        return index
    }
}
