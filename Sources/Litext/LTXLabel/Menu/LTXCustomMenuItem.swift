//
//  LTXCustomMenuItem.swift
//  Litext
//

import Foundation

/// Controls where custom menu items appear relative to built-in items.
///
/// On iOS, `UIMenuController` always places built-in items first regardless of this setting.
/// On Mac Catalyst and macOS, this controls the actual ordering.
public enum LTXCustomMenuItemPosition {
    case beforeBuiltIn
    case afterBuiltIn
}

/// Metadata about the current text selection, passed to custom menu item handlers.
public struct LTXSelectionContext {
    /// The selected plain text.
    public let text: String

    /// The selected attributed text.
    public let attributedText: NSAttributedString

    /// The character range of the selection within the label's attributed string.
    public let range: NSRange

    /// The 1-based line number where the selection starts.
    public let startLine: Int

    /// The 1-based line number where the selection ends.
    public let endLine: Int
}

/// A custom menu item that developers can add to the text selection menu.
public struct LTXCustomMenuItem {
    public let title: String
    public let image: PlatformImage?
    public let handler: (LTXSelectionContext) -> Void

    public init(title: String, image: PlatformImage? = nil, handler: @escaping (LTXSelectionContext) -> Void) {
        self.title = title
        self.image = image
        self.handler = handler
    }
}
