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
        /// Any drag event carried the trackpad-touch subtype.
        var isTouchDrag = false
        /// The three-finger-lift grace already applied the layout; the real
        /// (late) mouseUp must not apply again.
        var earlyApplied = false
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
    private var lastDragEventAt: TimeInterval = 0
    private var earlyApplyToken: UInt64 = 0

    // Wired by TidyEngine after construction.
    var startIdentification: (@Sendable (_ generation: UInt64, _ downPoint: QPoint) -> Void)!
    var applyLayout: (@Sendable (_ layout: Layout, _ target: TargetWindow, _ screen: ScreenSnapshot) -> Void)!
    var overlayShow: (@Sendable (_ screenID: CGDirectDisplayID, _ token: UInt64) -> Void)!
    var overlayHideAll: (@Sendable (_ animated: Bool) -> Void)!
    var overlaySetHover: (@Sendable (_ layoutID: UUID?) -> Void)!
    var reenableTap: (@Sendable () -> Void)!
    var emitEvent: (@Sendable (EngineEvent) -> Void)!
    /// Runs a block on the tap thread after a delay (early-apply deadline).
    var scheduleOnTapThread: (@Sendable (_ delay: TimeInterval, _ block: @escaping @Sendable () -> Void) -> Void)!

    init(shared: EngineSharedState) {
        self.shared = shared
    }

    // MARK: - Event entry points (tap thread)

    func handleMouse(_ type: CGEventType, location: QPoint, optionDown flag: Bool, isTouch: Bool) {
        if !loggedFirstEvent {
            loggedFirstEvent = true
            EngineDiagnostics.log("tap: events flowing (first mouse event)")
        }
        shared.cursor.withLock { $0 = location }
        optionDown = flag
        switch type {
        case .leftMouseDown: mouseDown(at: location)
        case .leftMouseDragged:
            lastDragEventAt = ProcessInfo.processInfo.systemUptime
            if isTouch, case .windowDrag(let session) = state { session.isTouchDrag = true }
            mouseDragged(to: location)
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
            earlyApplyToken &+= 1
            state = .idle
            // Hide pads FIRST and instantly — a snappy release is the product.
            overlayHideAll(false)
            defer { emitEvent(.dragEnded) }
            let now = ProcessInfo.processInfo.systemUptime
            let upGap = Int((now - lastDragEventAt) * 1000)
            if session.earlyApplied {
                // The three-finger-lift grace already applied this drop.
                EngineDiagnostics.log("drop: skipped (early-applied) upGap=\(upGap)ms")
                return
            }
            // The RELEASE POINT is ground truth: hit-test the mouseUp location
            // directly (the async view highlight can lag either way). Fall back
            // to the tracked hover, then to a brief sticky window for the
            // release-twitch case, then to the ⌥-release grace.
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
            EngineDiagnostics.log("drop: via=\(via) hovered=\(effectiveHover?.uuidString.prefix(8) ?? "nil") cursor=(\(Int(cursor.x)),\(Int(cursor.y))) upGap=\(upGap)ms cancelled=\(session.cancelled)")
            guard !session.cancelled, let layoutID = effectiveHover else { return }
            applyDrop(session, layoutID: layoutID, via: via)
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
        if session.earlyApplied {
            // Fingers came back during the three-finger-lift grace: the system
            // resumes the drag. Treat it as a fresh live drag — clear the
            // early-apply state so pads and drops work immediately instead of
            // absorbing the whole gesture.
            EngineDiagnostics.log("drag: resumed after early-apply — re-entering live drag")
            session.earlyApplied = false
            session.hoveredLayoutID = nil
            session.recentHover = nil
        }
        // Escape-to-cancel without a keyboard listener: cheap WindowServer poll.
        if !session.cancelled, CGEventSource.keyState(.combinedSessionState, key: 53) {
            session.cancelled = true
            session.hoveredLayoutID = nil
            earlyApplyToken &+= 1
            overlayHideAll(true)
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
            earlyApplyToken &+= 1
            if let newHover, let newHit {
                session.graceHoverID = nil
                session.recentHover = RecentHover(
                    id: newHover, rect: newHit.rectQ,
                    at: ProcessInfo.processInfo.systemUptime)
                // Three-finger drags: the OS delays the synthetic mouseUp for
                // hundreds of ms after the fingers lift. Fingers resting on
                // the trackpad emit continuous micro-tremor events; true
                // silence while hovering means the fingers are OFF — start
                // the silence watch.
                if session.isTouchDrag { armEarlyApply(earlyApplyToken) }
            }
            EngineDiagnostics.log("hover: \(newHover?.uuidString.prefix(8) ?? "nil") cursor=(\(Int(cursor.x)),\(Int(cursor.y))) snapToken=\(snapshot?.token ?? 0) stripToken=\(stripToken)")
            overlaySetHover(newHover)
        }
    }

    // MARK: - Three-finger-lift early apply

    /// Silence long enough to mean "fingers are off the trackpad". Tuned by
    /// feel: 0.2s fired during natural aiming pauses, 0.35s felt sluggish —
    /// 0.3s is the sweet spot, still clearly ahead of the OS's 0.5–0.8s
    /// synthetic mouseUp.
    private static let earlyApplyQuiet: TimeInterval = 0.30

    private func armEarlyApply(_ token: UInt64) {
        scheduleOnTapThread(Self.earlyApplyQuiet + 0.02) { [weak self] in
            self?.earlyApplyCheck(token)
        }
    }

    private func earlyApplyCheck(_ token: UInt64) {
        guard token == earlyApplyToken,
              case .windowDrag(let session) = state,
              session.isTouchDrag, !session.cancelled, !session.earlyApplied,
              session.padsVisible, let hover = session.hoveredLayoutID else { return }
        let quiet = ProcessInfo.processInfo.systemUptime - lastDragEventAt
        if quiet < Self.earlyApplyQuiet {
            // Still trembling — fingers are on the pad; keep watching.
            scheduleOnTapThread(Swift.max(0.05, Self.earlyApplyQuiet + 0.02 - quiet)) { [weak self] in
                self?.earlyApplyCheck(token)
            }
            return
        }
        session.earlyApplied = true
        overlayHideAll(false)
        _ = applyDrop(session, layoutID: hover, via: "early(quiet=\(Int(quiet * 1000))ms)")
        emitEvent(.dragEnded)
    }

    @discardableResult
    private func applyDrop(_ session: Session, layoutID: UUID, via: String) -> Bool {
        let config = shared.configuration.withLock { $0 }
        let screens = shared.screens.withLock { $0 }
        guard let layout = config.layouts.first(where: { $0.id == layoutID }),
              let screen = screens.screen(withID: session.stripScreenID) else {
            EngineDiagnostics.log("drop: layout or screen lookup FAILED")
            return false
        }
        EngineDiagnostics.log("drop: via=\(via) applying '\(layout.name)' on screen=\(screen.displayID)")
        applyLayout(layout, session.target, screen)
        return true
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
            earlyApplyToken &+= 1
            overlayHideAll(true)
        }
    }

    // MARK: - Reset

    /// Unconditional reset from ground truth (physical button state decides
    /// idle vs absorbing-rejected). Always hides overlays — idempotent, cheap.
    private func forceCancel() {
        bumpGeneration()
        pendingRelease = nil
        earlyApplyToken &+= 1
        watchdogIdleMisses = 0
        let buttonDown = CGEventSource.buttonState(.combinedSessionState, button: .left)
        state = buttonDown ? .rejected : .idle
        overlayHideAll(false)
    }

    private func bumpGeneration() {
        generation &+= 1
        shared.resolverGeneration.store(generation, ordering: .relaxed)
    }
}
