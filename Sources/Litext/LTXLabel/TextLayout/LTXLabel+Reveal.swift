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

// MARK: - Group reveal coordination
//
// Labels sharing a `streamingRevealGroup` reveal as one top-to-bottom cascade:
// only the topmost label whose reveal isn't complete advances its frontier; the
// rest stay hidden until their turn. Composes a response split across several
// labels/cells into one continuous stream.

private struct LTXWeakLabel {
    weak var label: LTXLabel?
}

private final class LTXRevealGroupRegistry {
    static let shared = LTXRevealGroupRegistry()
    private var groups: [String: [LTXWeakLabel]] = [:]

    func add(_ label: LTXLabel, to group: String) {
        var members = (groups[group] ?? []).filter { $0.label != nil }
        if !members.contains(where: { $0.label === label }) {
            members.append(LTXWeakLabel(label: label))
        }
        groups[group] = members
    }

    func remove(_ label: LTXLabel, from group: String) {
        guard let existing = groups[group] else { return }
        let members = existing.filter { $0.label != nil && $0.label !== label }
        groups[group] = members.isEmpty ? nil : members
    }

    func members(of group: String) -> [LTXLabel] {
        (groups[group] ?? []).compactMap(\.label)
    }
}

public extension Notification.Name {
    /// Posted on the main thread whenever a label in a streaming-reveal group settles
    /// (its frontier reaches the end). `userInfo["group"]` is the group key. A
    /// follower can re-check `isStreamingRevealActive(inGroup:aboveY:)` on each post
    /// to fade in as soon as the reveals above it finish — without waiting for cells
    /// below it.
    static let ltxStreamingRevealGroupDidAdvance = Notification.Name("LTXStreamingRevealGroupDidAdvance")
}

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
        if let group = streamingRevealGroup {
            LTXRevealGroupRegistry.shared.remove(self, from: group)
            postRevealGroupDidAdvance()
        }
    }

    /// Joins/leaves the group registry when `streamingRevealGroup` changes (called
    /// from the property's `didSet`).
    func revealGroupDidChange(from oldGroup: String?) {
        if let oldGroup {
            LTXRevealGroupRegistry.shared.remove(self, from: oldGroup)
        }
        if let group = streamingRevealGroup {
            LTXRevealGroupRegistry.shared.add(self, to: group)
        }
    }

    /// True while any label in `group` is still fading or waiting its turn.
    public static func isStreamingRevealActive(inGroup group: String) -> Bool {
        LTXRevealGroupRegistry.shared.members(of: group).contains { $0.revealActive }
    }

    /// True while any label in `group` positioned *above* `threshold` (in window
    /// coordinates) is still revealing. A following view uses this to fade in once
    /// the reveals above it finish, without waiting for cells below it.
    public static func isStreamingRevealActive(inGroup group: String, aboveY threshold: CGFloat) -> Bool {
        LTXRevealGroupRegistry.shared.members(of: group).contains { $0.revealActive && $0.revealWindowY < threshold }
    }

    /// Order-based counterpart to `isStreamingRevealActive(inGroup:aboveY:)`. True
    /// while any label in `group` whose `streamingRevealOrder` is earlier than
    /// `threshold` is still revealing. A following view (e.g. a card between text
    /// blocks) passes its own document-order key to fade in once the reveals above it
    /// finish — without depending on window geometry, so it stays correct while
    /// scrolling or when the revealing member is partly off-screen. Members with no
    /// `streamingRevealOrder` set are ignored by this query.
    public static func isStreamingRevealActive(inGroup group: String, aboveOrder threshold: Int) -> Bool {
        LTXRevealGroupRegistry.shared.members(of: group).contains { member in
            guard member.revealActive, let order = member.streamingRevealOrder else { return false }
            return order < threshold
        }
    }

    /// A member stops blocking the cascade once it has nothing left to reveal:
    /// empty, not animating, or its frontier has swept past the end.
    private var isRevealComplete: Bool {
        let length = Double(attributedText.length)
        if length == 0 { return true }
        if !streamingReveal, !revealActive { return true }
        return revealFrontier >= length + fadeWindowChars
    }

    /// Within a group, only the topmost label whose reveal isn't complete may
    /// advance; the rest wait. No group → always active. "Topmost" is decided by
    /// `revealSortKey` — the document-order key when set, else window geometry.
    private var isActiveRevealMember: Bool {
        guard let group = streamingRevealGroup else { return true }
        let members = LTXRevealGroupRegistry.shared.members(of: group)
            .sorted { $0.revealSortKey < $1.revealSortKey }
        for member in members {
            if member === self { return true }
            if !member.isRevealComplete { return false }
        }
        return true
    }

    /// Cascade ordering key. Prefers the caller-supplied document order
    /// (`streamingRevealOrder`) so sequencing is stable regardless of layout state;
    /// falls back to live window geometry when no order is set. The two are kept in
    /// disjoint numeric ranges (geometry is offset far above any realistic index) so
    /// a group that mixes ordered and unordered members still sorts deterministically
    /// — ordered members first, in order, then unordered by position.
    private var revealSortKey: Double {
        if let order = streamingRevealOrder { return Double(order) }
        return 1_000_000 + Double(revealWindowY)
    }

    private var revealWindowY: CGFloat {
        convert(bounds.origin, to: nil).y
    }

    /// Posts `.ltxStreamingRevealGroupDidAdvance` so followers can re-check whether
    /// the reveals above them have finished. Fires on every settle, not only when the
    /// whole group goes idle, so a card above a still-revealing cell isn't blocked.
    private func postRevealGroupDidAdvance() {
        guard let group = streamingRevealGroup else { return }
        NotificationCenter.default.post(
            name: .ltxStreamingRevealGroupDidAdvance,
            object: nil,
            userInfo: ["group": group]
        )
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

        // Grouped and not our turn yet: stay fully hidden (frontier 0) until the
        // labels above us finish, but keep the driver alive so we start on our turn.
        if streamingRevealGroup != nil, !isActiveRevealMember {
            revealFrontier = 0
            revealFrontierTime = 0
            revealActive = true
            startRevealDriver()
            setNeedsDisplayForReveal()
            return
        }

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
            if let group = streamingRevealGroup {
                LTXRevealGroupRegistry.shared.add(self, to: group)
            }
            // Fade in whatever is already present at the moment streaming begins.
            handleRevealTextChange()
        } else if !revealActive {
            // Streaming turned off with nothing in flight — already opaque.
            stopRevealDriver()
            onStreamingRevealComplete?()
            postRevealGroupDidAdvance()
        }
        // Turning off mid-fade — whether actively fading or still waiting our turn in
        // a group — keeps the driver running so the cascade finishes revealing this
        // label in turn. Never snap a not-yet-revealed label straight to opaque: the
        // stream ending before the cascade reaches the last cell would otherwise read
        // as a jarring static pop.
    }

    @objc func stepReveal() {
        // Grouped and not our turn: stay hidden, keep the driver alive, don't advance.
        if streamingRevealGroup != nil, !isActiveRevealMember {
            if revealFrontier != 0 || revealFrontierTime != 0 {
                revealFrontier = 0
                revealFrontierTime = 0
                setNeedsDisplayForReveal()
            }
            return
        }
        advanceFrontier()
        setNeedsDisplayForReveal()
        // Settle once the frontier has passed the end by the fade window, so the
        // last characters finish ramping to opaque.
        if revealFrontier >= Double(attributedText.length) + fadeWindowChars {
            revealActive = false
            revealFrontierTime = 0
            stopRevealDriver()
            setNeedsDisplayForReveal() // final fully-opaque pass (fast path)
            // Only a settle *after* the stream finished is a true completion; a
            // mid-stream pause that catches the frontier up keeps streaming.
            if !streamingReveal { onStreamingRevealComplete?() }
            postRevealGroupDidAdvance()
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
