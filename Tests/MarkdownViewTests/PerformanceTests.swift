import XCTest
@testable import MarkdownParser
@testable import MarkdownView

final class PerformanceTests: XCTestCase {

    // MARK: - Test Data Generators

    /// Generates a markdown document with the given number of varied blocks.
    private func generateLargeMarkdown(blockCount: Int) -> String {
        var lines: [String] = []
        for i in 0 ..< blockCount {
            switch i % 6 {
            case 0:
                lines.append("## Heading \(i)\n")
            case 1:
                lines.append("Paragraph \(i) with **bold** and *italic* and `inline code` and [a link](https://example.com).\n")
            case 2:
                lines.append("```python\nfunc f\(i)() -> Int { return \(i) }\n```\n")
            case 3:
                lines.append("- Item A\(i)\n- Item B\(i)\n- Item C\(i)\n")
            case 4:
                lines.append("> Blockquote \(i)\n")
            case 5:
                lines.append("| Col1 | Col2 |\n|------|------|\n| \(i) | \(i + 1) |\n")
            default:
                break
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Generates a large Python code block.
    private func generateLargeCode(lineCount: Int) -> String {
        var lines: [String] = []
        lines.append("import os")
        lines.append("")
        for i in 0 ..< lineCount {
            switch i % 5 {
            case 0:
                lines.append("def compute_\(i)(x: int) -> int:")
            case 1:
                lines.append("    result = x * \(i) + 42")
            case 2:
                lines.append("    if result <= 0:")
            case 3:
                lines.append("        return -1")
            case 4:
                lines.append("    return result")
            default:
                break
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Generates markdown with deeply nested blockquotes containing code blocks.
    private func generateNestedDocument(depth: Int, codeBlocksPerLevel: Int) -> String {
        var md = ""
        for d in 0 ..< depth {
            let prefix = String(repeating: "> ", count: d + 1)
            md += "\(prefix)Level \(d + 1) text\n\(prefix)\n"
        }
        // Add code blocks at various levels
        for i in 0 ..< codeBlocksPerLevel {
            md += "\n```python\nlet nested\(i) = \(i)\n```\n"
        }
        return md
    }

    // MARK: - Parsing Performance

    func testParsingPerformance_100Blocks() {
        let md = generateLargeMarkdown(blockCount: 100)
        let parser = MarkdownParser()

        measure {
            _ = parser.parse(md)
        }
    }

    func testParsingPerformance_500Blocks() {
        let md = generateLargeMarkdown(blockCount: 500)
        let parser = MarkdownParser()

        measure {
            _ = parser.parse(md)
        }
    }

    func testParsingPerformance_1000Blocks() {
        let md = generateLargeMarkdown(blockCount: 1000)
        let parser = MarkdownParser()

        measure {
            _ = parser.parse(md)
        }
    }

    // MARK: - Code Highlighting Performance

    func testHighlightPerformance_SmallCode() {
        let code = generateLargeCode(lineCount: 50)
        let highlighter = CodeHighlighter.current

        measure {
            // Use unique key each iteration to bypass cache
            let key = Int.random(in: Int.min ... Int.max)
            _ = highlighter.highlight(key: key, content: code, language: "python")
        }
    }

    func testHighlightPerformance_LargeCode() {
        let code = generateLargeCode(lineCount: 500)
        let highlighter = CodeHighlighter.current

        measure {
            let key = Int.random(in: Int.min ... Int.max)
            _ = highlighter.highlight(key: key, content: code, language: "python")
        }
    }

    func testHighlightCachePerformance() {
        let code = generateLargeCode(lineCount: 200)
        let highlighter = CodeHighlighter.current
        let key = highlighter.key(for: code, language: "python")

        // Prime the cache
        _ = highlighter.highlight(key: key, content: code, language: "python")

        measure {
            // All iterations should be cache hits
            _ = highlighter.highlight(key: key, content: code, language: "python")
        }
    }

    // MARK: - PreprocessedContent Performance (exercises BFS traversal)

    func testPreprocessedContentPerformance_ManyCodeBlocks() {
        var md = ""
        for i in 0 ..< 50 {
            md += "Paragraph \(i).\n\n```python\nlet v\(i) = \(i)\n```\n\n"
        }
        let parser = MarkdownParser()
        let result = parser.parse(md)

        measure {
            _ = MarkdownTextView.PreprocessedContent(
                parserResult: result,
                theme: .default
            )
        }
    }

    func testPreprocessedContentPerformance_ComplexDocument() {
        let md = generateLargeMarkdown(blockCount: 200)
        let parser = MarkdownParser()
        let result = parser.parse(md)

        measure {
            _ = MarkdownTextView.PreprocessedContent(
                parserResult: result,
                theme: .default
            )
        }
    }

    func testPreprocessedContentPerformance_NestedStructure() {
        let md = generateNestedDocument(depth: 5, codeBlocksPerLevel: 20)
        let parser = MarkdownParser()
        let result = parser.parse(md)

        measure {
            _ = MarkdownTextView.PreprocessedContent(
                parserResult: result,
                theme: .default
            )
        }
    }

    // MARK: - Key Generation Performance

    func testKeyGenerationPerformance() {
        let highlighter = CodeHighlighter.current
        let codes = (0 ..< 100).map { "func f\($0)() -> Int { return \($0) }" }

        measure {
            for code in codes {
                _ = highlighter.key(for: code, language: "python")
            }
        }
    }

    // MARK: - AST Diff Performance

    func testASTDiffPerformance_AppendOnlyStreaming() {
        let oldBlocks = (0 ..< 300).map {
            MarkdownBlockNode.paragraph(content: [.text("Paragraph \($0)")])
        }
        let newBlocks = oldBlocks + (300 ..< 360).map {
            MarkdownBlockNode.paragraph(content: [.text("Paragraph \($0)")])
        }

        measure {
            _ = ASTDiff.diff(old: oldBlocks, new: newBlocks)
        }
    }

    // MARK: - End-to-End Performance

    func testEndToEnd_ParseAndPreprocess() {
        let md = generateLargeMarkdown(blockCount: 300)
        let parser = MarkdownParser()

        measure {
            let result = parser.parse(md)
            _ = MarkdownTextView.PreprocessedContent(
                parserResult: result,
                theme: .default
            )
        }
    }
}
