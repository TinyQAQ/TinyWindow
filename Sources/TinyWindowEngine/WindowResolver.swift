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

    /// True when a frame covers (nearly) the union of all displays — the
    /// signature of Finder's desktop window and similar overlays.
    private func spansAllScreens(_ frame: QRect) -> Bool {
        let screens = shared.screens.withLock { $0 }
        guard let first = screens.first else { return false }
        var union = first.frameQ.rawQuartz
        for screen in screens.dropFirst() { union = union.union(screen.frameQ.rawQuartz) }
        return frame.width >= union.width * 0.97 && frame.height >= union.height * 0.97
    }

    private func run(generation gen: UInt64, downPoint down: QPoint) {
        guard fresh(gen) else { return }

        // STEP 1 — WindowServer pre-filter: what window is under the mouse-down
        // point, front-to-back, no IPC into any app, immune to hung apps.
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else {
            EngineDiagnostics.log("resolve: rejected (window list unavailable)")
            return deliver(gen, .rejected)
        }

        // Front-to-back scan for the first NORMAL (layer 0) window under the
        // point. Non-zero layers are SKIPPED, not rejected: the Dock owns a
        // full-screen transparent gesture window (layer 20, alpha 1) covering
        // the entire main display, and overlays/menus float everywhere. A drag
        // that genuinely started on the Dock or a menu is caught later by the
        // follow check — the layer-0 window underneath won't track the mouse.
        var hitPID: pid_t?
        var windowID: CGWindowID = 0
        var startBounds: QRect?
        for entry in list {
            if let alpha = entry[kCGWindowAlpha as String] as? Double, alpha <= 0.01 { continue }
            guard let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.contains(down.rawQuartz) else { continue }
            guard (entry[kCGWindowLayer as String] as? Int) == 0 else { continue }
            guard let ownerPID = entry[kCGWindowOwnerPID as String] as? Int,
                  pid_t(ownerPID) != ownPID else { continue }
            hitPID = pid_t(ownerPID)
            windowID = CGWindowID((entry[kCGWindowNumber as String] as? Int) ?? 0)
            startBounds = QRect(rawQuartz: bounds)
            break
        }
        guard let hitPID, let startBounds, windowID != 0 else {
            EngineDiagnostics.log("resolve: rejected (no normal window under downPoint)")
            return deliver(gen, .rejected)
        }

        let bundleID = bundleID(for: hitPID)
        let blacklist = shared.configuration.withLock { $0.settings.blacklistBundleIDs }
        if let bundleID, blacklist.contains(bundleID) {
            EngineDiagnostics.log("resolve: rejected (blacklisted \(bundleID))")
            return deliver(gen, .rejected)
        }

        // STEP 2 — one AX hit-test at the ORIGINAL down point (the live cursor
        // may already be over a different window for text/file drags). The AX
        // window is kept for the eventual frame WRITE only; the follow check
        // below tracks WindowServer bounds instead, because some apps
        // (Electron) freeze their AX-reported position during a native drag.
        guard fresh(gen) else { return }
        guard let element = AX.element(at: down),
              var window = AX.window(containing: element)
        else { return deliver(gen, .rejected) }

        // Identity check: the AX hit-test can land on an app's full-desktop
        // window instead of the one being dragged (Finder's desktop spans all
        // displays and contains every point). Match by WINDOW ID, never by
        // frame — AX frames go stale right after our own writes (Electron
        // keeps reporting the pre-apply frame for a while, which made a
        // frame-equality check reject every follow-up drag).
        if let axID = AX.windowID(of: window) {
            if axID != windowID {
                if let match = AX.windows(pid: hitPID).first(where: { AX.windowID(of: $0) == windowID }) {
                    window = match
                    EngineDiagnostics.log("resolve: hit-test hit window id=\(axID), dragged id=\(windowID) — re-matched by id")
                } else {
                    EngineDiagnostics.log("resolve: rejected (no AX window with id \(windowID))")
                    return deliver(gen, .rejected)
                }
            }
        } else if let axFrame = AX.frame(of: window), spansAllScreens(axFrame) {
            // Bridge unavailable: only intercept the desktop-window signature
            // (a frame covering the union of all displays); trust the
            // hit-test result otherwise.
            if let match = AX.windows(pid: hitPID).first(where: { candidate in
                AX.frame(of: candidate).map { !spansAllScreens($0) } ?? false
            }) {
                window = match
                EngineDiagnostics.log("resolve: hit-test hit a desktop-span window — using first normal window instead")
            } else {
                EngineDiagnostics.log("resolve: rejected (only desktop-span windows found)")
                return deliver(gen, .rejected)
            }
        }

        let target = TargetWindow(
            window: window,
            pid: AX.pid(of: window) ?? hitPID,
            bundleID: bundleID,
            initialFrame: startBounds)
        let m0 = shared.cursor.withLock { $0 }

        scheduleSample(gen: gen, target: target, windowID: windowID, b0: startBounds,
                       m0: m0, lastSampleCursor: m0, samplesTaken: 0)
    }

    /// Live window bounds straight from the WindowServer — ground truth during
    /// server-side drags, no app IPC, immune to laggy AX implementations.
    private func serverBounds(_ windowID: CGWindowID) -> QRect? {
        guard let list = CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID)
                as? [[String: Any]],
              let dict = list.first?[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: dict)
        else { return nil }
        return QRect(rawQuartz: bounds)
    }

    // MARK: - Follow check (WindowServer bounds, not AX)
    //
    //   size changed (±2 pt)                     → it's a RESIZE     → rejected
    //   |Δwindow − Δmouse| ≤ max(6, 0.3·|Δm|)    → window follows    → confirmed
    //   ≥2 samples and window hasn't moved half  → text/file drag    → rejected
    //   ≥8 samples                               → cap
    //
    // Server bounds are exact during system drags (no app IPC, no Electron AX
    // freeze), so sampling is cheap and fast. Sampling re-arms on ≥10 pt of
    // fresh cursor travel, never on a wall clock (a user pausing mid-drag
    // stays pending).

    private func scheduleSample(gen: UInt64, target: TargetWindow, windowID: CGWindowID,
                                b0: QRect, m0: QPoint, lastSampleCursor: QPoint,
                                samplesTaken: Int) {
        queue.asyncAfter(deadline: .now() + .milliseconds(35)) { [self] in
            sampleNow(gen: gen, target: target, windowID: windowID, b0: b0, m0: m0,
                      lastSampleCursor: lastSampleCursor, samplesTaken: samplesTaken)
        }
    }

    private func sampleNow(gen: UInt64, target: TargetWindow, windowID: CGWindowID,
                           b0: QRect, m0: QPoint, lastSampleCursor: QPoint,
                           samplesTaken: Int) {
        guard fresh(gen) else { return }
        let m = shared.cursor.withLock { $0 }
        // A fast flick releases before identification completes; once the
        // button is up no more travel is coming — evaluate what we have NOW
        // (the controller may be holding a pending release for a retro-apply).
        let buttonUp = !CGEventSource.buttonState(.combinedSessionState, button: .left)

        // No fresh travel since the last sample → cheap reschedule.
        if !buttonUp, samplesTaken > 0, m.distance(to: lastSampleCursor) < 10 {
            return scheduleSample(gen: gen, target: target, windowID: windowID, b0: b0,
                                  m0: m0, lastSampleCursor: lastSampleCursor,
                                  samplesTaken: samplesTaken)
        }

        guard let bounds = serverBounds(windowID) else {
            EngineDiagnostics.log("resolve: rejected (window gone)")
            return deliver(gen, .rejected)
        }

        if abs(bounds.width - b0.width) > 2 || abs(bounds.height - b0.height) > 2 {
            EngineDiagnostics.log("resolve: rejected (resize)")
            return deliver(gen, .rejected)
        }

        let dM = CGVector(dx: m.x - m0.x, dy: m.y - m0.y)
        let dW = CGVector(dx: bounds.x - b0.x, dy: bounds.y - b0.y)
        let travel = hypot(dM.dx, dM.dy)
        let taken = samplesTaken + 1

        if travel >= 10 {
            let mismatch = hypot(dW.dx - dM.dx, dW.dy - dM.dy)
            if mismatch <= max(6, 0.3 * travel) {
                EngineDiagnostics.log("resolve: CONFIRMED pid=\(target.pid) \(target.bundleID ?? "?") after \(taken) sample(s)")
                return deliver(gen, .confirmed(target))
            }
            let movedAlongMouse = (dW.dx * dM.dx + dW.dy * dM.dy) / travel
            if taken >= 2, movedAlongMouse < 0.5 * travel {
                EngineDiagnostics.log("resolve: rejected (window not following: dW=(\(Int(dW.dx)),\(Int(dW.dy))) dM=(\(Int(dM.dx)),\(Int(dM.dy))))")
                return deliver(gen, .rejected)
            }
        }
        if buttonUp {
            EngineDiagnostics.log("resolve: rejected (released before confirm, travel=\(Int(travel)))")
            return deliver(gen, .rejected)
        }
        if taken >= 8 {
            EngineDiagnostics.log("resolve: rejected (sample cap)")
            return deliver(gen, .rejected)
        }
        scheduleSample(gen: gen, target: target, windowID: windowID, b0: b0, m0: m0,
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
