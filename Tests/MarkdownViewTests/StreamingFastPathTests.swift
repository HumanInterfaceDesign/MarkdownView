import XCTest
@testable import MarkdownParser
@testable import MarkdownView

@MainActor
final class StreamingFastPathTests: XCTestCase {

    private let parser = MarkdownParser()

    func testBurstRetainsOnlyLatestPendingInput() {
        let view = MarkdownTextView()
        view.throttleInterval = nil
        view.setMarkdown(string: "First **input**")
        for index in 0..<100 {
            view.setMarkdown(string: "Latest **input \(index)**")
        }
        XCTAssertTrue(view.isRawPreprocessing)
        XCTAssertEqual(view.pendingRawMarkdown, "Latest **input 99**")
        waitForPreprocessing(view)
        XCTAssertEqual(view.lastRawMarkdown, "Latest **input 99**")
        XCTAssertEqual(view.document.blocks, parser.parse("Latest **input 99**").document)
    }

    func testCompletedParseRendersWhileNewerInputIsQueued() {
        let view = MarkdownTextView()
        view.throttleInterval = nil
        let first = "First **input**"
        let latest = "Latest **input 99**"
        view.setMarkdown(string: first)

        // The serial queue finishes the first parse but cannot start the next one
        // until released. This makes intermediate progress deterministic, independent
        // of parser speed, rather than accidentally observing only the final result.
        let releaseNextParse = DispatchSemaphore(value: 0)
        MarkdownTextView.preprocessingQueue.async {
            releaseNextParse.wait()
        }
        defer { releaseNextParse.signal() }
        for index in 0..<100 {
            view.setMarkdown(string: "Latest **input \(index)**")
        }
        XCTAssertEqual(view.pendingRawMarkdown, latest)

        let deadline = Date().addingTimeInterval(5)
        while view.pendingRawMarkdown != nil, Date() < deadline {
            _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.001))
        }
        XCTAssertNil(view.pendingRawMarkdown, "The completed parse must schedule the latest input")
        XCTAssertTrue(view.isRawPreprocessing)
        XCTAssertEqual(view.lastRawMarkdown, first, "Progress must render before the stream becomes idle")
        XCTAssertEqual(view.document.blocks, parser.parse(first).document)

        releaseNextParse.signal()
        waitForPreprocessing(view)
        XCTAssertEqual(view.lastRawMarkdown, latest)
        XCTAssertEqual(view.document.blocks, parser.parse(latest).document)
    }

    func testPlainAppendKeepsRangesForNextStructuralUpdate() throws {
        let view = MarkdownTextView()
        view.throttleInterval = nil
        let initial = "Alpha\n\nBravo\n\nCharlie\n\nDelta\n\nEcho\n\nFoxtrot"
        view.setMarkdown(string: initial)
        waitForPreprocessing(view)
        XCTAssertNotNil(view.lastRootBlockRanges)
        let appended = initial + " more"
        view.setMarkdown(string: appended)
        waitForPreprocessing(view)
        let ranges = try XCTUnwrap(view.lastRootBlockRanges)
        XCTAssertEqual(ranges.map { String(appended[$0.startIndex...$0.endIndex]) },
                       parser.parseWithBlockRanges(appended).blockRanges.map { String(appended[$0.startIndex...$0.endIndex]) })
        let structural = appended + " **bold**"
        view.setMarkdown(string: structural)
        waitForPreprocessing(view)
        XCTAssertEqual(view.document.blocks, parser.parse(structural).document)
    }

    func testResetDiscardsInFlightResult() {
        let view = MarkdownTextView()
        view.throttleInterval = nil
        view.setMarkdown(string: "Stale **content**")
        view.reset()
        waitForPreprocessing(view)
        XCTAssertNil(view.lastRawMarkdown)
        XCTAssertTrue(view.document.blocks.isEmpty)
    }

    func testManualContentSurvivesInFlightResult() {
        let view = MarkdownTextView()
        view.throttleInterval = nil
        view.setMarkdown(string: "Stale **content**")
        let manual = MarkdownTextView.PreprocessedContent(markdown: "Replacement", theme: .default)
        view.setMarkdownManually(manual)
        waitForPreprocessing(view)
        XCTAssertEqual(view.document.blocks, manual.blocks)
        XCTAssertNil(view.lastRawMarkdown)
    }

    func testRawPipelineCanRestartWhileOldWorkFinishes() {
        let view = MarkdownTextView()
        view.throttleInterval = nil
        view.setMarkdown(string: "Stale **content**")
        view.reset()
        view.setMarkdown(string: "New **content**")
        waitForPreprocessing(view)
        XCTAssertEqual(view.lastRawMarkdown, "New **content**")
        XCTAssertEqual(view.document.blocks, parser.parse("New **content**").document)
    }

    private func waitForPreprocessing(_ view: MarkdownTextView) {
        let deadline = Date().addingTimeInterval(5)
        while (view.isRawPreprocessing || view.pendingRawMarkdown != nil), Date() < deadline {
            _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.001))
        }
        XCTAssertFalse(view.isRawPreprocessing)
        XCTAssertNil(view.pendingRawMarkdown)
    }

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
