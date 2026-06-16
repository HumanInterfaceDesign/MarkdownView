import XCTest
import MarkdownLanguages
@testable import MarkdownParser
@testable import MarkdownView
#if canImport(AppKit)
    import AppKit
#elseif canImport(UIKit)
    import UIKit
#endif

final class DiffViewTests: XCTestCase {

    override class func setUp() {
        super.setUp()
        MarkdownLanguages.registerAll()
    }

    private let parser = MarkdownParser()
    private let userProvidedMixedDiff = """
        ```diff
        @@ -3,9 +3,12 @@ import { useState } from 'react';
         export default function App() {
        +  const [count, setCount] = useState<number>(0);
        +  const [name, setName] = useState<string>('');

           return (
             <div>
        -      <button onClick={() => setCount(count + 1)}>
        +      <input value={name} onChange={(e) => setName(e.target.value)} />
        +      <button onClick={() => setCount((prev) => prev + 1)}>
                 Count: {count}
               </button>
             </div>
        ```
        """
    private let userProvidedSingleReplacementDiff = """
        ```diff
        @@ -11,7 +11,7 @@ export default function Home() {
         <div>
        -  <h2>Design Engineer</h2>
        +  <h2>Designer</h2>
         </div>
        ```
        """

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

    func testPatchFenceAliasBuildsDiffRenderBlock() {
        let content = makeContent(
            from: """
            ```patch swift
            @@ -1 +1 @@
            -let title = "Design Engineer"
            +let title = "Designer"
            ```
            """
        )

        XCTAssertEqual(content.diffRenderBlocks.count, 1)
        XCTAssertTrue(content.highlightMaps.isEmpty)

        guard let renderBlock = content.diffRenderBlocks.values.first else {
            return XCTFail("Expected diff render block")
        }

        XCTAssertEqual(renderBlock.language, "swift")
        XCTAssertEqual(renderBlock.rows.first?.kind, .hunkHeader)
    }

    func testBlankFenceAutoDetectsUnifiedDiff() {
        let content = makeContent(
            from: """
            ```
            @@ -1 +1 @@
            -foo
            +bar
            ```
            """
        )

        XCTAssertEqual(content.diffRenderBlocks.count, 1)
        XCTAssertTrue(content.highlightMaps.isEmpty)

        guard let renderBlock = content.diffRenderBlocks.values.first else {
            return XCTFail("Expected auto-detected diff render block")
        }

        XCTAssertNil(renderBlock.language)
        XCTAssertEqual(renderBlock.rows[1].kind, .removed)
        XCTAssertEqual(renderBlock.rows[2].kind, .added)
    }

