# MarkdownView

A high-performance markdown rendering library for iOS, macOS, and visionOS.

<video src="https://github.com/user-attachments/assets/0f222f61-9c03-4341-a501-f41272e7561a" controls playsinline></video>

## Features

- Full GFM (GitHub Flavored Markdown) support: headings, lists, tables, blockquotes, task lists, and more
- Native syntax highlighting powered by [tree-sitter](https://tree-sitter.github.io/) — no JavaScript runtime overhead
- 19 languages: Swift, C, C++, C#, Python, JavaScript, TypeScript, TSX, Go, Rust, Java, Kotlin, Ruby, Bash, SQL, YAML, JSON, HTML, CSS
- GitHub-style unified diff rendering for fenced `diff` blocks, with optional inner-language syntax highlighting
- LaTeX math rendering
- Inline image rendering with async loading and caching
- Comprehensive theming with fonts, colors, and spacing
- Text selection with long-press, double-tap, and triple-tap gestures
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

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/user/MarkdownView", from: "1.0.0"),
]
```

Then add `"MarkdownView"` as a dependency of your target.

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

// Scale all fonts
theme.scaleFont(by: .large)

markdownView.theme = theme
```

</details>

### Unified Diffs

Use a fenced code block whose first info-string token is `diff`. Add an optional second token to syntax-highlight the changed lines with a specific language.

````md
```diff swift
@@ -11,7 +11,7 @@ export default function Home() {
 <div>
-  <h2>Design Engineer</h2>
+  <h2>Designer</h2>
 </div>
```
````

This renders as a dedicated diff view with hunk headers, dual line numbers, added/removed row styling, and inline change emphasis for paired edits.
Standard unified-diff file preamble lines like `diff --git`, `index`, `---`, and `+++` are also supported and render as styled header/meta rows above the hunks.

## Architecture

The library is split into two modules:

- **MarkdownParser** — Converts markdown strings into an AST using [swift-cmark](https://github.com/swiftlang/swift-cmark) (GFM extensions included). No UI dependencies.
- **MarkdownView** — Renders the AST into native views with syntax highlighting, math rendering, and interactive links.

## License

MIT

## Inspiration

Inspired by [Lakr233/MarkdownView](https://github.com/Lakr233/MarkdownView)
