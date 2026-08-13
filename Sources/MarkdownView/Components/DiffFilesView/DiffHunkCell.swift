import Foundation

#if canImport(UIKit)
    import UIKit

    /// Renders one hunk of a file section with the shared `DiffView`, sized to
    /// the hunk's rendered height so the collection view can lay it out without
    /// a self-sizing pass through Core Text.
    final class DiffHunkCell: UICollectionViewCell {
        private lazy var diffView: DiffView = .init()
        private var heightConstraint: NSLayoutConstraint?

        override init(frame: CGRect) {
            super.init(frame: frame)
            diffView.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(diffView)
            let height = diffView.heightAnchor.constraint(equalToConstant: 0)
            height.priority = .required - 1
            heightConstraint = height
            NSLayoutConstraint.activate([
                diffView.topAnchor.constraint(equalTo: contentView.topAnchor),
                diffView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                diffView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                diffView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                height,
            ])
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func configure(renderBlock: DiffRenderBlock, theme: MarkdownTheme) {
            let hunkTheme = DiffFilesViewConfiguration.hunkTheme(from: theme)
            diffView.theme = hunkTheme
            diffView.renderBlock = renderBlock
            heightConstraint?.constant = DiffViewConfiguration.intrinsicHeight(
                for: renderBlock,
                theme: hunkTheme
            )
        }
    }
#endif
