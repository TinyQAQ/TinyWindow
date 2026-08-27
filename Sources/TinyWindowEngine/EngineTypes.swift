import Foundation
import CoreGraphics
import Synchronization
import TinyWindowCore

// MARK: - Public configuration & events

public struct EngineConfiguration: Equatable, Sendable {
    /// Pad order on the strip is exactly this order.
    public var layouts: [Layout]
    public var settings: AppSettings

    public init(layouts: [Layout], settings: AppSettings) {
        self.layouts = layouts
        self.settings = settings
    }
}

public enum EnginePauseReason: Equatable, Sendable {
    case notStarted
    case disabled
    case accessibilityRevoked
}

public enum EngineHealth: Equatable, Sendable {
    case running
    case paused(EnginePauseReason)
}

public enum EngineEvent: Sendable {
    case dragBegan
    case dragEnded
    case didApplyLayout(layoutID: UUID, success: Bool)
    case healthChanged(EngineHealth)
}

public enum EngineError: Error, Sendable {
    case accessibilityNotGranted
    case noTargetWindow
}

// MARK: - Internal shared state
//
// One shared, lock-protected snapshot hub. Writers/readers:
//   cursor              — written by the tap thread on every mouse event
//   configuration       — written by TidyEngine (main), read everywhere
//   screens             — written by ScreenTracker (main), read on tap thread
//   padHits             — written by OverlayCoordinator (main), read on tap thread
//   resolverGeneration  — written by DragSessionController (tap thread),
//                         read by WindowResolver (axQueue) for early abort

final class EngineSharedState: Sendable {
    let cursor = Mutex<QPoint>(QPoint(x: 0, y: 0))
    let configuration = Mutex<EngineConfiguration>(
        EngineConfiguration(layouts: [], settings: AppSettings()))
    let screens = Mutex<[ScreenSnapshot]>([])
    let padHits = Mutex<PadHitSnapshot?>(nil)
    let resolverGeneration = Atomic<UInt64>(0)
}

/// The window being dragged, resolved once at drag identification.
/// AXUIElement is a thread-safe CF token; message it from the axQueue only.
struct TargetWindow: @unchecked Sendable {
    let window: AXElement
    let pid: pid_t
    let bundleID: String?
    let initialFrame: QRect
}

/// One pad's drop target, in Quartz global coordinates (already outset by slop).
struct PadHit: Sendable {
    let layoutID: UUID
    let rectQ: QRect
}

/// Published by OverlayCoordinator whenever the strip is (re)shown; the token
/// ties the snapshot to a specific strip presentation so stale rects are never
/// hit-tested after the strip moved to another screen.
struct PadHitSnapshot: Sendable {
    let token: UInt64
    let screenID: CGDirectDisplayID
    let pads: [PadHit]
}

enum ResolveVerdict: Sendable {
    case confirmed(TargetWindow)
    case rejected
}
