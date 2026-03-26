//
//  DetailViewController.swift
//  Example
//
//  Created by Gary Tokman on 3/26/26.
//

import MarkdownParser
import MarkdownView
import UIKit

class DetailViewController: UIViewController {

    private let example: DiffExample
    private let markdownView = MarkdownTextView()

    init(example: DiffExample) {
        self.example = example
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = example.title
        view.backgroundColor = .systemBackground

        // Custom menu items
        markdownView.textView.customMenuItems = [
            LTXCustomMenuItem(
                title: "Explain",
                image: UIImage(systemName: "lightbulb")
            ) { selectedText in
                print("Explain: \(selectedText)")
            },
            LTXCustomMenuItem(
                title: "Apply",
                image: UIImage(systemName: "checkmark.circle")
            ) { selectedText in
                print("Apply: \(selectedText)")
            },
            LTXCustomMenuItem(
                title: "Reject",
                image: UIImage(systemName: "xmark.circle")
            ) { selectedText in
                print("Reject: \(selectedText)")
            },
        ]

        view.addSubview(markdownView)
        markdownView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            markdownView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            markdownView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            markdownView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
        ])

        let parser = MarkdownParser()
        let result = parser.parse(example.markdown)
        let content = MarkdownTextView.PreprocessedContent(
            parserResult: result,
            theme: .default
        )
        markdownView.setMarkdown(content)
    }
}
