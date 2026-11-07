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

    func testIncrementalBuilderPreservesPrefixAndOriginalSnapshot() {
        let previous = MarkdownTextView.PreprocessedContent(markdown: "Alpha\n\nBravo\n\nCharlie", theme: .default)
        let provider = ReusableViewProvider()
        let original = TextBuilder(nodes: previous.blocks, context: previous, viewProvider: provider).build()
        let originalSnapshot = NSAttributedString(attributedString: original.document)
        for markdown in ["Alpha\n\nBravo\n\nChanged tail", "Alpha\n\nBravo", "Alpha\n\nInserted\n\nCharlie"] {
            let next = MarkdownTextView.PreprocessedContent(markdown: markdown, theme: .default)
            let incremental = TextBuilder(nodes: next.blocks, context: next, viewProvider: provider).buildIncremental(
                changes: ASTDiff.diff(old: previous.blocks, new: next.blocks),
                cachedSegments: original.blockSegments,
                cachedDocument: original.document
            )
            let full = TextBuilder(nodes: next.blocks, context: next, viewProvider: ReusableViewProvider()).build()
            XCTAssertTrue(incremental.document.isEqual(to: full.document))
            XCTAssertTrue(original.document.isEqual(to: originalSnapshot))
            XCTAssertGreaterThan(incremental.preservedPrefixUTF16Length, 0)
            XCTAssertTrue(incremental.blockSegments[0] === original.blockSegments[0])
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
