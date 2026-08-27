import Foundation
import CoreGraphics
import TinyWindowCore

/// The drag state machine. STRICTLY tap-thread-confined: every entry point runs
/// on the tap thread (mouse/flag events arrive there; resolver results and
/// watchdog checks hop in via EventTapService.perform). All outward effects go
/// through injected @Sendable closures.
final class DragSessionController: @unchecked Sendable {
    private enum State {
        case idle
        /// Button down, waiting to cross the minimum drag distance.
        case pressed(down: QPoint)
        /// Threshold crossed; WindowResolver is working on the axQueue.
        case identifying(down: QPoint)
        case windowDrag(Session)
        /// Absorbing: this button press was judged not-a-window-drag (or was
        /// force-cancelled). Silent until mouse up.
        case rejected
    }

    private struct RecentHover {
        let id: UUID
        let rect: QRect
        let at: TimeInterval
    }

    private final class Session {
        let target: TargetWindow
        var stripScreenID: CGDirectDisplayID
        var hoveredLayoutID: UUID?
        var padsVisible = false
        var cancelled = false
        /// Releasing the mouse often twitches the cursor a few px off a small
        /// region right before mouseUp — remember the last real hover briefly
        /// so the drop the user SAW highlighted still lands.
        var recentHover: RecentHover?
        /// holdOptionToShow only: users release ⌥ a beat before the mouse.
        /// Remember the hover through that gap so the drop still lands.
        var graceHoverID: UUID?
        var graceUntil: TimeInterval = 0

        init(target: TargetWindow, stripScreenID: CGDirectDisplayID) {
            self.target = target
            self.stripScreenID = stripScreenID
        }
    }

    private let shared: EngineSharedState
    /// A mouse-up that beat identification: the resolver keeps running (it
    /// finalizes immediately on button-up) and a confirm landing within the
    /// window still applies at the remembered release point.
    private struct PendingRelease {
        let cursor: QPoint
        let at: TimeInterval
        let generation: UInt64
    }

    private var state: State = .idle
    private var generation: UInt64 = 0
    private var stripToken: UInt64 = 0
    private var optionDown = false
    private var watchdogIdleMisses = 0
    private var loggedFirstEvent = false
    private var pendingRelease: PendingRelease?

    // Wired by TidyEngine after construction.
    var startIdentification: (@Sendable (_ generation: UInt64, _ downPoint: QPoint) -> Void)!
    var applyLayout: (@Sendable (_ layout: Layout, _ target: TargetWindow, _ screen: ScreenSnapshot) -> Void)!
    var overlayShow: (@Sendable (_ screenID: CGDirectDisplayID, _ token: UInt64) -> Void)!
    var overlayHideAll: (@Sendable () -> Void)!
    var overlaySetHover: (@Sendable (_ layoutID: UUID?) -> Void)!
    var reenableTap: (@Sendable () -> Void)!
    var emitEvent: (@Sendable (EngineEvent) -> Void)!

    init(shared: EngineSharedState) {
        self.shared = shared
    }

    // MARK: - Event entry points (tap thread)

    func handleMouse(_ type: CGEventType, location: QPoint, optionDown flag: Bool) {
        if !loggedFirstEvent {
            loggedFirstEvent = true
            EngineDiagnostics.log("tap: events flowing (first mouse event)")
        }
        shared.cursor.withLock { $0 = location }
        optionDown = flag
        switch type {
        case .leftMouseDown: mouseDown(at: location)
        case .leftMouseDragged: mouseDragged(to: location)
        case .leftMouseUp: mouseUp()
        default: break
        }
    }

    func tapWasDisabled() {
        reenableTap()
        // A mouseUp may have been swallowed during the gap — reset from ground truth.
        forceCancel()
    }

    /// Delivered on the tap thread every ~2 s by the watchdog.
    func watchdogCheck(buttonUp: Bool) {
        if case .idle = state {
            watchdogIdleMisses = 0
            return
        }
        if buttonUp {
            watchdogIdleMisses += 1
            if watchdogIdleMisses >= 2 { forceCancel() }
        } else {
            watchdogIdleMisses = 0
        }
    }

    /// Display configuration changed mid-session: cancel, safety first.
    func screensChanged() {
        if case .idle = state { return }
        forceCancel()
    }

    /// Resolver verdict, delivered on the tap thread.
    func resolved(_ gen: UInt64, verdict: ResolveVerdict) {
        if case .identifying = state, gen == generation {
            switch verdict {
            case .rejected:
                state = .rejected
            case .confirmed(let target):
                let screens = shared.screens.withLock { $0 }
                let cursor = shared.cursor.withLock { $0 }
                guard let screen = screens.screen(containing: cursor) else {
                    state = .rejected
                    return
                }
                let session = Session(target: target, stripScreenID: screen.displayID)
                state = .windowDrag(session)
                emitEvent(.dragBegan)
                updatePadVisibility(session)
            }
            return
        }
        // Retroactive path: the confirm landed just after a fast-flick release.
        guard let pending = pendingRelease, pending.generation == gen else { return }
        pendingRelease = nil
        guard case .confirmed(let target) = verdict,
              ProcessInfo.processInfo.systemUptime - pending.at < 0.30 else { return }
        retroApply(target: target, at: pending.cursor)
    }

