//
//  LTXLabel+Reveal.swift
//  Litext
//
//  Streaming "typing" reveal: characters appended to `attributedText` fade in
//  over `streamingRevealDuration` from when they first appear. Driven by a
//  display link so the fade is continuous between content updates and always
//  settles to fully opaque — independent of how chunky the stream is.
//

import CoreText
import Foundation
import QuartzCore

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

/// Shared typewriter cursors keyed by `streamingRevealGroup`. Main-thread only
/// (driven from UIKit/AppKit drawing). A single entry per group; values are wall
/// times that naturally reset to "now" between turns via `max(now, cursor)`.
private var ltxSharedRevealCursors: [String: CFTimeInterval] = [:]

extension LTXLabel {
    /// Returns a per-character alpha closure while a fade is in flight, else nil
    /// (so the draw path falls back to the fast `CTFrameDraw`).
    func revealGlyphAlphaProvider() -> ((Int) -> CGFloat)? {
        guard revealActive, !revealAppearance.isEmpty else { return nil }
        let now = CACurrentMediaTime()
        let duration = max(0.0001, streamingRevealDuration)
        let appearance = revealAppearance
        return { index in
            guard index >= 0, index < appearance.count else { return 1 }
            let elapsed = now - appearance[index]
            if elapsed >= duration { return 1 }
            if elapsed <= 0 { return 0 }
            let t = elapsed / duration
            return 1 - pow(1 - t, 2) // easeOut
        }
    }

    /// Immediately clears any in-flight reveal (e.g. on cell reuse) so a stale
    /// fade never bleeds onto new content.
    public func cancelStreamingReveal() {
        revealAppearance = []
        revealLastText = ""
        revealActive = false
        revealLastStamp = 0
        revealCursor = 0
        stopRevealDriver()
    }

    /// Reference lead (seconds) at which the sweep runs at ~2× to catch up, so a
    /// burst is revealed faster the further the schedule already runs ahead of now
    /// — keeping the lag bounded without hard-snapping later text.
    private var revealCatchUpLead: CFTimeInterval { 0.8 }

    /// The "typewriter" cursor this label schedules from. When `streamingRevealGroup`
    /// is set, the cursor is shared across all labels in that group so their reveals
    /// are sequenced strictly in the order they're appended (block 1, then 2, …) —
    /// giving a single top-to-bottom cascade across many cells rather than each
    /// cell revealing on its own clock. Otherwise it's per-label.
    private var sharedRevealCursor: CFTimeInterval {
        get {
            if let group = streamingRevealGroup { return ltxSharedRevealCursors[group] ?? 0 }
            return revealCursor
        }
        set {
            if let group = streamingRevealGroup { ltxSharedRevealCursors[group] = newValue }
            else { revealCursor = newValue }
        }
    }

    /// Schedule appearance times for newly-appended characters. Instead of stamping
    /// the whole batch at `now` (which fades a chunk in as one block), the batch is
    /// spread left→right at `streamingRevealCharactersPerSecond`, continuing from
    /// the (possibly shared) cursor so the sweep stays continuous and ordered.
    func handleRevealTextChange() {
        guard streamingReveal else {
            // Keep a fade that's still settling so it finishes smoothly when
            // streaming ends; only clear once it has gone idle.
            if !revealActive, !revealAppearance.isEmpty {
                revealAppearance = []
                revealLastText = ""
                stopRevealDriver()
            }
            return
        }

        // Preserve stamps only for the leading run that's unchanged from the last
        // render. Rendered markdown restructures mid-string (a closed inline span
        // strips its syntax, shifting later characters), so anything from the first
        // divergence must be re-stamped — keeping those stamps by index misaligns
        // the fade into mid-paragraph holes.
        let oldText = revealLastText as NSString
        let newText = attributedText.string as NSString
        let newLength = newText.length
        let compareLimit = min(oldText.length, newText.length)
        var commonPrefix = 0
        while commonPrefix < compareLimit,
              oldText.character(at: commonPrefix) == newText.character(at: commonPrefix) {
            commonPrefix += 1
        }
        revealLastText = attributedText.string

        if commonPrefix < revealAppearance.count {
            revealAppearance = Array(revealAppearance.prefix(commonPrefix))
        }
        // Nothing new past the preserved prefix (pure shrink / restyle).
        guard newLength > revealAppearance.count else { return }

        let now = CACurrentMediaTime()
        let count = newLength - revealAppearance.count
        let baseInterval = streamingRevealCharactersPerSecond > 0
            ? 1.0 / CFTimeInterval(streamingRevealCharactersPerSecond)
            : 0

        // Continue from the cursor (shared across the group → ordered cascade),
        // never starting in the past.
        let start = max(now, sharedRevealCursor)
        // Sweep faster the further the schedule already leads `now`, so a burst
        // catches up instead of lagging — without hard-snapping later text.
        let lead = max(0, start - now)
        let interval = baseInterval / (1 + lead / revealCatchUpLead)

        revealAppearance.reserveCapacity(newLength)
        for index in 0 ..< count {
            revealAppearance.append(start + CFTimeInterval(index) * interval)
        }
        sharedRevealCursor = start + CFTimeInterval(count) * interval
        revealLastStamp = start + CFTimeInterval(max(0, count - 1)) * interval
        revealActive = true
        startRevealDriver()
        setNeedsDisplayForReveal()
    }

    func handleStreamingRevealChanged() {
        if streamingReveal {
            // Fade in whatever is already present at the moment streaming begins.
            handleRevealTextChange()
        } else if !revealActive {
            stopRevealDriver()
        }
        // When turning off mid-fade, the driver keeps running until the last
        // stamp settles, then finalizes in `stepReveal`.
    }

    @objc func stepReveal() {
        setNeedsDisplayForReveal()
        let now = CACurrentMediaTime()
        if now >= revealLastStamp + streamingRevealDuration {
            // Settle: switch to the opaque fast path (driven by `revealActive`),
            // but KEEP the appearance stamps. Streaming UIs commonly re-emit an
            // already-finished block unchanged on later chunks; if we cleared the
            // stamps here, that same-length re-emission would look "new" and
            // re-fade a block that already settled. Stamps are only cleared on a
            // real shrink/reset (`handleRevealTextChange`) or `cancelStreamingReveal`.
            revealActive = false
            stopRevealDriver()
            setNeedsDisplayForReveal() // final fully-opaque pass (fast path)
        }
    }

    private func setNeedsDisplayForReveal() {
        #if canImport(UIKit)
            setNeedsDisplay()
        #elseif canImport(AppKit)
            needsDisplay = true
        #endif
    }

    #if canImport(UIKit)
        func startRevealDriver() {
            guard revealDisplayLink == nil else { return }
            let link = CADisplayLink(target: self, selector: #selector(stepReveal))
            link.add(to: .main, forMode: .common)
            revealDisplayLink = link
        }

        func stopRevealDriver() {
            revealDisplayLink?.invalidate()
            revealDisplayLink = nil
        }
    #else
        func startRevealDriver() {
            guard revealTimer == nil else { return }
            let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                self?.stepReveal()
            }
            RunLoop.main.add(timer, forMode: .common)
            revealTimer = timer
        }

        func stopRevealDriver() {
            revealTimer?.invalidate()
            revealTimer = nil
        }
    #endif
}
