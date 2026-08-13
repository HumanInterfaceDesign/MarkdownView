import Foundation

#if canImport(UIKit)
    import UIKit

    /// The row standing in for the lines a patch omits. Depending on the gap it
    /// offers an up arrow (lines above the next hunk), a down arrow (lines below
    /// the previous hunk) or both, and swaps the tapped arrow for a spinner
    /// while the host fetches the lines.
    final class DiffExpanderCell: UICollectionViewCell {
        private lazy var upControl: ExpanderControl = .init(direction: .up)
        private lazy var downControl: ExpanderControl = .init(direction: .down)
        private lazy var label: UILabel = .init()
        private lazy var separator: UIView = .init()
        private var tapHandler: ((DiffExpander.Direction) -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            configureSubviews()
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func configure(
            expander: DiffExpander,
            theme: MarkdownTheme,
            loadingDirections: Set<DiffExpander.Direction>,
            onTap: @escaping (DiffExpander.Direction) -> Void
        ) {
            tapHandler = onTap
            contentView.backgroundColor = theme.diff.collapsedContextBackground
            separator.backgroundColor = theme.diff.borderColor

            label.font = theme.fonts.footnote
            label.textColor = theme.diff.collapsedContextText
            label.text = expander.coversEntireGap
                ? "Show \(expander.hiddenLineCount) hidden lines"
                : "\(expander.hiddenLineCount) hidden lines"

            // One tap covers the whole gap, so a single control is enough;
            // otherwise each end of the gap gets its own arrow.
            let directions: [DiffExpander.Direction] = expander.coversEntireGap
                ? [expander.direction == .down ? .down : .up]
                : (expander.direction == .both ? [.up, .down] : [expander.direction])

            upControl.isHidden = !directions.contains(.up)
            downControl.isHidden = !directions.contains(.down)
            upControl.apply(
                theme: theme,
                isLoading: loadingDirections.contains(.up),
                coversEntireGap: expander.coversEntireGap
            )
            downControl.apply(
                theme: theme,
                isLoading: loadingDirections.contains(.down),
                coversEntireGap: expander.coversEntireGap
            )

            for control in [upControl, downControl] {
                control.tapHandler = { [weak self] direction in
                    guard let self else { return }
                    // `.both` fetches the gap in one request when it fits in a
                    // single chunk, whichever arrow is tapped.
                    tapHandler?(expander.coversEntireGap ? expander.direction : direction)
                }
            }
        }

        private func configureSubviews() {
            let heightConstraint = contentView.heightAnchor.constraint(
                equalToConstant: DiffFilesViewConfiguration.expanderRowHeight
            )
            heightConstraint.priority = .required - 1

            let stack = UIStackView(arrangedSubviews: [upControl, downControl, label])
            stack.axis = .horizontal
            stack.alignment = .fill
            stack.spacing = 4
            stack.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(stack)

            separator.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(separator)

            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                stack.trailingAnchor.constraint(
                    lessThanOrEqualTo: contentView.trailingAnchor,
                    constant: -DiffFilesViewConfiguration.headerPadding
                ),
                stack.topAnchor.constraint(equalTo: contentView.topAnchor),
                stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                heightConstraint,

                separator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                separator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                separator.heightAnchor.constraint(
                    equalToConstant: DiffFilesViewConfiguration.hairlineWidth
                ),
            ])
        }
    }

    /// A single arrow inside an expander row, showing a spinner in place of the
    /// arrow while its lines are in flight.
    private final class ExpanderControl: UIView {
        let direction: DiffExpander.Direction
        var tapHandler: ((DiffExpander.Direction) -> Void)?

        private lazy var button: UIButton = .init(type: .system)
        private lazy var spinner: UIActivityIndicatorView = .init(style: .medium)

        init(direction: DiffExpander.Direction) {
            self.direction = direction
            super.init(frame: .zero)

            button.addTarget(self, action: #selector(handleTap), for: .touchUpInside)

            for subview in [button, spinner] as [UIView] {
                subview.translatesAutoresizingMaskIntoConstraints = false
                addSubview(subview)
                NSLayoutConstraint.activate([
                    subview.centerXAnchor.constraint(equalTo: centerXAnchor),
                    subview.centerYAnchor.constraint(equalTo: centerYAnchor),
                ])
            }
            spinner.hidesWhenStopped = true

            widthAnchor.constraint(
                equalToConstant: DiffFilesViewConfiguration.expanderControlWidth
            ).isActive = true
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func apply(theme: MarkdownTheme, isLoading: Bool, coversEntireGap: Bool) {
            let symbol = if coversEntireGap {
                "arrow.up.and.down"
            } else {
                direction == .up ? "arrow.up.to.line" : "arrow.down.to.line"
            }
            button.setImage(
                UIImage(
                    systemName: symbol,
                    withConfiguration: UIImage.SymbolConfiguration(scale: .small)
                ),
                for: .normal
            )
            button.accessibilityLabel = if coversEntireGap {
                "Show all hidden lines"
            } else {
                direction == .up ? "Show lines above" : "Show lines below"
            }
            button.tintColor = theme.diff.hunkHeaderText
            spinner.color = theme.diff.hunkHeaderText
            button.isHidden = isLoading
            if isLoading {
                spinner.startAnimating()
            } else {
                spinner.stopAnimating()
            }
        }

        @objc private func handleTap() {
            tapHandler?(direction)
        }
    }
#endif
