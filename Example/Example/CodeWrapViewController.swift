//
//  CodeWrapViewController.swift
//  Example
//
//  Demonstrates `MarkdownTheme.wrapsCodeBlockLines`: code blocks soft-wrap to
//  the available width instead of scrolling horizontally. The toggle switches
//  between wrapped and scrolling layouts; line numbers always count logical
//  lines.
//

import MarkdownParser
import MarkdownView
import UIKit

final class CodeWrapViewController: UIViewController {

    private let scrollView = UIScrollView()
    private let markdownView = MarkdownTextView()
    private let parser = MarkdownParser()

    private let sampleMarkdown = """
    A single long line wraps instead of scrolling:

    ```text
    A cinematic still from an intimate, atmospheric New York indie drama: a young woman waits alone on a subway platform late at night, framed beneath flickering fluorescent lights as an arriving train throws streaks of motion-blurred light across her face.
    ```

    Mixed line lengths keep their logical line numbers:

    ```swift
    func makePrompt(for scene: Scene) -> String {
        let mood = scene.mood ?? "atmospheric"
        return "A cinematic still from an intimate, \\(mood) New York indie drama: \\(scene.subject) framed beneath flickering fluorescent lights as an arriving train throws streaks of motion-blurred light."
    }
    ```
    """

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Wrapped Code"
        view.backgroundColor = .systemBackground

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Wrap",
            primaryAction: UIAction { [weak self] _ in self?.toggleWrap() }
        )

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        markdownView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(markdownView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            markdownView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            markdownView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            markdownView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            markdownView.bottomAnchor.constraint(lessThanOrEqualTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16),
            markdownView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32),
        ])

        var theme = markdownView.theme
        theme.wrapsCodeBlockLines = true
        markdownView.theme = theme
        updateToggleTitle()
        render()
    }

    private func render() {
        let result = parser.parse(sampleMarkdown)
        let content = MarkdownTextView.PreprocessedContent(
            parserResult: result,
            theme: markdownView.theme
        )
        markdownView.setMarkdownManually(content)
    }

    private func toggleWrap() {
        var theme = markdownView.theme
        theme.wrapsCodeBlockLines.toggle()
        markdownView.theme = theme
        updateToggleTitle()
        render()
    }

    private func updateToggleTitle() {
        navigationItem.rightBarButtonItem?.title =
            markdownView.theme.wrapsCodeBlockLines ? "Scroll" : "Wrap"
    }
}
