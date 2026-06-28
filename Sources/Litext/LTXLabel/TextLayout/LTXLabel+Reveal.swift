//
//  LTXLabel+Reveal.swift
//  Litext
//
//  Streaming "typing" reveal. A monotonic "frontier" (a fractional character
//  position) advances left→right over time; each character's alpha is purely a
//  function of its index vs the frontier. Because alpha depends only on the index
//  and a forward-only counter — never on per-index timestamps captured at append
//  time — the fade is immune to the rendered markdown restructuring mid-stream
//  (a closed inline span stripping its `` ` ``/`*` syntax shifts later characters):
//  already-passed indices stay opaque, the frontier keeps sweeping, no holes.
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
        guard revealActive else { return nil }
        let frontier = revealFrontier
        let fade = fadeWindowChars
        return { index in
            let pos = Double(index)
            if pos <= frontier - fade { return 1 }
            if pos >= frontier { return 0 }
            let t = (frontier - pos) / fade
            return 1 - pow(1 - t, 2) // easeOut
        }
    }

    /// Seeds the reveal frontier (character position already swept) so a recycled
    /// cell continues an in-progress reveal instead of restarting from zero. Only
    /// advances forward — a stale seed never pulls the frontier backward.
    public func seedStreamingRevealFrontier(_ position: Double) {
        revealFrontier = max(revealFrontier, position)
    }

    /// Immediately clears any in-flight reveal (e.g. on cell reuse) so a stale
    /// fade never bleeds onto new content.
    public func cancelStreamingReveal() {
        revealFrontier = 0
        revealFrontierTime = 0
        revealActive = false
        stopRevealDriver()
    }

    /// Width of the soft fade edge, in characters. A character spends
    /// `fadeWindowChars / charactersPerSecond` ≈ `streamingRevealDuration` seconds
    /// ramping from 0→1 as the frontier passes over it.
    private var fadeWindowChars: Double {
        max(1, Double(streamingRevealCharactersPerSecond) * max(0.0001, streamingRevealDuration))
    }

    /// How far behind the live length (in characters) the frontier sweeps at ~2×,
    /// so a bursty arrival catches up instead of lagging.
    private var revealCatchUpChars: Double { 240 }

    /// Content changed. The frontier is a character count independent of content,
    /// so there are no per-index stamps to re-align — just keep the driver running
    /// while there's still text (plus the trailing fade window) left to reveal.
    func handleRevealTextChange() {
        guard streamingReveal else {
            // Let an in-flight fade finish; only stop once it has settled.
            if !revealActive { stopRevealDriver() }
            return
        }

        let length = Double(attributedText.length)
        // Text shrank below the frontier (reset / large re-render) — clamp so the
        // frontier never sits past the end.
        if revealFrontier > length { revealFrontier = length }

        // A large atomic arrival (a whole block in one chunk, not char-by-char
        // streaming) would leave the frontier far behind, blanking the new block and
        // sweeping it from zero over a second-plus. Cap how far it may trail the live
        // length so a burst snaps the bulk opaque and fades only the trailing window.
        // Forward-only and only when streaming, so it never disturbs settled text or
        // an in-progress fine-grained fade (which never lags this far).
        let maxLag = fadeWindowChars + streamingRevealMaxLagCharacters
        if length - revealFrontier > maxLag {
            revealFrontier = length - maxLag
        }

        guard revealFrontier < length + fadeWindowChars else { return }
        if revealFrontierTime == 0 { revealFrontierTime = CACurrentMediaTime() }
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
        // Turning off mid-fade: the driver keeps running until the frontier settles.
    }

    @objc func stepReveal() {
        advanceFrontier()
        setNeedsDisplayForReveal()
        // Settle once the frontier has passed the end by the fade window, so the
        // last characters finish ramping to opaque.
        if revealFrontier >= Double(attributedText.length) + fadeWindowChars {
            revealActive = false
            revealFrontierTime = 0
            stopRevealDriver()
            setNeedsDisplayForReveal() // final fully-opaque pass (fast path)
        }
    }

    /// Move the frontier toward the live length at the reveal rate, sweeping faster
    /// the further it trails the current text so a burst doesn't lag.
    private func advanceFrontier() {
        let now = CACurrentMediaTime()
        let last = revealFrontierTime == 0 ? now : revealFrontierTime
        revealFrontierTime = now
        let dt = max(0, now - last)
        let cps = max(1, Double(streamingRevealCharactersPerSecond))
        let length = Double(attributedText.length)
        let behind = max(0, length - revealFrontier)
        let speed = cps * (1 + behind / revealCatchUpChars)
        revealFrontier = min(length + fadeWindowChars, revealFrontier + dt * speed)
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
