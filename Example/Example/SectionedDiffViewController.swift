//
//  SectionedDiffViewController.swift
//  Example
//

import MarkdownView
import UIKit

/// Shows a multi-file patch with one sticky section per file, backed by an
/// async context provider that pretends to hit a server so the expander's
/// loading state is visible.
final class SectionedDiffViewController: UIViewController {
    private let diffController = DiffFilesViewController(
        patch: SectionedDiffFixture.patch,
        language: "swift"
    )

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Files Changed"
        view.backgroundColor = .systemBackground

        diffController.fileLineCountProvider = { path in
            SectionedDiffFixture.originalLines(for: path)?.count
        }
        diffController.contextProvider = { request in
            try await Task.sleep(nanoseconds: 600_000_000)
            guard let lines = SectionedDiffFixture.originalLines(for: request.filePath) else {
                return []
            }
            let range = request.oldLineRange.clamped(to: 1 ... lines.count)
            return range.map { lines[$0 - 1] }
        }
        diffController.expansionFailureHandler = { request, error in
            print("Failed to expand \(request.filePath): \(error)")
        }

        addChild(diffController)
        diffController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(diffController.view)
        NSLayoutConstraint.activate([
            diffController.view.topAnchor.constraint(equalTo: view.topAnchor),
            diffController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            diffController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            diffController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        diffController.didMove(toParent: self)
    }
}
