//
//  MarkdownTheme.swift
//  MarkdownView
//
//  Created by 秋星桥 on 2025/1/3.
//

import Foundation
import Litext

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

public extension MarkdownTheme {
    static var `default`: MarkdownTheme = .init()
    static let codeScale = 0.85
}

public struct MarkdownTheme: Equatable {
    public struct Fonts: Equatable {
        #if canImport(UIKit)
            public var body = UIFont.preferredFont(forTextStyle: .body)
            public var codeInline = UIFont.monospacedSystemFont(
                ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize,
                weight: .regular
            )
            public var bold = UIFont.preferredFont(forTextStyle: .body).bold
            public var italic = UIFont.preferredFont(forTextStyle: .body).italic
            public var code = UIFont.monospacedSystemFont(
                ofSize: ceil(UIFont.preferredFont(forTextStyle: .body).pointSize * codeScale),
                weight: .regular
            )
            public var largeTitle = UIFont.preferredFont(forTextStyle: .body).bold
            public var title = UIFont.preferredFont(forTextStyle: .body).bold
            public var footnote = UIFont.preferredFont(forTextStyle: .footnote)
        #elseif canImport(AppKit)
            public var body = NSFont.systemFont(ofSize: NSFont.systemFontSize)
            public var codeInline = NSFont.monospacedSystemFont(
                ofSize: NSFont.systemFontSize,
                weight: .regular
            )
            public var bold = NSFont.systemFont(ofSize: NSFont.systemFontSize).bold
            public var italic = NSFont.systemFont(ofSize: NSFont.systemFontSize).italic
            public var code = NSFont.monospacedSystemFont(
                ofSize: ceil(NSFont.systemFontSize * codeScale),
                weight: .regular
            )
            public var largeTitle = NSFont.systemFont(ofSize: NSFont.systemFontSize).bold
            public var title = NSFont.systemFont(ofSize: NSFont.systemFontSize).bold
            public var footnote = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        #endif
    }

    public var fonts: Fonts = .init()

    public struct Colors: Equatable {
        #if canImport(UIKit)
            private static var defaultAccentColor: UIColor {
                UIColor(named: "AccentColor")
                    ?? UIColor(named: "accentColor")
                    ?? .systemOrange
            }

            public var body = UIColor.label
            public var highlight = Self.defaultAccentColor
            public var emphasis = Self.defaultAccentColor
            public var code = UIColor.label
            public var codeBackground = UIColor.gray.withAlphaComponent(0.25)
            public var selectionTint = Self.defaultAccentColor
            public var selectionBackgroundOverride: UIColor?

            public var selectionBackground: UIColor? {
                get { selectionBackgroundOverride ?? selectionTint.withAlphaComponent(0.2) }
                set { selectionBackgroundOverride = newValue }
            }

            /// Background color for line selection highlights in code and diff views.
            /// Defaults to `selectionTint` at 15% opacity when `nil`.
            public var lineSelectionBackground: UIColor?
        #elseif canImport(AppKit)
            private static var defaultAccentColor: NSColor {
                NSColor(named: "AccentColor")
                    ?? NSColor(named: "accentColor")
                    ?? .systemOrange
            }

            public var body = NSColor.labelColor
            public var highlight = Self.defaultAccentColor
            public var emphasis = Self.defaultAccentColor
            public var code = NSColor.labelColor
            public var codeBackground = NSColor.gray.withAlphaComponent(0.25)
            public var selectionTint = Self.defaultAccentColor
            public var selectionBackgroundOverride: NSColor?

            public var selectionBackground: NSColor? {
                get { selectionBackgroundOverride ?? selectionTint.withAlphaComponent(0.2) }
                set { selectionBackgroundOverride = newValue }
            }

            /// Background color for line selection highlights in code and diff views.
            /// Defaults to `selectionTint` at 15% opacity when `nil`.
            public var lineSelectionBackground: NSColor?
        #endif
    }

    public var colors: Colors = .init()
    public var showsBlockHeaders: Bool = true

