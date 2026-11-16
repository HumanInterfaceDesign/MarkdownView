#if canImport(AppKit)
import AppKit
import CoreText
import XCTest
@testable import Litext
@testable import MarkdownView

@MainActor
final class BlockquoteDrawingTests: XCTestCase {
    func testQuoteEndCanBeDrawnWithoutItsStartMarker() throws {
        let view = MarkdownTextView()
        view.document = .init(markdown: "> " + String(repeating: "Quoted text. ", count: 200), theme: .default)
        let document = TextBuilder.build(view: view, viewProvider: .init()).document
        let layout = LTXTextLayout(attributedString: document)
        let size = CGSize(width: 320, height: 6000)
        layout.containerSize = size

        let frame = try XCTUnwrap(layout.ctFrame)
        let lines = CTFrameGetLines(frame) as! [CTLine]
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        let decoratedLines = lines.indices.filter { index in
            let runs = CTLineGetGlyphRuns(lines[index]) as! [CTRun]
            return runs.contains { run in
                let attributes = CTRunGetAttributes(run) as NSDictionary
                return attributes[LTXLineDrawingCallbackName] != nil
            }
        }
        XCTAssertEqual(decoratedLines.count, 2)
        let first = try XCTUnwrap(decoratedLines.first)
        let last = try XCTUnwrap(decoratedLines.last)
        let endBounds = TextBuilder.lineBoundingBox(lines[last], lineOrigin: origins[last])
        let visibleRect = CGRect(x: 0, y: size.height - endBounds.maxY, width: size.width, height: endBounds.height)
        let startBounds = TextBuilder.lineBoundingBox(lines[first], lineOrigin: origins[first])
        XCTAssertGreaterThan(startBounds.minY, endBounds.maxY)

        let context = try XCTUnwrap(CGContext(
            data: nil, width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: Int(size.width) * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        // Start with the ending tile, as can happen when scrolling into a long quote.
        layout.draw(in: context, visibleRect: visibleRect)
        layout.draw(in: context)
        layout.draw(in: context, visibleRect: visibleRect)
    }
}
#endif
