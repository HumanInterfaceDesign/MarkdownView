import Foundation

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

enum DiffViewConfiguration {
    static let verticalPadding: CGFloat = CodeViewConfiguration.codePadding
    static let horizontalPadding: CGFloat = 12
    static let gutterPadding: CGFloat = CodeViewConfiguration.lineNumberPadding
    static let columnSpacing: CGFloat = 8
    static let markerColumnWidth: CGFloat = 20
    static let separatorWidth: CGFloat = 1
    static let cornerRadius: CGFloat = 10
    static let minimumLineNumberText = "0"

    static func lineCount(of block: DiffRenderBlock) -> Int {
        max(block.rows.count, 1)
    }

    static func intrinsicHeight(
        for block: DiffRenderBlock,
        theme: MarkdownTheme = .default
    ) -> CGFloat {
        let font = theme.fonts.code
        #if canImport(UIKit)
            let lineHeight = font.lineHeight
        #elseif canImport(AppKit)
            let lineHeight = font.ascender + abs(font.descender) + font.leading
        #endif
        let numberOfRows = lineCount(of: block)
        let codeHeight = lineHeight * CGFloat(numberOfRows)
            + verticalPadding * 2
            + CodeViewConfiguration.codeLineSpacing * CGFloat(max(numberOfRows - 1, 0))
        return ceil(codeHeight)
    }
}