    public struct Spacings: Equatable {
        public var final: CGFloat = 16
        public var general: CGFloat = 8
        public var list: CGFloat = 8
        public var cell: CGFloat = 32
    }

    public var spacings: Spacings = .init()

    public struct Sizes: Equatable {
        public var bullet: CGFloat = 4
    }

    public var sizes: Sizes = .init()

    public struct Table: Equatable {
        public var cornerRadius: CGFloat = 8
        public var borderWidth: CGFloat = 1
        #if canImport(UIKit)
            public var borderColor = UIColor.separator
            public var headerBackgroundColor = UIColor.systemGray6
            public var cellBackgroundColor = UIColor.clear
            public var stripeCellBackgroundColor = UIColor.systemGray.withAlphaComponent(0.03)
        #elseif canImport(AppKit)
            public var borderColor = NSColor.separatorColor
            public var headerBackgroundColor = NSColor.windowBackgroundColor
            public var cellBackgroundColor = NSColor.clear
            public var stripeCellBackgroundColor = NSColor.systemGray.withAlphaComponent(0.03)
        #endif
    }

    public var table: Table = .init()

    public struct Image: Equatable {
        public var cornerRadius: CGFloat = 4
        public var maxWidthFraction: CGFloat = 1.0
        #if canImport(UIKit)
            public var placeholderColor = UIColor.systemGray5
        #elseif canImport(AppKit)
            public var placeholderColor = NSColor.windowBackgroundColor
        #endif
    }

    public var image: Image = .init()

    public struct Diff: Equatable {
        public enum DisplayMode: String, CaseIterable {
            case unified
            case sideBySide
        }

        public enum ChangeHighlightStyle: String, CaseIterable {
            case lineOnly
            case inlineOnly
            case both
        }

        public enum ScrollBehavior: String, CaseIterable {
            case horizontalOnly
            case bothAxes
        }

        public enum LineNumberStyle: String, CaseIterable {
            case dual
            case single
        }

