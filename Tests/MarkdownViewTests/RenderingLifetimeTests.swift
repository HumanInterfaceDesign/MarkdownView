import Foundation
import XCTest
@testable import MarkdownView

@MainActor
final class RenderingLifetimeTests: XCTestCase {
    private enum LayoutContext {
        @TaskLocal static var value = "outside"
    }

    func testInlineAttributeCacheReleaseInsideSynchronousTaskLocalScope() {
        checkSynchronousRelease {
            InlineAttributeCache(theme: .default)
        }
    }

    func testListProcessorAndOwnedCacheReleaseInsideSynchronousTaskLocalScope() {
        let theme = MarkdownTheme.default
        let context = MarkdownTextView.PreprocessedContent(markdown: "- **First**\n- `Second`", theme: theme)
        let viewProvider = ReusableViewProvider()
        checkSynchronousRelease {
            ListProcessor(
                theme: theme,
                viewProvider: viewProvider,
                context: context,
                bulletDrawing: nil,
                numberedDrawing: nil,
                checkboxDrawing: nil
            )
        }
    }

    // Keep this synchronous to match UIKit layout callbacks outside a Swift task.
    private func checkSynchronousRelease<T: AnyObject>(_ makeObject: () -> T) {
        for _ in 0 ..< 100 {
            LayoutContext.$value.withValue("layout") {
                autoreleasepool {
                    var objects = [0: makeObject()]
                    weak var object: T?
                    object = objects[0]
                    objects.removeAll()
                    XCTAssertNil(object)
                }
                XCTAssertEqual(LayoutContext.value, "layout")
            }
            XCTAssertEqual(LayoutContext.value, "outside")
        }
    }
}
