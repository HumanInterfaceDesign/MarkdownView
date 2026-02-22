//
//  LTXLabel+Interaction.swift
//  Litext
//
//  Created by 秋星桥 on 3/26/25.
//

import Foundation

private let kMinimalDistanceToMove: CGFloat = 3.0
private let kMultiClickTimeThreshold: TimeInterval = 0.25
private let kLongPressDelay: TimeInterval = 0.5

extension LTXLabel {
    func setInteractionStateToBegin(initialLocation: CGPoint) {
        interactionState.initialTouchLocation = initialLocation
        interactionState.isFirstMove = true
        isInteractionInProgress = true
    }

    func bumpClickCountIfWithinTimeGap() {
        let currentTime = Date().timeIntervalSince1970
        let isContinuousClick = currentTime - interactionState.lastClickTime <= kMultiClickTimeThreshold
        interactionState.lastClickTime = currentTime
        if isContinuousClick {
            interactionState.clickCount += 1
        }
        scheduleContinuousStateReset()
    }

    func scheduleContinuousStateReset() {
        NSObject.cancelPreviousPerformRequests(
            withTarget: self,
            selector: #selector(performContinuousStateReset),
            object: nil
        )
        perform(
            #selector(performContinuousStateReset),
            with: nil,
            afterDelay: kMultiClickTimeThreshold
        )
    }

    @objc func performContinuousStateReset() {
        interactionState.clickCount = 1
        interactionState.lastClickTime = 0
    }

    func isTouchReallyMoved(_ point: CGPoint) -> Bool {
        let distance = hypot(
            point.x - interactionState.initialTouchLocation.x,
            point.y - interactionState.initialTouchLocation.y
        )
        return distance > 3
    }

    // MARK: - Long Press

    func cancelLongPressTimer() {
        interactionState.longPressWorkItem?.cancel()
        interactionState.longPressWorkItem = nil
        #if canImport(UIKit) && !os(tvOS) && !os(watchOS)
            interactionState.feedbackGenerator = nil
        #endif
    }

    #if canImport(UIKit) && !os(tvOS) && !os(watchOS)
        func scheduleLongPressTimer(at point: CGPoint) {
            guard isSelectable, longPressSelectsWord else { return }
            cancelLongPressTimer()

            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.prepare()
            interactionState.feedbackGenerator = generator

            let workItem = DispatchWorkItem { [weak self] in
                self?.handleLongPress(at: point)
            }
            interactionState.longPressWorkItem = workItem
            DispatchQueue.main.asyncAfter(
                deadline: .now() + kLongPressDelay,
                execute: workItem
            )
        }

        private func handleLongPress(at point: CGPoint) {
            guard highlightRegionAtPoint(point) == nil else {
                cancelLongPressTimer()
                return
            }
            guard let index = textIndexAtPoint(point) else { return }
            selectWordAtIndex(index)
            interactionState.feedbackGenerator?.impactOccurred()
            interactionState.feedbackGenerator = nil
            DispatchQueue.main.async {
                self.showSelectionMenuController()
            }
        }
    #endif
}
