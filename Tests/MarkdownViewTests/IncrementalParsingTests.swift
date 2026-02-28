import XCTest
@testable import MarkdownParser

final class IncrementalParsingTests: XCTestCase {

    private let parser = MarkdownParser()

    func testParseIncrementalMatchesFullParseForTrailingPlainTextAppend() {
        let paragraphs = ["Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot"]
        let previous = paragraphs.joined(separator: "\n\n")
        let new = previous + " extended"

        let previousResult = parser.parse(previous)
        guard let incremental = parser.parseIncremental(
            previousMarkdown: previous,
            newMarkdown: new,
            previousBlocks: previousResult.document
        ) else {
            return XCTFail("Expected incremental parse result")
        }

        XCTAssertEqual(incremental.stablePrefixBlockCount, 3)
        XCTAssertEqual(
            mergedBlocks(from: previousResult, incremental: incremental),
            parser.parse(new).document
        )
    }

    func testParseIncrementalMatchesFullParseForTailMarkdownAppend() {
        let paragraphs = ["Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot"]
        let previous = paragraphs.joined(separator: "\n\n")
        let new = previous + "\n\n```swift\nlet value = 1\n```"

        let previousResult = parser.parse(previous)
        guard let incremental = parser.parseIncremental(
            previousMarkdown: previous,
            newMarkdown: new,
            previousBlocks: previousResult.document
        ) else {
            return XCTFail("Expected incremental parse result")
        }

        XCTAssertGreaterThan(incremental.stablePrefixBlockCount, 0)
        XCTAssertEqual(
            mergedBlocks(from: previousResult, incremental: incremental),
            parser.parse(new).document
        )
    }

    func testParseIncrementalMatchesFullParseForOpenCodeFenceAppend() {
        let paragraphs = ["Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot"]
        let previous = paragraphs.joined(separator: "\n\n")
        let new = previous + "\n\n```swift\nlet value = 1"

        let previousResult = parser.parse(previous)
        guard let incremental = parser.parseIncremental(
            previousMarkdown: previous,
            newMarkdown: new,
            previousBlocks: previousResult.document
        ) else {
            return XCTFail("Expected incremental parse result")
        }

        XCTAssertGreaterThan(incremental.stablePrefixBlockCount, 0)
        XCTAssertEqual(
            mergedBlocks(from: previousResult, incremental: incremental),
            parser.parse(new).document
        )
    }

    func testParseIncrementalShiftsTailMathIdentifiersPastStablePrefix() {
        let previous = [
            "Prefix $a$",
            "Second $b$",
            "Third",
            "Fourth",
            "Fifth",
            "Sixth",
        ].joined(separator: "\n\n")
        let new = previous + "\n\nTail math $c$"

        let previousResult = parser.parse(previous)
        guard let incremental = parser.parseIncremental(
            previousMarkdown: previous,
            newMarkdown: new,
            previousBlocks: previousResult.document
        ) else {
            return XCTFail("Expected incremental parse result")
        }

        XCTAssertEqual(Set(incremental.tailResult.mathContext.keys), Set([2]))
        XCTAssertEqual(
            mergedBlocks(from: previousResult, incremental: incremental),
            parser.parse(new).document
        )
    }

    func testParseIncrementalFallsBackWhenEditTouchesStablePrefix() {
        let previous = ["Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot"]
            .joined(separator: "\n\n")
        let new = ["Alpha updated", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot"]
            .joined(separator: "\n\n")

        let previousResult = parser.parse(previous)
        XCTAssertNil(
            parser.parseIncremental(
                previousMarkdown: previous,
                newMarkdown: new,
                previousBlocks: previousResult.document
            )
        )
    }

    func testParseIncrementalFallsBackForDeletion() {
        let previous = ["Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot"]
            .joined(separator: "\n\n")
        let new = ["Alpha", "Bravo", "Charlie", "Delta", "Echo"]
            .joined(separator: "\n\n")

        let previousResult = parser.parse(previous)
        XCTAssertNil(
            parser.parseIncremental(
                previousMarkdown: previous,
                newMarkdown: new,
                previousBlocks: previousResult.document
            )
        )
    }

    func testParseIncrementalFallsBackForIdenticalResend() {
        let markdown = ["Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot"]
            .joined(separator: "\n\n")
        let previousResult = parser.parse(markdown)

        XCTAssertNil(
            parser.parseIncremental(
                previousMarkdown: markdown,
                newMarkdown: markdown,
                previousBlocks: previousResult.document
            )
        )
    }

    private func mergedBlocks(
        from previousResult: MarkdownParser.ParseResult,
        incremental: MarkdownParser.IncrementalParseResult
    ) -> [MarkdownBlockNode] {
        Array(previousResult.document.prefix(incremental.stablePrefixBlockCount)) + incremental.tailResult.document
    }
}
