import Foundation

#if canImport(UIKit)
    import UIKit

    /// The collapsed transcript teaser that sits underneath an audio
    /// ("podcast") bubble in a chat cell: the first few lines of the spoken
    /// text, with a "Show more" affordance once the transcript overflows them.
    ///
    /// Tapping the text or the button reports through `showMoreHandler`, where
    /// hosts typically present the full transcript:
    ///
    /// ```swift
    /// let preview = TranscriptPreviewView()
    /// preview.setTranscript(transcript)
    /// preview.showMoreHandler = { [weak self, weak preview] in
    ///     guard let self, let preview else { return }
    ///     present(preview.makeDetailViewController(), animated: true)
    /// }
    /// ```
    public final class TranscriptPreviewView: UIView {
        public var theme: MarkdownTheme = .default {
            didSet { applyTheme() }
        }

        /// Transcript lines visible while collapsed.
        public var maxPreviewLines: Int = 3 {
            didSet {
                textLabel.numberOfLines = maxPreviewLines
                setNeedsLayout()
            }
        }

        /// Overrides the preview text color. `nil` falls back to
        /// `.secondaryLabel`, matching the muted transcript of an audio bubble.
        public var textColor: UIColor? {
            didSet { applyTheme() }
        }

        /// Called when the preview text or its "Show more" button is tapped.
        public var showMoreHandler: (() -> Void)?

        /// The markdown transcript as passed to `setTranscript`.
        public private(set) var transcript: String = ""

        /// Whether the transcript overflows the collapsed preview. Updated
        /// during layout; drives the "Show more" button's visibility.
        public private(set) var isTruncated = false

        private let textLabel = UILabel()
        private let showMoreButton = UIButton(type: .system)
        private let stackView = UIStackView()

        override public init(frame: CGRect) {
            super.init(frame: frame)

            stackView.axis = .vertical
            stackView.alignment = .fill
            stackView.spacing = 4
            stackView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(stackView)
            NSLayoutConstraint.activate([
                stackView.topAnchor.constraint(equalTo: topAnchor),
                stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
                stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
                stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])

            textLabel.numberOfLines = maxPreviewLines
            textLabel.lineBreakMode = .byTruncatingTail
            stackView.addArrangedSubview(textLabel)

            showMoreButton.configuration = {
                var config = UIButton.Configuration.plain()
                config.title = TranscriptLocalizedText.showMore
                config.contentInsets = .zero
                return config
            }()
            showMoreButton.contentHorizontalAlignment = .leading
            showMoreButton.isHidden = true
            showMoreButton.addTarget(self, action: #selector(showMoreTapped), for: .touchUpInside)
            stackView.addArrangedSubview(showMoreButton)

            let tap = UITapGestureRecognizer(target: self, action: #selector(showMoreTapped))
            tap.delegate = self
            addGestureRecognizer(tap)

            applyTheme()
        }

        @available(*, unavailable)
        public required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        /// Replaces the transcript, collapsing markdown to plain text for the
        /// preview. The full markdown is kept for `makeDetailViewController()`.
        public func setTranscript(_ markdown: String) {
            transcript = markdown
            textLabel.text = TranscriptPlainText.flatten(markdown: markdown)
            setNeedsLayout()
        }

        /// A detail screen with the full transcript rendered as markdown, ready
        /// to be presented modally.
        public func makeDetailViewController(title: String? = nil) -> TranscriptDetailViewController {
            TranscriptDetailViewController(transcript: transcript, theme: theme, title: title)
        }

        override public func layoutSubviews() {
            super.layoutSubviews()
            updateTruncation()
        }

        // MARK: - Private

        private func applyTheme() {
            textLabel.font = theme.fonts.body
            textLabel.textColor = textColor ?? .secondaryLabel
            showMoreButton.configuration?.baseForegroundColor = textColor ?? theme.colors.highlight
            showMoreButton.configuration?.attributedTitle = AttributedString(
                TranscriptLocalizedText.showMore,
                attributes: AttributeContainer([.font: theme.fonts.footnote.bold])
            )
            setNeedsLayout()
        }

        private func updateTruncation() {
            let width = bounds.width
            guard width > 0,
                  let text = textLabel.text, !text.isEmpty,
                  let font = textLabel.font
            else {
                setTruncated(false)
                return
            }
            let bounding = (text as NSString).boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font],
                context: nil
            )
            let linesNeeded = Int((bounding.height / font.lineHeight).rounded())
            setTruncated(linesNeeded > maxPreviewLines)
        }

        private func setTruncated(_ truncated: Bool) {
            guard truncated != isTruncated || showMoreButton.isHidden != !truncated else { return }
            isTruncated = truncated
            showMoreButton.isHidden = !truncated
        }

        @objc private func showMoreTapped() {
            showMoreHandler?()
        }
    }

    extension TranscriptPreviewView: UIGestureRecognizerDelegate {
        // Let the "Show more" button handle its own touches so a tap on it
        // doesn't also fire the whole-view gesture.
        public func gestureRecognizer(
            _: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            guard let view = touch.view else { return true }
            return !view.isDescendant(of: showMoreButton)
        }
    }
#endif