        public var displayMode: DisplayMode = .unified
        public var changeHighlightStyle: ChangeHighlightStyle = .both
        public var scrollBehavior: ScrollBehavior = .horizontalOnly
        public var lineNumberStyle: LineNumberStyle = .dual
        public var showsChangeMarkers: Bool = true
        public var contextCollapseThreshold: Int = 8
        public var visibleContextLines: Int = 2
        #if canImport(UIKit)
            public var gutterBackground = CodeHighlighter.dynamicColor(
                light: UIColor(red: 0.965, green: 0.969, blue: 0.976, alpha: 1),
                dark: UIColor(red: 0.094, green: 0.106, blue: 0.125, alpha: 1)
            )
            public var backgroundColor: UIColor?
            public var gutterText = UIColor.secondaryLabel
            public var separatorColor = UIColor.separator.withAlphaComponent(0.18)
            public var borderWidth: CGFloat = 1
            public var borderColor = UIColor.separator.withAlphaComponent(0.22)
            public var fileHeaderBackground = CodeHighlighter.dynamicColor(
                light: UIColor(red: 0.953, green: 0.957, blue: 0.965, alpha: 1),
                dark: UIColor(red: 0.141, green: 0.149, blue: 0.176, alpha: 1)
            )
            public var fileHeaderText = UIColor.label
            public var fileMetadataText = UIColor.secondaryLabel
            public var addedLineBackground = CodeHighlighter.dynamicColor(
                light: UIColor(red: 0.894, green: 0.973, blue: 0.918, alpha: 1),
                dark: UIColor(red: 0.075, green: 0.247, blue: 0.153, alpha: 1)
            )
            public var removedLineBackground = CodeHighlighter.dynamicColor(
                light: UIColor(red: 0.992, green: 0.918, blue: 0.918, alpha: 1),
                dark: UIColor(red: 0.325, green: 0.133, blue: 0.153, alpha: 1)
            )
            public var addedHighlightBackground = CodeHighlighter.dynamicColor(
                light: UIColor(red: 0.769, green: 0.918, blue: 0.808, alpha: 1),
                dark: UIColor(red: 0.102, green: 0.388, blue: 0.239, alpha: 1)
            )
            public var removedHighlightBackground = CodeHighlighter.dynamicColor(
                light: UIColor(red: 0.976, green: 0.773, blue: 0.773, alpha: 1),
                dark: UIColor(red: 0.490, green: 0.184, blue: 0.212, alpha: 1)
            )
            public var hunkHeaderBackground = CodeHighlighter.dynamicColor(
                light: UIColor(red: 0.871, green: 0.929, blue: 0.984, alpha: 1),
                dark: UIColor(red: 0.078, green: 0.192, blue: 0.314, alpha: 1)
            )
            public var hunkHeaderText = CodeHighlighter.dynamicColor(
                light: UIColor(red: 0.114, green: 0.341, blue: 0.620, alpha: 1),
                dark: UIColor(red: 0.545, green: 0.761, blue: 0.973, alpha: 1)
            )
            public var collapsedContextBackground = CodeHighlighter.dynamicColor(
                light: UIColor(red: 0.941, green: 0.945, blue: 0.953, alpha: 1),
                dark: UIColor(red: 0.118, green: 0.133, blue: 0.157, alpha: 1)
            )
            public var collapsedContextText = UIColor.secondaryLabel
            public var addedIndicatorText = CodeHighlighter.dynamicColor(
                light: UIColor(red: 0.114, green: 0.478, blue: 0.247, alpha: 1),
                dark: UIColor(red: 0.451, green: 0.851, blue: 0.573, alpha: 1)
            )
            public var removedIndicatorText = CodeHighlighter.dynamicColor(
                light: UIColor(red: 0.773, green: 0.157, blue: 0.188, alpha: 1),
                dark: UIColor(red: 0.973, green: 0.506, blue: 0.529, alpha: 1)
            )
            public var annotationIndicatorText = UIColor.secondaryLabel
            public var annotationText = UIColor.secondaryLabel
        #elseif canImport(AppKit)
            public var gutterBackground = CodeHighlighter.dynamicColor(
                light: NSColor(red: 0.965, green: 0.969, blue: 0.976, alpha: 1),
                dark: NSColor(red: 0.094, green: 0.106, blue: 0.125, alpha: 1)
            )
            public var backgroundColor: NSColor?
            public var gutterText = NSColor.secondaryLabelColor
            public var separatorColor = NSColor.separatorColor.withAlphaComponent(0.18)
            public var borderWidth: CGFloat = 1
            public var borderColor = NSColor.separatorColor.withAlphaComponent(0.22)
            public var fileHeaderBackground = CodeHighlighter.dynamicColor(
                light: NSColor(red: 0.953, green: 0.957, blue: 0.965, alpha: 1),
                dark: NSColor(red: 0.141, green: 0.149, blue: 0.176, alpha: 1)
            )
            public var fileHeaderText = NSColor.labelColor
            public var fileMetadataText = NSColor.secondaryLabelColor
            public var addedLineBackground = CodeHighlighter.dynamicColor(
                light: NSColor(red: 0.894, green: 0.973, blue: 0.918, alpha: 1),
                dark: NSColor(red: 0.075, green: 0.247, blue: 0.153, alpha: 1)
            )
            public var removedLineBackground = CodeHighlighter.dynamicColor(
                light: NSColor(red: 0.992, green: 0.918, blue: 0.918, alpha: 1),
                dark: NSColor(red: 0.325, green: 0.133, blue: 0.153, alpha: 1)
            )
            public var addedHighlightBackground = CodeHighlighter.dynamicColor(
                light: NSColor(red: 0.769, green: 0.918, blue: 0.808, alpha: 1),
                dark: NSColor(red: 0.102, green: 0.388, blue: 0.239, alpha: 1)
            )
            public var removedHighlightBackground = CodeHighlighter.dynamicColor(
                light: NSColor(red: 0.976, green: 0.773, blue: 0.773, alpha: 1),
                dark: NSColor(red: 0.490, green: 0.184, blue: 0.212, alpha: 1)
            )
            public var hunkHeaderBackground = CodeHighlighter.dynamicColor(
                light: NSColor(red: 0.871, green: 0.929, blue: 0.984, alpha: 1),
                dark: NSColor(red: 0.078, green: 0.192, blue: 0.314, alpha: 1)
            )
            public var hunkHeaderText = CodeHighlighter.dynamicColor(
                light: NSColor(red: 0.114, green: 0.341, blue: 0.620, alpha: 1),
                dark: NSColor(red: 0.545, green: 0.761, blue: 0.973, alpha: 1)
            )
            public var collapsedContextBackground = CodeHighlighter.dynamicColor(
                light: NSColor(red: 0.941, green: 0.945, blue: 0.953, alpha: 1),
                dark: NSColor(red: 0.118, green: 0.133, blue: 0.157, alpha: 1)
            )
            public var collapsedContextText = NSColor.secondaryLabelColor
            public var addedIndicatorText = CodeHighlighter.dynamicColor(
                light: NSColor(red: 0.114, green: 0.478, blue: 0.247, alpha: 1),
                dark: NSColor(red: 0.451, green: 0.851, blue: 0.573, alpha: 1)
            )
            public var removedIndicatorText = CodeHighlighter.dynamicColor(
                light: NSColor(red: 0.773, green: 0.157, blue: 0.188, alpha: 1),
                dark: NSColor(red: 0.973, green: 0.506, blue: 0.529, alpha: 1)
            )
            public var annotationIndicatorText = NSColor.secondaryLabelColor
            public var annotationText = NSColor.secondaryLabelColor
        #endif
    }

