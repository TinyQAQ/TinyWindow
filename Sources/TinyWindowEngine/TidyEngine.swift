import AppKit
import TinyWindowCore

/// The engine facade the app shell talks to. Main-actor; everything behind it
/// runs on its own lanes (tap thread, axQueue) per the threading design.
@MainActor
public final class TidyEngine {
    public private(set) var health: EngineHealth = .paused(.notStarted)
    public let events: AsyncStream<EngineEvent>

    private let eventsContinuation: AsyncStream<EngineEvent>.Continuation
    private let shared = EngineSharedState()
    private let axQueue = DispatchQueue(label: "com.tinyqaq.TinyWindow.ax", qos: .userInteractive)
    private let eventTap = EventTapService()
    private let controller: DragSessionController
    private let resolver: WindowResolver
    private let applier: LayoutApplier
    private let overlay: OverlayCoordinator
    private let screenTracker: ScreenTracker
    private var watchdog: Timer?
    private var watchdogTicks = 0
    private var started = false

    public init() {
        (events, eventsContinuation) = AsyncStream.makeStream(of: EngineEvent.self)
        controller = DragSessionController(shared: shared)
        resolver = WindowResolver(queue: axQueue, shared: shared)
        applier = LayoutApplier(queue: axQueue)
        overlay = OverlayCoordinator(shared: shared)
        screenTracker = ScreenTracker(shared: shared)
        wire()
    }

