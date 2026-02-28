//
//  ASTDiff.swift
//  MarkdownView
//
//  Block-level diff for incremental markdown updates.
//  Uses MarkdownBlockNode's Hashable conformance to detect which blocks changed.
//

import Foundation
import MarkdownParser

enum ASTDiff {
    /// A change operation on the block array.
    enum Change {
        /// Block at `index` in the new array is unchanged from the old array.
        case keep(newIndex: Int)
        /// Block at `newIndex` was inserted or modified and needs rebuilding.
        case rebuild(newIndex: Int)
        /// Block at `oldIndex` was removed.
        case remove(oldIndex: Int)
    }

    /// Computes a minimal set of changes to transform `old` blocks into `new` blocks.
    /// Optimized for the common streaming case where blocks are only appended.
    static func diff(
        old: [MarkdownBlockNode],
        new: [MarkdownBlockNode]
    ) -> [Change] {
        // Fast path: identical arrays
        if old == new { return new.indices.map { .keep(newIndex: $0) } }

        // Fast path: append-only (common for streaming LLM responses)
        if new.count >= old.count {
            let prefixMatch = zip(old, new).prefix(while: { $0 == $1 }).count
            if prefixMatch == old.count {
                // All old blocks match the prefix of new blocks — pure append
                var changes: [Change] = []
                changes.reserveCapacity(new.count)
                for i in 0 ..< prefixMatch {
                    changes.append(.keep(newIndex: i))
                }
                for i in prefixMatch ..< new.count {
                    changes.append(.rebuild(newIndex: i))
                }
                return changes
            }
        }

        // General case: find longest common prefix and suffix, diff the middle
        var prefixLen = 0
        let minLen = min(old.count, new.count)
        while prefixLen < minLen && old[prefixLen] == new[prefixLen] {
            prefixLen += 1
        }

        var suffixLen = 0
        while suffixLen < (minLen - prefixLen)
            && old[old.count - 1 - suffixLen] == new[new.count - 1 - suffixLen]
        {
            suffixLen += 1
        }

        var changes: [Change] = []
        changes.reserveCapacity(max(old.count, new.count))

        // Common prefix — kept as-is
        for i in 0 ..< prefixLen {
            changes.append(.keep(newIndex: i))
        }

        // Removed blocks from old middle section
        for i in prefixLen ..< (old.count - suffixLen) {
            changes.append(.remove(oldIndex: i))
        }

        // New/modified blocks in new middle section
        for i in prefixLen ..< (new.count - suffixLen) {
            changes.append(.rebuild(newIndex: i))
        }

        // Common suffix — kept (but at new indices)
        for i in 0 ..< suffixLen {
            changes.append(.keep(newIndex: new.count - suffixLen + i))
        }

        return changes
    }
}
