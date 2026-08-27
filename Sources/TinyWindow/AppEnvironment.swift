import AppKit
import TinyWindowCore
import TinyWindowEngine

/// Composition root: wires store + preferences + engine + status item, and
/// owns the app-level flows (first run, import, permission gate).
@MainActor
final class AppEnvironment {
    let engine = TidyEngine()
    let store = LayoutStore()
    let prefs = PreferencesStore()
    private(set) var layouts: [Layout] = []
    private(set) var lastHealth: EngineHealth = .paused(.notStarted)

    private var statusItem: StatusItemController?
    private var gate: AccessibilityGate?
    private var eventsTask: Task<Void, Never>?
    private var settingsController: SettingsWindowController?
    private var onboardingController: OnboardingWindowController?
    /// Set by the settings window so external changes (menu re-import,
    /// onboarding import) refresh its list.
    var layoutsDidChangeExternally: (() -> Void)?

    static let legacyWTBundleID = "com.lightpillar.Window-Tidy"

    func bootstrap() {
        prefs.onChange = { [weak self] in self?.settingsChanged() }
        statusItem = StatusItemController(environment: self) // icon first, always
        loadLayouts()
        subscribeToEngineEvents()

        if AccessibilityGate.isTrusted {
            startEngine()
        } else {
            beginAccessibilityGate()
        }
        if !prefs.firstRunCompleted {
            showOnboarding()
        }
    }

    // MARK: - Layouts

    private func loadLayouts() {
        do {
            layouts = try store.load()
        } catch {
            layouts = []
            NSLog("LayoutStore load failed: \(error)")
            presentAlert(title: "无法读取布局文件",
                         text: "layouts.json 读取失败，本次会话将从内存布局开始。\n\(error)")
        }
        // First run seeds through onboarding (import or defaults). A completed
        // setup with an empty list is respected as the user's choice.
    }

    /// Returns true on success. Applies the imported global preferences too.
    @discardableResult
    func performWTImport(replaceExisting: Bool) -> Bool {
        do {
            let result = try WindowTidyImporter.importFile()
            if replaceExisting {
                layouts = result.layouts
            } else {
                layouts.append(contentsOf: result.layouts)
            }
            if let mode = result.preferences.padVisibilityMode { prefs.padVisibilityMode = mode }
            if let titles = result.preferences.showPadTitles { prefs.showPadTitles = titles }
            if let enabled = result.preferences.enabled { prefs.enabled = enabled }
            prefs.lastWTImportHash = result.sourceHash
            persistLayouts()
            return true
        } catch {
            NSLog("WT import failed: \(error)")
            presentAlert(title: "导入失败",
                         text: "无法解析 Window Tidy 的 Layouts.data。\n\(error)")
            return false
        }
    }

    func updateLayouts(_ newLayouts: [Layout]) {
        layouts = newLayouts
        persistLayouts()
    }

    private func persistLayouts() {
        do {
            try store.save(layouts)
        } catch {
            NSLog("LayoutStore save failed: \(error)")
        }
        pushConfiguration()
        layoutsDidChangeExternally?()
    }

    // MARK: - Engine

    private func startEngine() {
        do {
            try engine.start()
            pushConfiguration()
            warnIfLegacyWTRunning()
        } catch {
            beginAccessibilityGate()
        }
    }

    private func beginAccessibilityGate() {
        guard gate == nil else { return }
        let gate = AccessibilityGate { [weak self] in
            self?.gate = nil
            self?.startEngine()
        }
        self.gate = gate
        gate.begin()
    }

    func pushConfiguration() {
        engine.apply(EngineConfiguration(layouts: layouts, settings: prefs.appSettings))
    }

    private func settingsChanged() {
        pushConfiguration()
    }

    private func subscribeToEngineEvents() {
        let stream = engine.events
        eventsTask = Task { @MainActor [weak self] in
            for await event in stream {
                guard let self else { break }
                if case .healthChanged(let health) = event {
                    self.lastHealth = health
                    self.statusItem?.refresh()
                }
            }
        }
    }

    // MARK: - Misc flows

    var legacyWTRunning: Bool {
        !NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.legacyWTBundleID).isEmpty
    }

    private func warnIfLegacyWTRunning() {
        // During first run the onboarding window carries this warning instead.
        guard prefs.firstRunCompleted, legacyWTRunning, !prefs.legacyWTWarningShown else { return }
        prefs.legacyWTWarningShown = true
        let alert = NSAlert()
        alert.messageText = "旧版 Window Tidy 正在运行"
        alert.informativeText = "两个工具会同时响应窗口拖拽、互相打架。建议退出旧版 Window Tidy（并取消它的登录启动）。"
        alert.addButton(withTitle: "帮我退出它")
        alert.addButton(withTitle: "保留运行")
        if alert.runModal() == .alertFirstButtonReturn {
            for app in NSRunningApplication.runningApplications(
                withBundleIdentifier: Self.legacyWTBundleID) {
                app.terminate()
            }
        }
    }

    func showSettings() {
        if settingsController == nil {
            settingsController = SettingsWindowController(environment: self)
        }
        settingsController?.show()
    }

    // MARK: - Onboarding

    func showOnboarding() {
        if onboardingController == nil {
            onboardingController = OnboardingWindowController(environment: self)
        }
        onboardingController?.show()
    }

    func finishOnboarding(importedLayouts: Bool) {
        if layouts.isEmpty, !importedLayouts {
            layouts = LayoutDefaults.starterSet()
            persistLayouts()
        }
        prefs.firstRunCompleted = true
        onboardingController?.close()
    }

    /// Closing the window with ⨯ counts as finishing (defaults get seeded so
    /// the app is usable immediately).
    func onboardingWindowClosed() {
        if !prefs.firstRunCompleted {
            if layouts.isEmpty {
                layouts = LayoutDefaults.starterSet()
                persistLayouts()
            }
            prefs.firstRunCompleted = true
        }
    }

    private func presentAlert(title: String, text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }
}
