import AppKit
import TinyWindowCore
import TinyWindowEngine

/// The menu bar item. Subtle but load-bearing: clicking a status item does NOT
/// activate this app, so the "frontmost app" a menu action should target is
/// snapshotted in menuWillOpen — with a fallback to the last externally
/// activated app for the moment right after our own Settings window was key.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private unowned let environment: AppEnvironment
    private var capturedFrontmostPID: pid_t?
    private var lastExternalActivePID: pid_t?
    private var workspaceObserver: NSObjectProtocol?

    init(environment: AppEnvironment) {
        self.environment = environment
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "rectangle.3.group",
                                   accessibilityDescription: "TinyWindow")
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            // Extract the Sendable pid before hopping into the isolated block.
            let pid = (notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                       as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated {
                guard let pid, pid != getpid() else { return }
                self?.lastExternalActivePID = pid
            }
        }
        refresh()
    }

    func refresh() {
        statusItem.button?.appearsDisabled = environment.lastHealth != .running
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        capturedFrontmostPID = currentFrontmostPID()
        rebuild(menu)
    }

    private func currentFrontmostPID() -> pid_t? {
        if let front = NSWorkspace.shared.frontmostApplication,
           front.processIdentifier != getpid() {
            return front.processIdentifier
        }
        return lastExternalActivePID
    }

    // MARK: - Menu construction

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()

        switch environment.lastHealth {
        case .paused(.accessibilityRevoked), .paused(.notStarted):
            let waiting = menu.addItem(withTitle: "等待辅助功能授权…", action: nil, keyEquivalent: "")
            waiting.isEnabled = false
            let open = menu.addItem(withTitle: "打开系统设置授权",
                                    action: #selector(openAccessibilitySettings), keyEquivalent: "")
            open.target = self
            menu.addItem(.separator())
        default:
            break
        }

        let toggle = menu.addItem(withTitle: "启用拖拽布局",
                                  action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self
        toggle.state = environment.prefs.enabled ? .on : .off
        menu.addItem(.separator())

        if environment.layouts.isEmpty {
            let empty = menu.addItem(withTitle: "（没有布局）", action: nil, keyEquivalent: "")
            empty.isEnabled = false
        }
        for layout in environment.layouts {
            let item = menu.addItem(withTitle: layout.name,
                                    action: #selector(applyLayoutItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = layout
            item.image = Self.glyphImage(for: layout)
            item.isEnabled = environment.lastHealth == .running && capturedFrontmostPID != nil
        }
        menu.addItem(.separator())

        let recover = menu.addItem(withTitle: "把当前窗口移到鼠标所在屏幕",
                                   action: #selector(moveWindowToCursorScreen), keyEquivalent: "")
        recover.target = self
        recover.isEnabled = environment.lastHealth == .running && capturedFrontmostPID != nil
        menu.addItem(.separator())

        if WindowTidyImporter.dataFileExists() {
            let importItem = menu.addItem(withTitle: "重新导入 Window Tidy 布局",
                                          action: #selector(reimportWT), keyEquivalent: "")
            importItem.target = self
        }
        let login = menu.addItem(withTitle: "登录时启动",
                                 action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = LaunchAtLogin.isEnabled ? .on : .off

        let settings = menu.addItem(withTitle: "设置…", action: nil, keyEquivalent: ",")
        settings.isEnabled = false // arrives with the Settings window milestone

        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "退出 TinyWindow",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
    }

    /// Small menu icon drawn with the same GlyphRenderer as the pads.
    private static func glyphImage(for layout: Layout) -> NSImage {
        let size = CGSize(width: 22, height: 15)
        let image = NSImage(size: size, flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let accent = NSColor.controlAccentColor
            let style = GlyphStyle(
                screenFill: NSColor.labelColor.withAlphaComponent(0.10).cgColor,
                screenStroke: NSColor.labelColor.withAlphaComponent(0.45).cgColor,
                regionFill: accent.withAlphaComponent(0.9).cgColor,
                regionStroke: accent.cgColor,
                cornerRadius: 2.5)
            GlyphRenderer.draw(layout, in: ctx, rect: rect.insetBy(dx: 0.5, dy: 0.5), style: style)
            return true
        }
        return image
    }

    // MARK: - Actions

    @objc private func toggleEnabled() {
        environment.prefs.enabled.toggle()
        refresh()
    }

    @objc private func applyLayoutItem(_ sender: NSMenuItem) {
        guard let layout = sender.representedObject as? Layout else { return }
        try? environment.engine.applyLayout(layout, toFrontmostWindowOf: capturedFrontmostPID)
    }

    @objc private func moveWindowToCursorScreen() {
        try? environment.engine.moveFrontmostWindowToCursorScreen(pid: capturedFrontmostPID)
    }

    @objc private func reimportWT() {
        environment.performWTImport(replaceExisting: true)
    }

    @objc private func toggleLaunchAtLogin() {
        LaunchAtLogin.setEnabled(!LaunchAtLogin.isEnabled)
    }

    @objc private func openAccessibilitySettings() {
        AccessibilityGate.openSystemSettings()
    }
}
