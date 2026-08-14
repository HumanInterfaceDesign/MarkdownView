//
//  SectionedDiffExample.swift
//  Example
//

import Foundation

/// A stand-in "repository": full file contents plus the patch describing the
/// pull request, built from the same lines so expanding context lines up with
/// what the diff shows.
enum SectionedDiffFixture {
    struct Change {
        /// 1-based line in the original file where the change starts.
        let oldStart: Int
        /// Lines replaced, which must match the original file.
        let removed: [String]
        let added: [String]
    }

    struct File {
        let path: String
        let originalLines: [String]
        let changes: [Change]
    }

    static let contextLines = 3

    static let files: [File] = [
        .init(
            path: "Sources/Networking/APIClient.swift",
            originalLines: originalLines(
                type: "APIClient",
                methods: ["send", "upload", "download", "cancel", "invalidate"]
            ),
            changes: [
                .init(
                    oldStart: 8,
                    removed: ["        let request = makeRequest(for: send)"],
                    added: [
                        "        var request = makeRequest(for: send)",
                        "        request.timeoutInterval = configuration.timeout",
                    ]
                ),
                .init(
                    oldStart: 63,
                    removed: ["        return try decoder.decode(Response.self, from: data)"],
                    added: [
                        "        do {",
                        "            return try decoder.decode(Response.self, from: data)",
                        "        } catch {",
                        "            throw APIError.decoding(error)",
                        "        }",
                    ]
                ),
            ]
        ),
        .init(
            path: "Sources/Networking/RetryPolicy.swift",
            originalLines: originalLines(
                type: "RetryPolicy",
                methods: ["shouldRetry", "delay", "reset"]
            ),
            changes: [
                .init(
                    oldStart: 39,
                    removed: ["    private let delayStep8 = Step(id: 8)"],
                    added: [
                        "    private let delayStep8 = Step(id: 8, jitter: 0.2)",
                        "    private let delayStep9 = Step(id: 9, jitter: 0.4)",
                    ]
                ),
            ]
        ),
    ]

    static var patch: String {
        files.map(patch(for:)).joined(separator: "\n")
    }

    /// Original contents of a file, keyed by the path shown in the section header.
    static func originalLines(for path: String) -> [String]? {
        files.first { $0.path == path }?.originalLines
    }

    private static func patch(for file: File) -> String {
        var lines = [
            "diff --git a/\(file.path) b/\(file.path)",
            "--- a/\(file.path)",
            "+++ b/\(file.path)",
        ]

        // The patch is generated left to right, so the running offset keeps the
        // `+` side line numbers in step with the edits already applied.
        var newOffset = 0
        for change in file.changes {
            let leading = Array(
                file.originalLines[
                    max(change.oldStart - 1 - contextLines, 0) ..< (change.oldStart - 1)
                ]
            )
            let trailingStart = change.oldStart - 1 + change.removed.count
            let trailing = Array(
                file.originalLines[
                    trailingStart ..< min(trailingStart + contextLines, file.originalLines.count)
                ]
            )

            let oldStart = change.oldStart - leading.count
            let oldCount = leading.count + change.removed.count + trailing.count
            let newCount = leading.count + change.added.count + trailing.count
            lines.append("@@ -\(oldStart),\(oldCount) +\(oldStart + newOffset),\(newCount) @@")
            lines += leading.map { " \($0)" }
            lines += change.removed.map { "-\($0)" }
            lines += change.added.map { "+\($0)" }
            lines += trailing.map { " \($0)" }
            newOffset += change.added.count - change.removed.count
        }

        return lines.joined(separator: "\n")
    }

    private static func originalLines(type: String, methods: [String]) -> [String] {
        var lines = [
            "import Foundation",
            "",
            "/// Generated stand-in source used by the sectioned diff example.",
            "struct \(type) {",
            "    let configuration: Configuration",
            "",
        ]

        for (index, method) in methods.enumerated() {
            lines += [
                "    func \(method)(_ request: Request) throws -> Response {",
                "        let request = makeRequest(for: \(method))",
                "        try validate(request, index: \(index))",
                "        let data = try transport.perform(request)",
                "        try log(\"\(method)\", bytes: data.count)",
                "        return try decoder.decode(Response.self, from: data)",
                "    }",
                "",
            ]
            // Pad each method so the hunks sit far enough apart for the
            // expanders between them to be interesting.
            for step in 1 ... 8 {
                lines.append("    private let \(method)Step\(step) = Step(id: \(step))")
            }
            lines.append("")
        }

        lines.append("}")
        return lines
    }
}
