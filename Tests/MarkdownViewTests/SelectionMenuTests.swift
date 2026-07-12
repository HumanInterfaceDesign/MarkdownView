import XCTest
@testable import Litext

@MainActor
final class SelectionMenuTests: XCTestCase {
    func testCustomMenuItemAvailabilityUsesCurrentSelection() {
        let label = LTXLabel()
        label.isSelectable = true
        label.attributedText = NSAttributedString(string: "highlighted plain")

        let item = LTXCustomMenuItem(
            title: "Unhighlight",
            isAvailable: { $0.range.location < 11 },
            handler: { _ in }
        )

        label.selectionRange = NSRange(location: 0, length: 11)
        XCTAssertTrue(item.isAvailable(try XCTUnwrap(label.selectionContext())))

        label.selectionRange = NSRange(location: 12, length: 5)
        XCTAssertFalse(item.isAvailable(try XCTUnwrap(label.selectionContext())))
    }

    func testSelectionChangeDelegateRunsBeforeSelectionLayerUpdate() {
        let label = LTXLabel()
        label.isSelectable = true
        label.attributedText = NSAttributedString(string: "text")
        let delegate = SelectionDelegateSpy()
        label.delegate = delegate

        label.selectionRange = NSRange(location: 0, length: 4)

        XCTAssertEqual(delegate.selections, [NSRange(location: 0, length: 4)])
    }
}

@MainActor
private final class SelectionDelegateSpy: LTXLabelDelegate {
    var selections: [NSRange?] = []

    func ltxLabelSelectionDidChange(_ ltxLabel: LTXLabel, selection: NSRange?) {
        selections.append(selection)
    }

    func ltxLabelDidTapOnHighlightContent(
        _ ltxLabel: LTXLabel,
        region: LTXHighlightRegion?,
        location: CGPoint
    ) {}

    func ltxLabelDetectedUserEventMovingAtLocation(_ ltxLabel: LTXLabel, location: CGPoint) {}
}
