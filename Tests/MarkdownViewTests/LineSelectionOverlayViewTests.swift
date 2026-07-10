import XCTest
@testable import MarkdownView
#if canImport(AppKit)
    import AppKit
#elseif canImport(UIKit)
    import UIKit
#endif

@MainActor
final class LineSelectionOverlayViewTests: XCTestCase {
    private let lineHeight: CGFloat = 20
    private let gap: CGFloat = 4
    private let firstLineY: CGFloat = 10

    /// Synthetic resolved line rects: three 20pt lines separated by a 4pt gap,
    /// starting at y=10 — line 1 spans 10..<30, line 2 spans 34..<54, line 3
    /// spans 58..<78.
    private func makeOverlay(lineCount: Int = 3) -> LineSelectionOverlayView {
        let overlay = LineSelectionOverlayView(frame: .zero)
        let rects = (0 ..< lineCount).map { index in
            CGRect(
                x: 0,
                y: firstLineY + CGFloat(index) * (lineHeight + gap),
                width: 100,
                height: lineHeight
            )
        }
        overlay.updateLineRects(rects)
        return overlay
    }

    func testHasLineRects() {
        let empty = LineSelectionOverlayView(frame: .zero)
        XCTAssertFalse(empty.hasLineRects)
        XCTAssertTrue(makeOverlay().hasLineRects)
    }

    func testEmptyRectsReturnsNil() {
        let overlay = LineSelectionOverlayView(frame: .zero)
        XCTAssertNil(overlay.lineIndex(atY: 10, trailingGap: gap))
    }

    func testPointInsideLine() {
        let overlay = makeOverlay()
        XCTAssertEqual(overlay.lineIndex(atY: 10, trailingGap: gap), 1)
        XCTAssertEqual(overlay.lineIndex(atY: 29, trailingGap: gap), 1)
        XCTAssertEqual(overlay.lineIndex(atY: 44, trailingGap: gap), 2)
        XCTAssertEqual(overlay.lineIndex(atY: 70, trailingGap: gap), 3)
    }

    func testPointInGapBelongsToLineAbove() {
        let overlay = makeOverlay()
        // Gap between line 1 (ends 30) and line 2 (starts 34).
        XCTAssertEqual(overlay.lineIndex(atY: 30, trailingGap: gap), 1)
        XCTAssertEqual(overlay.lineIndex(atY: 33.5, trailingGap: gap), 1)
        // Gap between line 2 (ends 54) and line 3 (starts 58).
        XCTAssertEqual(overlay.lineIndex(atY: 56, trailingGap: gap), 2)
    }

    func testPointAboveFirstLineReturnsNil() {
        let overlay = makeOverlay()
        XCTAssertNil(overlay.lineIndex(atY: 9.5, trailingGap: gap))
        XCTAssertNil(overlay.lineIndex(atY: -5, trailingGap: gap))
    }

    func testTrailingGapBelongsToLastLine() {
        let overlay = makeOverlay()
        // Line 3 ends at 78; it owns one trailing gap (< 82).
        XCTAssertEqual(overlay.lineIndex(atY: 78, trailingGap: gap), 3)
        XCTAssertEqual(overlay.lineIndex(atY: 81.5, trailingGap: gap), 3)
        XCTAssertNil(overlay.lineIndex(atY: 82, trailingGap: gap))
        XCTAssertNil(overlay.lineIndex(atY: 200, trailingGap: gap))
    }

    func testSingleLine() {
        let overlay = makeOverlay(lineCount: 1)
        XCTAssertNil(overlay.lineIndex(atY: 9, trailingGap: gap))
        XCTAssertEqual(overlay.lineIndex(atY: 10, trailingGap: gap), 1)
        XCTAssertEqual(overlay.lineIndex(atY: 33, trailingGap: gap), 1)
        XCTAssertNil(overlay.lineIndex(atY: 34, trailingGap: gap))
    }

    /// The motivating case for rect-based hit-testing: lines whose real
    /// heights vary (fallback-font glyphs, accumulated layout drift) must
    /// still resolve to the rect that contains the point.
    func testUnevenLineHeights() {
        let overlay = LineSelectionOverlayView(frame: .zero)
        overlay.updateLineRects([
            CGRect(x: 0, y: 0, width: 100, height: 20),
            CGRect(x: 0, y: 24, width: 100, height: 32), // taller (emoji/CJK)
            CGRect(x: 0, y: 60, width: 100, height: 20),
        ])
        XCTAssertEqual(overlay.lineIndex(atY: 12, trailingGap: gap), 1)
        XCTAssertEqual(overlay.lineIndex(atY: 40, trailingGap: gap), 2)
        XCTAssertEqual(overlay.lineIndex(atY: 59, trailingGap: gap), 2)
        XCTAssertEqual(overlay.lineIndex(atY: 61, trailingGap: gap), 3)
    }
}
