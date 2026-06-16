# MarkdownView

A high-performance markdown rendering library for iOS, macOS, and visionOS.

<video src="https://github.com/user-attachments/assets/0f222f61-9c03-4341-a501-f41272e7561a" controls playsinline></video>

## Features

- Full GFM (GitHub Flavored Markdown) support: headings, lists, tables, blockquotes, task lists, and more
- Native syntax highlighting powered by [tree-sitter](https://tree-sitter.github.io/) — no JavaScript runtime overhead
- 19 languages: Swift, C, C++, C#, Python, JavaScript, TypeScript, TSX, Go, Rust, Java, Kotlin, Ruby, Bash, SQL, YAML, JSON, HTML, CSS
- GitHub-style unified diff rendering for fenced `diff` / `patch` blocks, fenced auto-detection, and raw unified patch strings passed to `setMarkdown(string:)` or `PreprocessedContent(markdown:theme:)`
- LaTeX math rendering
- Inline image rendering with async loading and caching
- Comprehensive theming with fonts, colors, and spacing
- Two selection modes: text selection (default) with long-press and custom menu items, or opt-in line selection with tap/drag and callback
- VoiceOver accessibility for text, code blocks, tables, and math content
- UIKit and AppKit support via a single API

## Performance

Syntax highlighting uses tree-sitter's native C parser instead of JavaScript-based solutions like highlight.js. This eliminates the JavaScriptCore runtime entirely and produces color ranges directly from semantic parse trees. Language parsers are initialized lazily — only the languages actually used are loaded.

| Benchmark | Time |
|---|---|
| Plain-text stream append (steady-state) | <0.1 ms |
| Highlight 50 lines | ~2 ms |
| Highlight 500 lines | ~21 ms |
| Parse 500 blocks | ~5 ms |
| Parse + preprocess 300 blocks | ~3 ms |

The plain-text streaming fast path applies to safe token appends that do not introduce new markdown syntax, allowing the view to skip reparsing and update only the trailing paragraph.

## Requirements

- iOS 16+ / macOS 13+ / visionOS 1+
- Swift 5.9+

## Installation

In Xcode, add this repository as a Swift Package dependency:

```text
https://github.com/HumanInterfaceDesign/MarkdownView
```

Choose the `main` branch to use the latest version.

Or add it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/HumanInterfaceDesign/MarkdownView", branch: "main"),
]
```

### All languages (default)

Use the `MarkdownViewAll` product to include all 19 bundled language parsers:

```swift
.target(name: "YourApp", dependencies: [
    .product(name: "MarkdownViewAll", package: "MarkdownView"),
])
```

Then register the languages at app launch:

```swift
import MarkdownView
import MarkdownLanguages

// In your App.init or AppDelegate:
MarkdownLanguages.registerAll()
```

### Core only (reduced binary size)

Use the `MarkdownView` product for just the core renderer without any language parsers (~40 MB smaller):

```swift
.target(name: "YourApp", dependencies: [
    .product(name: "MarkdownView", package: "MarkdownView"),
])
```

Then register only the languages you need by adding their tree-sitter packages
to your own dependencies and calling `CodeHighlighter.registerLanguage`:

```swift
import MarkdownView
import SwiftTreeSitter
import TreeSitterPython

// Register individual languages at app launch:
CodeHighlighter.registerLanguage(aliases: ["python", "py", "python3"]) {
    try CodeHighlighter.makeConfig(tree_sitter_python(), name: "Python")
}
```

## Usage

<img width="575" height="283" alt="Xcode 2026-03-02 09 24 19" src="https://github.com/user-attachments/assets/3c6b9fc2-f8c4-4afa-94a1-7fc47501b6b2" />

### UIKit

<details>
<summary>Show UIKit example</summary>

```swift
import UIKit
import MarkdownParser
import MarkdownView

class ViewController: UIViewController {

    private let markdownView = MarkdownTextView()

    override func viewDidLoad() {
        super.viewDidLoad()

        view.addSubview(markdownView)
        markdownView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            markdownView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            markdownView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            markdownView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
        ])

        // Parse and render markdown
        let parser = MarkdownParser()
        let result = parser.parse("""
        # Hello, Markdown!

        This is **bold**, *italic*, and `inline code`.

        ```python
        def greet(name):
            return f"Hello, {name}!"
        ```

        - Item one
        - Item two
        - Item three
        """)

        let content = MarkdownTextView.PreprocessedContent(
            parserResult: result,
            theme: .default
        )
        markdownView.setMarkdown(content)

        // Handle link taps
        markdownView.linkHandler = { payload, range, point in
            switch payload {
            case .url(let url):
                UIApplication.shared.open(url)
            case .string(let string):
                print("Tapped link: \(string)")
            }
        }

        // Handle image taps
        markdownView.imageTapHandler = { source, point in
            print("Image tapped: \(source)")
        }
    }
}
```

</details>

### SwiftUI

Wrap `MarkdownTextView` in `UIViewRepresentable` when you want to use it from SwiftUI on iOS or visionOS.

<details>
<summary>Show SwiftUI example</summary>

```swift
import SwiftUI
import MarkdownParser
import MarkdownView

