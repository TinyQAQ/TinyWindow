import AppKit
import ApplicationServices

/// Accessibility permission flow: system prompt + 1 s polling until granted
/// (no relaunch needed), then the completion fires exactly once.
@MainActor
final class AccessibilityGate {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    private var timer: Timer?
    private let onGranted: () -> Void

    init(onGranted: @escaping () -> Void) {
        self.onGranted = onGranted
    }

    func begin() {
        guard !AXIsProcessTrusted() else {
            onGranted()
            return
        }
        // Raw key: the kAXTrustedCheckOptionPrompt global trips Swift 6
        // concurrency checking.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, AXIsProcessTrusted() else { return }
                self.stop()
                self.onGranted()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
