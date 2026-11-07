import CoreGraphics
import CoreText
import Foundation
import XCTest
@testable import Litext

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
