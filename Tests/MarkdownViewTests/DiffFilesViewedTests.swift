#if canImport(UIKit)
    import UIKit
    import XCTest
    @testable import MarkdownView

    @MainActor
    final class DiffFilesViewedTests: XCTestCase {
        private let patch = """
            diff --git a/example.swift b/example.swift
            --- a/example.swift
            +++ b/example.swift
            @@ -1 +1 @@
            -let value = 1
            +let value = 2
            """

        func testViewedToggleCollapsesAndUncheckingExpandsBeforeViewLoads() {
            let controller = DiffFilesViewController(patch: patch)
            XCTAssertTrue(controller.showsFileViewedControl)
            XCTAssertTrue(controller.collapsesViewedFiles)
            var collapseStates: [Bool] = []
            var viewedStates: [Bool] = []
            controller.fileCollapseHandler = { path, collapsed in
                XCTAssertEqual(path, "example.swift")
                collapseStates.append(collapsed)
            }
            controller.fileViewedHandler = { path, viewed in
                XCTAssertEqual(path, "example.swift")
                viewedStates.append(viewed)
            }

            controller.setFileViewed(true, at: "example.swift")
            XCTAssertEqual(controller.viewedFilePaths, ["example.swift"])
            controller.setFileViewed(true, at: "example.swift")
            controller.setFileViewed(false, at: "example.swift")
            controller.setFileViewed(true, at: "missing.swift")

            XCTAssertTrue(controller.viewedFilePaths.isEmpty)
            XCTAssertEqual(collapseStates, [true, false])
            XCTAssertEqual(viewedStates, [true, false])
            XCTAssertFalse(controller.isViewLoaded)
        }

        func testAutomaticCollapseCanBeDisabled() {
            let controller = DiffFilesViewController(patch: patch)
            controller.collapsesViewedFiles = false
            controller.fileCollapseHandler = { _, _ in
                XCTFail("Reviewing must not change collapse state when disabled")
            }
            controller.setFileViewed(true, at: "example.swift")
            XCTAssertEqual(controller.viewedFilePaths, ["example.swift"])
            controller.setFileViewed(false, at: "example.swift")
            XCTAssertTrue(controller.viewedFilePaths.isEmpty)
        }

        func testViewedPathsSurvivePatchRefreshAndRemovedFilesArePruned() {
            let controller = DiffFilesViewController(patch: patch)
            controller.setFileViewed(true, at: "example.swift")
            controller.setPatch(patch)
            XCTAssertEqual(controller.viewedFilePaths, ["example.swift"])
            controller.setPatch("")
            XCTAssertTrue(controller.viewedFilePaths.isEmpty)
        }

        func testHeaderExposesIndependentAccessibleActions() throws {
            let document = try XCTUnwrap(DiffPatchDocument(patch: patch, language: "swift"))
            let file = try XCTUnwrap(document.files.first)
            let header = DiffFileHeaderView(frame: CGRect(x: 0, y: 0, width: 390, height: 48))
            var collapseTaps = 0
            var viewedTaps = 0
            func configure(viewed: Bool, visible: Bool = true) {
                header.configure(
                    file: file,
                    theme: .default,
                    isCollapsed: viewed,
                    isViewed: viewed,
                    showsViewedControl: visible,
                    onToggle: { collapseTaps += 1 },
                    onToggleViewed: { viewedTaps += 1 }
                )
            }
            configure(viewed: false)
            let controls = try XCTUnwrap(header.subviews.compactMap { $0 as? UIStackView }.first)
            let viewed = try XCTUnwrap(controls.arrangedSubviews.first as? SymbolActionView)
            let collapse = try XCTUnwrap(controls.arrangedSubviews.last as? UIButton)
            header.semanticContentAttribute = .forceLeftToRight
            controls.semanticContentAttribute = .forceLeftToRight
            header.layoutIfNeeded()
            XCTAssertLessThanOrEqual(viewed.frame.maxX, collapse.frame.minX)
            XCTAssertEqual(viewed.frame.width, 44, accuracy: 0.5)
            XCTAssertFalse(header.isAccessibilityElement)
            XCTAssertTrue(viewed.isAccessibilityElement)
            XCTAssertEqual(viewed.accessibilityValue, "Not viewed")
            XCTAssertTrue(viewed.accessibilityActivate())
            XCTAssertEqual(viewedTaps, 1)
            XCTAssertEqual(collapseTaps, 0)
            let collapseActions = try XCTUnwrap(collapse.actions(forTarget: header, forControlEvent: .touchUpInside))
            XCTAssertEqual(collapseActions.count, 1)
            let collapseAction = NSSelectorFromString(try XCTUnwrap(collapseActions.first))
            XCTAssertTrue(header.responds(to: collapseAction))
            // Package tests have no UIApplication host to dispatch sendActions.
            // Invoke the registered selector directly to verify the actual wiring.
            _ = header.perform(collapseAction)
            XCTAssertEqual(collapseTaps, 1)
            XCTAssertEqual(viewedTaps, 1)

            configure(viewed: true)
            XCTAssertEqual(viewed.accessibilityValue, "Viewed")
            XCTAssertTrue(viewed.accessibilityTraits.contains(.selected))
            configure(viewed: true, visible: false)
            XCTAssertTrue(viewed.isHidden)
        }
    }
#endif
