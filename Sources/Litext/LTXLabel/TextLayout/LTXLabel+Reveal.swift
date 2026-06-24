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
        revealActive = false
        revealLastStamp = 0
        revealCursor = 0
        stopRevealDriver()
    }

    /// How far ahead of "now" the reveal schedule is allowed to run, so a fast
    /// stream can't make the sweep lag indefinitely (it compresses to keep up).
    private var revealMaxLeadTime: CFTimeInterval { 0.6 }

    /// Schedule appearance times for newly-appended characters. Instead of stamping
    /// the whole batch at `now` (which fades a chunk in as one block), the batch is
    /// spread left→right at `streamingRevealCharactersPerSecond`, continuing from
    /// where the previous batch left off so the sweep stays continuous. The
    /// schedule is capped at `revealMaxLeadTime` ahead of now to bound the lag.
    func handleRevealTextChange() {
        guard streamingReveal else {
            // Keep a fade that's still settling so it finishes smoothly when
            // streaming ends; only clear once it has gone idle.
            if !revealActive, !revealAppearance.isEmpty {
                revealAppearance = []
                stopRevealDriver()
            }
            return
        }

        let newLength = attributedText.length
        guard newLength != revealAppearance.count else { return }

        if newLength < revealAppearance.count {
            // Content shrank (reset / re-render) — drop stale stamps.
            revealAppearance = Array(revealAppearance.prefix(newLength))
            return
        }

        let now = CACurrentMediaTime()
        let count = newLength - revealAppearance.count
        let baseInterval = streamingRevealCharactersPerSecond > 0
            ? 1.0 / CFTimeInterval(streamingRevealCharactersPerSecond)
            : 0

        // Continue the typewriter from the cursor, but never start in the past.
        var start = max(now, revealCursor)
        // Cap how far ahead the batch may finish; compress the spacing if the
        // batch is large so the reveal keeps up with the incoming stream.
        let deadline = now + revealMaxLeadTime
        var interval = baseInterval
        if start > deadline {
            start = deadline
            interval = 0
        } else if start + CFTimeInterval(count) * baseInterval > deadline {
            interval = max(0, (deadline - start) / CFTimeInterval(count))
        }

        revealAppearance.reserveCapacity(newLength)
        for index in 0 ..< count {
            revealAppearance.append(start + CFTimeInterval(index) * interval)
        }
        revealCursor = start + CFTimeInterval(count) * interval
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
