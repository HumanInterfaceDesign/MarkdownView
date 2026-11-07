import XCTest
@testable import MarkdownParser

final class IncrementalParsingTests: XCTestCase {

    private let parser = MarkdownParser()

    func testCombinedParseMatchesStandaloneParsingAndRanges() {
        let fixtures = [
            "", "你好\r\n\r\nCafe\u{301}",
            "# Title\n\nText **bold**\n\n```js\nconst x = 1;\n```",
            "- Item\n\n  ```js\n  const x = 1;\n  ```\n\nAfter",
            "| A | B |\n|---|---|\n| C | D |\n\n> Quote"
        ]
        for markdown in fixtures {
            let combined = parser.parseWithBlockRanges(markdown)
            let standalone = parser.parse(markdown)
            XCTAssertEqual(combined.result.document, standalone.document)
            XCTAssertEqual(combined.result.mathContext, standalone.mathContext)
            XCTAssertEqual(combined.blockRanges.reduce(0) { $0 + $1.outputBlockCount }, combined.result.document.count)
            let ranges = parser.parseBlockRange(markdown)
            XCTAssertEqual(combined.blockRanges.map(\.startIndex), ranges.map(\.startIndex))
            XCTAssertEqual(combined.blockRanges.map(\.endIndex), ranges.map(\.endIndex))
            XCTAssertEqual(combined.blockRanges.map(\.outputBlockCount), ranges.map(\.outputBlockCount))
        }
    }

    func testCombinedParseMapsMultilineMathToOriginalUnicodeSource() {
        let blocks = ["前言 cafe\u{301}", "$$\nx + y\n$$", "間 $$z$$ 後", "End"]
        for newline in ["\n", "\r\n"] {
            let expected = blocks.map { $0.replacingOccurrences(of: "\n", with: newline) }
            let markdown = expected.joined(separator: newline + newline)
            let combined = parser.parseWithBlockRanges(markdown)
            XCTAssertEqual(combined.result.document, parser.parse(markdown).document)
            XCTAssertEqual(combined.result.mathContext.count, 2)
            XCTAssertEqual(combined.blockRanges.map { String(markdown[$0.startIndex...$0.endIndex]) }, expected)
            XCTAssertEqual(combined.blockRanges.reduce(0) { $0 + $1.outputBlockCount }, combined.result.document.count)
        }
    }

    func testMathSourceRangesSurviveRepeatedIncrementalUpdates() throws {
        var markdown = "前言\n\n$$\nx + y\n$$\n\nAlpha\n\nBravo\n\nCharlie\n\nDelta"
        let initial = parser.parseWithBlockRanges(markdown)
        var blocks = initial.result.document
        var ranges = initial.blockRanges
        for suffix in [" more", "\n\nEcho", " text"] {
            let next = markdown + suffix
            let incremental = try XCTUnwrap(parser.parseIncremental(
                previousMarkdown: markdown, newMarkdown: next,
                previousBlocks: blocks, previousRanges: ranges
            ))
            blocks = Array(blocks.prefix(incremental.stablePrefixBlockCount)) + incremental.tailResult.document
            ranges = incremental.blockRanges
            let full = parser.parseWithBlockRanges(next)
            XCTAssertEqual(blocks, full.result.document)
            XCTAssertEqual(ranges.map { String(next[$0.startIndex...$0.endIndex]) },
                           full.blockRanges.map { String(next[$0.startIndex...$0.endIndex]) })
            markdown = next
        }
    }

    func testUnicodeInlineMathPreservesTrailingText() {
        let result = parser.parse("你好 $x$ 後文")
        XCTAssertEqual(Array(result.mathContext.values), ["x"])
        guard let first = result.document.first,
              case let .paragraph(content) = first else { return XCTFail("Expected paragraph") }
        XCTAssertEqual(content.first, .text("你好 "))
        XCTAssertEqual(content.last, .text(" 後文"))
    }

