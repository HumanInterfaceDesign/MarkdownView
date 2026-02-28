import XCTest
@testable import MarkdownParser
@testable import MarkdownView

final class ASTDiffTests: XCTestCase {

    func testDiffIdenticalKeepsOriginalIndices() {
        let blocks = [
            MarkdownBlockNode.paragraph(content: [.text("A")]),
            .paragraph(content: [.text("B")]),
        ]

        let changes = ASTDiff.diff(old: blocks, new: blocks)

        XCTAssertEqual(changes.count, 2)
        guard case let .keep(oldIndex, newIndex) = changes[0] else {
            return XCTFail("Expected keep")
        }
        XCTAssertEqual(oldIndex, 0)
        XCTAssertEqual(newIndex, 0)
        guard case let .keep(oldIndex, newIndex) = changes[1] else {
            return XCTFail("Expected keep")
        }
        XCTAssertEqual(oldIndex, 1)
        XCTAssertEqual(newIndex, 1)
    }

    func testDiffAppendOnlyKeepsPrefixAndRebuildsSuffix() {
        let old = [
            MarkdownBlockNode.paragraph(content: [.text("A")]),
            .paragraph(content: [.text("B")]),
        ]
        let new = old + [.paragraph(content: [.text("C")])]

        let changes = ASTDiff.diff(old: old, new: new)

        XCTAssertEqual(changes.count, 3)
        guard case let .keep(oldIndex, newIndex) = changes[0] else {
            return XCTFail("Expected keep")
        }
        XCTAssertEqual(oldIndex, 0)
        XCTAssertEqual(newIndex, 0)
        guard case let .keep(oldIndex, newIndex) = changes[1] else {
            return XCTFail("Expected keep")
        }
        XCTAssertEqual(oldIndex, 1)
        XCTAssertEqual(newIndex, 1)
        guard case let .rebuild(newIndex) = changes[2] else {
            return XCTFail("Expected rebuild")
        }
        XCTAssertEqual(newIndex, 2)
    }

    func testDiffInsertionPreservesSuffixMapping() {
        let old = [
            MarkdownBlockNode.paragraph(content: [.text("A")]),
            .paragraph(content: [.text("C")]),
        ]
        let new = [
            MarkdownBlockNode.paragraph(content: [.text("A")]),
            .paragraph(content: [.text("B")]),
            .paragraph(content: [.text("C")]),
        ]

        let changes = ASTDiff.diff(old: old, new: new)

        XCTAssertEqual(changes.count, 3)
        guard case let .keep(oldIndex, newIndex) = changes[0] else {
            return XCTFail("Expected keep")
        }
        XCTAssertEqual(oldIndex, 0)
        XCTAssertEqual(newIndex, 0)
        guard case let .rebuild(newIndex) = changes[1] else {
            return XCTFail("Expected rebuild")
        }
        XCTAssertEqual(newIndex, 1)
        guard case let .keep(oldIndex, newIndex) = changes[2] else {
            return XCTFail("Expected keep")
        }
        XCTAssertEqual(oldIndex, 1)
        XCTAssertEqual(newIndex, 2)
    }

    func testDiffDeletionPreservesSuffixMapping() {
        let old = [
            MarkdownBlockNode.paragraph(content: [.text("A")]),
            .paragraph(content: [.text("B")]),
            .paragraph(content: [.text("C")]),
        ]
        let new = [
            MarkdownBlockNode.paragraph(content: [.text("A")]),
            .paragraph(content: [.text("C")]),
        ]

        let changes = ASTDiff.diff(old: old, new: new)

        XCTAssertEqual(changes.count, 3)
        guard case let .keep(oldIndex, newIndex) = changes[0] else {
            return XCTFail("Expected keep")
        }
        XCTAssertEqual(oldIndex, 0)
        XCTAssertEqual(newIndex, 0)
        guard case let .remove(oldIndex) = changes[1] else {
            return XCTFail("Expected remove")
        }
        XCTAssertEqual(oldIndex, 1)
        guard case let .keep(oldIndex, newIndex) = changes[2] else {
            return XCTFail("Expected keep")
        }
        XCTAssertEqual(oldIndex, 2)
        XCTAssertEqual(newIndex, 1)
    }
}
