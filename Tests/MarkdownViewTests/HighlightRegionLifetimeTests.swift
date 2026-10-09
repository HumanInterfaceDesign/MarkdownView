import Foundation
import XCTest
@testable import Litext

@MainActor
final class HighlightRegionLifetimeTests: XCTestCase {
    private enum LayoutContext {
        @TaskLocal static var value = "outside"
    }

    // Keep this synchronous: UIKit layout and observation callbacks need not run in a Swift task.
    func testSynchronousReleaseInsideTaskLocalScope() {
        for _ in 0 ..< 100 {
            LayoutContext.$value.withValue("layout") {
                autoreleasepool {
                    var regions = [0: LTXHighlightRegion(
                        attributes: [NSAttributedString.Key("link"): "https://example.com"],
                        stringRange: NSRange(location: 0, length: 4)
                    )]
                    weak var region: LTXHighlightRegion?
                    region = regions[0]
                    regions.removeAll()
                    XCTAssertNil(region)
                }
                XCTAssertEqual(LayoutContext.value, "layout")
            }
            XCTAssertEqual(LayoutContext.value, "outside")
        }
    }
}
