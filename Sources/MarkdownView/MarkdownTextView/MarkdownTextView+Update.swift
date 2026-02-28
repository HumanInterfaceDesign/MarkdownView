//
//  MarkdownTextView+Update.swift
//  MarkdownView
//
//  Created by 秋星桥 on 7/9/25.
//

import CoreText
import Litext

extension MarkdownTextView {
    private typealias IncrementalRenderContext = (
        changes: [ASTDiff.Change],
        cachedSegments: [NSAttributedString],
        preservedViewIDs: Set<ObjectIdentifier>
    )

    private func makeIncrementalRenderContext() -> IncrementalRenderContext? {
        guard let lastBuildResult else { return nil }
        guard !lastRenderedBlocks.isEmpty else { return nil }
        guard lastRenderedBlocks != document.blocks else { return nil }

        let changes = ASTDiff.diff(old: lastRenderedBlocks, new: document.blocks)
        let hasKeptBlocks = changes.contains { change in
            if case .keep = change {
                return true
            }
            return false
        }
        guard hasKeptBlocks else { return nil }

        var preservedViewIDs = Set<ObjectIdentifier>()
        for change in changes {
            guard case let .keep(oldIndex, _) = change else { continue }
            guard oldIndex < lastBuildResult.blockSegments.count else { continue }
            for preservedView in TextBuilder.contextViews(in: lastBuildResult.blockSegments[oldIndex]) {
                preservedViewIDs.insert(ObjectIdentifier(preservedView))
            }
        }

        return (changes, lastBuildResult.blockSegments, preservedViewIDs)
    }

    func updateTextExecute() {
        assert(Thread.isMainThread)

        let incrementalRenderContext = makeIncrementalRenderContext()

        viewProvider.lockPool()
        defer { viewProvider.unlockPool() }

        var oldViews: Set<PlatformView> = .init()
        for view in contextViews {
            oldViews.insert(view)

            if let incrementalRenderContext,
               incrementalRenderContext.preservedViewIDs.contains(ObjectIdentifier(view)) {
                continue
            }

            if let view = view as? CodeView {
                viewProvider.stashCodeView(view)
                continue
            }
            if let view = view as? TableView {
                viewProvider.stashTableView(view)
                continue
            }
            assertionFailure()
        }

        viewProvider.reorderViews(matching: contextViews)
        contextViews.removeAll()

        let artifacts: TextBuilder.BuildResult
        if let incrementalRenderContext {
            artifacts = TextBuilder.buildIncremental(
                view: self,
                viewProvider: viewProvider,
                changes: incrementalRenderContext.changes,
                cachedSegments: incrementalRenderContext.cachedSegments
            )
        } else {
            artifacts = TextBuilder.build(
                view: self,
                viewProvider: viewProvider
            )
        }

        textView.attributedText = artifacts.document
        contextViews = artifacts.subviews
        lastRenderedBlocks = document.blocks
        lastBuildResult = artifacts

        for view in artifacts.subviews {
            if let view = view as? CodeView {
                view.textView.delegate = self
            }
        }

        for goneView in oldViews where !artifacts.subviews.contains(goneView) {
            goneView.removeFromSuperview()
        }
    }
}