struct MarkdownTextViewRepresentable: UIViewRepresentable {
    let markdown: String
    var theme: MarkdownTheme = .default

    func makeUIView(context: Context) -> MarkdownTextView {
        let view = MarkdownTextView()
        view.backgroundColor = .clear
        view.isOpaque = false
        return view
    }

    func updateUIView(_ uiView: MarkdownTextView, context: Context) {
        uiView.theme = theme
        let parser = MarkdownParser()
        let result = parser.parse(markdown)
        let content = MarkdownTextView.PreprocessedContent(
            parserResult: result,
            theme: theme
        )
        uiView.setMarkdown(content)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: MarkdownTextView,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width, width > 0 else {
            return uiView.intrinsicContentSize
        }
        let measuredSize = uiView.boundingSize(for: width)
        return CGSize(width: width, height: measuredSize.height)
    }
}

struct ContentView: View {
    private let markdown = """
    # Hello, SwiftUI!

    This `MarkdownTextView` is wrapped with `UIViewRepresentable`.

    ```swift
    struct GreetingView: View {
        var body: some View {
            Text("Hello from MarkdownView")
        }
    }
    ```
    """

    var body: some View {
        ScrollView {
            MarkdownTextViewRepresentable(markdown: markdown)
                .padding(.horizontal)
        }
    }
}
```

</details>

### Theming

<details>
<summary>Show theming example</summary>

```swift
var theme = MarkdownTheme()

// Customize fonts
theme.fonts.body = .preferredFont(forTextStyle: .body)
theme.fonts.code = .monospacedSystemFont(ofSize: 14, weight: .regular)

// Customize colors
theme.colors.body = .label
theme.colors.code = .secondaryLabel
theme.colors.codeBackground = .secondarySystemBackground
theme.colors.selectionTint = .systemBlue
// Optional override if you want a custom translucent fill instead of
// selectionTint.withAlphaComponent(0.2)
theme.colors.selectionBackground = .systemBlue.withAlphaComponent(0.16)
// Optional override for line selection highlight in code/diff views
theme.colors.lineSelectionBackground = .systemBlue.withAlphaComponent(0.15)

// Diff-specific styling
theme.diff.backgroundColor = .black
theme.diff.borderColor = .darkGray
theme.diff.borderWidth = 1
theme.diff.changeHighlightStyle = .both
theme.diff.addedLineBackground = UIColor(red: 0.08, green: 0.25, blue: 0.16, alpha: 1)
theme.diff.removedLineBackground = UIColor(red: 0.28, green: 0.10, blue: 0.12, alpha: 1)
theme.diff.addedHighlightBackground = UIColor(red: 0.12, green: 0.34, blue: 0.21, alpha: 1)
theme.diff.removedHighlightBackground = UIColor(red: 0.38, green: 0.14, blue: 0.16, alpha: 1)
theme.diff.scrollBehavior = .horizontalOnly

// Hide the code/diff header rows that contain the copy button
theme.showsBlockHeaders = false

// Scale all fonts
theme.scaleFont(by: .large)

markdownView.theme = theme
```

</details>

Selection tint is theme-driven. By default, `selectionBackground` is derived from `selectionTint` with a 20% alpha. Set `selectionBackground` explicitly when you want a different selection fill without changing the tint.

### Selection Modes

Code blocks and diff views support two mutually exclusive selection modes:

#### Text Selection (Default)

Text selection is enabled by default. Long-press to select text, then use the standard system menu (Copy, Select All, Share) or add custom actions with `LTXCustomMenuItem`. No additional setup is needed.

<details>
<summary>Show custom menu items example</summary>

```swift
markdownView.textView.customMenuItems = [
    LTXCustomMenuItem(title: "Explain", image: UIImage(systemName: "lightbulb")) { context in
        print("Explain: \(context.text) (lines \(context.startLine)-\(context.endLine))")
    },
    LTXCustomMenuItem(title: "Apply", image: UIImage(systemName: "checkmark.circle")) { context in
        print("Apply: \(context.text)")
    },
]
```

</details>

Custom items appear after the built-in Copy, Select All, and Share actions. On iOS they integrate with `UIMenuController`, on Mac Catalyst with `UIContextMenuInteraction`, and on macOS with `NSMenu`.

#### Line Selection (Opt-in)

Setting `lineSelectionHandler` switches code blocks and diff views from text selection to line selection. Tap to select a single line, or long-press-and-drag to select a range. The selected lines are highlighted and a callback provides the 1-based line range, the text contents, and the language.

Set `lineSelectionEndedHandler` to be notified only when the gesture settles — a tap completing, or a long-press/drag releasing. It fires exactly once per interaction with the final range. Use `lineSelectionHandler` for live visual feedback that should track the drag, and `lineSelectionEndedHandler` for actions that should only happen after the user lifts their finger (e.g. animating in a contextual button).

<details>
<summary>Show line selection example</summary>

```swift
markdownView.lineSelectionHandler = { info in
    guard let info else {
        print("Selection cleared")
        return
    }
    print("Selected lines \(info.lineRange) in \(info.language ?? "unknown"):")
    for line in info.contents {
        print("  \(line)")
    }
}

