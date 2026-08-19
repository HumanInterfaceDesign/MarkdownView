import Foundation

#if canImport(UIKit)
    import UIKit

    /// Sticky section header naming the file a diff section renders, with its
    /// added/removed counts and a trailing chevron that collapses the file,
    /// rotating a quarter turn to point at the collapsed section.
    final class DiffFileHeaderView: UICollectionReusableView {
        private static let collapsedChevronRotation = -CGFloat.pi / 2

        private lazy var chevronView: UIImageView = .init()
        private lazy var pathLabel: UILabel = .init()
        private lazy var additionsLabel: UILabel = .init()
        private lazy var deletionsLabel: UILabel = .init()
        private lazy var separator: UIView = .init()
        /// System-material chrome (like grouped-section headers/bars) instead
        /// of a flat color, so diff content scrolling under the pinned header
        /// reads through the blur.
        private lazy var backgroundBlur: UIVisualEffectView = .init(
            effect: UIBlurEffect(style: .systemChromeMaterial)
        )
        private var tapHandler: (() -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            configureSubviews()
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func configure(
            file: DiffFilePatch,
            theme: MarkdownTheme,
            isCollapsed: Bool,
            onToggle: @escaping () -> Void
        ) {
            tapHandler = onToggle
            separator.backgroundColor = theme.diff.borderColor

            let radius = theme.diff.fileHeaderCornerRadius
            layer.cornerRadius = radius
            layer.cornerCurve = .continuous
            layer.maskedCorners = isCollapsed
                ? [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
                : [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            clipsToBounds = radius > 0
            // A rounded collapsed header floats as its own row — a bottom
            // hairline would read as an underline.
            separator.isHidden = radius > 0 && isCollapsed

            pathLabel.font = theme.fonts.code
            pathLabel.textColor = theme.diff.fileHeaderText
            pathLabel.text = file.displayPath

            additionsLabel.font = theme.fonts.footnote
            additionsLabel.textColor = theme.diff.addedIndicatorText
            additionsLabel.text = "+\(file.additions)"

            deletionsLabel.font = theme.fonts.footnote
            deletionsLabel.textColor = theme.diff.removedIndicatorText
            deletionsLabel.text = "-\(file.deletions)"

            chevronView.tintColor = theme.diff.fileMetadataText
            chevronView.image = UIImage(
                systemName: "chevron.down",
                withConfiguration: UIImage.SymbolConfiguration(scale: .small)
            )
            // Instant, matching the section toggle itself (which snaps).
            chevronView.transform = isCollapsed
                ? CGAffineTransform(rotationAngle: Self.collapsedChevronRotation)
                : .identity

            accessibilityLabel = "\(file.displayPath), \(file.additions) added, \(file.deletions) removed"
            accessibilityHint = isCollapsed ? "Expands the file" : "Collapses the file"
        }

        private func configureSubviews() {
            isAccessibilityElement = true
            accessibilityTraits = .button

            backgroundBlur.translatesAutoresizingMaskIntoConstraints = false
            addSubview(backgroundBlur)
            NSLayoutConstraint.activate([
                backgroundBlur.topAnchor.constraint(equalTo: topAnchor),
                backgroundBlur.leadingAnchor.constraint(equalTo: leadingAnchor),
                backgroundBlur.trailingAnchor.constraint(equalTo: trailingAnchor),
                backgroundBlur.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])

            chevronView.contentMode = .center
            chevronView.setContentHuggingPriority(.required, for: .horizontal)

            pathLabel.lineBreakMode = .byTruncatingHead
            pathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            for label in [additionsLabel, deletionsLabel] {
                label.setContentHuggingPriority(.required, for: .horizontal)
                label.setContentCompressionResistancePriority(.required, for: .horizontal)
            }

            let stack = UIStackView(arrangedSubviews: [
                pathLabel, additionsLabel, deletionsLabel, chevronView,
            ])
            stack.axis = .horizontal
            stack.alignment = .center
            stack.spacing = 8
            stack.translatesAutoresizingMaskIntoConstraints = false
            addSubview(stack)

            separator.translatesAutoresizingMaskIntoConstraints = false
            addSubview(separator)

            let padding = DiffFilesViewConfiguration.headerPadding
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
                stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
                stack.topAnchor.constraint(equalTo: topAnchor),
                stack.bottomAnchor.constraint(equalTo: bottomAnchor),

                separator.leadingAnchor.constraint(equalTo: leadingAnchor),
                separator.trailingAnchor.constraint(equalTo: trailingAnchor),
                separator.bottomAnchor.constraint(equalTo: bottomAnchor),
                separator.heightAnchor.constraint(
                    equalToConstant: DiffFilesViewConfiguration.hairlineWidth
                ),
            ])

            addGestureRecognizer(
                UITapGestureRecognizer(target: self, action: #selector(handleTap))
            )
        }

        @objc private func handleTap() {
            tapHandler?()
        }

        override func accessibilityActivate() -> Bool {
            tapHandler?()
            return tapHandler != nil
        }
    }
#endif
