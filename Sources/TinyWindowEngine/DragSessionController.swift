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

    private final class Session {
        let target: TargetWindow
        var stripScreenID: CGDirectDisplayID
        var hoveredLayoutID: UUID?
        var padsVisible = false
        var cancelled = false

        init(target: TargetWindow, stripScreenID: CGDirectDisplayID) {
            self.target = target
            self.stripScreenID = stripScreenID
        }
    }

    private let shared: EngineSharedState
    private var state: State = .idle
    private var generation: UInt64 = 0
    private var stripToken: UInt64 = 0
    private var optionDown = false
    private var watchdogIdleMisses = 0

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
        shared.cursor.withLock { $0 = location }
        optionDown = flag
        switch type {
        case .leftMouseDown: mouseDown(at: location)
        case .leftMouseDragged: mouseDragged(to: location)
        case .leftMouseUp: mouseUp()
        default: break
        }
    }

    func optionChanged(_ down: Bool) {
        optionDown = down
        if case .windowDrag(let session) = state, !session.cancelled {
            updatePadVisibility(session)
            refreshHover(session, cursor: shared.cursor.withLock { $0 })
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
        guard case .identifying = state, gen == generation else { return }
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
    }

    // MARK: - Mouse handling

    private func mouseDown(at point: QPoint) {
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
            guard !session.cancelled, session.padsVisible,
                  let layoutID = session.hoveredLayoutID else { return }
            let config = shared.configuration.withLock { $0 }
            let screens = shared.screens.withLock { $0 }
            guard let layout = config.layouts.first(where: { $0.id == layoutID }),
                  let screen = screens.screen(withID: session.stripScreenID) else { return }
            applyLayout(layout, session.target, screen)
        case .identifying:
            bumpGeneration() // drop the in-flight resolver result
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
        var newHover: UUID?
        if let snapshot, snapshot.token == stripToken, snapshot.screenID == session.stripScreenID {
            newHover = snapshot.pads.first { $0.rectQ.contains(cursor) }?.layoutID
        }
        if newHover != session.hoveredLayoutID {
            session.hoveredLayoutID = newHover
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
            stripToken &+= 1
            overlayShow(session.stripScreenID, stripToken)
        } else {
            session.hoveredLayoutID = nil
            overlayHideAll()
        }
    }

    // MARK: - Reset

    /// Unconditional reset from ground truth (physical button state decides
    /// idle vs absorbing-rejected). Always hides overlays — idempotent, cheap.
    private func forceCancel() {
        bumpGeneration()
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