    func testBlockRangesHandleUnicodeAndLineEndings() {
        for newline in ["\n", "\r\n", "\r"] {
            let blocks = ["你好", "cafe\u{301}", "終わり"]
            let markdown = blocks.joined(separator: newline + newline)
            let ranges = parser.parseBlockRange(markdown)
            XCTAssertEqual(ranges.count, blocks.count)
            for (range, expected) in zip(ranges, blocks) {
                XCTAssertEqual(String(markdown[range.startIndex...range.endIndex]), expected)
            }
        }
    }

    func testUnicodeIncrementalRangesMatchFullParsing() throws {
        let previous = ["你好", "cafe\u{301}", "第三段", "最後"].joined(separator: "\r\n\r\n")
        let new = previous + " extended"
        let original = parser.parse(previous)
        let result = try XCTUnwrap(parser.parseIncremental(
            previousMarkdown: previous,
            newMarkdown: new,
            previousBlocks: original.document,
            previousRanges: parser.parseBlockRange(previous)
        ))
        XCTAssertEqual(mergedBlocks(from: original, incremental: result), parser.parse(new).document)
        XCTAssertEqual(
            result.blockRanges.map { String(new[$0.startIndex...$0.endIndex]) },
            parser.parseBlockRange(new).map { String(new[$0.startIndex...$0.endIndex]) }
        )
    }

    func testParsedValuesOutliveNativeTrees() {
        let markdown = "# Title\n\nA **bold** paragraph.\n\n| A | B |\n|---|---|\n| C | D |"
        let expected = parser.parse(markdown).document
        for _ in 0..<100 {
            XCTAssertEqual(parser.parse(markdown).document, expected)
            XCTAssertEqual(parser.parseBlockRange(markdown).count, 3)
        }
    }

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

