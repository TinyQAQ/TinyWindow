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
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
