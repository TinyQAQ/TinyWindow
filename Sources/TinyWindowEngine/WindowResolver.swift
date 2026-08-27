import Foundation
import AppKit
import TinyWindowCore

/// Decides whether the current button-press is a window drag. Runs entirely on
/// the axQueue. Zero AX calls happen before the drag threshold is crossed;
/// the common case (a real title-bar drag) confirms on the first follow sample,
/// ~80–150 ms after the threshold.
final class WindowResolver: @unchecked Sendable {
    private let queue: DispatchQueue
    private let shared: EngineSharedState
    /// Delivers the verdict back onto the tap thread.
    var deliver: (@Sendable (_ generation: UInt64, _ verdict: ResolveVerdict) -> Void)!

    private let ownPID = getpid()
    /// pid → bundle id cache (axQueue-confined); pids recycle rarely enough
    /// that a small bound + full flush is plenty.
    private var bundleIDCache: [pid_t: String?] = [:]

    init(queue: DispatchQueue, shared: EngineSharedState) {
        self.queue = queue
        self.shared = shared
    }

    func identify(generation: UInt64, downPoint: QPoint) {
        queue.async { [self] in
            run(generation: generation, downPoint: downPoint)
        }
    }

    private func fresh(_ generation: UInt64) -> Bool {
        shared.resolverGeneration.load(ordering: .relaxed) == generation
    }

    private func run(generation gen: UInt64, downPoint down: QPoint) {
        guard fresh(gen) else { return }

        // STEP 1 — WindowServer pre-filter: what window is under the mouse-down
        // point, front-to-back, no IPC into any app, immune to hung apps.
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return deliver(gen, .rejected) }

        var hitPID: pid_t?
        for entry in list {
            if let alpha = entry[kCGWindowAlpha as String] as? Double, alpha <= 0.01 { continue }
            guard let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.contains(down.rawQuartz) else { continue }
            // Topmost window under the point. Only normal windows qualify —
            // layer != 0 kills menus, status items, the Dock, overlays.
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                  let ownerPID = entry[kCGWindowOwnerPID as String] as? Int else {
                return deliver(gen, .rejected)
            }
            hitPID = pid_t(ownerPID)
            break
        }
        guard let hitPID, hitPID != ownPID else { return deliver(gen, .rejected) }

        let bundleID = bundleID(for: hitPID)
        let blacklist = shared.configuration.withLock { $0.settings.blacklistBundleIDs }
        if let bundleID, blacklist.contains(bundleID) { return deliver(gen, .rejected) }

        // STEP 2 — one AX hit-test at the ORIGINAL down point (the live cursor
        // may already be over a different window for text/file drags).
        guard fresh(gen) else { return }
        guard let element = AX.element(at: down),
              let window = AX.window(containing: element),
              let p0 = AX.position(of: window),
              let s0 = AX.size(of: window)
        else { return deliver(gen, .rejected) }

        let target = TargetWindow(
            window: window,
            pid: AX.pid(of: window) ?? hitPID,
            bundleID: bundleID,
            initialFrame: QRect(x: p0.x, y: p0.y, width: s0.width, height: s0.height))
        let m0 = shared.cursor.withLock { $0 }

        scheduleSample(gen: gen, target: target, p0: p0, s0: s0, m0: m0,
                       lastSampleCursor: m0, samplesTaken: 0)
    }

    // MARK: - Follow check
    //
    //   size changed (±2 pt)                     → it's a RESIZE     → rejected
    //   |Δwindow − Δmouse| ≤ max(8, 0.35·|Δm|)   → window follows    → confirmed
    //   ≥2 samples and window hasn't moved half  → text/file drag    → rejected
    //   ≥6 samples                               → hard cap on AX spend
    //
    // The proportional tolerance absorbs the frame-or-two of lag apps report
    // during server-side drags; sampling re-arms on ≥12 pt of fresh cursor
    // travel, never on a wall clock (a user pausing mid-drag stays pending).

    private func scheduleSample(gen: UInt64, target: TargetWindow, p0: QPoint, s0: CGSize,
                                m0: QPoint, lastSampleCursor: QPoint, samplesTaken: Int) {
        queue.asyncAfter(deadline: .now() + .milliseconds(70)) { [self] in
            sampleNow(gen: gen, target: target, p0: p0, s0: s0, m0: m0,
                      lastSampleCursor: lastSampleCursor, samplesTaken: samplesTaken)
        }
    }

    private func sampleNow(gen: UInt64, target: TargetWindow, p0: QPoint, s0: CGSize,
                           m0: QPoint, lastSampleCursor: QPoint, samplesTaken: Int) {
        guard fresh(gen) else { return }
        let m = shared.cursor.withLock { $0 }

        // No fresh travel since the last AX sample → cheap reschedule, no IPC.
        if samplesTaken > 0, m.distance(to: lastSampleCursor) < 12 {
            return scheduleSample(gen: gen, target: target, p0: p0, s0: s0, m0: m0,
                                  lastSampleCursor: lastSampleCursor, samplesTaken: samplesTaken)
        }

        guard let p = AX.position(of: target.window),
              let s = AX.size(of: target.window)
        else { return deliver(gen, .rejected) }

        if abs(s.width - s0.width) > 2 || abs(s.height - s0.height) > 2 {
            return deliver(gen, .rejected)
        }

        let dM = CGVector(dx: m.x - m0.x, dy: m.y - m0.y)
        let dW = CGVector(dx: p.x - p0.x, dy: p.y - p0.y)
        let travel = hypot(dM.dx, dM.dy)
        let taken = samplesTaken + 1

        if travel >= 12 {
            let mismatch = hypot(dW.dx - dM.dx, dW.dy - dM.dy)
            if mismatch <= max(8, 0.35 * travel) {
                return deliver(gen, .confirmed(target))
            }
            let movedAlongMouse = (dW.dx * dM.dx + dW.dy * dM.dy) / travel
            if taken >= 2, movedAlongMouse < 0.5 * travel {
                return deliver(gen, .rejected)
            }
        }
        if taken >= 6 { return deliver(gen, .rejected) }
        scheduleSample(gen: gen, target: target, p0: p0, s0: s0, m0: m0,
                       lastSampleCursor: m, samplesTaken: taken)
    }

    // MARK: - Bundle id lookup

    private func bundleID(for pid: pid_t) -> String? {
        if let cached = bundleIDCache[pid] { return cached }
        if bundleIDCache.count > 256 { bundleIDCache.removeAll(keepingCapacity: true) }
        let id = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        bundleIDCache[pid] = id
        return id
    }
}