    /// Applies a layout for a release that happened before pads ever showed —
    /// the pad band's position is fixed per screen, so power users throw
    /// windows at it from muscle memory. Only fires when the release point
    /// actually lands inside a pad.
    private func retroApply(target: TargetWindow, at point: QPoint) {
        let config = shared.configuration.withLock { $0 }
        guard config.settings.enabled else { return }
        // Respect the visibility mode: never surprise-apply while the pads
        // would have been hidden.
        switch config.settings.padVisibilityMode {
        case .holdOptionToShow: if !optionDown { return }
        case .optionHides: if optionDown { return }
        case .always: break
        }
        let screens = shared.screens.withLock { $0 }
        guard let screen = screens.screen(containing: point) else { return }
        let primaryHeight = CoordinateSpace.primaryHeight(cocoaScreenFrames: screens.map(\.frameC))
        guard let geometry = PadStripGeometry.compute(
                layouts: config.layouts, settings: config.settings,
                screen: screen, primaryHeight: primaryHeight),
              let hit = layoutHit(in: geometry.hitGroups, at: point),
              let layout = config.layouts.first(where: { $0.id == hit.layoutID })
        else {
            EngineDiagnostics.log("drop: retro release missed pads at (\(Int(point.x)),\(Int(point.y)))")
            return
        }
        EngineDiagnostics.log("drop: via=retro applying '\(layout.name)' on screen=\(screen.displayID)")
        applyLayout(layout, target, screen)
        emitEvent(.dragEnded)
    }

    // MARK: - Mouse handling

    private func mouseDown(at point: QPoint) {
        pendingRelease = nil
        if case .idle = state {} else {
            // Spurious duplicate mouseDown — reset, then begin normally.
            forceCancel()
        }
        guard shared.configuration.withLock({ $0.settings.enabled }) else {
            state = .rejected
            return
        }
        state = .pressed(down: point)
    }

    private func mouseDragged(to point: QPoint) {
        switch state {
        case .pressed(let down):
            let threshold = CGFloat(max(4, shared.configuration.withLock { $0.settings.minimumDragDistance }))
            if point.distance(to: down) >= threshold {
                bumpGeneration()
                state = .identifying(down: down)
                startIdentification(generation, down)
            }
        case .windowDrag(let session):
            dragMoved(session, cursor: point)
        case .idle, .identifying, .rejected:
            break
        }
    }

    private func mouseUp() {
        watchdogIdleMisses = 0
        switch state {
        case .windowDrag(let session):
            state = .idle
            // Hide pads FIRST, in this same turn — a slow AX write must never
            // pin overlay state.
            overlayHideAll()
            defer { emitEvent(.dragEnded) }
            // The RELEASE POINT is ground truth: hit-test the mouseUp location
            // directly (the async view highlight can lag either way). Fall back
            // to the tracked hover, then to a brief sticky window for the
            // release-twitch case, then to the ⌥-release grace.
            let now = ProcessInfo.processInfo.systemUptime
            let cursor = shared.cursor.withLock { $0 }
            let snapshot = shared.padHits.withLock { $0 }
            var effectiveHover: UUID?
            var via = "none"
            if session.padsVisible, !session.cancelled {
                if let snapshot, snapshot.token == stripToken,
                   snapshot.screenID == session.stripScreenID,
                   let direct = snapshot.layoutHit(at: cursor)?.layoutID {
                    effectiveHover = direct
                    via = "direct"
                } else if let hovered = session.hoveredLayoutID {
                    effectiveHover = hovered
                    via = "session"
                } else if let recent = session.recentHover,
                          now - recent.at < 0.35,
                          recent.rect.insetBy(dx: -40, dy: -40).contains(cursor) {
                    effectiveHover = recent.id
                    via = "recent"
                }
            }
            if effectiveHover == nil, !session.cancelled,
               now < session.graceUntil, let grace = session.graceHoverID {
                effectiveHover = grace
                via = "optionGrace"
            }
            EngineDiagnostics.log("drop: via=\(via) hovered=\(effectiveHover?.uuidString.prefix(8) ?? "nil") cursor=(\(Int(cursor.x)),\(Int(cursor.y))) cancelled=\(session.cancelled)")
            guard !session.cancelled, let layoutID = effectiveHover else { return }
            let config = shared.configuration.withLock { $0 }
            let screens = shared.screens.withLock { $0 }
            guard let layout = config.layouts.first(where: { $0.id == layoutID }),
                  let screen = screens.screen(withID: session.stripScreenID) else {
                EngineDiagnostics.log("drop: layout or screen lookup FAILED")
                return
            }
            EngineDiagnostics.log("drop: applying '\(layout.name)' on screen=\(screen.displayID)")
            applyLayout(layout, session.target, screen)
        case .identifying:
            // Fast flick: released before identification completed. Keep the
            // resolver alive (it finalizes on button-up) — a confirm within
            // 0.3s still applies at this release point.
            pendingRelease = PendingRelease(
                cursor: shared.cursor.withLock { $0 },
                at: ProcessInfo.processInfo.systemUptime,
                generation: generation)
            state = .idle
        case .pressed, .rejected:
            state = .idle
        case .idle:
            break
        }
    }

