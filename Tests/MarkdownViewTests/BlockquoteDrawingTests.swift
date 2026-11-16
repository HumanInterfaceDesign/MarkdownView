#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import CoreText
import XCTest
@testable import Litext
@testable import MarkdownView

@MainActor
final class BlockquoteDrawingTests: XCTestCase {
    func testSingleLineRTLQuoteDrawsBarOnFirstPassAndRedraw() throws {
        try assertQuoteBars(
            markdown: "> مرحبا بالعالم",
            quotedTexts: ["مرحبا بالعالم"]
        )
    }

    func testSeparatedRTLQuotesDoNotDrawBarAcrossParagraph() throws {
        try assertQuoteBars(
            markdown: "> مرحبا بالعالم\n\n" + String(repeating: "Intervening paragraph. ", count: 100)
                + "\n\n> صباح الخير",
            quotedTexts: ["مرحبا بالعالم", "صباح الخير"]
        )
    }

    func testWrappedQuoteDrawsContinuousBarOnFullPass() throws {
        let quote = String(repeating: "Quoted text. ", count: 100).trimmingCharacters(in: .whitespaces)
        try assertQuoteBars(markdown: "> " + quote, quotedTexts: [quote])
    }

    private func assertQuoteBars(markdown: String, quotedTexts: [String]) throws {
        let view = MarkdownTextView()
        view.document = .init(markdown: markdown, theme: .default)
        let document = TextBuilder.build(view: view, viewProvider: .init()).document
        let layout = LTXTextLayout(attributedString: document)
        let size = CGSize(width: 320, height: 6000)
        layout.containerSize = size
        let frame = try XCTUnwrap(layout.ctFrame)
        let lines = CTFrameGetLines(frame) as! [CTLine]
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        let expected = try makeContext(size: size)
        let undecorated = NSMutableAttributedString(attributedString: document)
        undecorated.removeAttribute(LTXLineDrawingCallbackName, range: NSRange(location: 0, length: document.length))
        let textOnly = LTXTextLayout(attributedString: undecorated)
        textOnly.containerSize = size
        textOnly.draw(in: expected)
        expected.translateBy(x: 0, y: size.height)
        expected.scaleBy(x: 1, y: -1)
        expected.setFillColor(view.theme.colors.body.withAlphaComponent(0.1).cgColor)
        for text in quotedTexts {
            let range = (document.string as NSString).range(of: text)
            XCTAssertNotEqual(range.location, NSNotFound)
            let quoteLines = lines.indices.filter { index in
                let lineRange = CTLineGetStringRange(lines[index])
                return NSIntersectionRange(range, NSRange(location: lineRange.location, length: lineRange.length)).length > 0
            }
            let first = try XCTUnwrap(quoteLines.first)
            let last = try XCTUnwrap(quoteLines.last)
            let top = TextBuilder.lineBoundingBox(lines[first], lineOrigin: origins[first]).maxY
            let bottom = TextBuilder.lineBoundingBox(lines[last], lineOrigin: origins[last]).minY
            let rect = CGRect(x: 0, y: bottom, width: 4, height: top - bottom)
            expected.addPath(CGPath(roundedRect: rect, cornerWidth: 2, cornerHeight: 2, transform: nil))
            expected.fillPath()
        }
        let expectedPixels = try barPixels(expected)
        XCTAssertTrue(expectedPixels.contains { $0 != 0 })
        for pass in 1...2 {
            let actual = try makeContext(size: size)
            layout.draw(in: actual)
            XCTAssertEqual(try barPixels(actual), expectedPixels, "Incorrect bar geometry on pass \(pass)")
        }
    }

    private func makeContext(size: CGSize) throws -> CGContext {
        try XCTUnwrap(CGContext(
            data: nil, width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: Int(size.width) * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
    }

    private func barPixels(_ context: CGContext) throws -> Data {
        let data = try XCTUnwrap(context.data)
        var pixels = Data()
        for row in 0..<context.height {
            pixels.append(Data(bytes: data.advanced(by: row * context.bytesPerRow), count: 4 * 4))
        }
        return pixels
    }

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
