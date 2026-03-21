import Foundation

struct DiffFenceInfo: Hashable {
    let language: String?

    static func parse(_ fenceInfo: String?) -> DiffFenceInfo? {
        guard let fenceInfo else { return nil }
        let components = fenceInfo
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        guard let first = components.first?.lowercased(), first == "diff" else {
            return nil
        }

        let language = components.dropFirst().first.flatMap {
            let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return .init(language: language)
    }
}

struct DiffRenderBlock {
    enum RowKind: Hashable {
        case fileHeader
        case fileMetadata
        case hunkHeader
        case context
        case removed
        case added
        case annotation
    }

    struct Row {
        let kind: RowKind
        let oldLineNumber: Int?
        let newLineNumber: Int?
        let text: String
        let syntaxHighlights: CodeHighlighter.HighlightMap
        let emphasizedRanges: [NSRange]
    }

    let language: String?
    let rows: [Row]
}

extension DiffRenderBlock {
    static func key(for content: String, language: String?) -> Int {
        let normalizedContent = content.deletingSuffix(of: .newlines)
        var hasher = Hasher()
        hasher.combine(normalizedContent)
        hasher.combine(language?.lowercased() ?? "")
        return hasher.finalize()
    }
}

enum UnifiedDiffParser {
    static func renderBlock(content: String, fenceInfo: DiffFenceInfo) -> DiffRenderBlock? {
        let normalizedContent = content.deletingSuffix(of: .newlines)
        guard let parsed = parse(content: normalizedContent, language: fenceInfo.language) else {
            return nil
        }
        return DiffRenderBlock(
            language: parsed.language,
            rows: buildRenderedRows(from: parsed)
        )
    }
}

private extension UnifiedDiffParser {
    struct ParsedBlock {
        let language: String?
        let preambleRows: [ParsedRow]
        let hunks: [ParsedHunk]
    }

    struct ParsedHunk {
        let headerText: String
        let oldStart: Int
        let oldCount: Int
        let newStart: Int
        let newCount: Int
        let rows: [ParsedRow]
    }

    struct ParsedRow {
        let kind: DiffRenderBlock.RowKind
        let oldLineNumber: Int?
        let newLineNumber: Int?
        let text: String
    }