    private func wire() {
        let continuation = eventsContinuation
        let overlay = overlay
        let controller = controller
        let resolver = resolver
        let applier = applier
        let eventTap = eventTap

        controller.startIdentification = { generation, down in
            resolver.identify(generation: generation, downPoint: down)
        }
        controller.applyLayout = { layout, target, screen in
            applier.apply(layout, to: target, on: screen)
        }
        controller.overlayShow = { screenID, token in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { overlay.showStrip(on: screenID, token: token) }
            }
        }
        controller.overlayHideAll = {
            DispatchQueue.main.async {
                MainActor.assumeIsolated { overlay.hideAll() }
            }
        }
        controller.overlaySetHover = { layoutID in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { overlay.setHover(layoutID) }
            }
        }
        controller.reenableTap = { eventTap.reenable() }
        controller.emitEvent = { continuation.yield($0) }

        resolver.deliver = { generation, verdict in
            eventTap.perform { controller.resolved(generation, verdict: verdict) }
        }
        applier.emitEvent = { continuation.yield($0) }

        screenTracker.onWillChange = { [weak self] in
            guard let self else { return }
            self.eventTap.perform { [controller = self.controller] in
                controller.screensChanged()
            }
        }
        screenTracker.onDidRebuild = { [weak self] snapshots in
            self?.overlay.updateScreens(snapshots)
        }
    }

    // MARK: - Lifecycle

    public func start() throws {
        guard !started else { return }
        guard AX.isTrusted() else {
            setHealth(.paused(.accessibilityRevoked))
            throw EngineError.accessibilityNotGranted
        }
        AX.configureGlobalTimeout(seconds: 0.25)
        screenTracker.start()
        overlay.updateScreens(screenTracker.snapshots)
        started = true
        startTapIfNeeded()
        startWatchdog()
    }

    public func stop() {
        eventTap.stop()
        watchdog?.invalidate()
        watchdog = nil
        overlay.hideAll()
        screenTracker.stop()
        started = false
        setHealth(.paused(.disabled))
    }

    /// Idempotent; callable live — pushes layouts + settings and reconciles
    /// the tap with the enabled flag.
    public func apply(_ configuration: EngineConfiguration) {
        shared.configuration.withLock { $0 = configuration }
        overlay.updateConfiguration(configuration)
        guard started else { return }
        if configuration.settings.enabled {
            startTapIfNeeded()
        } else if eventTap.isRunning {
            eventTap.stop()
            overlay.hideAll()
            setHealth(.paused(.disabled))
        }
    }

    // MARK: - Direct apply (menu bar path, no drag involved)

    public func applyLayout(_ layout: Layout, toFrontmostWindowOf pid: pid_t?) throws {
        guard AX.isTrusted() else { throw EngineError.accessibilityNotGranted }
        guard let pid else { throw EngineError.noTargetWindow }
        let screens = shared.screens.withLock { $0 }
        let continuation = eventsContinuation
        axQueue.async {
            guard let window = AX.focusedWindow(pid: pid),
                  let frame = AX.frame(of: window),
                  let screen = screens.screen(containing: frame.center) ?? screens.first
            else {
                continuation.yield(.didApplyLayout(layoutID: layout.id, success: false))
                return
            }
            let target = TargetWindow(window: window, pid: pid, bundleID: nil, initialFrame: frame)
            let rect = LayoutResolver.targetRect(for: layout, visibleFrameQ: screen.visibleQ)
            let ok = LayoutApplier.setFrame(rect, of: target)
            continuation.yield(.didApplyLayout(layoutID: layout.id, success: ok))
        }
    }

    /// Recover a window lost on another (possibly disconnected) display:
    /// center the app's focused window on the screen under the cursor.
    public func moveFrontmostWindowToCursorScreen(pid: pid_t?) throws {
        guard AX.isTrusted() else { throw EngineError.accessibilityNotGranted }
        guard let pid else { throw EngineError.noTargetWindow }
        let screens = shared.screens.withLock { $0 }
        guard let cursorEvent = CGEvent(source: nil) else { return }
        let cursor = QPoint(rawQuartz: cursorEvent.location)
        axQueue.async {
            guard let window = AX.focusedWindow(pid: pid),
                  let frame = AX.frame(of: window),
                  let screen = screens.screen(containing: cursor)
            else { return }
            let vis = screen.visibleQ
            let width = min(frame.width, vis.width)
            let height = min(frame.height, vis.height)
            let rect = QRect(x: (vis.minX + (vis.width - width) / 2).rounded(),
                             y: (vis.minY + (vis.height - height) / 2).rounded(),
                             width: width, height: height)
            let target = TargetWindow(window: window, pid: pid, bundleID: nil, initialFrame: frame)
            _ = LayoutApplier.setFrame(rect, of: target)
        }
    }

    // MARK: - Internals

    private func startTapIfNeeded() {
        guard shared.configuration.withLock({ $0.settings.enabled }) else {
            setHealth(.paused(.disabled))
            return
        }
        if eventTap.isRunning {
            setHealth(.running)
            return
        }
        if AX.isTrusted(), eventTap.start(controller: controller) {
            setHealth(.running)
        } else {
            setHealth(.paused(.accessibilityRevoked))
        }
    }

    private func setHealth(_ newHealth: EngineHealth) {
        guard newHealth != health else { return }
        health = newHealth
        eventsContinuation.yield(.healthChanged(newHealth))
    }

    private func startWatchdog() {
        watchdog?.invalidate()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }

    private func tick() {
        watchdogTicks += 1
        if eventTap.isRunning {
            if !eventTap.tapEnabled { eventTap.reenable() }
            let buttonUp = !CGEventSource.buttonState(.combinedSessionState, button: .left)
            eventTap.perform { [controller] in
                controller.watchdogCheck(buttonUp: buttonUp)
            }
        }
        guard watchdogTicks % 5 == 0 else { return }
        let trusted = AX.isTrusted()
        if eventTap.isRunning, !trusted {
            // Permission revoked mid-run: engine off, shell shows the alert state.
            eventTap.stop()
            overlay.hideAll()
            setHealth(.paused(.accessibilityRevoked))
        } else if !eventTap.isRunning, trusted, started {
            // Auto-recover after re-grant (a dead tap is never revived — recreate).
            startTapIfNeeded()
        }
    }
}
