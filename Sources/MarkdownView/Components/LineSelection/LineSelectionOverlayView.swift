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
