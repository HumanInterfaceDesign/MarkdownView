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

    func testPureInsertionHunkFabricatesNoLineZeroGap() {
        let newFilePatch = """
        diff --git a/app/page.tsx b/app/page.tsx
        --- /dev/null
        +++ b/app/page.tsx
        @@ -0,0 +1,3 @@
        +one
        +two
        +three
        """
        guard let document = DiffPatchDocument(patch: newFilePatch, language: "tsx") else {
            return XCTFail("patch should parse")
        }

        // Empty pre-image: no gap exists anywhere, even though oldEnd (-1) is
        // below the reported total (0).
        let emptyPreImage = document.items(forFileWithID: 0, chunkSize: 20, totalOldLineCount: 0)
        XCTAssertEqual(emptyPreImage.count, 1)
        if case .expander = emptyPreImage[0] { XCTFail("no expander for an empty pre-image") }

        // Non-empty pre-image below a pure-insertion hunk: the gap starts at
        // line 1, never line 0.
        let items = document.items(forFileWithID: 0, chunkSize: 20, totalOldLineCount: 5)
        guard case let .expander(trailing) = items.last else {
            return XCTFail("expected trailing expander: \(items)")
        }
        XCTAssertEqual(trailing.gap, 1 ... 5)
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

    func testOverlappingRangeDoesNotDuplicateLinesOrSwallowRemovals() {
        var document = makeDocument()
        let items = document.items(forFileWithID: 0, chunkSize: 20, totalOldLineCount: 200)
        guard case let .expander(middle) = items[2] else { return XCTFail("expected expander") }

        // The caller passes a range overlapping both hunks. The merge must drop
        // the redundant context copies, not the second hunk's removed row.
        document.insertContext(
            lines: (1 ... 120).map { "line\($0)" },
            forOldLineRange: 1 ... 120,
            fileID: 0,
            direction: .down,
            expander: middle
        )

        XCTAssertEqual(document.files[0].hunks.count, 1)
        let hunk = document.files[0].hunks[0]
        XCTAssertEqual(hunk.oldStart, 10)
        XCTAssertEqual(hunk.rows.compactMap(\.oldLineNumber), Array(10 ... 101))
        XCTAssertTrue(hunk.rows.contains { $0.kind == .removed && $0.oldLineNumber == 101 })
        XCTAssertEqual(document.files[0].additions, 3)
        XCTAssertEqual(document.files[0].deletions, 2)
    }

    func testOverLongResponseIsClampedToRequestedRange() {
        var document = makeDocument()
        let items = document.items(forFileWithID: 0, chunkSize: 20, totalOldLineCount: 200)
        guard case let .expander(middle) = items[2] else { return XCTFail("expected expander") }

        // Downwards: the provider returns far more lines than the requested
        // 13...32; the extra tail must not spill towards the next hunk.
        let downRange = middle.requestedRange(for: .down, chunkSize: 20)
        document.insertContext(
            lines: (downRange.lowerBound ... 200).map { "line\($0)" },
            forOldLineRange: downRange,
            fileID: 0,
            direction: .down,
            expander: middle
        )
        XCTAssertEqual(document.files[0].hunks[0].oldEnd, 32)
        XCTAssertEqual(document.files[0].hunks[0].rows.last?.text, "line32")

        // Upwards: line i of the response is range.lowerBound + i, so an
        // over-long response's tail (lines past 99, inside the hunk) must be
        // cut rather than misnumbered as the lines nearest the hunk.
        let upRange = middle.requestedRange(for: .up, chunkSize: 20)
        document.insertContext(
            lines: (upRange.lowerBound ... 150).map { "line\($0)" },
            forOldLineRange: upRange,
            fileID: 0,
            direction: .up,
            expander: middle
        )
        let below = document.files[0].hunks[1]
        XCTAssertEqual(below.oldStart, 80)
        XCTAssertEqual(below.rows.first?.text, "line80")
        XCTAssertEqual(below.rows.first?.oldLineNumber, 80)
    }

    private let threeHunkPatch = """
    diff --git a/C.swift b/C.swift
    --- a/C.swift
    +++ b/C.swift
    @@ -10,2 +10,2 @@
     line10
    -line11
    +line11b
    @@ -20,2 +20,2 @@
     line20
    -line21
    +line21b
    @@ -100,2 +100,2 @@
     line100
    -line101
    +line101b
    """

    func testInFlightExpansionSurvivesUnrelatedMerge() {
        guard var document = DiffPatchDocument(patch: threeHunkPatch, language: "swift") else {
            return XCTFail("patch should parse")
        }
        let items = document.items(forFileWithID: 0, chunkSize: 20, totalOldLineCount: 200)
        guard case let .expander(first) = items[2], // gap 12...19, fits one chunk
              case let .expander(second) = items[4] // gap 22...99
        else { return XCTFail("unexpected items: \(items)") }
        XCTAssertTrue(first.coversEntireGap)

        // Filling the first gap merges hunks 0 and 1 while the second gap's
        // expansion is still "in flight".
        document.insertContext(
            lines: first.gap.map { "line\($0)" },
            forOldLineRange: first.gap,
            fileID: 0,
            direction: .both,
            expander: first
        )
        XCTAssertEqual(document.files[0].hunks.count, 2)

        // The stale expander references hunks by ID, so its upward expansion
        // still grows the correct (third) hunk after the merge shifted indices.
        let upRange = second.requestedRange(for: .up, chunkSize: 20)
        document.insertContext(
            lines: upRange.map { "line\($0)" },
            forOldLineRange: upRange,
            fileID: 0,
            direction: .up,
            expander: second
        )
        XCTAssertEqual(document.files[0].hunks[1].oldStart, 80)
        XCTAssertEqual(document.files[0].hunks[1].rows.first?.text, "line80")
    }

    func testExpansionTargetingSwallowedHunkIsIgnored() {
        guard var document = DiffPatchDocument(patch: threeHunkPatch, language: "swift") else {
            return XCTFail("patch should parse")
        }
        let items = document.items(forFileWithID: 0, chunkSize: 20, totalOldLineCount: 200)
        guard case let .expander(first) = items[2],
              case let .expander(second) = items[4]
        else { return XCTFail("unexpected items: \(items)") }

        document.insertContext(
            lines: first.gap.map { "line\($0)" },
            forOldLineRange: first.gap,
            fileID: 0,
            direction: .both,
            expander: first
        )
        let hunksAfterMerge = document.files[0].hunks

        // The second expander's "hunk above" was swallowed by the merge; its
        // downward expansion must be a no-op, not a splice into whichever hunk
        // now sits at that index.
        let downRange = second.requestedRange(for: .down, chunkSize: 20)
        document.insertContext(
            lines: downRange.map { "line\($0)" },
            forOldLineRange: downRange,
            fileID: 0,
            direction: .down,
            expander: second
        )
        XCTAssertEqual(
            document.files[0].hunks.map { $0.rows.count },
            hunksAfterMerge.map { $0.rows.count }
        )
    }
}
