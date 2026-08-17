import Foundation

/// One hunk of a file's patch. Rows exclude the `@@` header row, which is
/// synthesized from the current line ranges so it stays correct after context
/// expansion grows the hunk.
nonisolated struct DiffFileHunk: Identifiable {
    let id: Int
    var oldStart: Int
    var newStart: Int
    var rows: [DiffRenderBlock.Row]

    var oldCount: Int {
        rows.reduce(into: 0) { partialResult, row in
            switch row.kind {
            case .context, .removed:
                partialResult += 1
            case .added, .annotation, .fileHeader, .fileMetadata, .hunkHeader:
                break
            }
        }
    }

    var newCount: Int {
        rows.reduce(into: 0) { partialResult, row in
            switch row.kind {
            case .context, .added:
                partialResult += 1
            case .removed, .annotation, .fileHeader, .fileMetadata, .hunkHeader:
                break
            }
        }
    }

    /// Last line of the hunk in the old file, or `oldStart - 1` when the hunk
    /// covers no old lines (a pure insertion).
    var oldEnd: Int {
        oldStart + oldCount - 1
    }

    var headerText: String {
        "@@ -\(oldStart),\(oldCount) +\(newStart),\(newCount) @@"
    }

    var headerRow: DiffRenderBlock.Row {
        .init(
            kind: .hunkHeader,
            oldLineNumber: nil,
            newLineNumber: nil,
            text: headerText,
            syntaxHighlights: [:],
            emphasizedRanges: []
        )
    }
}

/// A single file inside a unified patch. A sectioned diff renders one section
/// per file, with the file's hunks (and the expanders between them) as items.
nonisolated struct DiffFilePatch: Identifiable {
    let id: Int
    let displayPath: String
    let oldPath: String?
    let newPath: String?
    let language: String?
    /// `diff --git` / `---` / `+++` / `index` rows, kept so the raw patch text
    /// can be reproduced for copy.
    let headerRows: [DiffRenderBlock.Row]
    var hunks: [DiffFileHunk]

    var additions: Int {
        hunks.reduce(into: 0) { $0 += $1.rows.filter { $0.kind == .added }.count }
    }

    var deletions: Int {
        hunks.reduce(into: 0) { $0 += $1.rows.filter { $0.kind == .removed }.count }
    }

    /// The render block for a single hunk, including its `@@` header row.
    func renderBlock(forHunkAt index: Int) -> DiffRenderBlock {
        guard hunks.indices.contains(index) else {
            return .init(language: language, rows: [])
        }
        let hunk = hunks[index]
        return .init(language: language, rows: [hunk.headerRow] + hunk.rows)
    }
}

/// A tappable "show more lines" row sitting in the gap between two hunks (or
/// above the first / below the last hunk) of a file.
nonisolated struct DiffExpander: Hashable {
    enum Direction: Hashable {
        /// Reveal the lines directly above the hunk that follows the gap.
        case up
        /// Reveal the lines directly below the hunk that precedes the gap.
        case down
        /// The gap is bounded on both sides and larger than one chunk, so both
        /// arrows are offered.
        case both
    }

    let fileID: Int
    /// ID of the hunk preceding the gap, expanded downwards. An ID (not an
    /// index): expansions resolve against the live document, so a merge that
    /// completes while another expansion is in flight cannot redirect it to a
    /// different hunk.
    let hunkAboveID: Int?
    /// ID of the hunk following the gap, expanded upwards.
    let hunkBelowID: Int?
    /// Hidden old-file lines, 1-based and inclusive.
    let gapLowerBound: Int
    let gapUpperBound: Int
    let direction: Direction
    /// The whole gap fits inside a single expansion chunk, so one tap reveals
    /// all of it and the row collapses to a single control.
    let coversEntireGap: Bool

    var gap: ClosedRange<Int> {
        gapLowerBound ... gapUpperBound
    }

    var hiddenLineCount: Int {
        gapUpperBound - gapLowerBound + 1
    }

    /// Old-file line range fetched when the expander is tapped in `direction`.
    func requestedRange(for direction: Direction, chunkSize: Int) -> ClosedRange<Int> {
        guard !coversEntireGap, chunkSize > 0 else { return gap }
        switch direction {
        case .up:
            return max(gapLowerBound, gapUpperBound - chunkSize + 1) ... gapUpperBound
        case .down:
            return gapLowerBound ... min(gapUpperBound, gapLowerBound + chunkSize - 1)
        case .both:
            return gap
        }
    }
}

/// An item rendered inside a file's section.
nonisolated enum DiffFileItem: Hashable {
    case expander(DiffExpander)
    case hunk(fileID: Int, hunkID: Int)
}

