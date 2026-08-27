import AppKit
import TinyWindowCore

/// One display, with both coordinate representations precomputed at rebuild
/// time so the hot path never converts.
struct ScreenSnapshot: Equatable, Sendable {
    let displayID: CGDirectDisplayID
    /// Quartz (top-left origin) — what the engine speaks.
    let frameQ: QRect
    let visibleQ: QRect
    /// Cocoa (bottom-left origin) — for NSPanel placement only.
    let frameC: CGRect
    let visibleC: CGRect
    let scale: CGFloat
}

extension [ScreenSnapshot] {
    func screen(withID id: CGDirectDisplayID) -> ScreenSnapshot? {
        first { $0.displayID == id }
    }

    /// Screen containing a Quartz point, with a nearest-screen fallback (the
    /// cursor can be momentarily outside every frame during reconfiguration,
    /// and CGRect.contains excludes max edges).
    func screen(containing point: QPoint) -> ScreenSnapshot? {
        if let hit = first(where: { $0.frameQ.contains(point) }) { return hit }
        return self.min { distance(from: point, to: $0.frameQ) < distance(from: point, to: $1.frameQ) }
    }

    private func distance(from p: QPoint, to r: QRect) -> CGFloat {
        let dx = Swift.max(r.minX - p.x, 0, p.x - r.maxX)
        let dy = Swift.max(r.minY - p.y, 0, p.y - r.maxY)
        return dx * dx + dy * dy
    }
}

/// Rebuilds screen snapshots on display changes. Publishes to the engine's
/// shared state for tap-thread reads; notifies the engine immediately on any
/// change (sessions are cancelled — mid-drag display surgery is not a flow
/// worth preserving) and again after a 0.5 s debounce with the rebuilt list.
@MainActor
final class ScreenTracker {
    private let shared: EngineSharedState
    private(set) var snapshots: [ScreenSnapshot] = []
    var onWillChange: (() -> Void)?
    var onDidRebuild: (([ScreenSnapshot]) -> Void)?

    private var observer: NSObjectProtocol?
    private var debounceTask: Task<Void, Never>?

    init(shared: EngineSharedState) {
        self.shared = shared
    }

    func start() {
        rebuild()
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.screensChanged()
            }
        }
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        debounceTask?.cancel()
        debounceTask = nil
    }

    private func screensChanged() {
        onWillChange?()
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self else { return }
            self.rebuild()
            self.onDidRebuild?(self.snapshots)
        }
    }

    func rebuild() {
        let screens = NSScreen.screens
        let primaryHeight = CoordinateSpace.primaryHeight(cocoaScreenFrames: screens.map(\.frame))
        snapshots = screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            return ScreenSnapshot(
                displayID: CGDirectDisplayID(number.uint32Value),
                frameQ: CoordinateSpace.quartz(fromCocoa: screen.frame, primaryHeight: primaryHeight),
                visibleQ: CoordinateSpace.quartz(fromCocoa: screen.visibleFrame, primaryHeight: primaryHeight),
                frameC: screen.frame,
                visibleC: screen.visibleFrame,
                scale: screen.backingScaleFactor)
        }
        shared.screens.withLock { $0 = snapshots }
    }
}
