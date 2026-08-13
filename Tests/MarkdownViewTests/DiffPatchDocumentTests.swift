import XCTest
@testable import MarkdownView

final class DiffPatchDocumentTests: XCTestCase {
    private let patch = """
    diff --git a/Sources/A.swift b/Sources/A.swift
    --- a/Sources/A.swift
    +++ b/Sources/A.swift
    @@ -10,3 +10,4 @@
     line10
    -line11
    +line11b
    +line11c
     line12
    @@ -100,2 +101,2 @@
     line100
    -line101
    +line101b
    diff --git a/B.swift b/B.swift
    --- a/B.swift
    +++ b/B.swift
    @@ -1,2 +1,3 @@
     one
    +two
     three
    """

    private func makeDocument() -> DiffPatchDocument {
        guard let document = DiffPatchDocument(patch: patch, language: "swift") else {
            fatalError("patch should parse")
        }
        return document
    }

    func testSplitsFilesAndHunks() {
        let document = makeDocument()
        XCTAssertEqual(document.files.map(\.displayPath), ["Sources/A.swift", "B.swift"])

        let a = document.files[0]
        XCTAssertEqual(a.hunks.count, 2)
        XCTAssertEqual(a.hunks[0].oldStart, 10)
        XCTAssertEqual(a.hunks[0].oldCount, 3)
        XCTAssertEqual(a.hunks[0].newCount, 4)
        XCTAssertEqual(a.hunks[0].oldEnd, 12)
        XCTAssertEqual(a.hunks[1].oldStart, 100)
        XCTAssertEqual(a.additions, 3)
        XCTAssertEqual(a.deletions, 2)

        let b = document.files[1]
        XCTAssertEqual(b.hunks.count, 1)
        XCTAssertEqual(b.hunks[0].oldStart, 1)
    }

    func testItemsInterleaveExpanders() {
        let document = makeDocument()
        let items = document.items(forFileWithID: 0, chunkSize: 20, totalOldLineCount: 200)

        guard items.count == 5,
              case let .expander(leading) = items[0],
              case .hunk = items[1],
              case let .expander(middle) = items[2],
              case .hunk = items[3],
              case let .expander(trailing) = items[4]
        else { return XCTFail("unexpected items: \(items)") }

        XCTAssertEqual(leading.gap, 1 ... 9)
        XCTAssertEqual(leading.direction, .up)
        XCTAssertTrue(leading.coversEntireGap)

        XCTAssertEqual(middle.gap, 13 ... 99)
        XCTAssertEqual(middle.direction, .both)
        XCTAssertFalse(middle.coversEntireGap)

        XCTAssertEqual(trailing.gap, 102 ... 200)
        XCTAssertEqual(trailing.direction, .down)
    }

    func testTrailingExpanderNeedsFileLength() {
        let document = makeDocument()
        let items = document.items(forFileWithID: 0, chunkSize: 20)
        XCTAssertEqual(items.count, 4)
        if case .expander = items[3] { XCTFail("no trailing expander without a line count") }
    }

    func testNoExpanderWhenFileStartsAtFirstLine() {
        let document = makeDocument()
        let items = document.items(forFileWithID: 1, chunkSize: 20)
        XCTAssertEqual(items.count, 1)
        if case .expander = items[0] { XCTFail("first hunk starts at line 1") }
    }

    func testRequestedRangesForPartialGap() {
        let document = makeDocument()
        let items = document.items(forFileWithID: 0, chunkSize: 20, totalOldLineCount: 200)
        guard case let .expander(middle) = items[2] else { return XCTFail("expected expander") }

        XCTAssertEqual(middle.requestedRange(for: .up, chunkSize: 20), 80 ... 99)
        XCTAssertEqual(middle.requestedRange(for: .down, chunkSize: 20), 13 ... 32)

        guard case let .expander(leading) = items[0] else { return XCTFail("expected expander") }
        XCTAssertEqual(leading.requestedRange(for: .up, chunkSize: 20), 1 ... 9)
    }

