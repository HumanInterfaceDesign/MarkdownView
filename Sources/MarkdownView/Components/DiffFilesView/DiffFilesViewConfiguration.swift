import Foundation

#if canImport(UIKit)
    import UIKit

    enum DiffFilesViewConfiguration {
        static let sectionSpacing: CGFloat = 16
        static let headerPadding: CGFloat = 12
        static let expanderRowHeight: CGFloat = 36
        static let expanderControlWidth: CGFloat = 44
        static let hairlineWidth: CGFloat = 1

        static func backgroundColor(theme: MarkdownTheme) -> UIColor {
            theme.diff.backgroundColor ?? theme.colors.codeBackground.withAlphaComponent(0.08)
        }

        static func headerHeight(theme: MarkdownTheme) -> CGFloat {
            max(theme.fonts.code.lineHeight + headerPadding * 2, 44)
        }

        static func estimatedItemHeight(theme: MarkdownTheme) -> CGFloat {
            theme.fonts.code.lineHeight * 8
        }

        /// Theme for the diff inside a section: the section header already names
        /// the file, and the hunks are stacked edge to edge, so the per-block
        /// chrome is dropped. Context collapsing is disabled as well, since the
        /// expander rows are what hide context here — leaving it on would fold
        /// freshly revealed lines back into a "… unchanged lines …" row.
        static func hunkTheme(from theme: MarkdownTheme) -> MarkdownTheme {
            var hunkTheme = theme
            hunkTheme.showsBlockHeaders = false
            hunkTheme.diff.cornerRadius = 0
            hunkTheme.diff.borderWidth = 0
            hunkTheme.diff.contextCollapseThreshold = 0
            return hunkTheme
        }
    }
#endif
