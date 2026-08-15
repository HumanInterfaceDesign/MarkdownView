import Foundation

#if canImport(UIKit)
    import UIKit

    /// The full-transcript detail screen presented when a
    /// `TranscriptPreviewView` is tapped: a modal sheet with the whole
    /// transcript rendered as markdown in a scroll view.
    ///
    /// When presented as a sheet it defaults to medium/large detents with a
    /// grabber; hosts can reconfigure `sheetPresentationController` after
    /// initialization.
    public final class TranscriptDetailViewController: UIViewController {
        public var theme: MarkdownTheme {
            didSet {
                markdownView.theme = theme
                render()
            }
        }

        public private(set) var transcript: String

        private let navigationBar = UINavigationBar()
        private let scrollView = UIScrollView()
        private let markdownView = MarkdownTextView()
        private let titleText: String

        public init(
            transcript: String,
            theme: MarkdownTheme = .default,
            title: String? = nil
        ) {
            self.transcript = transcript
            self.theme = theme
            titleText = title ?? TranscriptLocalizedText.transcript
            super.init(nibName: nil, bundle: nil)
            modalPresentationStyle = .pageSheet
            if let sheet = sheetPresentationController {
                sheet.detents = [.medium(), .large()]
                sheet.prefersGrabberVisible = true
            }
        }

        @available(*, unavailable)
        public required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        /// Replaces the rendered transcript.
        public func setTranscript(_ markdown: String) {
            transcript = markdown
            guard isViewLoaded else { return }
            render()
        }

        override public func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .systemBackground
            setupNavigationBar()
            setupScrollView()
            markdownView.theme = theme
            render()
        }

        // MARK: - Setup

        private func setupNavigationBar() {
            navigationBar.isTranslucent = false
            navigationBar.barTintColor = .systemBackground
            navigationBar.shadowImage = UIImage()
            navigationBar.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(navigationBar)
            NSLayoutConstraint.activate([
                navigationBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                navigationBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                navigationBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ])

            let item = UINavigationItem(title: titleText)
            let closeButton = UIBarButtonItem(
                image: UIImage(systemName: "xmark"),
                style: .plain,
                target: self,
                action: #selector(closeTapped)
            )
            closeButton.tintColor = .secondaryLabel
            item.rightBarButtonItem = closeButton
            navigationBar.setItems([item], animated: false)
        }

        private func setupScrollView() {
            scrollView.alwaysBounceVertical = true
            scrollView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(scrollView)

            markdownView.translatesAutoresizingMaskIntoConstraints = false
            scrollView.addSubview(markdownView)

            NSLayoutConstraint.activate([
                scrollView.topAnchor.constraint(equalTo: navigationBar.bottomAnchor),
                scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

                markdownView.topAnchor.constraint(
                    equalTo: scrollView.contentLayoutGuide.topAnchor,
                    constant: 16
                ),
                markdownView.bottomAnchor.constraint(
                    equalTo: scrollView.contentLayoutGuide.bottomAnchor,
                    constant: -24
                ),
                markdownView.leadingAnchor.constraint(
                    equalTo: scrollView.frameLayoutGuide.leadingAnchor,
                    constant: 16
                ),
                markdownView.trailingAnchor.constraint(
                    equalTo: scrollView.frameLayoutGuide.trailingAnchor,
                    constant: -16
                ),
                scrollView.contentLayoutGuide.widthAnchor.constraint(
                    equalTo: scrollView.frameLayoutGuide.widthAnchor
                ),
            ])
        }

        private func render() {
            let content = MarkdownTextView.PreprocessedContent(
                markdown: transcript,
                theme: theme
            )
            markdownView.setMarkdown(content)
        }

        @objc private func closeTapped() {
            dismiss(animated: true)
        }
    }
#endif
