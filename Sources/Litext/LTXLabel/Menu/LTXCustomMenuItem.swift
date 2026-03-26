//
//  LTXCustomMenuItem.swift
//  Litext
//

/// Controls where custom menu items appear relative to built-in items.
///
/// On iOS, `UIMenuController` always places built-in items first regardless of this setting.
/// On Mac Catalyst and macOS, this controls the actual ordering.
public enum LTXCustomMenuItemPosition {
    case beforeBuiltIn
    case afterBuiltIn
}

/// A custom menu item that developers can add to the text selection menu.
public struct LTXCustomMenuItem {
    public let title: String
    public let image: PlatformImage?
    public let handler: (String) -> Void

    public init(title: String, image: PlatformImage? = nil, handler: @escaping (String) -> Void) {
        self.title = title
        self.image = image
        self.handler = handler
    }
}
