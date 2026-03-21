import XCTest
@testable import MarkdownParser
@testable import MarkdownView

final class DiffViewTests: XCTestCase {

    private let parser = MarkdownParser()

    func testPreprocessedContentBuildsDiffRenderBlock() {
        let content = makeContent(
            from: """
            ```diff swift
            @@ -11,7 +11,7 @@ export default function Home() {
             <div>
            -  <h2>Design Engineer</h2>
            +  <h2>Designer</h2>
             </div>
            ```
            """
        )

        XCTAssertEqual(content.diffRenderBlocks.count, 1)
        XCTAssertTrue(content.highlightMaps.isEmpty, "Diff fences should not use normal code-block highlighting")

        guard let renderBlock = content.diffRenderBlocks.values.first else {
            return XCTFail("Expected diff render block")
        }

        XCTAssertEqual(renderBlock.language, "swift")
        XCTAssertEqual(renderBlock.rows.count, 5)
        XCTAssertEqual(renderBlock.rows[0].kind, .hunkHeader)
        XCTAssertEqual(renderBlock.rows[1].oldLineNumber, 11)
        XCTAssertEqual(renderBlock.rows[1].newLineNumber, 11)
        XCTAssertEqual(renderBlock.rows[2].kind, .removed)
        XCTAssertEqual(renderBlock.rows[2].oldLineNumber, 12)
        XCTAssertNil(renderBlock.rows[2].newLineNumber)
        XCTAssertEqual(renderBlock.rows[3].kind, .added)
        XCTAssertNil(renderBlock.rows[3].oldLineNumber)
        XCTAssertEqual(renderBlock.rows[3].newLineNumber, 12)
        XCTAssertEqual(renderBlock.rows[4].oldLineNumber, 13)
        XCTAssertEqual(renderBlock.rows[4].newLineNumber, 13)
    }

    func testDiffWithoutLanguageUsesPlainDiffSyntax() {
        let content = makeContent(
            from: """
            ```diff
            @@ -1 +1 @@
            -foo
            +bar
            ```
            """
        )

        guard let renderBlock = content.diffRenderBlocks.values.first else {
            return XCTFail("Expected diff render block")
        }

        XCTAssertNil(renderBlock.language)
        XCTAssertTrue(renderBlock.rows[1].syntaxHighlights.isEmpty)
        XCTAssertTrue(renderBlock.rows[2].syntaxHighlights.isEmpty)
    }

    func testDiffRenderBlockTracksAnnotationRows() {
        let content = makeContent(
            from: """
            ```diff
            @@ -1 +1 @@
            -foo
            +bar
            \\ No newline at end of file
            ```
            """
        )

        guard let renderBlock = content.diffRenderBlocks.values.first else {
            return XCTFail("Expected diff render block")
        }

        XCTAssertEqual(renderBlock.rows.count, 4)
        XCTAssertEqual(renderBlock.rows[3].kind, .annotation)
        XCTAssertNil(renderBlock.rows[3].oldLineNumber)
        XCTAssertNil(renderBlock.rows[3].newLineNumber)
    }

    func testDiffRenderBlockPreservesFileHeaderRows() {
        let content = makeContent(
            from: """
            ```diff swift
            diff --git a/components/screens/home/index.tsx b/components/screens/home/index.tsx
            index 1234567..89abcde 100644
            --- a/components/screens/home/index.tsx
            +++ b/components/screens/home/index.tsx
            @@ -11,2 +11,2 @@ export default function Home() {
            -  <h2>Design Engineer</h2>
            +  <h2>Designer</h2>
            ```
            """
        )

        guard let renderBlock = content.diffRenderBlocks.values.first else {
            return XCTFail("Expected diff render block")
        }

        XCTAssertEqual(renderBlock.rows[0].kind, .fileHeader)
        XCTAssertEqual(renderBlock.rows[0].text, "diff --git a/components/screens/home/index.tsx b/components/screens/home/index.tsx")
        XCTAssertEqual(renderBlock.rows[1].kind, .fileMetadata)
        XCTAssertEqual(renderBlock.rows[2].kind, .fileHeader)
        XCTAssertEqual(renderBlock.rows[3].kind, .fileHeader)
        XCTAssertEqual(renderBlock.rows[4].kind, .hunkHeader)
        XCTAssertEqual(renderBlock.rows[5].kind, .removed)
        XCTAssertEqual(renderBlock.rows[6].kind, .added)
    }

    func testInlineDiffEmphasisPairsRemovedAndAddedRowsByIndex() {
        let content = makeContent(
            from: """
            ```diff swift
            @@ -1,2 +1,3 @@
            -let greeting = "hello"
            -let parting = "bye"
            +let greeting = "hi there"
            +let parting = "goodbye"
            +let extra = "!"
            ```
            """
        )

        guard let renderBlock = content.diffRenderBlocks.values.first else {
            return XCTFail("Expected diff render block")
        }

        XCTAssertFalse(renderBlock.rows[1].emphasizedRanges.isEmpty)
        XCTAssertFalse(renderBlock.rows[2].emphasizedRanges.isEmpty)
        XCTAssertFalse(renderBlock.rows[3].emphasizedRanges.isEmpty)
        XCTAssertFalse(renderBlock.rows[4].emphasizedRanges.isEmpty)
        XCTAssertTrue(renderBlock.rows[5].emphasizedRanges.isEmpty, "Unpaired added rows should remain line-level only")
    }

    func testInvalidDiffFallsBackToCodeView() {
        let content = makeContent(
            from: """
            ```diff swift
            not a unified diff
            ```
            """
        )

        XCTAssertTrue(content.diffRenderBlocks.isEmpty)

        runOnMain {
            let view = MarkdownTextView()
            view.setMarkdownManually(content)

            XCTAssertEqual(view.contextViews.count, 1)
            XCTAssertTrue(view.contextViews.first is CodeView)
            XCTAssertFalse(view.contextViews.first is DiffView)
        }
    }

    func testValidDiffRendersDiffView() {
        let content = makeContent(
            from: """
            ```diff swift
            @@ -1 +1 @@
            -let title = "Design Engineer"
            +let title = "Designer"
            ```
            """
        )

        runOnMain {
            let view = MarkdownTextView()
            view.setMarkdownManually(content)

            XCTAssertEqual(view.contextViews.count, 1)
            XCTAssertTrue(view.contextViews.first is DiffView)
        }
    }

    func testDiffViewIsReusedFromPool() {
        let content = makeContent(
            from: """
            ```diff swift
            @@ -1 +1 @@
            -let title = "Design Engineer"
            +let title = "Designer"
            ```
            """
        )

        runOnMain {
            let provider = ReusableViewProvider()
            let view = MarkdownTextView(viewProvider: provider)
            view.setMarkdownManually(content)

            guard let firstDiffView = view.contextViews.first as? DiffView else {
                return XCTFail("Expected first render to use DiffView")
            }

            view.setMarkdownManually(.init())
            view.setMarkdownManually(content)

            guard let reusedDiffView = view.contextViews.first as? DiffView else {
                return XCTFail("Expected second render to use DiffView")
            }

            XCTAssertTrue(firstDiffView === reusedDiffView)
        }
    }

    private func makeContent(from markdown: String) -> MarkdownTextView.PreprocessedContent {
        let result = parser.parse(markdown)
        return MarkdownTextView.PreprocessedContent(
            parserResult: result,
            theme: .default
        )
    }

    private func runOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
            return
        }

        DispatchQueue.main.sync {
            work()
        }
    }
}
