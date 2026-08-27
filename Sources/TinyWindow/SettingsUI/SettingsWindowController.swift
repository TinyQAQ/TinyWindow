import AppKit
import SwiftUI

/// Manual NSWindow + NSHostingController (the SwiftUI Settings scene sinks
/// behind other apps in LSUIElement apps). Reliable fronting recipe: flip the
/// activation policy to .regular while the window is open, restore .accessory
/// on close.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let environment: AppEnvironment
    private var window: NSWindow?
    private var model: SettingsModel?

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    func show() {
        if window == nil {
            let model = SettingsModel(environment: environment)
            self.model = model
            let hosting = NSHostingController(rootView: SettingsRootView(model: model))
            let window = NSWindow(contentViewController: hosting)
            window.title = "TinyWindow 设置"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setFrameAutosaveName("TinyWindowSettings")
            window.isReleasedWhenClosed = false
            window.delegate = self
            self.window = window
            window.center()
        }
        model?.refreshFromEnvironment()
        Self.front(window)
    }

    /// Cooperative activation (macOS 14+) is routinely DENIED when invoked
    /// from an accessory app's status-item menu — the window lands behind the
    /// active app. Force it, and repeat once on the next runloop turn because
    /// the activation-policy flip needs a beat to settle.
    @MainActor
    static func front(_ window: NSWindow?) {
        guard let window else { return }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
