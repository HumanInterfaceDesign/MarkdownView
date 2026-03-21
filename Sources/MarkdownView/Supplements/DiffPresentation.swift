import Foundation

struct DiffPresentation {
    struct UnifiedRow {
        enum Kind: Hashable {
            case fileHeader
            case fileMetadata
            case hunkHeader
            case context
            case removed
            case added
            case annotation
            case collapsedContext
        }

        let kind: Kind
        let oldLineNumber: Int?
        let newLineNumber: Int?
        let text: String
        let syntaxHighlights: CodeHighlighter.HighlightMap
        let emphasizedRanges: [NSRange]
    }

    struct SideBySideRow {
        enum Kind: Hashable {
            case fileHeader
            case fileMetadata
            case hunkHeader
            case annotation
            case collapsedContext
            case content
        }

        enum CellRole: Hashable {
            case empty
            case context
            case removed
            case added
        }

        struct Cell {
            let lineNumber: Int?
            let text: String
            let syntaxHighlights: CodeHighlighter.HighlightMap
            let emphasizedRanges: [NSRange]
        }

        let kind: Kind
        let fullWidthText: String?
        let oldCell: Cell?
        let newCell: Cell?
        let oldRole: CellRole
        let newRole: CellRole
    }

    fileprivate enum SourceRow {
        case row(DiffRenderBlock.Row)
        case collapsedContext(Int)
    }

    static let sideBySideSeparatorText = "    "

    static func unifiedRows(
        from block: DiffRenderBlock,
        configuration: MarkdownTheme.Diff
    ) -> [UnifiedRow] {
        collapseContextRows(in: block.rows, configuration: configuration).map { source in
            switch source {
            case let .row(row):
                return UnifiedRow(
                    kind: unifiedKind(for: row.kind),
                    oldLineNumber: row.oldLineNumber,
                    newLineNumber: row.newLineNumber,
                    text: row.text,
                    syntaxHighlights: row.syntaxHighlights,
                    emphasizedRanges: row.emphasizedRanges
                )
            case let .collapsedContext(hiddenCount):
                return UnifiedRow(
                    kind: .collapsedContext,
                    oldLineNumber: nil,
                    newLineNumber: nil,
                    text: collapsedContextLabel(hiddenCount: hiddenCount),
                    syntaxHighlights: [:],
                    emphasizedRanges: []
                )
            }
        }
    }

    static func sideBySideRows(
        from block: DiffRenderBlock,
        configuration: MarkdownTheme.Diff
    ) -> [SideBySideRow] {
        let rows = collapseContextRows(in: block.rows, configuration: configuration)
        var result: [SideBySideRow] = []
        var index = 0

        while index < rows.count {
            switch rows[index] {
            case let .collapsedContext(hiddenCount):
                result.append(
                    SideBySideRow(
                        kind: .collapsedContext,
                        fullWidthText: collapsedContextLabel(hiddenCount: hiddenCount),
                        oldCell: nil,
                        newCell: nil,
                        oldRole: .empty,
                        newRole: .empty
                    )
                )
                index += 1

            case let .row(row):
                switch row.kind {
                case .fileHeader:
                    result.append(fullWidthRow(kind: .fileHeader, text: row.text))
                    index += 1
                case .fileMetadata:
                    result.append(fullWidthRow(kind: .fileMetadata, text: row.text))
                    index += 1
                case .hunkHeader:
                    result.append(fullWidthRow(kind: .hunkHeader, text: row.text))
                    index += 1
                case .annotation:
                    result.append(fullWidthRow(kind: .annotation, text: row.text))
                    index += 1
                case .context:
                    let cell = makeCell(from: row)
                    result.append(
                        SideBySideRow(
                            kind: .content,
                            fullWidthText: nil,
                            oldCell: cell,
                            newCell: cell,
                            oldRole: .context,
                            newRole: .context
                        )
                    )
                    index += 1
                case .removed:
                    let removedStart = index
                    while index < rows.count, rows[index].isRemovedRow {
                        index += 1
                    }
                    let addedStart = index
                    while index < rows.count, rows[index].isAddedRow {
                        index += 1
                    }

                    let removedRows = rows[removedStart ..< addedStart].compactMap(\.actualRow)
                    let addedRows = rows[addedStart ..< index].compactMap(\.actualRow)
                    let pairCount = min(removedRows.count, addedRows.count)

                    for pairIndex in 0 ..< pairCount {
                        result.append(
                            SideBySideRow(
                                kind: .content,
                                fullWidthText: nil,
                                oldCell: makeCell(from: removedRows[pairIndex]),
                                newCell: makeCell(from: addedRows[pairIndex]),
                                oldRole: .removed,
                                newRole: .added
                            )
                        )
                    }

                    if removedRows.count > pairCount {
                        for removedRow in removedRows[pairCount...] {
                            result.append(
                                SideBySideRow(
                                    kind: .content,
                                    fullWidthText: nil,
                                    oldCell: makeCell(from: removedRow),
                                    newCell: nil,
                                    oldRole: .removed,
                                    newRole: .empty
                                )
                            )
                        }
                    }

                    if addedRows.count > pairCount {
                        for addedRow in addedRows[pairCount...] {
                            result.append(
                                SideBySideRow(
                                    kind: .content,
                                    fullWidthText: nil,
                                    oldCell: nil,
                                    newCell: makeCell(from: addedRow),
                                    oldRole: .empty,
                                    newRole: .added
                                )
                            )
                        }
                    }

                case .added:
                    result.append(
                        SideBySideRow(
                            kind: .content,
                            fullWidthText: nil,
                            oldCell: nil,
                            newCell: makeCell(from: row),
                            oldRole: .empty,
                            newRole: .added
                        )
                    )
                    index += 1
                }
            }
        }

        return result
    }

