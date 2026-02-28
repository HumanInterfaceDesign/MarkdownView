import XCTest
@testable import MarkdownParser
@testable import MarkdownView

final class StreamingFastPathTests: XCTestCase {

    private let parser = MarkdownParser()

    func testPlainTextAppendFastPathUpdatesTrailingParagraph() {
        let result = parser.parse("Hello")
        let content = MarkdownTextView.PreprocessedContent(
            parserResult: result,
            theme: .default
        )

        let fastPath = runOnMain {
            let view = MarkdownTextView()
            view.setMarkdownManually(content)
            view.lastRawMarkdown = "Hello"
            return view.makePlainTextAppendFastPath(for: "Hello world")
        }

        guard let fastPath else {
            return XCTFail("Expected plain-text append fast path")
        }
        XCTAssertEqual(fastPath.blocks.count, 1)
        guard case let .paragraph(inlines) = fastPath.blocks[0] else {
            return XCTFail("Expected paragraph")
        }
        XCTAssertEqual(inlines, [.text("Hello world")])
    }

    func testPlainTextAppendFastPathRejectsMarkdownSyntax() {
        let result = parser.parse("Hello")
        let content = MarkdownTextView.PreprocessedContent(
            parserResult: result,
            theme: .default
        )

        let fastPath = runOnMain {
            let view = MarkdownTextView()
            view.setMarkdownManually(content)
            view.lastRawMarkdown = "Hello"
            return view.makePlainTextAppendFastPath(for: "Hello **world")
        }

        XCTAssertNil(fastPath)
    }

    func testPlainTextAppendFastPathRejectsRichInlineContent() {
        let result = parser.parse("Hello **bold**")
        let content = MarkdownTextView.PreprocessedContent(
            parserResult: result,
            theme: .default
        )

        let fastPath = runOnMain {
            let view = MarkdownTextView()
            view.setMarkdownManually(content)
            view.lastRawMarkdown = "Hello **bold**"
            return view.makePlainTextAppendFastPath(for: "Hello **bold** world")
        }

        XCTAssertNil(fastPath)
    }

    private func runOnMain<T>(_ work: @escaping () -> T) -> T {
        if Thread.isMainThread {
            return work()
        }

        var result: T?
        DispatchQueue.main.sync {
            result = work()
        }
        return result!
    }
}