    static let hunkHeaderRegex: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"^@@ -([0-9]+)(?:,([0-9]+))? \+([0-9]+)(?:,([0-9]+))? @@(?: ?(.*))?$"#
        )
    }()

    static func parse(content: String, language: String?) -> ParsedBlock? {
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var preambleRows: [ParsedRow] = []
        var hunks: [ParsedHunk] = []
        var index = 0

        func preambleRowKind(for line: String) -> DiffRenderBlock.RowKind? {
            if line.isEmpty { return nil }
            if line.hasPrefix("diff --git ")
                || line.hasPrefix("--- ")
                || line.hasPrefix("+++ ")
            {
                return .fileHeader
            }
            if line.hasPrefix("index ")
                || line.hasPrefix("new file mode ")
                || line.hasPrefix("deleted file mode ")
                || line.hasPrefix("rename from ")
                || line.hasPrefix("rename to ")
                || line.hasPrefix("old mode ")
                || line.hasPrefix("new mode ")
                || line.hasPrefix("similarity index ")
                || line.hasPrefix("dissimilarity index ")
            {
                return .fileMetadata
            }
            return nil
        }

        while index < lines.count {
            let line = lines[index]
            if line.isEmpty {
                index += 1
                continue
            }
            if let rowKind = preambleRowKind(for: line) {
                preambleRows.append(
                    .init(
                        kind: rowKind,
                        oldLineNumber: nil,
                        newLineNumber: nil,
                        text: line
                    )
                )
                index += 1
                continue
            }
            break
        }

        while index < lines.count {
            while index < lines.count, lines[index].isEmpty {
                index += 1
            }
            guard index < lines.count else { break }

            let line = lines[index]
            guard let header = parseHunkHeader(line) else {
                return nil
            }
            index += 1

            var rows: [ParsedRow] = []
            var oldLine = header.oldStart
            var newLine = header.newStart

            while index < lines.count {
                let currentLine = lines[index]

                if currentLine.isEmpty {
                    return nil
                }
                if parseHunkHeader(currentLine) != nil {
                    break
                }
                if preambleRowKind(for: currentLine) != nil {
                    return nil
                }

                if currentLine == #"\ No newline at end of file"# {
                    rows.append(
                        .init(
                            kind: .annotation,
                            oldLineNumber: nil,
                            newLineNumber: nil,
                            text: currentLine
                        )
                    )
                    index += 1
                    continue
                }

                guard let prefix = currentLine.first else {
                    return nil
                }
                let text = String(currentLine.dropFirst())

                switch prefix {
                case " ":
                    rows.append(
                        .init(
                            kind: .context,
                            oldLineNumber: oldLine,
                            newLineNumber: newLine,
                            text: text
                        )
                    )
                    oldLine += 1
                    newLine += 1
                case "-":
                    rows.append(
                        .init(
                            kind: .removed,
                            oldLineNumber: oldLine,
                            newLineNumber: nil,
                            text: text
                        )
                    )
                    oldLine += 1
                case "+":
                    rows.append(
                        .init(
                            kind: .added,
                            oldLineNumber: nil,
                            newLineNumber: newLine,
                            text: text
                        )
                    )
                    newLine += 1
                default:
                    return nil
                }
                index += 1
            }

            hunks.append(
                .init(
                    headerText: header.text,
                    oldStart: header.oldStart,
                    oldCount: header.oldCount,
                    newStart: header.newStart,
                    newCount: header.newCount,
                    rows: rows
                )
            )
        }

        guard !hunks.isEmpty else { return nil }
        return .init(language: language, preambleRows: preambleRows, hunks: hunks)
    }

    static func buildRenderedRows(from block: ParsedBlock) -> [DiffRenderBlock.Row] {
        var rows: [DiffRenderBlock.Row] = block.preambleRows.map {
            .init(
                kind: $0.kind,
                oldLineNumber: nil,
                newLineNumber: nil,
                text: $0.text,
                syntaxHighlights: [:],
                emphasizedRanges: []
            )
        }

        for hunk in block.hunks {
            rows.append(
                .init(
                    kind: .hunkHeader,
                    oldLineNumber: nil,
                    newLineNumber: nil,
                    text: hunk.headerText,
                    syntaxHighlights: [:],
                    emphasizedRanges: []
                )
            )

            var renderedRows = hunk.rows.map { row in
                DiffRenderBlock.Row(
                    kind: row.kind,
                    oldLineNumber: row.oldLineNumber,
                    newLineNumber: row.newLineNumber,
                    text: row.text,
                    syntaxHighlights: highlightMap(for: row.text, language: block.language),
                    emphasizedRanges: []
                )
            }

            applyInlineDiffRanges(to: &renderedRows)
            rows.append(contentsOf: renderedRows)
        }

        return rows
    }

    static func highlightMap(for text: String, language: String?) -> CodeHighlighter.HighlightMap {
        guard let language, !language.isEmpty else { return [:] }
        guard !text.isEmpty else { return [:] }
        let key = CodeHighlighter.current.key(for: text, language: language)
        return CodeHighlighter.current.highlight(key: key, content: text, language: language)
    }

    static func applyInlineDiffRanges(to rows: inout [DiffRenderBlock.Row]) {
        var index = 0

        while index < rows.count {
            guard rows[index].kind == .removed else {
                index += 1
                continue
            }

            let removedStart = index
            while index < rows.count, rows[index].kind == .removed {
                index += 1
            }
            let addedStart = index
            while index < rows.count, rows[index].kind == .added {
                index += 1
            }

            let removedRange = removedStart ..< addedStart
            let addedRange = addedStart ..< index
            let pairCount = min(removedRange.count, addedRange.count)

            guard pairCount > 0 else { continue }

            let removedRows = Array(rows[removedRange])
            let addedRows = Array(rows[addedRange])

            for pairIndex in 0 ..< pairCount {
                let emphasis = inlineEmphasisRanges(
                    removed: removedRows[pairIndex].text,
                    added: addedRows[pairIndex].text
                )

                if !emphasis.removed.isEmpty {
                    let targetIndex = removedStart + pairIndex
                    rows[targetIndex] = .init(
                        kind: rows[targetIndex].kind,
                        oldLineNumber: rows[targetIndex].oldLineNumber,
                        newLineNumber: rows[targetIndex].newLineNumber,
                        text: rows[targetIndex].text,
                        syntaxHighlights: rows[targetIndex].syntaxHighlights,
                        emphasizedRanges: emphasis.removed
                    )
                }

                if !emphasis.added.isEmpty {
                    let targetIndex = addedStart + pairIndex
                    rows[targetIndex] = .init(
                        kind: rows[targetIndex].kind,
                        oldLineNumber: rows[targetIndex].oldLineNumber,
                        newLineNumber: rows[targetIndex].newLineNumber,
                        text: rows[targetIndex].text,
                        syntaxHighlights: rows[targetIndex].syntaxHighlights,
                        emphasizedRanges: emphasis.added
                    )
                }
            }
        }
    }

    static func inlineEmphasisRanges(removed: String, added: String) -> (removed: [NSRange], added: [NSRange]) {
        let removedTokens = tokenize(removed)
        let addedTokens = tokenize(added)

        guard !removedTokens.isEmpty, !addedTokens.isEmpty else {
            return (
                removed: removed.isEmpty ? [] : [NSRange(location: 0, length: removed.utf16.count)],
                added: added.isEmpty ? [] : [NSRange(location: 0, length: added.utf16.count)]
            )
        }

        let matched = lcsMatchedIndices(
            lhs: removedTokens.map(\.text),
            rhs: addedTokens.map(\.text)
        )
        let removedMatched = Set(matched.lhs)
        let addedMatched = Set(matched.rhs)

        let removedRanges = removedTokens.enumerated()
            .filter { !removedMatched.contains($0.offset) }
            .map(\.element.range)
        let addedRanges = addedTokens.enumerated()
            .filter { !addedMatched.contains($0.offset) }
            .map(\.element.range)

        return (coalesce(removedRanges), coalesce(addedRanges))
    }

    struct HunkHeader {
        let text: String
        let oldStart: Int
        let oldCount: Int
        let newStart: Int
        let newCount: Int
    }

    static func parseHunkHeader(_ line: String) -> HunkHeader? {
        let range = NSRange(location: 0, length: line.utf16.count)
        guard let match = hunkHeaderRegex.firstMatch(in: line, range: range) else {
            return nil
        }

        func value(at index: Int) -> Int? {
            let nsRange = match.range(at: index)
            guard nsRange.location != NSNotFound,
                  let range = Range(nsRange, in: line) else {
                return nil
            }
            return Int(line[range])
        }

        guard let oldStart = value(at: 1),
              let newStart = value(at: 3) else {
            return nil
        }

        return .init(
            text: line,
            oldStart: oldStart,
            oldCount: value(at: 2) ?? 1,
            newStart: newStart,
            newCount: value(at: 4) ?? 1
        )
    }

    struct DiffToken: Hashable {
        let text: String
        let range: NSRange
    }

    static func tokenize(_ text: String) -> [DiffToken] {
        guard !text.isEmpty else { return [] }

        let nsText = text as NSString
        let scalars = Array(text.unicodeScalars)
        var tokens: [DiffToken] = []
        var tokenStart = 0

        enum TokenKind {
            case identifier
            case whitespace
            case punctuation
        }

        func kind(for scalar: UnicodeScalar) -> TokenKind {
            if CharacterSet.whitespaces.contains(scalar) {
                return .whitespace
            }
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "_" {
                return .identifier
            }
            return .punctuation
        }

        var currentKind = kind(for: scalars[0])

        for index in 1 ..< scalars.count {
            let nextKind = kind(for: scalars[index])
            guard nextKind != currentKind else { continue }
            let range = NSRange(location: tokenStart, length: index - tokenStart)
            tokens.append(.init(text: nsText.substring(with: range), range: range))
            tokenStart = index
            currentKind = nextKind
        }

        let range = NSRange(location: tokenStart, length: scalars.count - tokenStart)
        tokens.append(.init(text: nsText.substring(with: range), range: range))
        return tokens
    }

    static func lcsMatchedIndices(lhs: [String], rhs: [String]) -> (lhs: [Int], rhs: [Int]) {
        guard !lhs.isEmpty, !rhs.isEmpty else { return ([], []) }

        var table = Array(
            repeating: Array(repeating: 0, count: rhs.count + 1),
            count: lhs.count + 1
        )

        for lhsIndex in 0 ..< lhs.count {
            for rhsIndex in 0 ..< rhs.count {
                if lhs[lhsIndex] == rhs[rhsIndex] {
                    table[lhsIndex + 1][rhsIndex + 1] = table[lhsIndex][rhsIndex] + 1
                } else {
                    table[lhsIndex + 1][rhsIndex + 1] = max(
                        table[lhsIndex][rhsIndex + 1],
                        table[lhsIndex + 1][rhsIndex]
                    )
                }
            }
        }

        var lhsMatches: [Int] = []
        var rhsMatches: [Int] = []
        var lhsIndex = lhs.count
        var rhsIndex = rhs.count

        while lhsIndex > 0, rhsIndex > 0 {
            if lhs[lhsIndex - 1] == rhs[rhsIndex - 1] {
                lhsMatches.append(lhsIndex - 1)
                rhsMatches.append(rhsIndex - 1)
                lhsIndex -= 1
                rhsIndex -= 1
            } else if table[lhsIndex - 1][rhsIndex] >= table[lhsIndex][rhsIndex - 1] {
                lhsIndex -= 1
            } else {
                rhsIndex -= 1
            }
        }

        return (lhsMatches.reversed(), rhsMatches.reversed())
    }

    static func coalesce(_ ranges: [NSRange]) -> [NSRange] {
        guard !ranges.isEmpty else { return [] }

        var result: [NSRange] = []
        for range in ranges.sorted(by: { $0.location < $1.location }) {
            guard let last = result.last else {
                result.append(range)
                continue
            }

            let lastUpperBound = last.location + last.length
            if range.location <= lastUpperBound {
                result[result.count - 1] = NSRange(
                    location: last.location,
                    length: max(lastUpperBound, range.location + range.length) - last.location
                )
            } else {
                result.append(range)
            }
        }
        return result
    }
}
