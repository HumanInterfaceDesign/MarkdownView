import MarkdownParser
import XCTest

final class PublicParserAPITests: XCTestCase {
    func testRootBlockRangeCanBeConstructedOutsideParserModule() throws {
        let markdown = "Original paragraph"
        let parsed = MarkdownParser().parseWithBlockRanges(markdown)
        let original = try XCTUnwrap(parsed.blockRanges.first)
        let reconstructed = MarkdownParser.RootBlockRange(
            type: original.type,
            startIndex: original.startIndex,
            endIndex: original.endIndex,
            outputBlockCount: original.outputBlockCount
        )
        XCTAssertEqual(reconstructed.type, original.type)
        XCTAssertEqual(reconstructed.startIndex, original.startIndex)
        XCTAssertEqual(reconstructed.endIndex, original.endIndex)
        XCTAssertEqual(reconstructed.outputBlockCount, original.outputBlockCount)
    }
}
