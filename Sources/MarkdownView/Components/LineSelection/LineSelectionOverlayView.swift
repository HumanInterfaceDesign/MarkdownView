#if canImport(UIKit)
    import UIKit

    final class LineSelectionOverlayView: UIView {
        var selectionColor: UIColor = .systemBlue.withAlphaComponent(0.15) {
            didSet { setNeedsDisplay() }
        }

        var selectedRange: ClosedRange<Int>? {
            didSet {
                guard oldValue != selectedRange else { return }
                setNeedsDisplay()
            }
        }

        private var lineRects: [CGRect] = []

        var hasLineRects: Bool { !lineRects.isEmpty }

        override init(frame: CGRect) {
            super.init(frame: frame)
            isOpaque = false
            backgroundColor = .clear
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) { fatalError() }

        func updateLineRects(_ rects: [CGRect]) {
            lineRects = rects
            setNeedsDisplay()
        }

        /// Maps a y in this overlay's coordinate space to a 1-based line index
        /// using the same rects the highlight draws, so a hit-tested line always
        /// matches the rendered selection. Each line owns the spacing gap below
        /// it; nil above the first line. Indices past the last rect are
        /// extrapolated at the last line's advance — CoreText emits no line for
        /// a trailing blank row (text ending in a newline), so logical rows can
        /// outnumber resolved rects. Callers cap the result to their logical
        /// line count, which turns points beyond the real content into nil.
        func lineIndex(atY y: CGFloat, trailingGap: CGFloat) -> Int? {
            guard let first = lineRects.first, let last = lineRects.last else { return nil }
            guard y >= first.minY else { return nil }
            for index in 0 ..< (lineRects.count - 1) where y < lineRects[index + 1].minY {
                return index + 1
            }
            if y < last.maxY + trailingGap {
                return lineRects.count
            }
            let advance = last.height + trailingGap
            guard advance > 0 else { return nil }
            let extra = Int((y - (last.maxY + trailingGap)) / advance) + 1
            return lineRects.count + extra
        }

        func clearSelection() {
            selectedRange = nil
        }

        override func draw(_ rect: CGRect) {
            guard let range = selectedRange,
                  let ctx = UIGraphicsGetCurrentContext()
            else { return }

            ctx.setFillColor(selectionColor.cgColor)

            for lineIndex in range {
                let arrayIndex = lineIndex - 1
                guard arrayIndex >= 0, arrayIndex < lineRects.count else { continue }
                let lineRect = lineRects[arrayIndex]
                // Extend selection across full width
                let highlightRect = CGRect(
                    x: 0,
                    y: lineRect.origin.y,
                    width: bounds.width,
                    height: lineRect.height
                )
                guard highlightRect.intersects(rect) else { continue }
                ctx.fill(highlightRect)
            }
        }
    }

#elseif canImport(AppKit)
    import AppKit

    final class LineSelectionOverlayView: NSView {
        var selectionColor: NSColor = .systemBlue.withAlphaComponent(0.15) {
            didSet { needsDisplay = true }
        }

        var selectedRange: ClosedRange<Int>? {
            didSet {
                guard oldValue != selectedRange else { return }
                needsDisplay = true
            }
        }

        private var lineRects: [CGRect] = []

        var hasLineRects: Bool { !lineRects.isEmpty }

        override init(frame: CGRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.backgroundColor = NSColor.clear.cgColor
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) { fatalError() }

        override var isFlipped: Bool { true }

        func updateLineRects(_ rects: [CGRect]) {
            lineRects = rects
            needsDisplay = true
        }

        /// Maps a y in this overlay's coordinate space to a 1-based line index
        /// using the same rects the highlight draws, so a hit-tested line always
        /// matches the rendered selection. Each line owns the spacing gap below
        /// it; nil above the first line. Indices past the last rect are
        /// extrapolated at the last line's advance — CoreText emits no line for
        /// a trailing blank row (text ending in a newline), so logical rows can
        /// outnumber resolved rects. Callers cap the result to their logical
        /// line count, which turns points beyond the real content into nil.
        func lineIndex(atY y: CGFloat, trailingGap: CGFloat) -> Int? {
            guard let first = lineRects.first, let last = lineRects.last else { return nil }
            guard y >= first.minY else { return nil }
            for index in 0 ..< (lineRects.count - 1) where y < lineRects[index + 1].minY {
                return index + 1
            }
            if y < last.maxY + trailingGap {
                return lineRects.count
            }
            let advance = last.height + trailingGap
            guard advance > 0 else { return nil }
            let extra = Int((y - (last.maxY + trailingGap)) / advance) + 1
            return lineRects.count + extra
        }

        func clearSelection() {
            selectedRange = nil
        }

        override func draw(_ dirtyRect: NSRect) {
            guard let range = selectedRange,
                  let ctx = NSGraphicsContext.current?.cgContext
            else { return }

            ctx.setFillColor(selectionColor.cgColor)

            for lineIndex in range {
                let arrayIndex = lineIndex - 1
                guard arrayIndex >= 0, arrayIndex < lineRects.count else { continue }
                let lineRect = lineRects[arrayIndex]
                let highlightRect = CGRect(
                    x: 0,
                    y: lineRect.origin.y,
                    width: bounds.width,
                    height: lineRect.height
                )
                guard highlightRect.intersects(dirtyRect) else { continue }
                ctx.fill(highlightRect)
            }
        }
    }
#endif
