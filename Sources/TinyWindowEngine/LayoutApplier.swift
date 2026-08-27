import Foundation
import ApplicationServices
import TinyWindowCore

/// The AX write path. Runs on the axQueue.
final class LayoutApplier: @unchecked Sendable {
    private let queue: DispatchQueue
    var emitEvent: (@Sendable (EngineEvent) -> Void)!

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    func apply(_ layout: Layout, to target: TargetWindow, on screen: ScreenSnapshot) {
        queue.async { [self] in
            let rect = LayoutResolver.targetRect(for: layout, visibleFrameQ: screen.visibleQ)
            let ok = Self.setFrame(rect, of: target)
            emitEvent(.didApplyLayout(layoutID: layout.id, success: ok))
        }
    }

    func setFrame(_ rect: QRect, of target: TargetWindow,
                  completion: (@Sendable (Bool) -> Void)? = nil) {
        queue.async {
            let ok = Self.setFrame(rect, of: target)
            completion?(ok)
        }
    }

    /// The synchronous dance. Call on the axQueue only.
    ///
    /// Order is position → size → position: moving first lands the window on
    /// the destination display so the size write resolves against THAT
    /// display's constraints (the cross-display case); the trailing position
    /// write repairs origin drift from apps that anchor resizes somewhere
    /// other than top-left. Failure is silent best-effort by design.
    static func setFrame(_ rect: QRect, of target: TargetWindow) -> Bool {
        let appElement = AX.appElement(pid: target.pid)
        // Writes get a longer leash than the 0.25 s global read timeout.
        AX.setMessagingTimeout(target.window, seconds: 1.0)
        defer { AX.setMessagingTimeout(target.window, seconds: 0) }

        // Electron/Chromium quirk: with AXEnhancedUserInterface set on the app
        // element, frame writes get animated/adjusted and land wrong. Clear it
        // for the dance, restore only if it was set (never leave it flipped).
        let enhanced = AX.boolAttribute(appElement, "AXEnhancedUserInterface") ?? false
        if enhanced { AX.setBoolAttribute(appElement, "AXEnhancedUserInterface", false) }
        defer { if enhanced { AX.setBoolAttribute(appElement, "AXEnhancedUserInterface", true) } }

        func dance() -> AXError {
            var error = AX.setPosition(rect.origin, of: target.window)
            if error != .success { EngineDiagnostics.log("apply: setPosition#1 AXError=\(error.rawValue)") }
            if error == .success {
                error = AX.setSize(CGSize(width: rect.width, height: rect.height), of: target.window)
                if error != .success { EngineDiagnostics.log("apply: setSize AXError=\(error.rawValue)") }
            }
            if error == .success {
                error = AX.setPosition(rect.origin, of: target.window)
                if error != .success { EngineDiagnostics.log("apply: setPosition#2 AXError=\(error.rawValue)") }
            }
            return error
        }

        EngineDiagnostics.log("apply: pid=\(target.pid) rect=(\(Int(rect.x)),\(Int(rect.y)),\(Int(rect.width)),\(Int(rect.height))) enhancedUI=\(enhanced)")
        var error = dance()
        if error == .cannotComplete {
            usleep(100_000) // one retry for momentarily busy apps
            error = dance()
        }
        guard error == .success else {
            EngineDiagnostics.log("apply: FAILED AXError=\(error.rawValue)")
            return false
        }

        // Tolerate app-imposed geometry (Terminal cell rounding, min/max sizes)
        // but keep the top-left corner honest.
        if let actual = AX.frame(of: target.window),
           abs(actual.width - rect.width) > 2 || abs(actual.height - rect.height) > 2 {
            AX.setPosition(rect.origin, of: target.window)
            EngineDiagnostics.log("apply: ok, app kept size (\(Int(actual.width))×\(Int(actual.height))), origin repaired")
        } else {
            EngineDiagnostics.log("apply: ok")
        }
        return true
    }
}