    func testSingleTokenFenceAutoDetectsUnifiedDiffAndUsesInnerLanguage() {
        let content = makeContent(
            from: """
            ```swift
            @@ -1 +1 @@
            -let title = "Design Engineer"
            +let title = "Designer"
            ```
            """
        )

        XCTAssertEqual(content.diffRenderBlocks.count, 1)
        XCTAssertTrue(content.highlightMaps.isEmpty)

        guard let renderBlock = content.diffRenderBlocks.values.first else {
            return XCTFail("Expected auto-detected diff render block")
        }

        XCTAssertEqual(renderBlock.language, "swift")
        XCTAssertEqual(renderBlock.rows[1].kind, .removed)
        XCTAssertFalse(renderBlock.rows[1].syntaxHighlights.isEmpty)
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

    func testTextFenceDisablesDiffAutoDetection() {
        let content = makeContent(
            from: """
            ```text
            @@ -1 +1 @@
            -foo
            +bar
            ```
            """
        )

        XCTAssertTrue(content.diffRenderBlocks.isEmpty)
        XCTAssertFalse(content.highlightMaps.isEmpty)

        runOnMain {
            let view = MarkdownTextView()
            view.setMarkdownManually(content)

            XCTAssertEqual(view.contextViews.count, 1)
            XCTAssertTrue(view.contextViews.first is CodeView)
            XCTAssertFalse(view.contextViews.first is DiffView)
        }
    }

    func testPlaintextFenceDisablesDiffAutoDetection() {
        let content = makeContent(
            from: """
            ```plaintext
            @@ -1 +1 @@
            -foo
            +bar
            ```
            """
        )

        XCTAssertTrue(content.diffRenderBlocks.isEmpty)
    }

    func testMultiTokenNonDiffFenceDoesNotAutoDetect() {
        let content = makeContent(
            from: """
            ```swift linenums
            @@ -1 +1 @@
            -let title = "Design Engineer"
            +let title = "Designer"
            ```
            """
        )

        XCTAssertTrue(content.diffRenderBlocks.isEmpty)

        runOnMain {
            let view = MarkdownTextView()
            view.setMarkdownManually(content)

            XCTAssertEqual(view.contextViews.count, 1)
            XCTAssertTrue(view.contextViews.first is CodeView)
        }
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

    func testDiffRenderBlockPreservesMultiFileSectionOrdering() {
        let content = makeContent(
            from: """
            ```diff swift
            diff --git a/app/page.tsx b/app/page.tsx
            index 1234567..89abcde 100644
            --- a/app/page.tsx
            +++ b/app/page.tsx
            @@ -1 +1 @@
            -const title = "Before"
            +const title = "After"
            diff --git a/lib/client.ts b/lib/client.ts
            index abcdef0..1234567 100644
            --- a/lib/client.ts
            +++ b/lib/client.ts
            @@ -2 +2 @@
            -export const status = "old"
            +export const status = "new"
            ```
            """
        )

        guard let renderBlock = content.diffRenderBlocks.values.first else {
            return XCTFail("Expected diff render block")
        }

        XCTAssertEqual(renderBlock.rows[0].text, "diff --git a/app/page.tsx b/app/page.tsx")
        XCTAssertEqual(renderBlock.rows[4].kind, .hunkHeader)
        XCTAssertEqual(renderBlock.rows[5].kind, .removed)
        XCTAssertEqual(renderBlock.rows[6].kind, .added)
        XCTAssertEqual(renderBlock.rows[7].kind, .fileHeader)
        XCTAssertEqual(renderBlock.rows[7].text, "diff --git a/lib/client.ts b/lib/client.ts")
        XCTAssertEqual(renderBlock.rows[8].kind, .fileMetadata)
        XCTAssertEqual(renderBlock.rows[9].kind, .fileHeader)
        XCTAssertEqual(renderBlock.rows[10].kind, .fileHeader)
        XCTAssertEqual(renderBlock.rows[11].kind, .hunkHeader)
        XCTAssertEqual(renderBlock.rows[12].kind, .removed)
        XCTAssertEqual(renderBlock.rows[13].kind, .added)
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

    func testInvalidAutoDetectedDiffFallsBackToCodeView() {
        let content = makeContent(
            from: """
            ```swift
            not a unified diff
            ```
            """
        )

        XCTAssertTrue(content.diffRenderBlocks.isEmpty)
        XCTAssertFalse(content.highlightMaps.isEmpty)

        runOnMain {
            let view = MarkdownTextView()
            view.setMarkdownManually(content)

            XCTAssertEqual(view.contextViews.count, 1)
            XCTAssertTrue(view.contextViews.first is CodeView)
            XCTAssertFalse(view.contextViews.first is DiffView)
        }
    }

    func testOrdinaryCodeBlockWithAddedRemovedTextDoesNotAutoDetect() {
        let content = makeContent(
            from: """
            ```swift
            let markers = [
                "+ keep this literal line",
                "- keep this one too",
            ]
            ```
            """
        )

        XCTAssertTrue(content.diffRenderBlocks.isEmpty)
        XCTAssertFalse(content.highlightMaps.isEmpty)
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

    func testValidAutoDetectedDiffRendersDiffView() {
        let content = makeContent(
            from: """
            ```swift
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

    func testRawUnifiedDiffStringNormalizesToPatchFence() {
        let patch = """
        diff --git a/app/page.tsx b/app/page.tsx
        index 1234567..89abcde 100644
        --- a/app/page.tsx
        +++ b/app/page.tsx
        @@ -1 +1 @@
        -const title = "Before"
        +const title = "After"
        """

        let normalized = RawDiffMarkdownNormalizer.normalizeForParsing(patch)

        XCTAssertTrue(normalized.hasPrefix("```patch\n"))
        XCTAssertTrue(normalized.hasSuffix("\n```"))
        XCTAssertTrue(normalized.contains(patch))
    }

    func testRawUnifiedDiffStringRendersDiffView() {
        let patch = """
        diff --git a/app/page.tsx b/app/page.tsx
        index 1234567..89abcde 100644
        --- a/app/page.tsx
        +++ b/app/page.tsx
        @@ -1 +1 @@
        -const title = "Before"
        +const title = "After"
        """

        runOnMain {
            let view = MarkdownTextView()
            view.throttleInterval = nil
            view.setMarkdown(string: patch)

            let deadline = Date().addingTimeInterval(2)
            while view.document.diffRenderBlocks.isEmpty, Date() < deadline {
                _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.001))
            }

            XCTAssertEqual(view.contextViews.count, 1)
            XCTAssertTrue(view.contextViews.first is DiffView)
        }
    }

    func testPreprocessedContentMarkdownInitializerRendersRawUnifiedDiff() {
        let patch = """
        diff --git a/app/page.tsx b/app/page.tsx
        index 1234567..89abcde 100644
        --- a/app/page.tsx
        +++ b/app/page.tsx
        @@ -1 +1 @@
        -const title = "Before"
        +const title = "After"
        """

        let content = MarkdownTextView.PreprocessedContent(
            markdown: patch,
            theme: .default
        )

        XCTAssertEqual(content.diffRenderBlocks.count, 1)
        XCTAssertTrue(content.highlightMaps.isEmpty)
    }

    func testPreprocessedContentBackgroundSafeMarkdownInitializerRendersRawUnifiedDiff() {
        let patch = """
        diff --git a/app/page.tsx b/app/page.tsx
        index 1234567..89abcde 100644
        --- a/app/page.tsx
        +++ b/app/page.tsx
        @@ -1 +1 @@
        -const title = "Before"
        +const title = "After"
        """

        let content = MarkdownTextView.PreprocessedContent(
            markdown: patch,
            theme: .default,
            backgroundSafe: true
        )

        XCTAssertEqual(content.diffRenderBlocks.count, 1)
        XCTAssertTrue(content.highlightMaps.isEmpty)
        XCTAssertTrue(content.rendered.isEmpty)
    }

    func testPreprocessedContentMarkdownInitializerRendersRawMultiFileUnifiedDiff() {
        let patch = """
        diff --git a/app/page.tsx b/app/page.tsx
        index 1234567..89abcde 100644
        --- a/app/page.tsx
        +++ b/app/page.tsx
        @@ -1 +1 @@
        -const title = "Before"
        +const title = "After"
        diff --git a/lib/client.ts b/lib/client.ts
        index abcdef0..1234567 100644
        --- a/lib/client.ts
        +++ b/lib/client.ts
        @@ -2 +2 @@
        -export const status = "old"
        +export const status = "new"
        """

        let content = MarkdownTextView.PreprocessedContent(
            markdown: patch,
            theme: .default
        )

        XCTAssertEqual(content.diffRenderBlocks.count, 1)

        guard let renderBlock = content.diffRenderBlocks.values.first else {
            return XCTFail("Expected diff render block")
        }

        XCTAssertEqual(
            renderBlock.rows.filter { $0.kind == .fileHeader }.map(\.text),
            [
                "diff --git a/app/page.tsx b/app/page.tsx",
                "--- a/app/page.tsx",
                "+++ b/app/page.tsx",
                "diff --git a/lib/client.ts b/lib/client.ts",
                "--- a/lib/client.ts",
                "+++ b/lib/client.ts",
            ]
        )
    }

    func testRawMarkdownNormalizerLeavesOrdinaryMarkdownUntouched() {
        let markdown = """
        # Hello

        This is a normal paragraph.
        """

        XCTAssertEqual(
            RawDiffMarkdownNormalizer.normalizeForParsing(markdown),
            markdown
        )
    }

    func testExplicitDiffFenceRendersUserProvidedMultiFilePatchSample() {
        let markdown = """
        ```diff
        --- a/Sources/MarkdownView/MarkdownTextView.swift
        +++ b/Sources/MarkdownView/MarkdownTextView.swift
        @@ -1,12 +1,18 @@
         import UIKit
        +import MarkdownParser
         
         public class MarkdownTextView: UIView {
        -    private var blocks: [MarkdownBlock] = []
        +    private var blocks: [Block] = []
        +    private let parser = MarkdownParser()
             private let highlighter = TreeSitterHighlighter()
         
             public var theme: MarkdownTheme = .default {
                 didSet { rerender() }
             }
         
        -    public func setMarkdown(_ string: String) {
        -        blocks = MarkdownParser.parse(string)
        +    public func setMarkdown(_ content: PreprocessedContent) {
        +        blocks = content.blocks
        +        rerender()
        +    }
        +
        +    public func setMarkdown(string: String) {
        +        let content = PreprocessedContent(markdown: string, theme: theme)
        +        blocks = content.blocks
                 rerender()
             }
        --- a/Sources/MarkdownView/Rendering/DiffRenderer.swift
        +++ b/Sources/MarkdownView/Rendering/DiffRenderer.swift
        @@ -0,0 +1,45 @@
        +import UIKit
        +
        +/// Renders unified diff blocks with GitHub-style line coloring.
        +struct DiffRenderer {
        +    let theme: MarkdownTheme.Diff
        +
        +    func render(lines: [DiffLine]) -> NSAttributedString {
        +        let result = NSMutableAttributedString()
        +        for line in lines {
        +            let attrs = attributes(for: line.kind)
        +            let text = NSAttributedString(string: line.text + "\\n", attributes: attrs)
        +            result.append(text)
        +        }
        +        return result
        +    }
        +
        +    private func attributes(for kind: DiffLine.Kind) -> [NSAttributedString.Key: Any] {
        +        let font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        +        switch kind {
        +        case .addition:
        +            return [
        +                .font: font,
        +                .foregroundColor: theme.addedTextColor,
        +                .backgroundColor: theme.addedBackgroundColor,
        +            ]
        +        case .deletion:
        +            return [
        +                .font: font,
        +                .foregroundColor: theme.removedTextColor,
        +                .backgroundColor: theme.removedBackgroundColor,
        +            ]
        +        case .context:
        +            return [.font: font, .foregroundColor: theme.contextTextColor]
        +        case .header:
        +            return [
        +                .font: font,
        +                .foregroundColor: theme.headerTextColor,
        +                .backgroundColor: theme.headerBackgroundColor,
        +            ]
        +        }
        +    }
        +}
        ```
        """

        let content = makeContent(from: markdown)
        XCTAssertEqual(content.diffRenderBlocks.count, 1)
        XCTAssertTrue(content.highlightMaps.isEmpty)

        runOnMain {
            let view = MarkdownTextView()
            view.setMarkdownManually(content)

            XCTAssertEqual(view.contextViews.count, 1)
            XCTAssertTrue(view.contextViews.first is DiffView)
            XCTAssertFalse(view.contextViews.first is CodeView)
        }
    }

    func testExplicitDiffFenceAllowsBlankContextLinesWithoutLeadingSpace() {
        let markdown = """
        ```diff
        diff --git a/app/globals.css b/app/globals.css
        index dc2aea1..03a1384 100644
        --- a/app/globals.css
        +++ b/app/globals.css
        @@ -4,8 +4,8 @@
         @custom-variant dark (&:is(.dark *));

         :root {
        -  --background: oklch(1 0 0);
        -  --foreground: oklch(0.145 0 0);
        +  --background: oklch(0.577 0.245 27.325);
        +  --foreground: oklch(1 0 0);
           --card: oklch(1 0 0);
           --card-foreground: oklch(0.145 0 0);
           --popover: oklch(1 0 0);
        ```
        """

        let content = makeContent(from: markdown)
        XCTAssertEqual(content.diffRenderBlocks.count, 1)

        guard let renderBlock = content.diffRenderBlocks.values.first else {
            return XCTFail("Expected diff render block")
        }

        XCTAssertTrue(renderBlock.rows.contains { $0.kind == .removed && $0.text.contains("--background: oklch(1 0 0);") })
        XCTAssertTrue(renderBlock.rows.contains { $0.kind == .added && $0.text.contains("--background: oklch(0.577 0.245 27.325);") })

        runOnMain {
            let view = MarkdownTextView()
            view.setMarkdownManually(content)

            XCTAssertEqual(view.contextViews.count, 1)
            XCTAssertTrue(view.contextViews.first is DiffView)
            XCTAssertFalse(view.contextViews.first is CodeView)
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

    func testUnifiedPresentationCollapsesLongContextRuns() {
        let content = makeContent(
            from: """
            ```diff
            @@ -1,11 +1,11 @@
             line 1
             line 2
             line 3
             line 4
             line 5
             line 6
             line 7
             line 8
             line 9
             line 10
            -line 11
            +line eleven
            ```
            """
        )

        guard let renderBlock = content.diffRenderBlocks.values.first else {
            return XCTFail("Expected diff render block")
        }

        var theme = MarkdownTheme.default
        theme.diff.contextCollapseThreshold = 6
        theme.diff.visibleContextLines = 2

        let rows = DiffPresentation.unifiedRows(from: renderBlock, configuration: theme.diff)

        XCTAssertEqual(rows.count, 8)
        XCTAssertEqual(rows[1].kind, .context)
        XCTAssertEqual(rows[2].kind, .context)
        XCTAssertEqual(rows[3].kind, .collapsedContext)
        XCTAssertEqual(rows[3].text, "... 6 unchanged lines ...")
        XCTAssertEqual(rows[4].kind, .context)
        XCTAssertEqual(rows[5].kind, .context)

        var uncollapsedTheme = MarkdownTheme.default
        uncollapsedTheme.diff.contextCollapseThreshold = 0
        let uncollapsedHeight = DiffViewConfiguration.intrinsicHeight(for: renderBlock, theme: uncollapsedTheme)
        let collapsedHeight = DiffViewConfiguration.intrinsicHeight(for: renderBlock, theme: theme)
        XCTAssertLessThan(collapsedHeight, uncollapsedHeight)
    }

    func testSideBySidePresentationPairsRemovedAndAddedRows() {
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

        let rows = DiffPresentation.sideBySideRows(from: renderBlock, configuration: .init())

        XCTAssertEqual(rows.count, 4)
        XCTAssertEqual(rows[0].kind, .hunkHeader)
        XCTAssertEqual(rows[1].kind, .content)
        XCTAssertEqual(rows[1].oldRole, .removed)
        XCTAssertEqual(rows[1].newRole, .added)
        XCTAssertEqual(rows[1].oldCell?.text, "let greeting = \"hello\"")
        XCTAssertEqual(rows[1].newCell?.text, "let greeting = \"hi there\"")
        XCTAssertEqual(rows[2].oldCell?.text, "let parting = \"bye\"")
        XCTAssertEqual(rows[2].newCell?.text, "let parting = \"goodbye\"")
        XCTAssertEqual(rows[3].oldRole, .empty)
        XCTAssertEqual(rows[3].newRole, .added)
        XCTAssertNil(rows[3].oldCell)
        XCTAssertEqual(rows[3].newCell?.text, "let extra = \"!\"")
    }

    func testSideBySideDiffViewUsesPairedDisplayRowsButPreservesRawSelectionText() {
        let content = makeContent(
            from: """
            ```diff swift
            @@ -1 +1 @@
            -let title = "Design Engineer"
            +let title = "Designer"
            ```
            """
        )

        guard let renderBlock = content.diffRenderBlocks.values.first else {
            return XCTFail("Expected diff render block")
        }

        runOnMain {
            var theme = MarkdownTheme.default
            theme.diff.displayMode = .sideBySide

            let view = DiffView(frame: .zero)
            view.theme = theme
            view.renderBlock = renderBlock

            let displayLines = view.textView.attributedText.string.components(separatedBy: "\n")
            XCTAssertEqual(displayLines.count, 2)
            XCTAssertTrue(displayLines[1].contains("Design Engineer"))
            XCTAssertTrue(displayLines[1].contains("Designer"))

            let selectionText = view.attributedStringRepresentation().string
            XCTAssertTrue(selectionText.contains("-let title = \"Design Engineer\""))
            XCTAssertTrue(selectionText.contains("+let title = \"Designer\""))
        }
    }

    func testDiffViewShowsCopyBarAndCopiesRawPatchText() {
        let content = makeContent(
            from: """
            ```diff swift
            @@ -1 +1 @@
            -let title = "Design Engineer"
            +let title = "Designer"
            ```
            """
        )

        guard let renderBlock = content.diffRenderBlocks.values.first else {
            return XCTFail("Expected diff render block")
        }

        runOnMain {
            let view = DiffView(frame: CGRect(x: 0, y: 0, width: 400, height: 180))
            view.renderBlock = renderBlock

            #if canImport(AppKit)
                XCTAssertEqual(view.titleLabel.stringValue, "diff swift")
                view.copyButton.performClick(nil)
                XCTAssertEqual(NSPasteboard.general.string(forType: .string), view.attributedStringRepresentation().string)
            #elseif canImport(UIKit)
                XCTAssertEqual(view.titleLabel.text, "diff swift")
                view.copyButton.sendActions(for: .touchUpInside)
                XCTAssertEqual(UIPasteboard.general.string, view.attributedStringRepresentation().string)
            #endif
        }
    }

    func testDiffViewCollapsesUnusedOldGutterColumnForNewFile() {
        let newFileContent = makeContent(
            from: """
            ```diff swift
            diff --git a/lib/client.ts b/lib/client.ts
            new file mode 100644
            index 0000000..c48a435
            --- /dev/null
            +++ b/lib/client.ts
            @@ -0,0 +1,2 @@
            +import { createBrowserClient } from "@supabase/ssr"
            +export function createClient() {}
            ```
            """
        )
        let editedFileContent = makeContent(
            from: """
            ```diff swift
            diff --git a/lib/client.ts b/lib/client.ts
            index 1234567..c48a435 100644
            --- a/lib/client.ts
            +++ b/lib/client.ts
            @@ -1,2 +1,2 @@
            -import { oldClient } from "@supabase/ssr"
            +import { createBrowserClient } from "@supabase/ssr"
            -export function oldClient() {}
            +export function createClient() {}
            ```
            """
        )

        guard let newFileRenderBlock = newFileContent.diffRenderBlocks.values.first,
              let editedFileRenderBlock = editedFileContent.diffRenderBlocks.values.first else {
            return XCTFail("Expected diff render blocks")
        }

        runOnMain {
            var theme = MarkdownTheme.default
            theme.showsBlockHeaders = false

            let newFileView = DiffView(frame: CGRect(x: 0, y: 0, width: 320, height: 140))
            newFileView.theme = theme
            newFileView.renderBlock = newFileRenderBlock

            let editedFileView = DiffView(frame: CGRect(x: 0, y: 0, width: 320, height: 140))
            editedFileView.theme = theme
            editedFileView.renderBlock = editedFileRenderBlock

            #if canImport(AppKit)
                newFileView.layoutSubtreeIfNeeded()
                editedFileView.layoutSubtreeIfNeeded()
            #elseif canImport(UIKit)
                newFileView.layoutIfNeeded()
                editedFileView.layoutIfNeeded()
            #endif

            XCTAssertLessThan(newFileView.scrollView.frame.minX, editedFileView.scrollView.frame.minX)
        }
    }

    func testDiffViewDefaultsToHorizontalOnlyScrolling() {
        let content = makeContent(
            from: """
            ```diff swift
            diff --git a/lib/client.ts b/lib/client.ts
            new file mode 100644
            index 0000000..c48a435
            --- /dev/null
            +++ b/lib/client.ts
            @@ -0,0 +1,8 @@
            +line 1
            +line 2
            +line 3
            +line 4
            +line 5
            +line 6
            +line 7
            +line 8
            ```
            """
        )

        guard let renderBlock = content.diffRenderBlocks.values.first else {
            return XCTFail("Expected diff render block")
        }

        runOnMain {
            var theme = MarkdownTheme.default
            theme.showsBlockHeaders = false

            let view = DiffView(frame: CGRect(x: 0, y: 0, width: 280, height: 80))
            view.theme = theme
            view.renderBlock = renderBlock

            #if canImport(AppKit)
                view.layoutSubtreeIfNeeded()
                XCTAssertEqual(view.scrollView.documentView?.frame.height, view.scrollView.bounds.height)
            #elseif canImport(UIKit)
                view.layoutIfNeeded()
                XCTAssertEqual(view.scrollView.contentSize.height, view.scrollView.bounds.height)
            #endif
        }
    }

    func testDiffViewCanOptIntoBothAxesScrolling() {
        let content = makeContent(
            from: """
            ```diff swift
            diff --git a/lib/client.ts b/lib/client.ts
            new file mode 100644
            index 0000000..c48a435
            --- /dev/null
            +++ b/lib/client.ts
            @@ -0,0 +1,8 @@
            +line 1
            +line 2
            +line 3
            +line 4
            +line 5
            +line 6
            +line 7
            +line 8
            ```
            """
        )

        guard let renderBlock = content.diffRenderBlocks.values.first else {
            return XCTFail("Expected diff render block")
        }

        runOnMain {
            var theme = MarkdownTheme.default
            theme.showsBlockHeaders = false
            theme.diff.scrollBehavior = .bothAxes

            let view = DiffView(frame: CGRect(x: 0, y: 0, width: 280, height: 80))
            view.theme = theme
            view.renderBlock = renderBlock

            #if canImport(AppKit)
                view.layoutSubtreeIfNeeded()
                XCTAssertGreaterThan(view.scrollView.documentView?.frame.height ?? 0, view.scrollView.bounds.height)
            #elseif canImport(UIKit)
                view.layoutIfNeeded()
                XCTAssertGreaterThan(view.scrollView.contentSize.height, view.scrollView.bounds.height)
            #endif
        }
    }

    func testDiffThemeDefaultsToBothLineAndInlineHighlights() {
        XCTAssertEqual(MarkdownTheme.default.diff.changeHighlightStyle, .both)
    }

    func testUserProvidedMixedUnifiedDiffPreservesBlankContextAndChangedRows() {
        let content = makeContent(from: userProvidedMixedDiff)

        guard let renderBlock = content.diffRenderBlocks.values.first else {
            return XCTFail("Expected diff render block")
        }

        XCTAssertEqual(renderBlock.rows.first?.kind, .hunkHeader)
        XCTAssertTrue(renderBlock.rows.contains { $0.kind == .added && $0.text.contains("const [count, setCount]") })
        XCTAssertTrue(renderBlock.rows.contains { $0.kind == .added && $0.text.contains("const [name, setName]") })
        XCTAssertTrue(renderBlock.rows.contains { $0.kind == .removed && $0.text.contains("setCount(count + 1)") })
        XCTAssertTrue(renderBlock.rows.contains { $0.kind == .added && $0.text.contains("setCount((prev) => prev + 1)") })
        XCTAssertTrue(renderBlock.rows.contains { $0.kind == .added && $0.text.contains("<input value={name}") })
        XCTAssertTrue(renderBlock.rows.contains { $0.kind == .context && $0.text.isEmpty })
    }

    func testUserProvidedSingleReplacementDiffBuildsExpectedRows() {
        let content = makeContent(from: userProvidedSingleReplacementDiff)

        guard let renderBlock = content.diffRenderBlocks.values.first else {
            return XCTFail("Expected diff render block")
        }

        XCTAssertEqual(renderBlock.rows.count, 5)
        XCTAssertEqual(renderBlock.rows[0].kind, .hunkHeader)
        XCTAssertEqual(renderBlock.rows[1].kind, .context)
        XCTAssertEqual(renderBlock.rows[2].kind, .removed)
        XCTAssertEqual(renderBlock.rows[3].kind, .added)
        XCTAssertEqual(renderBlock.rows[4].kind, .context)
    }

    func testDiffViewLineOnlyStyleSuppressesInlineBackgroundAttributes() {
        let content = makeContent(from: userProvidedSingleReplacementDiff)

        guard let renderBlock = content.diffRenderBlocks.values.first else {
            return XCTFail("Expected diff render block")
        }

        runOnMain {
            var theme = MarkdownTheme.default
            theme.diff.changeHighlightStyle = .lineOnly

            let view = DiffView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
            view.theme = theme
            view.renderBlock = renderBlock

            #if canImport(AppKit)
                view.layoutSubtreeIfNeeded()
            #elseif canImport(UIKit)
                view.layoutIfNeeded()
            #endif

            XCTAssertEqual(self.countBackgroundAttributes(in: view.textView.attributedText), 0)
        }
    }

    func testDiffViewInlineOnlyStyleAppliesInlineBackgroundAttributes() {
        let content = makeContent(from: userProvidedSingleReplacementDiff)

        guard let renderBlock = content.diffRenderBlocks.values.first else {
            return XCTFail("Expected diff render block")
        }

        runOnMain {
            var theme = MarkdownTheme.default
            theme.diff.changeHighlightStyle = .inlineOnly

            let view = DiffView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
            view.theme = theme
            view.renderBlock = renderBlock

            #if canImport(AppKit)
                view.layoutSubtreeIfNeeded()
            #elseif canImport(UIKit)
                view.layoutIfNeeded()
            #endif

            XCTAssertGreaterThan(self.countBackgroundAttributes(in: view.textView.attributedText), 0)
        }
    }

    func testDiffViewBothStyleRetainsInlineBackgroundAttributes() {
        let content = makeContent(from: userProvidedSingleReplacementDiff)

        guard let renderBlock = content.diffRenderBlocks.values.first else {
            return XCTFail("Expected diff render block")
        }

        runOnMain {
            var theme = MarkdownTheme.default
            theme.diff.changeHighlightStyle = .both

            let view = DiffView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
            view.theme = theme
            view.renderBlock = renderBlock

            #if canImport(AppKit)
                view.layoutSubtreeIfNeeded()
            #elseif canImport(UIKit)
                view.layoutIfNeeded()
            #endif

            XCTAssertGreaterThan(self.countBackgroundAttributes(in: view.textView.attributedText), 0)
        }
    }

    func testSelectionTintDerivesSelectionBackgroundAndAppliesToDiffView() {
        let content = makeContent(
            from: """
            ```diff swift
            @@ -1 +1 @@
            -let title = "Design Engineer"
            +let title = "Designer"
            ```
            """
        )

        guard let renderBlock = content.diffRenderBlocks.values.first else {
            return XCTFail("Expected diff render block")
        }

        runOnMain {
            var theme = MarkdownTheme.default
            #if canImport(AppKit)
                let tint = NSColor(
                    calibratedRed: 0.42,
                    green: 0.28,
                    blue: 0.83,
                    alpha: 1
                )
            #elseif canImport(UIKit)
                let tint = UIColor(
                    red: 0.42,
                    green: 0.28,
                    blue: 0.83,
                    alpha: 1
                )
            #endif
            theme.colors.selectionTint = tint

            let view = DiffView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
            view.theme = theme
            view.renderBlock = renderBlock

            #if canImport(AppKit)
                view.layoutSubtreeIfNeeded()
            #elseif canImport(UIKit)
                view.layoutIfNeeded()
            #endif

            self.assertEqualColor(theme.colors.selectionBackground, tint.withAlphaComponent(0.2))
            self.assertEqualColor(view.textView.selectionBackgroundColor, tint.withAlphaComponent(0.2))
        }
    }

    func testDiffViewAppliesThemeBackgroundAndBorder() {
        let content = makeContent(
            from: """
            ```diff swift
            @@ -1 +1 @@
            -let title = "Design Engineer"
            +let title = "Designer"
            ```
            """
        )

        guard let renderBlock = content.diffRenderBlocks.values.first else {
            return XCTFail("Expected diff render block")
        }

        runOnMain {
            var theme = MarkdownTheme.default
            #if canImport(AppKit)
                let background = NSColor(
                    calibratedRed: 0.08,
                    green: 0.09,
                    blue: 0.11,
                    alpha: 1
                )
                let border = NSColor(
                    calibratedRed: 0.62,
                    green: 0.66,
                    blue: 0.73,
                    alpha: 1
                )
            #elseif canImport(UIKit)
                let background = UIColor(
                    red: 0.08,
                    green: 0.09,
                    blue: 0.11,
                    alpha: 1
                )
                let border = UIColor(
                    red: 0.62,
                    green: 0.66,
                    blue: 0.73,
                    alpha: 1
                )
            #endif
            theme.diff.backgroundColor = background
            theme.diff.borderColor = border
            theme.diff.borderWidth = 3

            let view = DiffView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
            view.theme = theme
            view.renderBlock = renderBlock

            #if canImport(AppKit)
                view.layoutSubtreeIfNeeded()
                self.assertEqualColor(NSColor(cgColor: view.layer?.backgroundColor ?? background.cgColor), background)
            #elseif canImport(UIKit)
                view.layoutIfNeeded()
                self.assertEqualColor(view.backgroundColor, background)
            #endif

            XCTAssertEqual(view.layer?.borderWidth, 3)
            XCTAssertEqual(view.layer?.borderColor, border.cgColor)
        }
    }

    func testHeaderBarHeightsFitTheirButtons() {
        XCTAssertGreaterThanOrEqual(
            DiffViewConfiguration.barHeight(theme: .default),
            DiffViewConfiguration.buttonSize.height
        )
        XCTAssertGreaterThanOrEqual(
            CodeViewConfiguration.barHeight(theme: .default),
            CodeViewConfiguration.buttonSize.height
        )
    }

    func testThemeCanHideBlockHeaders() {
        var theme = MarkdownTheme.default
        theme.showsBlockHeaders = false

        XCTAssertEqual(DiffViewConfiguration.barHeight(theme: theme), 0)
        XCTAssertEqual(CodeViewConfiguration.barHeight(theme: theme), 0)

        let content = makeContent(
            from: """
            ```diff swift
            @@ -1 +1 @@
            -let title = "Design Engineer"
            +let title = "Designer"
            ```
            """
        )

        guard let renderBlock = content.diffRenderBlocks.values.first else {
            return XCTFail("Expected diff render block")
        }

        runOnMain {
            let codeView = CodeView(frame: CGRect(x: 0, y: 0, width: 320, height: 140))
            codeView.theme = theme
            codeView.language = "swift"
            codeView.content = "let title = \"Designer\""

            let diffView = DiffView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
            diffView.theme = theme
            diffView.renderBlock = renderBlock

            #if canImport(AppKit)
                codeView.layoutSubtreeIfNeeded()
                diffView.layoutSubtreeIfNeeded()
            #elseif canImport(UIKit)
                codeView.layoutIfNeeded()
                diffView.layoutIfNeeded()
            #endif

            XCTAssertTrue(codeView.barView.isHidden)
            XCTAssertTrue(codeView.copyButton.isHidden)
            XCTAssertTrue(diffView.barView.isHidden)
            XCTAssertTrue(diffView.copyButton.isHidden)
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

    private func countBackgroundAttributes(in attributedString: NSAttributedString) -> Int {
        var count = 0
        attributedString.enumerateAttribute(
            .backgroundColor,
            in: NSRange(location: 0, length: attributedString.length),
            options: []
        ) { value, _, _ in
            if value != nil {
                count += 1
            }
        }
        return count
    }

    #if canImport(UIKit)
        private func assertEqualColor(
            _ lhs: UIColor?,
            _ rhs: UIColor?,
            file: StaticString = #filePath,
            line: UInt = #line
        ) {
            XCTAssertEqual(rgbaComponents(for: lhs), rgbaComponents(for: rhs), file: file, line: line)
        }

        private func rgbaComponents(for color: UIColor?) -> [CGFloat]? {
            guard let color else { return nil }
            let resolved = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            guard resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
            return [red, green, blue, alpha]
        }
    #elseif canImport(AppKit)
        private func assertEqualColor(
            _ lhs: NSColor?,
            _ rhs: NSColor?,
            file: StaticString = #filePath,
            line: UInt = #line
        ) {
            XCTAssertEqual(rgbaComponents(for: lhs), rgbaComponents(for: rhs), file: file, line: line)
        }

        private func rgbaComponents(for color: NSColor?) -> [CGFloat]? {
            guard let color = color?.usingColorSpace(.deviceRGB) else { return nil }
            return [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent]
        }
    #endif
}