    private func dragMoved(_ session: Session, cursor: QPoint) {
        // Escape-to-cancel without a keyboard listener: cheap WindowServer poll.
        if !session.cancelled, CGEventSource.keyState(.combinedSessionState, key: 53) {
            session.cancelled = true
            session.hoveredLayoutID = nil
            overlayHideAll()
            return
        }
        guard !session.cancelled else { return }

        // The tap is mouse-only (no flagsChanged — that's a keyboard-class
        // event with its own permission gate), so refresh ⌥ from a cheap
        // WindowServer state poll; a stationary press registers on the next
        // pointer twitch, same as Escape.
        optionDown = CGEventSource.flagsState(.combinedSessionState).contains(.maskAlternate)
        updatePadVisibility(session)

        let screens = shared.screens.withLock { $0 }
        if let screen = screens.screen(containing: cursor), screen.displayID != session.stripScreenID {
            session.stripScreenID = screen.displayID
            session.hoveredLayoutID = nil
            if session.padsVisible {
                stripToken &+= 1
                overlayShow(screen.displayID, stripToken)
            }
        }
        refreshHover(session, cursor: cursor)
    }

    private func refreshHover(_ session: Session, cursor: QPoint) {
        guard session.padsVisible, !session.cancelled else { return }
        let snapshot = shared.padHits.withLock { $0 }
        var newHit: PadHit?
        if let snapshot, snapshot.token == stripToken, snapshot.screenID == session.stripScreenID {
            newHit = snapshot.layoutHit(at: cursor)
        }
        let newHover = newHit?.layoutID
        if newHover != session.hoveredLayoutID {
            session.hoveredLayoutID = newHover
            if let newHover, let newHit {
                session.graceHoverID = nil
                session.recentHover = RecentHover(
                    id: newHover, rect: newHit.rectQ,
                    at: ProcessInfo.processInfo.systemUptime)
            }
            EngineDiagnostics.log("hover: \(newHover?.uuidString.prefix(8) ?? "nil") cursor=(\(Int(cursor.x)),\(Int(cursor.y))) snapToken=\(snapshot?.token ?? 0) stripToken=\(stripToken)")
            overlaySetHover(newHover)
        }
    }

    private func updatePadVisibility(_ session: Session) {
        let mode = shared.configuration.withLock { $0.settings.padVisibilityMode }
        let shouldShow: Bool
        switch mode {
        case .always: shouldShow = true
        case .holdOptionToShow: shouldShow = optionDown
        case .optionHides: shouldShow = !optionDown
        }
        guard shouldShow != session.padsVisible else { return }
        session.padsVisible = shouldShow
        if shouldShow {
            session.graceHoverID = nil
            stripToken &+= 1
            EngineDiagnostics.log("pads: show screen=\(session.stripScreenID) token=\(stripToken)")
            overlayShow(session.stripScreenID, stripToken)
        } else {
            // In holdOptionToShow, hiding means "⌥ released" — likely the
            // start of a simultaneous release, not a cancel. Keep the hover
            // alive briefly. In optionHides, pressing ⌥ IS the cancel gesture.
            if mode == .holdOptionToShow, let hovered = session.hoveredLayoutID {
                session.graceHoverID = hovered
                session.graceUntil = ProcessInfo.processInfo.systemUptime + 0.4
            }
            EngineDiagnostics.log("pads: hide mode=\(mode.rawValue) grace=\(session.graceHoverID?.uuidString.prefix(8) ?? "nil")")
            session.hoveredLayoutID = nil
            overlayHideAll()
        }
    }

    // MARK: - Reset

    /// Unconditional reset from ground truth (physical button state decides
    /// idle vs absorbing-rejected). Always hides overlays — idempotent, cheap.
    private func forceCancel() {
        bumpGeneration()
        pendingRelease = nil
        watchdogIdleMisses = 0
        let buttonDown = CGEventSource.buttonState(.combinedSessionState, button: .left)
        state = buttonDown ? .rejected : .idle
        overlayHideAll()
    }

    private func bumpGeneration() {
        generation &+= 1
        shared.resolverGeneration.store(generation, ordering: .relaxed)
    }
}
