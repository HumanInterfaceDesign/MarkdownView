import XCTest
@testable import MarkdownView

final class TranscriptPlainTextTests: XCTestCase {
    func testPlainParagraphPassesThrough() {
        XCTAssertEqual(
            TranscriptPlainText.flatten(markdown: "Hello, world!"),
            "Hello, world!"
        )
    }

    func testInlineStylingIsStripped() {
        XCTAssertEqual(
            TranscriptPlainText.flatten(markdown: "Welcome to **the show**, with *your host* and `guests`."),
            "Welcome to the show, with your host and guests."
        )
    }

    func testLinksKeepTheirTextOnly() {
        XCTAssertEqual(
            TranscriptPlainText.flatten(markdown: "Read the [blog post](https://example.com) today."),
            "Read the blog post today."
        )
    }

    func testBlocksJoinWithSingleSpaces() {
        let markdown = """
        # Episode 12

        First paragraph.

        Second paragraph.
        """
        XCTAssertEqual(
            TranscriptPlainText.flatten(markdown: markdown),
            "Episode 12 First paragraph. Second paragraph."
        )
    }

    func testSoftBreaksCollapseToSpaces() {
        let markdown = """
        line one
        line two
        """
        XCTAssertEqual(
            TranscriptPlainText.flatten(markdown: markdown),
            "line one line two"
        )
    }

    func testListsFlattenInOrder() {
        let markdown = """
        - first point
        - second point
        """
        XCTAssertEqual(
            TranscriptPlainText.flatten(markdown: markdown),
            "first point second point"
        )
    }

    func testThematicBreakIsDropped() {
        let markdown = """
        Before.

        ---

        After.
        """
        XCTAssertEqual(
            TranscriptPlainText.flatten(markdown: markdown),
            "Before. After."
        )
    }

    func testEmptyInputProducesEmptyString() {
        XCTAssertEqual(TranscriptPlainText.flatten(markdown: ""), "")
    }
}