    func testExpandingUpwardsGrowsFollowingHunk() {
        var document = makeDocument()
        let items = document.items(forFileWithID: 0, chunkSize: 20, totalOldLineCount: 200)
        guard case let .expander(middle) = items[2] else { return XCTFail("expected expander") }

        let range = middle.requestedRange(for: .up, chunkSize: 20)
        document.insertContext(
            lines: range.map { "line\($0)" },
            forOldLineRange: range,
            fileID: 0,
            direction: .up,
            expander: middle
        )

        let hunk = document.files[0].hunks[1]
        XCTAssertEqual(hunk.oldStart, 80)
        XCTAssertEqual(hunk.newStart, 81)
        XCTAssertEqual(hunk.rows.first?.text, "line80")
        XCTAssertEqual(hunk.rows.first?.oldLineNumber, 80)
        XCTAssertEqual(hunk.rows.first?.newLineNumber, 81)
        XCTAssertEqual(hunk.oldCount, 22)
        XCTAssertEqual(document.files[0].hunks.count, 2)
    }

    func testExpandingDownwardsGrowsPrecedingHunk() {
        var document = makeDocument()
        let items = document.items(forFileWithID: 0, chunkSize: 20, totalOldLineCount: 200)
        guard case let .expander(middle) = items[2] else { return XCTFail("expected expander") }

        let range = middle.requestedRange(for: .down, chunkSize: 20)
        document.insertContext(
            lines: range.map { "line\($0)" },
            forOldLineRange: range,
            fileID: 0,
            direction: .down,
            expander: middle
        )

        let hunk = document.files[0].hunks[0]
        XCTAssertEqual(hunk.oldStart, 10)
        XCTAssertEqual(hunk.oldEnd, 32)
        XCTAssertEqual(hunk.rows.last?.text, "line32")
        XCTAssertEqual(hunk.rows.last?.newLineNumber, 33)
    }

    func testFillingGapMergesAdjacentHunks() {
        var document = makeDocument()
        let items = document.items(forFileWithID: 0, chunkSize: 200, totalOldLineCount: 200)
        guard case let .expander(middle) = items[2] else { return XCTFail("expected expander") }
        XCTAssertTrue(middle.coversEntireGap)

        document.insertContext(
            lines: middle.gap.map { "line\($0)" },
            forOldLineRange: middle.gap,
            fileID: 0,
            direction: .both,
            expander: middle
        )

        XCTAssertEqual(document.files[0].hunks.count, 1)
        let hunk = document.files[0].hunks[0]
        XCTAssertEqual(hunk.oldStart, 10)
        XCTAssertEqual(hunk.oldEnd, 101)
        XCTAssertEqual(document.files[0].additions, 3)
        XCTAssertEqual(document.files[0].deletions, 2)
    }

    func testLeadingExpansionReachesTopOfFile() {
        var document = makeDocument()
        let items = document.items(forFileWithID: 0, chunkSize: 20, totalOldLineCount: 200)
        guard case let .expander(leading) = items[0] else { return XCTFail("expected expander") }

        document.insertContext(
            lines: leading.gap.map { "line\($0)" },
            forOldLineRange: leading.gap,
            fileID: 0,
            direction: .both,
            expander: leading
        )

        XCTAssertEqual(document.files[0].hunks[0].oldStart, 1)
        XCTAssertEqual(document.files[0].hunks[0].newStart, 1)
        let remaining = document.items(forFileWithID: 0, chunkSize: 20, totalOldLineCount: 200)
        if case .expander = remaining[0] { XCTFail("gap above the first hunk is gone") }
    }

    func testOverlappingResponseDoesNotDuplicateLines() {
        var document = makeDocument()
        let items = document.items(forFileWithID: 0, chunkSize: 20, totalOldLineCount: 200)
        guard case let .expander(middle) = items[2] else { return XCTFail("expected expander") }

        // Provider returns more than was asked for, overlapping both hunks.
        document.insertContext(
            lines: (1 ... 120).map { "line\($0)" },
            forOldLineRange: 1 ... 120,
            fileID: 0,
            direction: .down,
            expander: middle
        )

        let hunk = document.files[0].hunks[0]
        XCTAssertEqual(hunk.oldStart, 10)
        XCTAssertEqual(hunk.rows.map(\.oldLineNumber).compactMap { $0 }, Array(10 ... 12) + Array(13 ... 120))
    }
}
