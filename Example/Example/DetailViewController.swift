//
//  DetailViewController.swift
//  Example
//
//  Created by Gary Tokman on 3/26/26.
//

import Litext
import MarkdownParser
import MarkdownView
import UIKit

class DetailViewController: UIViewController {

    private let example: DiffExample
    private let markdownView = MarkdownTextView()
    private let commentButton = UIButton(type: .system)
    private var currentSelectionInfo: LineSelectionInfo?
    private var lineNumberStyle: MarkdownTheme.Diff.LineNumberStyle = .dual
    private var showsChangeMarkers: Bool = true

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

        switch example.selectionMode {
        case .textSelection:
            setupTextSelection()
        case .lineSelection:
            setupLineSelection()
        }

        view.addSubview(markdownView)
        markdownView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            markdownView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            markdownView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            markdownView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
        ])

        applyTheme()
        setupGutterStyleMenu()

        let parser = MarkdownParser()
        let result = parser.parse(example.markdown)
        let content = MarkdownTextView.PreprocessedContent(
            parserResult: result,
            theme: markdownView.theme
        )
        markdownView.setMarkdown(content)
    }

    private func setupGutterStyleMenu() {
        let button = UIBarButtonItem(
            image: UIImage(systemName: "number"),
            menu: makeGutterStyleMenu()
        )
        navigationItem.rightBarButtonItem = button
    }

    private func makeGutterStyleMenu() -> UIMenu {
        let lineNumberMenu = UIMenu(title: "Line Numbers", options: .displayInline, children: [
            UIAction(
                title: "Dual Column",
                state: lineNumberStyle == .dual ? .on : .off
            ) { [weak self] _ in
                self?.setLineNumberStyle(.dual)
            },
            UIAction(
                title: "Single Column",
                state: lineNumberStyle == .single ? .on : .off
            ) { [weak self] _ in
                self?.setLineNumberStyle(.single)
            },
        ])
        let markersMenu = UIMenu(title: "Change Markers", options: .displayInline, children: [
            UIAction(
                title: "Show +/− Markers",
                state: showsChangeMarkers ? .on : .off
            ) { [weak self] _ in
                self?.toggleChangeMarkers()
            },
        ])
        return UIMenu(title: "Gutter", children: [lineNumberMenu, markersMenu])
    }

    private func setLineNumberStyle(_ style: MarkdownTheme.Diff.LineNumberStyle) {
        lineNumberStyle = style
        navigationItem.rightBarButtonItem?.menu = makeGutterStyleMenu()
        applyTheme()
    }

    private func toggleChangeMarkers() {
        showsChangeMarkers.toggle()
        navigationItem.rightBarButtonItem?.menu = makeGutterStyleMenu()
        applyTheme()
    }

    private func applyTheme() {
        var theme = MarkdownTheme.default
        theme.diff.lineNumberStyle = lineNumberStyle
        theme.diff.showsChangeMarkers = showsChangeMarkers
        markdownView.theme = theme
    }

    // MARK: - Text Selection

    private func setupTextSelection() {
        markdownView.textView.customMenuItems = [
            LTXCustomMenuItem(
                title: "Explain",
                image: UIImage(systemName: "lightbulb")
            ) { context in
                print("Explain: \"\(context.text)\" (lines \(context.startLine)-\(context.endLine))")
            },
            LTXCustomMenuItem(
                title: "Apply",
                image: UIImage(systemName: "checkmark.circle")
            ) { context in
                print("Apply: \"\(context.text)\" (lines \(context.startLine)-\(context.endLine))")
            },
            LTXCustomMenuItem(
                title: "Reject",
                image: UIImage(systemName: "xmark.circle")
            ) { context in
                print("Reject: \"\(context.text)\" (lines \(context.startLine)-\(context.endLine))")
            },
        ]
    }

    // MARK: - Line Selection

    private func setupLineSelection() {
        markdownView.lineSelectionHandler = { [weak self] info in
            self?.updateCommentButton(info: info, animated: false)
        }
        markdownView.lineSelectionEndedHandler = { [weak self] info in
            self?.updateCommentButton(info: info, animated: true)
        }

        setupCommentButton()
    }

    private func setupCommentButton() {
        commentButton.isHidden = true

        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = .systemGray5
        config.baseForegroundColor = .label
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
        config.image = UIImage(systemName: "text.bubble")
        config.imagePadding = 8
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 14)
        commentButton.configuration = config
        commentButton.addTarget(self, action: #selector(commentTapped), for: .touchUpInside)

        view.addSubview(commentButton)
        commentButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            commentButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            commentButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
        ])
    }

    private func updateCommentButton(info: LineSelectionInfo?, animated: Bool) {
        currentSelectionInfo = info
        guard let info else {
            commentButton.isHidden = true
            return
        }

        let range = info.lineRange
        let title: String
        if range.lowerBound == range.upperBound {
            title = "Comment on line \(range.lowerBound)"
        } else {
            title = "Comment on lines \(range.lowerBound)-\(range.upperBound)"
        }
        commentButton.configuration?.title = title
        commentButton.isHidden = false

        guard animated else { return }
        UIView.animate(withDuration: 0.2) {
            self.commentButton.transform = CGAffineTransform(scaleX: 1.05, y: 1.05)
        } completion: { _ in
            UIView.animate(withDuration: 0.15) {
                self.commentButton.transform = .identity
            }
        }
    }

    @objc private func commentTapped() {
        guard let info = currentSelectionInfo else { return }
        let sheet = CommentSheetViewController(selectionInfo: info, language: example.language)
        if let pc = sheet.presentationController as? UISheetPresentationController {
            pc.detents = [.large()]
        }
        present(sheet, animated: true)
    }
}