    static func sideBySideMaxOldUTF16Length(rows: [SideBySideRow]) -> Int {
        rows.reduce(into: 0) { partialResult, row in
            partialResult = max(partialResult, row.oldCell?.text.utf16.count ?? 0)
        }
    }
}

private extension DiffPresentation {
    static func fullWidthRow(kind: SideBySideRow.Kind, text: String) -> SideBySideRow {
        SideBySideRow(
            kind: kind,
            fullWidthText: text,
            oldCell: nil,
            newCell: nil,
            oldRole: .empty,
            newRole: .empty
        )
    }

    static func makeCell(from row: DiffRenderBlock.Row) -> SideBySideRow.Cell {
        .init(
            lineNumber: row.oldLineNumber ?? row.newLineNumber,
            text: row.text,
            syntaxHighlights: row.syntaxHighlights,
            emphasizedRanges: row.emphasizedRanges
        )
    }

    static func unifiedKind(for kind: DiffRenderBlock.RowKind) -> UnifiedRow.Kind {
        switch kind {
        case .fileHeader:
            .fileHeader
        case .fileMetadata:
            .fileMetadata
        case .hunkHeader:
            .hunkHeader
        case .context:
            .context
        case .removed:
            .removed
        case .added:
            .added
        case .annotation:
            .annotation
        }
    }

    private static func collapseContextRows(
        in rows: [DiffRenderBlock.Row],
        configuration: MarkdownTheme.Diff
    ) -> [SourceRow] {
        let threshold = configuration.contextCollapseThreshold
        let visibleContextLines = max(configuration.visibleContextLines, 0)

        guard threshold > 0 else {
            return rows.map(SourceRow.row)
        }

        var result: [SourceRow] = []
        var index = 0

        while index < rows.count {
            guard rows[index].kind == .context else {
                result.append(.row(rows[index]))
                index += 1
                continue
            }

            let start = index
            while index < rows.count, rows[index].kind == .context {
                index += 1
            }

            let run = Array(rows[start ..< index])
            let minimumCollapseCount = max(threshold, visibleContextLines * 2 + 1)
            guard run.count >= minimumCollapseCount else {
                result.append(contentsOf: run.map(SourceRow.row))
                continue
            }

            let visiblePrefixCount = min(visibleContextLines, run.count)
            let visibleSuffixCount = min(visibleContextLines, max(run.count - visiblePrefixCount, 0))
            let hiddenCount = run.count - visiblePrefixCount - visibleSuffixCount

            guard hiddenCount > 0 else {
                result.append(contentsOf: run.map(SourceRow.row))
                continue
            }

            result.append(contentsOf: run.prefix(visiblePrefixCount).map(SourceRow.row))
            result.append(.collapsedContext(hiddenCount))
            result.append(contentsOf: run.suffix(visibleSuffixCount).map(SourceRow.row))
        }

        return result
    }

    static func collapsedContextLabel(hiddenCount: Int) -> String {
        if hiddenCount == 1 {
            return "... 1 unchanged line ..."
        }
        return "... \(hiddenCount) unchanged lines ..."
    }
}

fileprivate extension DiffPresentation.SourceRow {
    var actualRow: DiffRenderBlock.Row? {
        switch self {
        case let .row(row):
            row
        case .collapsedContext:
            nil
        }
    }

    var isRemovedRow: Bool {
        switch self {
        case let .row(row):
            row.kind == .removed
        case .collapsedContext:
            false
        }
    }

    var isAddedRow: Bool {
        switch self {
        case let .row(row):
            row.kind == .added
        case .collapsedContext:
            false
        }
    }
}
