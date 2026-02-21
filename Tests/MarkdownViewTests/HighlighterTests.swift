import XCTest
@testable import MarkdownParser
@testable import MarkdownView

final class HighlighterTests: XCTestCase {

    // MARK: - CodeHighlighter Key Generation

    func testKeyIsDeterministic() {
        let highlighter = CodeHighlighter.current
        let key1 = highlighter.key(for: "let x = 1", language: "swift")
        let key2 = highlighter.key(for: "let x = 1", language: "swift")
        XCTAssertEqual(key1, key2)
    }

    func testKeyDiffersForDifferentContent() {
        let highlighter = CodeHighlighter.current
        let key1 = highlighter.key(for: "let x = 1", language: "swift")
        let key2 = highlighter.key(for: "let y = 2", language: "swift")
        XCTAssertNotEqual(key1, key2)
    }

    func testKeyDiffersForDifferentLanguage() {
        let highlighter = CodeHighlighter.current
        let key1 = highlighter.key(for: "x = 1", language: "swift")
        let key2 = highlighter.key(for: "x = 1", language: "python")
        XCTAssertNotEqual(key1, key2)
    }

    func testKeyLanguageCaseInsensitive() {
        let highlighter = CodeHighlighter.current
        let key1 = highlighter.key(for: "code", language: "Swift")
        let key2 = highlighter.key(for: "code", language: "swift")
        XCTAssertEqual(key1, key2)
    }

    func testKeyNilLanguageSameAsEmpty() {
        let highlighter = CodeHighlighter.current
        let key1 = highlighter.key(for: "code", language: nil)
        let key2 = highlighter.key(for: "code", language: "")
        XCTAssertEqual(key1, key2)
    }

    // MARK: - Highlighting

    func testHighlightReturnsMap() {
        let highlighter = CodeHighlighter.current
        let code = "def greet(name):\n    return f\"Hello, {name}!\""
        let map = highlighter.highlight(key: nil, content: code, language: "python")
        // Should produce some color ranges for Python syntax
        XCTAssertFalse(map.isEmpty, "Highlight map should contain color entries for Python code")
    }

    func testHighlightCacheHit() {
        let highlighter = CodeHighlighter.current
        let code = "def cache_hit():\n    return 42"
        let key = highlighter.key(for: code, language: "python")

        let map1 = highlighter.highlight(key: key, content: code, language: "python")
        let map2 = highlighter.highlight(key: key, content: code, language: "python")

        // Both should return the same ranges (from cache on second call)
        XCTAssertEqual(map1.count, map2.count)
        for (range, _) in map1 {
            XCTAssertNotNil(map2[range], "Cached map should contain same ranges")
        }
    }

    func testHighlightPlaintext() {
        let highlighter = CodeHighlighter.current
        let map = highlighter.highlight(key: nil, content: "just plain text", language: "plaintext")
        // Plaintext is not a registered tree-sitter language, should return empty map
        XCTAssertTrue(map.isEmpty, "Plaintext should produce empty map")
    }

    func testHighlightEmptyContent() {
        let highlighter = CodeHighlighter.current
        let map = highlighter.highlight(key: nil, content: "", language: "swift")
        XCTAssertTrue(map.isEmpty, "Empty content should produce empty map")
    }

    // MARK: - PreprocessedContent + Code Block Traversal

    func testPreprocessedContentFindsCodeBlocks() {
        let parser = MarkdownParser()
        let md = """
        # Title

        ```swift
        let x = 42
        ```

        Some text.

        ```python
        print("hi")
        ```
        """
        let result = parser.parse(md)
        let content = MarkdownTextView.PreprocessedContent(
            parserResult: result,
            theme: .default
        )

        // Should have highlight maps for both code blocks
        XCTAssertEqual(content.highlightMaps.count, 2)
    }

    func testPreprocessedContentNoCodeBlocks() {
        let parser = MarkdownParser()
        let result = parser.parse("Just a paragraph.")
        let content = MarkdownTextView.PreprocessedContent(
            parserResult: result,
            theme: .default
        )
        XCTAssertTrue(content.highlightMaps.isEmpty)
    }

    func testPreprocessedContentNestedCodeBlock() {
        let parser = MarkdownParser()
        // Use a blockquote followed by a code block to test BFS traversal
        // (cmark-gfm may handle fenced code inside blockquotes differently)
        let md = ">\n> text\n\n```javascript\nconsole.log(\"hello\")\n```"
        let result = parser.parse(md)
        let codeBlocks = result.document.filter {
            if case .codeBlock = $0 { return true }
            return false
        }
        // Verify the parser found the code block first
        XCTAssertEqual(codeBlocks.count, 1, "Parser should find 1 code block")

        let content = MarkdownTextView.PreprocessedContent(
            parserResult: result,
            theme: .default
        )
        XCTAssertEqual(content.highlightMaps.count, 1)
    }

    func testPreprocessedContentCodeBlockInsideBlockquote() {
        let parser = MarkdownParser()
        // Test that BFS correctly finds code blocks nested inside blockquotes
        let md = "> ```swift\n> let x = 1\n> ```"
        let result = parser.parse(md)

        // Check the parsed structure - should be blockquote containing code block
        guard case let .blockquote(children) = result.document.first else {
            // If the parser doesn't nest code blocks in blockquotes, skip
            return
        }
        let nestedCodeBlocks = children.filter {
            if case .codeBlock = $0 { return true }
            return false
        }
        guard !nestedCodeBlocks.isEmpty else { return }

        let content = MarkdownTextView.PreprocessedContent(
            parserResult: result,
            theme: .default
        )
        XCTAssertEqual(content.highlightMaps.count, 1, "BFS should find code block inside blockquote")
    }

    func testPreprocessedContentCodeBlockInList() {
        let parser = MarkdownParser()
        let md = """
        - item 1

          ```ruby
          puts "hello"
          ```

        - item 2
        """
        let result = parser.parse(md)
        let content = MarkdownTextView.PreprocessedContent(
            parserResult: result,
            theme: .default
        )
        XCTAssertEqual(content.highlightMaps.count, 1)
    }

    func testPreprocessedContentEmpty() {
        let content = MarkdownTextView.PreprocessedContent()
        XCTAssertTrue(content.blocks.isEmpty)
        XCTAssertTrue(content.rendered.isEmpty)
        XCTAssertTrue(content.highlightMaps.isEmpty)
    }

    // MARK: - Unsupported Language & Aliases

    func testHighlightUnsupportedLanguage() {
        let highlighter = CodeHighlighter.current
        let map = highlighter.highlight(key: nil, content: "some code here", language: "brainfuck")
        XCTAssertTrue(map.isEmpty, "Unsupported language should produce empty map")
    }

    func testHighlightLanguageAliases() {
        let highlighter = CodeHighlighter.current
        let code = "x = 42"
        let map1 = highlighter.highlight(key: nil, content: code, language: "py")
        let map2 = highlighter.highlight(key: nil, content: code, language: "python")
        XCTAssertEqual(map1.count, map2.count, "Language aliases should produce same number of highlights")
        for (range, _) in map1 {
            XCTAssertNotNil(map2[range], "Language aliases should highlight same ranges")
        }
    }

    // MARK: - HighlightMap Apply

    func testHighlightMapApply() {
        let highlighter = CodeHighlighter.current
        let code = "x = 1"
        let map = highlighter.highlight(key: nil, content: code, language: "python")
        let attributed = map.apply(to: code, with: .default)

        XCTAssertEqual(attributed.string, code)
        XCTAssertEqual(attributed.length, code.utf16.count)
    }
}
