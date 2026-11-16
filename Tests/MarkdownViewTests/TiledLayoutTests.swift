import CoreGraphics
import CoreText
import Foundation
import XCTest
@testable import Litext
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

final class TiledLayoutTests: XCTestCase {
    private let size = CGSize(width: 320, height: 6000)

    private func makeLayout() -> LTXTextLayout {
        let text = NSMutableAttributedString(string: "")
        for index in 0..<180 {
            let font = CTFontCreateWithName("Helvetica" as CFString, index % 7 == 0 ? 22 : 14, nil)
            text.append(NSAttributedString(
                string: "Line \(index): mixed size text\n",
                attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]
            ))
        }
        let layout = LTXTextLayout(attributedString: text)
        layout.containerSize = size
        return layout
    }

    private func makeContext() throws -> CGContext {
        try XCTUnwrap(CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: Int(size.width) * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
    }

    private func pixels(_ context: CGContext) throws -> Data {
        Data(bytes: try XCTUnwrap(context.data), count: context.bytesPerRow * context.height)
    }

    func testVisibleBandsMatchClippedFullDrawing() throws {
        let layout = makeLayout()
        for y in [CGFloat(0), 500, 1800, 3200, 5900] {
            let band = CGRect(x: 0, y: y, width: size.width, height: 180)
            let full = try makeContext()
            full.clip(to: band)
            layout.draw(in: full)
            let tiled = try makeContext()
            tiled.clip(to: band)
            layout.draw(in: tiled, visibleRect: band)
            XCTAssertEqual(try pixels(full), try pixels(tiled), "Drawing differs at y=\(y)")
        }
    }

    func testChangingContainerRebuildsVisibleLineIndex() throws {
        let layout = makeLayout()
        layout.containerSize = CGSize(width: 160, height: size.height)
        let band = CGRect(x: 0, y: 3200, width: 160, height: 180)
        let full = try makeContext()
        full.clip(to: band)
        layout.draw(in: full)
        let tiled = try makeContext()
        tiled.clip(to: band)
        layout.draw(in: tiled, visibleRect: band)
        XCTAssertEqual(try pixels(full), try pixels(tiled))
    }

    func testReusedPrefixMatchesFullLayoutAndPixels() throws {
        let previous = makeLayout()
        let changed = previous.attributedString.mutableCopy() as! NSMutableAttributedString
        let lastParagraph = (changed.string as NSString).paragraphRange(for: NSRange(location: changed.length - 1, length: 0))
        changed.replaceCharacters(in: lastParagraph, with: "Changed tail with 日本語 and cafe\u{301}\nExtra line\n")
        let incremental = LTXTextLayout(attributedString: changed)
        incremental.reusePrefix(from: previous, utf16Length: lastParagraph.location)
        incremental.containerSize = size
        let full = LTXTextLayout(attributedString: changed)
        full.containerSize = size
        XCTAssertGreaterThan(incremental.reusedLineCount, 0)
        XCTAssertEqual(incremental.lineStringRanges(), full.lineStringRanges())
        assertEquivalentGeometry(incremental, full)
        let expectedPixels = try makeContext()
        full.draw(in: expectedPixels)
        let actualPixels = try makeContext()
        incremental.draw(in: actualPixels)
        XCTAssertEqual(try pixels(actualPixels), try pixels(expectedPixels))
        let band = CGRect(x: 0, y: 3200, width: size.width, height: 180)
        let fullTile = try makeContext()
        fullTile.clip(to: band)
        full.draw(in: fullTile, visibleRect: band)
        let incrementalTile = try makeContext()
        incrementalTile.clip(to: band)
        incremental.draw(in: incrementalTile, visibleRect: band)
        XCTAssertEqual(try pixels(fullTile), try pixels(incrementalTile))
    }

    @MainActor
    func testReusePreservesParagraphSpacingAndLinkRegions() {
        let source = makeLayout().attributedString.mutableCopy() as! NSMutableAttributedString
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = 7
        style.paragraphSpacingBefore = 3
        style.lineSpacing = 2
        style.firstLineHeadIndent = 12
        source.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: source.length))
        source.addAttribute(.link, value: "https://example.com", range: NSRange(location: 8, length: 10))
        let previous = LTXTextLayout(attributedString: source)
        previous.containerSize = CGSize(width: 320, height: 12000)
        let changed = source.mutableCopy() as! NSMutableAttributedString
        changed.append(NSAttributedString(string: "More linked text\n", attributes: [
            .paragraphStyle: style, .link: "https://example.com/tail"
        ]))
        let incremental = LTXTextLayout(attributedString: changed)
        incremental.reusePrefix(from: previous, utf16Length: source.length)
        incremental.containerSize = previous.containerSize
        let full = LTXTextLayout(attributedString: changed)
        full.containerSize = previous.containerSize
        XCTAssertGreaterThan(incremental.reusedLineCount, 0)
        assertEquivalentGeometry(incremental, full)
        incremental.updateHighlightRegions()
        full.updateHighlightRegions()
        let actualRegions = incremental.highlightRegions.sorted { $0.stringRange.location < $1.stringRange.location }
        let expectedRegions = full.highlightRegions.sorted { $0.stringRange.location < $1.stringRange.location }
        XCTAssertEqual(actualRegions.map(\.stringRange), expectedRegions.map(\.stringRange))
        for (actual, expected) in zip(actualRegions, expectedRegions) {
            XCTAssertEqual(actual.rects, expected.rects)
        }
    }

    func testReuseFallsBackForWidthChangesAndClippedContainers() {
        let previous = makeLayout()
        let changed = previous.attributedString.mutableCopy() as! NSMutableAttributedString
        changed.append(NSAttributedString(string: "More text"))
        for dimensions in [CGSize(width: 160, height: size.height), CGSize(width: size.width, height: 200)] {
            let incremental = LTXTextLayout(attributedString: changed)
            incremental.reusePrefix(from: previous, utf16Length: previous.attributedString.length)
            incremental.containerSize = dimensions
            let full = LTXTextLayout(attributedString: changed)
            full.containerSize = dimensions
            XCTAssertEqual(incremental.reusedLineCount, 0)
            assertEquivalentGeometry(incremental, full)
        }
    }

    func testReuseRejectsChangedPrefixAttributes() {
        let previous = makeLayout()
        let changed = previous.attributedString.mutableCopy() as! NSMutableAttributedString
        changed.addAttribute(NSAttributedString.Key(kCTFontAttributeName as String),
                             value: CTFontCreateWithName("Helvetica" as CFString, 30, nil),
                             range: NSRange(location: 0, length: 5))
        let incremental = LTXTextLayout(attributedString: changed)
        incremental.reusePrefix(from: previous, utf16Length: changed.length)
        incremental.containerSize = size
        let full = LTXTextLayout(attributedString: changed)
        full.containerSize = size
        XCTAssertEqual(incremental.reusedLineCount, 0)
        assertEquivalentGeometry(incremental, full)
    }

    func testReusedPrefixTracksContainerHeightChanges() {
        let previous = makeLayout()
        let changed = previous.attributedString.mutableCopy() as! NSMutableAttributedString
        changed.append(NSAttributedString(string: "New paragraph\n"))
        let incremental = LTXTextLayout(attributedString: changed)
        incremental.reusePrefix(from: previous, utf16Length: previous.attributedString.length)
        incremental.containerSize = CGSize(width: size.width, height: size.height + 100)
        let full = LTXTextLayout(attributedString: changed)
        full.containerSize = incremental.containerSize
        XCTAssertGreaterThan(incremental.reusedLineCount, 0)
        assertEquivalentGeometry(incremental, full)
    }

    private func assertEquivalentGeometry(_ actual: LTXTextLayout, _ expected: LTXTextLayout,
                                          file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.lineStringRanges(), expected.lineStringRanges(), file: file, line: line)
        let actualRects = actual.lineRects()
        let expectedRects = expected.lineRects()
        XCTAssertEqual(actualRects.count, expectedRects.count, file: file, line: line)
        for (a, b) in zip(actualRects, expectedRects) {
            XCTAssertEqual(a.minX, b.minX, accuracy: 0.001, file: file, line: line)
            XCTAssertEqual(a.minY, b.minY, accuracy: 0.001, file: file, line: line)
            XCTAssertEqual(a.width, b.width, accuracy: 0.001, file: file, line: line)
            XCTAssertEqual(a.height, b.height, accuracy: 0.001, file: file, line: line)
            XCTAssertEqual(actual.nearestTextIndex(at: CGPoint(x: a.midX, y: a.midY)),
                           expected.nearestTextIndex(at: CGPoint(x: b.midX, y: b.midY)), file: file, line: line)
        }
        let range = NSRange(location: 0, length: actual.attributedString.length)
        let actualSelection = actual.rects(for: range)
        let expectedSelection = expected.rects(for: range)
        XCTAssertEqual(actualSelection.count, expectedSelection.count, file: file, line: line)
        for (a, b) in zip(actualSelection, expectedSelection) {
            XCTAssertEqual(a.minY, b.minY, accuracy: 0.001, file: file, line: line)
            XCTAssertEqual(a.width, b.width, accuracy: 0.001, file: file, line: line)
        }
    }

    func testReusedPrefixLayoutPerformance() {
        let previous = makeLayout()
        let changed = previous.attributedString.mutableCopy() as! NSMutableAttributedString
        changed.append(NSAttributedString(string: "New paragraph\n"))
        measure {
            let layout = LTXTextLayout(attributedString: changed)
            layout.reusePrefix(from: previous, utf16Length: previous.attributedString.length)
            layout.containerSize = size
            XCTAssertGreaterThan(layout.reusedLineCount, 0)
        }
    }

    func testFullLayoutPerformance() {
        let previous = makeLayout()
        let changed = previous.attributedString.mutableCopy() as! NSMutableAttributedString
        changed.append(NSAttributedString(string: "New paragraph\n"))
        measure {
            let layout = LTXTextLayout(attributedString: changed)
            layout.containerSize = size
        }
    }

    func testLowerDocumentTileDrawingPerformance() throws {
        let layout = makeLayout()
        let context = try makeContext()
        let band = CGRect(x: 0, y: 3200, width: size.width, height: 180)
        context.clip(to: band)
        measure {
            for _ in 0..<100 {
                layout.draw(in: context, visibleRect: band)
            }
        }
    }
}