/// The parsed patch backing a sectioned diff: files, their hunks, and the
/// expanders derived from the gaps between hunks.
nonisolated struct DiffPatchDocument {
    /// Number of lines revealed by a single tap on an expander.
    static let defaultExpansionChunkSize = 20

    var files: [DiffFilePatch]
    let language: String?

    init(files: [DiffFilePatch], language: String?) {
        self.files = files
        self.language = language
    }

    init?(patch: String, language: String? = nil) {
        let fenceInfo = DiffFenceInfo(language: language)
        guard let block = UnifiedDiffParser.renderBlock(content: patch, fenceInfo: fenceInfo) else {
            return nil
        }
        self.init(block: block)
    }

    init(block: DiffRenderBlock) {
        files = DiffPatchDocument.splitFiles(in: block)
        language = block.language
    }

    func file(withID id: Int) -> DiffFilePatch? {
        files.first { $0.id == id }
    }

    func fileIndex(withID id: Int) -> Int? {
        files.firstIndex { $0.id == id }
    }

    /// Section items for a file: hunks interleaved with the expanders that
    /// stand in for the lines the patch left out.
    ///
    /// - Parameter totalOldLineCount: total line count of the pre-image, when
    ///   known. Without it the trailing expander is omitted, since there is no
    ///   way to tell whether the last hunk reaches the end of the file.
    func items(
        forFileWithID fileID: Int,
        chunkSize: Int = defaultExpansionChunkSize,
        totalOldLineCount: Int? = nil
    ) -> [DiffFileItem] {
        guard let file = file(withID: fileID) else { return [] }
        var items: [DiffFileItem] = []

        for (index, hunk) in file.hunks.enumerated() {
            if index == 0 {
                if hunk.oldStart > 1 {
                    items.append(
                        .expander(
                            makeExpander(
                                fileID: fileID,
                                hunkAboveID: nil,
                                hunkBelowID: hunk.id,
                                gap: 1 ... (hunk.oldStart - 1),
                                chunkSize: chunkSize
                            )
                        )
                    )
                }
            } else {
                let previous = file.hunks[index - 1]
                // Old-file lines are 1-based; a pure-insertion hunk
                // (`@@ -0,0 …`) has `oldEnd == -1`, and an unclamped bound
                // would fabricate a "line 0" gap.
                let gapLowerBound = max(previous.oldEnd + 1, 1)
                let gapUpperBound = hunk.oldStart - 1
                if gapLowerBound <= gapUpperBound {
                    items.append(
                        .expander(
                            makeExpander(
                                fileID: fileID,
                                hunkAboveID: previous.id,
                                hunkBelowID: hunk.id,
                                gap: gapLowerBound ... gapUpperBound,
                                chunkSize: chunkSize
                            )
                        )
                    )
                }
            }

            items.append(.hunk(fileID: fileID, hunkID: hunk.id))
        }

        if let last = file.hunks.last, let totalOldLineCount {
            // Same 1-based clamp as above: a trailing pure-insertion hunk has
            // `oldEnd == -1`, and an empty pre-image (`totalOldLineCount == 0`)
            // must produce no expander rather than a phantom "line 0" gap.
            let gapLowerBound = max(last.oldEnd + 1, 1)
            if gapLowerBound <= totalOldLineCount {
                items.append(
                    .expander(
                        makeExpander(
                            fileID: fileID,
                            hunkAboveID: last.id,
                            hunkBelowID: nil,
                            gap: gapLowerBound ... totalOldLineCount,
                            chunkSize: chunkSize
                        )
                    )
                )
            }
        }

        return items
    }

    /// Splices fetched pre-image lines into the file, growing the hunk the
    /// expander points at and merging hunks that meet as a result.
    ///
    /// - Parameters:
    ///   - lines: the pre-image lines for `range`, in order.
    ///   - range: old-file line numbers the lines belong to.
    mutating func insertContext(
        lines: [String],
        forOldLineRange range: ClosedRange<Int>,
        fileID: Int,
        direction: DiffExpander.Direction,
        expander: DiffExpander
    ) {
        guard !lines.isEmpty, let fileIndex = fileIndex(withID: fileID) else { return }

        // `.both` only reaches here when one tap covers the gap; attach it to
        // the hunk above so the merge below folds the two hunks together.
        let hunkID: Int? = switch direction {
        case .up: expander.hunkBelowID
        case .down: expander.hunkAboveID
        case .both: expander.hunkAboveID ?? expander.hunkBelowID
        }
        // Resolved by ID at insert time; a hunk swallowed by a merge since the
        // expander was built makes this a no-op rather than a mis-splice.
        guard let hunkID,
              let hunkIndex = files[fileIndex].hunks.firstIndex(where: { $0.id == hunkID })
        else { return }

        let attachesAbove = direction == .up
            || (direction == .both && expander.hunkAboveID == nil)
        if attachesAbove {
            prependContext(lines: lines, range: range, fileIndex: fileIndex, hunkIndex: hunkIndex)
        } else {
            appendContext(lines: lines, range: range, fileIndex: fileIndex, hunkIndex: hunkIndex)
        }
        mergeAdjacentHunks(fileIndex: fileIndex)
    }
}