// Customize the selection highlight color
var theme = MarkdownTheme()
theme.colors.lineSelectionBackground = .systemBlue.withAlphaComponent(0.2)
markdownView.theme = theme
```

</details>

Selection is exclusive: selecting lines in one code or diff block automatically clears any selection in other blocks. When `lineSelectionHandler` is `nil` (the default), text selection is active and the line selection gestures are not installed.

### Unified Diffs

Use `diff` or `patch` to force the dedicated diff renderer. You can also paste a valid unified diff into a plain fenced code block, or use a single language token like `swift`, and MarkdownView will auto-detect it as a diff.

````md
```diff swift
@@ -11,7 +11,7 @@ export default function Home() {
 <div>
-  <h2>Design Engineer</h2>
+  <h2>Designer</h2>
 </div>
```
````

````md
```patch
diff --git a/app.ts b/app.ts
index 1234567..89abcde 100644
--- a/app.ts
+++ b/app.ts
@@ -1 +1 @@
-const title = "Design Engineer"
+const title = "Designer"
```
````

````md
```swift
@@ -11,7 +11,7 @@ export default function Home() {
 <div>
-  <h2>Design Engineer</h2>
+  <h2>Designer</h2>
 </div>
```
````

This renders as a dedicated diff view with hunk headers, dual line numbers, added/removed row styling, and inline change emphasis for paired edits.
Standard unified-diff file preamble lines like `diff --git`, `index`, `---`, and `+++` are also supported and render as styled header/meta rows above the hunks.
If the entire markdown string is itself a valid unified diff, MarkdownView will normalize it internally and render the dedicated diff view even without fences.
This is useful when an API returns only the patch text.
Use `text` or `plaintext` if you want to show patch text literally without auto-detecting the diff view.

Diff presentation is fully themeable through `MarkdownTheme.Diff`, including the gutter, file header, added/removed row colors, inline highlight colors, separators, border, and the overall diff background. Use `theme.diff.changeHighlightStyle` to choose between `.lineOnly`, `.inlineOnly`, and `.both`. Diff blocks default to horizontal-only scrolling so they embed cleanly inside outer scroll views; set `theme.diff.scrollBehavior = .bothAxes` if you want the diff view itself to scroll vertically too.

The gutter layout is also configurable. `theme.diff.lineNumberStyle` defaults to `.dual` (separate old/new columns, like GitHub on desktop); set it to `.single` for a unified column that shows the old number on removed lines and the new number everywhere else (like GitHub on mobile). `theme.diff.showsChangeMarkers` defaults to `true`; set it to `false` to hide the `+`/`−` column entirely, letting the row background color indicate the change. Combining `.single` with `showsChangeMarkers = false` yields a minimal gutter with just one line-number column. These settings apply to unified display mode; side-by-side mode always uses both line-number columns.

```swift
theme.diff.lineNumberStyle = .single
theme.diff.showsChangeMarkers = false
```

```swift
let patch = apiResponse.patch
markdownView.setMarkdown(string: patch)
```

If you preprocess content manually, use the markdown-based initializer so raw diff normalization still runs:

```swift
let patch = apiResponse.patch
let content = MarkdownTextView.PreprocessedContent(
    markdown: patch,
    theme: .default
)
markdownView.setMarkdown(content)
```

Pass the patch string itself, not the surrounding JSON object. Avoid calling `parser.parse(patch)` directly for raw unified diffs, because that bypasses the normalizer that wraps the patch for diff rendering.

## Architecture

The library is split into two modules:

- **MarkdownParser** — Converts markdown strings into an AST using [swift-cmark](https://github.com/swiftlang/swift-cmark) (GFM extensions included). No UI dependencies.
- **MarkdownView** — Renders the AST into native views with syntax highlighting, math rendering, and interactive links.

## License

MIT
