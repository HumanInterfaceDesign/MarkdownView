# MarkdownView

A high-performance markdown rendering library for iOS, macOS, and visionOS.

## Features

- Full GFM (GitHub Flavored Markdown) support: headings, lists, tables, blockquotes, task lists, and more
- Native syntax highlighting powered by [tree-sitter](https://tree-sitter.github.io/) — no JavaScript runtime overhead
- 12 languages: Python, JavaScript, TypeScript, TSX, Go, Rust, C++, Java, Ruby, Bash, JSON, HTML, CSS
- LaTeX math rendering
- Comprehensive theming with fonts, colors, and spacing
- UIKit and AppKit support via a single API

## Performance

Syntax highlighting uses tree-sitter's native C parser instead of JavaScript-based solutions like highlight.js. This eliminates the JavaScriptCore runtime entirely and produces color ranges directly from semantic parse trees.

| Benchmark | Time |
|---|---|
| Highlight 50 lines | ~3 ms |
| Highlight 500 lines | ~21 ms |
| Parse 500 blocks | ~3 ms |
| Parse + preprocess 300 blocks | ~12 ms |

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

### UIKit

```swift
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
    }
}
```

### Theming

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

## Architecture

The library is split into two modules:

- **MarkdownParser** — Converts markdown strings into an AST using [swift-cmark](https://github.com/swiftlang/swift-cmark) (GFM extensions included). No UI dependencies.
- **MarkdownView** — Renders the AST into native views with syntax highlighting, math rendering, and interactive links.

## License

MIT

## Inspiration

Inspired by [Lakr233/MarkdownView](https://github.com/Lakr233/MarkdownView)