private nonisolated extension DiffPatchDocument {
    static func isHunkBodyKind(_ kind: DiffRenderBlock.RowKind) -> Bool {
        switch kind {
        case .context, .removed, .added, .annotation:
            true
        case .fileHeader, .fileMetadata, .hunkHeader:
            false
        }
    }

    func makeExpander(
        fileID: Int,
        hunkAboveID: Int?,
        hunkBelowID: Int?,
        gap: ClosedRange<Int>,
        chunkSize: Int
    ) -> DiffExpander {
        let coversEntireGap = chunkSize <= 0 || gap.count <= chunkSize
        let direction: DiffExpander.Direction = if coversEntireGap {
            hunkAboveID == nil ? .up : (hunkBelowID == nil ? .down : .both)
        } else if hunkAboveID == nil {
            .up
        } else if hunkBelowID == nil {
            .down
        } else {
            .both
        }
        return .init(
            fileID: fileID,
            hunkAboveID: hunkAboveID,
            hunkBelowID: hunkBelowID,
            gapLowerBound: gap.lowerBound,
            gapUpperBound: gap.upperBound,
            direction: direction,
            coversEntireGap: coversEntireGap
        )
    }

    func contextRows(
        lines: [String],
        oldStart: Int,
        newStart: Int,
        language: String?
    ) -> [DiffRenderBlock.Row] {
        lines.enumerated().map { offset, line in
            .init(
                kind: .context,
                oldLineNumber: oldStart + offset,
                newLineNumber: newStart + offset,
                text: line,
                syntaxHighlights: UnifiedDiffParser.contextHighlights(for: line, language: language),
                emphasizedRanges: []
            )
        }
    }

    mutating func prependContext(
        lines: [String],
        range: ClosedRange<Int>,
        fileIndex: Int,
        hunkIndex: Int
    ) {
        let language = files[fileIndex].language
        var hunk = files[fileIndex].hunks[hunkIndex]
        // Line i of the response is old line `range.lowerBound + i`, so an
        // over-long response's tail falls past `range` — cut it before the
        // hunk-edge alignment below, or the tail would be misnumbered as the
        // lines nearest the hunk.
        let ranged = lines.prefix(range.count)
        // Align the fetched lines against the hunk's top edge and trim anything
        // it already shows, so a stale response cannot duplicate lines.
        let usable = Array(ranged.suffix(max(hunk.oldStart - range.lowerBound, 0)))
        guard !usable.isEmpty else { return }

        let oldStart = hunk.oldStart - usable.count
        let newStart = hunk.newStart - usable.count
        hunk.rows = contextRows(
            lines: usable,
            oldStart: oldStart,
            newStart: newStart,
            language: language
        ) + hunk.rows
        hunk.oldStart = oldStart
        hunk.newStart = newStart
        files[fileIndex].hunks[hunkIndex] = hunk
    }

    mutating func appendContext(
        lines: [String],
        range: ClosedRange<Int>,
        fileIndex: Int,
        hunkIndex: Int
    ) {
        let language = files[fileIndex].language
        var hunk = files[fileIndex].hunks[hunkIndex]
        let oldStart = hunk.oldEnd + 1
        let skipCount = max(oldStart - range.lowerBound, 0)
        // Line i of the response is old line `range.lowerBound + i`; cutting at
        // `range.count` keeps an over-long response from spilling past the gap
        // into the next hunk's lines.
        let ranged = lines.prefix(range.count)
        guard skipCount < ranged.count else { return }
        let usable = Array(ranged.dropFirst(skipCount))

        hunk.rows += contextRows(
            lines: usable,
            oldStart: oldStart,
            newStart: hunk.newStart + hunk.newCount,
            language: language
        )
        files[fileIndex].hunks[hunkIndex] = hunk
    }

    /// Folds hunks whose ranges now touch or overlap into one, dropping the
    /// duplicate rows in the overlap.
    mutating func mergeAdjacentHunks(fileIndex: Int) {
        var merged: [DiffFileHunk] = []
        for hunk in files[fileIndex].hunks {
            guard var previous = merged.last, previous.oldEnd + 1 >= hunk.oldStart else {
                merged.append(hunk)
                continue
            }

            // Overlap only arises from expansion context appended to the
            // previous hunk, so its trailing context copies are the rows to
            // drop — the following hunk's rows are authoritative diff rows and
            // may mark those same lines as removed.
            while let last = previous.rows.last,
                  last.kind == .context,
                  let oldNumber = last.oldLineNumber,
                  oldNumber >= hunk.oldStart
            {
                previous.rows.removeLast()
            }

            // Any overlap left means both hunks claim real diff rows for the
            // same lines (malformed input); trim the duplicate head rows as a
            // last resort so lines are never double-counted.
            var rows = hunk.rows
            var oldLine = hunk.oldStart
            while let first = rows.first, oldLine <= previous.oldEnd {
                switch first.kind {
                case .context, .removed:
                    oldLine += 1
                    rows.removeFirst()
                case .added, .annotation, .fileHeader, .fileMetadata, .hunkHeader:
                    // Added rows carry no old-file line, so they can never be a
                    // duplicate of the preceding hunk's trailing context.
                    oldLine = previous.oldEnd + 1
                }
            }

            previous.rows += rows
            merged[merged.count - 1] = previous
        }
        files[fileIndex].hunks = merged
    }

    static func splitFiles(in block: DiffRenderBlock) -> [DiffFilePatch] {
        var files: [DiffFilePatch] = []
        var headerRows: [DiffRenderBlock.Row] = []
        var hunks: [DiffFileHunk] = []
        var hunkID = 0
        var index = 0

        func flush() {
            guard !headerRows.isEmpty || !hunks.isEmpty else { return }
            let paths = filePaths(in: headerRows)
            files.append(
                .init(
                    id: files.count,
                    displayPath: paths.display ?? "Patch \(files.count + 1)",
                    oldPath: paths.old,
                    newPath: paths.new,
                    language: block.language,
                    headerRows: headerRows,
                    hunks: hunks
                )
            )
            headerRows = []
            hunks = []
        }

        while index < block.rows.count {
            let row = block.rows[index]
            switch row.kind {
            case .fileHeader, .fileMetadata:
                // A file header after a hunk starts the next file.
                if !hunks.isEmpty { flush() }
                headerRows.append(row)
                index += 1
            case .hunkHeader:
                let header = UnifiedDiffParser.hunkRange(fromHeader: row.text)
                var rows: [DiffRenderBlock.Row] = []
                index += 1
                while index < block.rows.count, isHunkBodyKind(block.rows[index].kind) {
                    rows.append(block.rows[index])
                    index += 1
                }
                hunks.append(
                    .init(
                        id: hunkID,
                        oldStart: header?.oldStart ?? (rows.first?.oldLineNumber ?? 1),
                        newStart: header?.newStart ?? (rows.first?.newLineNumber ?? 1),
                        rows: rows
                    )
                )
                hunkID += 1
            case .context, .removed, .added, .annotation:
                // Rows outside a hunk are not produced by the parser; skip
                // defensively rather than dropping the file.
                index += 1
            }
        }

        flush()
        return files
    }

    static func filePaths(
        in headerRows: [DiffRenderBlock.Row]
    ) -> (old: String?, new: String?, display: String?) {
        var old: String?
        var new: String?

        for row in headerRows where row.kind == .fileHeader {
            if row.text.hasPrefix("--- ") {
                old = normalizedPath(String(row.text.dropFirst(4)))
            } else if row.text.hasPrefix("+++ ") {
                new = normalizedPath(String(row.text.dropFirst(4)))
            } else if row.text.hasPrefix("diff --git ") {
                let components = row.text.dropFirst("diff --git ".count)
                    .split(separator: " ", maxSplits: 1)
                    .map(String.init)
                if components.count == 2 {
                    old = old ?? normalizedPath(components[0])
                    new = new ?? normalizedPath(components[1])
                }
            }
        }

        let display: String? = if let new, new != "/dev/null" {
            new
        } else if let old, old != "/dev/null" {
            old
        } else {
            nil
        }
        return (old, new, display)
    }

    static func normalizedPath(_ raw: String) -> String? {
        var path = raw.trimmingCharacters(in: .whitespaces)
        // Drop a trailing tab-separated timestamp, as emitted by `diff -u`.
        if let tabIndex = path.firstIndex(of: "\t") {
            path = String(path[path.startIndex ..< tabIndex])
        }
        guard !path.isEmpty else { return nil }
        if path == "/dev/null" { return path }
        if path.hasPrefix("a/") || path.hasPrefix("b/") {
            path = String(path.dropFirst(2))
        }
        return path.isEmpty ? nil : path
    }
}