// MARK: - Comment Sheet

class CommentSheetViewController: UIViewController {

    private let selectionInfo: LineSelectionInfo
    private let language: String?
    private let codeMarkdownView = MarkdownTextView()
    private let commentTextView = UITextView()

    init(selectionInfo: LineSelectionInfo, language: String?) {
        self.selectionInfo = selectionInfo
        self.language = language
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupNavBar()
        setupCodePreview()
        setupCommentTextView()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        commentTextView.becomeFirstResponder()
    }

    private func setupNavBar() {
        let navBar = UINavigationBar()
        navBar.isTranslucent = false
        navBar.barTintColor = .systemBackground
        navBar.shadowImage = UIImage()
        navBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(navBar)
        NSLayoutConstraint.activate([
            navBar.topAnchor.constraint(equalTo: view.topAnchor),
            navBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            navBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        let navItem = UINavigationItem(title: "Add Comment")

        let closeButton = UIBarButtonItem(
            image: UIImage(systemName: "xmark"),
            style: .plain,
            target: self,
            action: #selector(closeTapped)
        )
        closeButton.tintColor = .secondaryLabel
        navItem.leftBarButtonItem = closeButton

        let commentAction = UIAction(title: "Comment") { [weak self] _ in
            self?.submitComment()
        }
        let commentButton = UIButton(type: .system, primaryAction: commentAction)
        commentButton.configuration = {
            var config = UIButton.Configuration.plain()
            config.title = "Comment"
            config.baseForegroundColor = .label
            config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14)
            return config
        }()
        navItem.rightBarButtonItem = UIBarButtonItem(customView: commentButton)

        navBar.setItems([navItem], animated: false)
    }

    private func setupCodePreview() {
        codeMarkdownView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(codeMarkdownView)
        NSLayoutConstraint.activate([
            codeMarkdownView.topAnchor.constraint(equalTo: view.topAnchor, constant: 56),
            codeMarkdownView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            codeMarkdownView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
        ])

        let lines = selectionInfo.contents
        let startLine = selectionInfo.lineRange.lowerBound
        let lang = language ?? ""
        let diffBlock = lines.enumerated().map { idx, line in
            let lineNum = startLine + idx
            return "\(lineNum) \(line)"
        }.joined(separator: "\n")

        let markdown = """
        ```diff \(lang)
        \(diffBlock)
        ```
        """

        let parser = MarkdownParser()
        let result = parser.parse(markdown)
        let content = MarkdownTextView.PreprocessedContent(
            parserResult: result,
            theme: .default
        )
        codeMarkdownView.setMarkdown(content)
    }

    private func setupCommentTextView() {
        commentTextView.font = .systemFont(ofSize: 16)
        commentTextView.textColor = .label
        commentTextView.backgroundColor = .clear
        commentTextView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        commentTextView.translatesAutoresizingMaskIntoConstraints = false

        let placeholder = UILabel()
        placeholder.text = "Leave a comment..."
        placeholder.font = .systemFont(ofSize: 16)
        placeholder.textColor = .placeholderText
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        commentTextView.addSubview(placeholder)
        NSLayoutConstraint.activate([
            placeholder.topAnchor.constraint(equalTo: commentTextView.topAnchor, constant: 12),
            placeholder.leadingAnchor.constraint(equalTo: commentTextView.leadingAnchor, constant: 17),
        ])
        self.placeholderLabel = placeholder
        commentTextView.delegate = self

        view.addSubview(commentTextView)
        NSLayoutConstraint.activate([
            commentTextView.topAnchor.constraint(equalTo: codeMarkdownView.bottomAnchor, constant: 8),
            commentTextView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            commentTextView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            commentTextView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
        ])
    }

    private weak var placeholderLabel: UILabel?

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    private func submitComment() {
        let text = commentTextView.text ?? ""
        print("Comment submitted: \"\(text)\" on lines \(selectionInfo.lineRange)")
        dismiss(animated: true)
    }
}

extension CommentSheetViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        placeholderLabel?.isHidden = !textView.text.isEmpty
    }
}
