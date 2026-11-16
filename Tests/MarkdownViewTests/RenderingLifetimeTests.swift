import Foundation
import XCTest
@testable import Litext
@testable import MarkdownView

@MainActor
final class RenderingLifetimeTests: XCTestCase {
    private enum LayoutContext {
        @TaskLocal static var value = "outside"
    }

    func testAttachmentReleaseInsideSynchronousTaskLocalScope() {
        checkSynchronousRelease { LTXAttachment() }
    }

    func testHolderAttachmentReleaseInsideSynchronousTaskLocalScope() {
        checkSynchronousRelease {
            let text = NSAttributedString(string: "Table contents")
            let attachment = LTXAttachment.hold(attrString: text)
            XCTAssertEqual(attachment.attributedStringRepresentation(), text)
            return attachment
        }
    }

    #if canImport(UIKit)
        func testLabelReleaseInsideSynchronousTaskLocalScope() {
            checkSynchronousRelease { LTXLabel() }
        }

        func testCodeViewReleaseInsideSynchronousTaskLocalScope() {
            checkSynchronousRelease {
                let view = CodeView()
                view.content = "let value = 1"
                return view
            }
        }

        func testTableViewReleaseInsideSynchronousTaskLocalScope() {
            checkSynchronousRelease {
                let view = TableView()
                view.setContents([[NSAttributedString(string: "Cell")]])
                return view
            }
        }

        func testMarkdownTextViewReleaseInsideSynchronousTaskLocalScope() {
            checkSynchronousRelease { MarkdownTextView() }
        }
    #endif

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

    func testBlockProcessorAndOwnedCacheReleaseInsideSynchronousTaskLocalScope() {
        let theme = MarkdownTheme.default
        let context = MarkdownTextView.PreprocessedContent(markdown: "**Hello** `world`", theme: theme)
        let viewProvider = ReusableViewProvider()
        checkSynchronousRelease {
            let processor = BlockProcessor(
                theme: theme,
                viewProvider: viewProvider,
                context: context,
                layoutWidth: 320,
                thematicBreakDrawing: nil,
                codeDrawing: nil,
                diffDrawing: nil,
                tableDrawing: nil,
                blockquoteMarking: nil,
                blockquoteDrawing: nil
            )
            let text = processor.processParagraph(contents: [.text("Hello world")])
            XCTAssertTrue(text.string.contains("Hello world"))
            return processor
        }
    }

    func testTextBuilderReleaseInsideSynchronousTaskLocalScope() {
        let context = MarkdownTextView.PreprocessedContent(markdown: "Hello", theme: .default)
        let viewProvider = ReusableViewProvider()
        checkSynchronousRelease {
            TextBuilder(nodes: context.blocks, context: context, viewProvider: viewProvider)
        }
    }

    func testTextBuilderAndOwnedProviderReleaseAfterSynchronousRender() {
        let context = MarkdownTextView.PreprocessedContent(markdown: "**Hello** `world`", theme: .default)
        checkSynchronousRelease {
            let builder = TextBuilder(
                nodes: context.blocks,
                context: context,
                viewProvider: ReusableViewProvider()
            )
            let result = builder.build()
            XCTAssertTrue(result.document.string.contains("Hello world"))
            return builder
        }
    }

    func testTextBuilderAndOwnedProviderReleaseAfterSynchronousIncrementalRender() {
        let context = MarkdownTextView.PreprocessedContent(markdown: "**Hello** `world`", theme: .default)
        checkSynchronousRelease {
            let builder = TextBuilder(
                nodes: context.blocks,
                context: context,
                viewProvider: ReusableViewProvider()
            )
            let result = builder.buildIncremental(changes: [.rebuild(newIndex: 0)], cachedSegments: [])
            XCTAssertTrue(result.document.string.contains("Hello world"))
            return builder
        }
    }

    func testTextBuilderSupportsBlocksWithoutDrawingCallbacks() {
        let fixtures = [
            "> Quote",
            "```swift\nlet value = 1\n```",
            "```diff\n@@ -1 +1 @@\n-old\n+new\n```",
            "| Header |\n| --- |\n| Cell |",
        ]
        for markdown in fixtures {
            let context = MarkdownTextView.PreprocessedContent(markdown: markdown, theme: .default)
            let builder = TextBuilder(nodes: context.blocks, context: context, viewProvider: .init())
            let result = builder.build()
            XCTAssertGreaterThan(result.document.length, 0, markdown)
            XCTAssertEqual(result.subviews.count, markdown.hasPrefix(">") ? 0 : 1, markdown)
        }
    }

    func testReusableViewProviderReleaseInsideSynchronousTaskLocalScope() {
        checkSynchronousRelease {
            ReusableViewProvider()
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
