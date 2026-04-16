import Foundation

/// Information about the currently selected lines in a code or diff view.
public struct LineSelectionInfo {
    /// The 1-based range of selected lines.
    public let lineRange: ClosedRange<Int>

    /// The text contents of each selected line.
    public let contents: [String]

    /// The language of the code block, if known.
    public let language: String?
}

/// A closure that handles line selection changes. Receives `nil` when the selection is cleared.
///
/// Used for both `lineSelectionHandler` (fires on every change, including intermediate
/// drag updates) and `lineSelectionEndedHandler` (fires once when the user's gesture
/// settles — tap completes, or long-press/drag ends).
public typealias LineSelectionHandler = (LineSelectionInfo?) -> Void
