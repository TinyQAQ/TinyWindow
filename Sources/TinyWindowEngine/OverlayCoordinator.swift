import AppKit
import TinyWindowCore

/// Owns all overlay panels. Main-thread only; receives hops from the tap
/// thread and publishes pad hit rects back through the shared state.
@MainActor
final class OverlayCoordinator {
    private let shared: EngineSharedState
    private var panels: [CGDirectDisplayID: PadStripPanel] = [:]
    private let preview = PreviewPanel()
    private var screens: [ScreenSnapshot] = []
    private var layouts: [Layout] = []
    private var settings = AppSettings()
    private var currentScreenID: CGDirectDisplayID?

    init(shared: EngineSharedState) {
        self.shared = shared
    }

    func updateScreens(_ snapshots: [ScreenSnapshot]) {
        hideAll()
        for panel in panels.values { panel.close() }
        panels = [:]
        screens = snapshots
        for screen in screens {
            let panel = PadStripPanel()
            panels[screen.displayID] = panel
            panel.prewarm()
        }
    }

    func updateConfiguration(_ configuration: EngineConfiguration) {
        layouts = configuration.layouts
        settings = configuration.settings
        hideAll() // config changes mid-drag are rare; a clean reset is always safe
    }

    /// Lightweight snapshot refresh (visibleFrames are dynamic: the Dock
    /// migrates between displays and the menu bar hides on inactive ones).
    /// Panels persist — they are re-framed on every present anyway.
    func refreshScreens(_ snapshots: [ScreenSnapshot]) {
        screens = snapshots
    }

    func showStrip(on screenID: CGDirectDisplayID, token: UInt64) {
        guard let screen = screens.screen(withID: screenID), !layouts.isEmpty else { return }
        if let current = currentScreenID, current != screenID {
            // Instant, not faded — a lingering ghost strip on the old screen looks broken.
            panels[current]?.hide(animated: false)
            preview.hide()
        }
        currentScreenID = screenID
        let primaryHeight = CoordinateSpace.primaryHeight(cocoaScreenFrames: screens.map(\.frameC))
        guard let geometry = PadStripGeometry.compute(
            layouts: layouts, settings: settings, screen: screen, primaryHeight: primaryHeight)
        else { return }
        let panel = panels[screenID] ?? {
            let created = PadStripPanel()
            panels[screenID] = created
            return created
        }()
        panel.hoveredLayoutID = nil
        panel.present(geometry: geometry)
        shared.padHits.withLock {
            $0 = PadHitSnapshot(token: token, screenID: screenID, pads: geometry.hits)
        }
        if let first = geometry.hits.first {
            EngineDiagnostics.log("overlay: strip on screen=\(screenID) pads=\(geometry.hits.count) token=\(token) firstHitQ=(\(Int(first.rectQ.x)),\(Int(first.rectQ.y)),\(Int(first.rectQ.width)),\(Int(first.rectQ.height)))")
        }
    }

    func setHover(_ layoutID: UUID?) {
        guard let currentScreenID, let panel = panels[currentScreenID] else { return }
        panel.hoveredLayoutID = layoutID
        guard let layoutID,
              let layout = layouts.first(where: { $0.id == layoutID }),
              let screen = screens.screen(withID: currentScreenID)
        else {
            preview.hide()
            return
        }
        let rectQ = LayoutResolver.targetRect(for: layout, visibleFrameQ: screen.visibleQ)
        let primaryHeight = CoordinateSpace.primaryHeight(cocoaScreenFrames: screens.map(\.frameC))
        preview.show(frameC: CoordinateSpace.cocoa(fromQuartz: rectQ, primaryHeight: primaryHeight))
    }

    func hideAll() {
        for panel in panels.values { panel.hide(animated: true) }
        preview.hide()
        currentScreenID = nil
        shared.padHits.withLock { $0 = nil }
    }
}