        XCTAssertEqual(incremental.stablePrefixBlockCount, 5)
        XCTAssertEqual(
            mergedBlocks(from: previousResult, incremental: incremental),
            parser.parse(new).document
        )
    }

    func testParseIncrementalKeepsTightTailWindowForClosedCodeFenceAppend() {
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

        XCTAssertEqual(incremental.stablePrefixBlockCount, 5)
        XCTAssertEqual(
            mergedBlocks(from: previousResult, incremental: incremental),
            parser.parse(new).document
        )
    }

    func testParseIncrementalUsesWiderTailWindowForOpenCodeFenceAppend() {
        let paragraphs = ["Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot"]
        let previous = paragraphs.joined(separator: "\n\n")
        let closedFence = previous + "\n\n```swift\nlet value = 1\n```"
        let new = previous + "\n\n```swift\nlet value = 1"

        let previousResult = parser.parse(previous)
        guard let closedIncremental = parser.parseIncremental(
            previousMarkdown: previous,
            newMarkdown: closedFence,
            previousBlocks: previousResult.document
        ) else {
            return XCTFail("Expected closed-fence incremental parse result")
        }
        guard let incremental = parser.parseIncremental(
            previousMarkdown: previous,
            newMarkdown: new,
            previousBlocks: previousResult.document
        ) else {
            return XCTFail("Expected incremental parse result")
        }

        XCTAssertGreaterThan(incremental.stablePrefixBlockCount, 0)
        XCTAssertLessThan(incremental.stablePrefixBlockCount, closedIncremental.stablePrefixBlockCount)
        XCTAssertEqual(
            mergedBlocks(from: previousResult, incremental: incremental),
            parser.parse(new).document
        )
    }

    func testParseIncrementalUsesWiderTailWindowForBlockquoteContinuation() {
        let paragraphs = ["Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot"]
        let previous = paragraphs.joined(separator: "\n\n")
        let stableTail = previous + " extended"
        let new = previous + "\n\n> quoted"

        let previousResult = parser.parse(previous)
        guard let stableIncremental = parser.parseIncremental(
            previousMarkdown: previous,
            newMarkdown: stableTail,
            previousBlocks: previousResult.document
        ) else {
            return XCTFail("Expected stable-tail incremental parse result")
        }
        guard let incremental = parser.parseIncremental(
            previousMarkdown: previous,
            newMarkdown: new,
            previousBlocks: previousResult.document
        ) else {
            return XCTFail("Expected blockquote incremental parse result")
        }

        XCTAssertGreaterThan(incremental.stablePrefixBlockCount, 0)
        XCTAssertLessThan(incremental.stablePrefixBlockCount, stableIncremental.stablePrefixBlockCount)
        XCTAssertEqual(
            mergedBlocks(from: previousResult, incremental: incremental),
            parser.parse(new).document
        )
    }

    func testParseIncrementalUsesWiderTailWindowForListContinuation() {
        let paragraphs = ["Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot"]
        let previous = paragraphs.joined(separator: "\n\n")
        let stableTail = previous + " extended"
        let new = previous + "\n\n- item"

        let previousResult = parser.parse(previous)
        guard let stableIncremental = parser.parseIncremental(
            previousMarkdown: previous,
            newMarkdown: stableTail,
            previousBlocks: previousResult.document
        ) else {
            return XCTFail("Expected stable-tail incremental parse result")
        }
        guard let incremental = parser.parseIncremental(
            previousMarkdown: previous,
            newMarkdown: new,
            previousBlocks: previousResult.document
        ) else {
            return XCTFail("Expected list incremental parse result")
        }

        XCTAssertGreaterThan(incremental.stablePrefixBlockCount, 0)
        XCTAssertLessThan(incremental.stablePrefixBlockCount, stableIncremental.stablePrefixBlockCount)
        XCTAssertEqual(
            mergedBlocks(from: previousResult, incremental: incremental),
            parser.parse(new).document
        )
    }

    func testParseIncrementalUsesWiderTailWindowForNumberedListContinuation() {
        let paragraphs = ["Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot"]
        let previous = paragraphs.joined(separator: "\n\n")
        let stableTail = previous + " extended"
        let new = previous + "\n\n1. item"

        let previousResult = parser.parse(previous)
        guard let stableIncremental = parser.parseIncremental(
            previousMarkdown: previous,
            newMarkdown: stableTail,
            previousBlocks: previousResult.document
        ) else {
            return XCTFail("Expected stable-tail incremental parse result")
        }
        guard let incremental = parser.parseIncremental(
            previousMarkdown: previous,
            newMarkdown: new,
            previousBlocks: previousResult.document
        ) else {
            return XCTFail("Expected numbered-list incremental parse result")
        }

        XCTAssertGreaterThan(incremental.stablePrefixBlockCount, 0)
        XCTAssertLessThan(incremental.stablePrefixBlockCount, stableIncremental.stablePrefixBlockCount)
        XCTAssertEqual(
            mergedBlocks(from: previousResult, incremental: incremental),
            parser.parse(new).document
        )
    }

    func testParseIncrementalUsesWiderTailWindowForTableContinuation() {
        let paragraphs = ["Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot"]
        let previous = paragraphs.joined(separator: "\n\n")
        let stableTail = previous + " extended"
        let new = previous + "\n\n| A |"

        let previousResult = parser.parse(previous)
        guard let stableIncremental = parser.parseIncremental(
            previousMarkdown: previous,
            newMarkdown: stableTail,
            previousBlocks: previousResult.document
        ) else {
            return XCTFail("Expected stable-tail incremental parse result")
        }
        guard let incremental = parser.parseIncremental(
            previousMarkdown: previous,
            newMarkdown: new,
            previousBlocks: previousResult.document
        ) else {
            return XCTFail("Expected table incremental parse result")
        }

        XCTAssertGreaterThan(incremental.stablePrefixBlockCount, 0)
        XCTAssertLessThan(incremental.stablePrefixBlockCount, stableIncremental.stablePrefixBlockCount)
        XCTAssertEqual(
            mergedBlocks(from: previousResult, incremental: incremental),
            parser.parse(new).document
        )
    }

    func testParseIncrementalKeepsTightTailWindowForClosedTableAppend() {
        let paragraphs = ["Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot"]
        let previous = paragraphs.joined(separator: "\n\n")
        let new = previous + "\n\n| A |\n|---|\n| B |"

        let previousResult = parser.parse(previous)
        guard let incremental = parser.parseIncremental(
            previousMarkdown: previous,
            newMarkdown: new,
            previousBlocks: previousResult.document
        ) else {
            return XCTFail("Expected closed-table incremental parse result")
        }

        XCTAssertEqual(incremental.stablePrefixBlockCount, 5)
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