    public var diff: Diff = .init()

    public init() {}
}

public extension MarkdownTheme {
    static var defaultValueFont: Fonts {
        Fonts()
    }

    static var defaultValueColor: Colors {
        Colors()
    }

    static var defaultValueSpacing: Spacings {
        Spacings()
    }

    static var defaultValueSize: Sizes {
        Sizes()
    }

    static var defaultValueTable: Table {
        Table()
    }

    static var defaultValueDiff: Diff {
        Diff()
    }
}

public extension MarkdownTheme {
    enum FontScale: String, CaseIterable {
        case tiny
        case small
        case middle
        case large
        case huge
    }
}

public extension MarkdownTheme.FontScale {
    var offset: Int {
        switch self {
        case .tiny: -4
        case .small: -2
        case .middle: 0
        case .large: 2
        case .huge: 4
        }
    }

    func scale(_ font: PlatformFont) -> PlatformFont {
        let size = max(4, font.pointSize + CGFloat(offset))
        return font.withSize(size)
    }
}

public extension MarkdownTheme {
    mutating func scaleFont(by scale: FontScale) {
        let defaultFont = Self.defaultValueFont
        fonts.body = scale.scale(defaultFont.body)
        fonts.codeInline = scale.scale(defaultFont.codeInline)
        fonts.bold = scale.scale(defaultFont.bold)
        fonts.italic = scale.scale(defaultFont.italic)
        fonts.code = scale.scale(defaultFont.code)
        fonts.largeTitle = scale.scale(defaultFont.largeTitle)
        fonts.title = scale.scale(defaultFont.title)
    }

    mutating func align(to pointSize: CGFloat) {
        fonts.body = fonts.body.withSize(pointSize)
        fonts.codeInline = fonts.codeInline.withSize(pointSize)
        fonts.bold = fonts.bold.withSize(pointSize).bold
        fonts.italic = fonts.italic.withSize(pointSize)
        fonts.code = fonts.code.withSize(pointSize * Self.codeScale)
        fonts.largeTitle = fonts.largeTitle.withSize(pointSize).bold
        fonts.title = fonts.title.withSize(pointSize).bold
    }
}
