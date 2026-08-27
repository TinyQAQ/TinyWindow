import AppKit
import SwiftUI
import ApplicationServices
import TinyWindowCore

/// First-run window: accessibility permission, system-tiling advisory, and
/// one-click Window Tidy import — all on one page with live status.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private unowned let environment: AppEnvironment
    private var window: NSWindow?
    private var model: OnboardingModel?

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    func show() {
        if window == nil {
            let model = OnboardingModel(environment: environment)
            self.model = model
            let hosting = NSHostingController(rootView: OnboardingView(model: model))
            let window = NSWindow(contentViewController: hosting)
            window.title = "欢迎使用 TinyWindow"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        model?.stop()
        NSApp.setActivationPolicy(.accessory)
        environment.onboardingWindowClosed()
    }
}

// MARK: - Model

@MainActor
final class OnboardingModel: ObservableObject {
    private unowned let environment: AppEnvironment
    private var timer: Timer?

    @Published var axTrusted = AccessibilityGate.isTrusted
    @Published var legacyWTRunning = false
    @Published var edgeTilingOn = SystemTilingAdvisor.edgeTilingEnabled
    @Published var importDone = false
    @Published var importMessage: String?

    let wtLayoutCount: Int?

    init(environment: AppEnvironment) {
        self.environment = environment
        wtLayoutCount = (try? WindowTidyImporter.importFile())?.layouts.count
        legacyWTRunning = environment.legacyWTRunning
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func refresh() {
        axTrusted = AccessibilityGate.isTrusted
        legacyWTRunning = environment.legacyWTRunning
        edgeTilingOn = SystemTilingAdvisor.edgeTilingEnabled
    }

    func promptAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    func quitLegacyWT() {
        for app in NSRunningApplication.runningApplications(
            withBundleIdentifier: AppEnvironment.legacyWTBundleID) {
            app.terminate()
        }
    }

    func performImport() {
        if environment.performWTImport(replaceExisting: true) {
            importDone = true
            importMessage = "已导入 \(environment.layouts.count) 个布局。"
        } else {
            importMessage = "导入失败。"
        }
    }

    func finish() {
        environment.finishOnboarding(importedLayouts: importDone)
    }
}

// MARK: - View

struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("三步完成设置")
                .font(.title2.weight(.semibold))

            card(number: "1", title: "授予辅助功能权限", done: model.axTrusted) {
                Text("TinyWindow 需要“辅助功能”权限来移动和缩放其他 App 的窗口。授权后无需重启，这里会自动变绿。")
                    .foregroundStyle(.secondary)
                HStack {
                    Button("重新弹出授权提示") { model.promptAccessibility() }
                    Button("打开系统设置") { AccessibilityGate.openSystemSettings() }
                }
                if model.legacyWTRunning {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text("旧版 Window Tidy 正在运行，两个工具会互相打架。")
                        Button("退出旧版") { model.quitLegacyWT() }
                    }
                    .font(.callout)
                }
            }

            card(number: "2", title: "关闭系统的拖边平铺（建议）", done: !model.edgeTilingOn) {
                Text("系统设置 → 桌面与程序坞 → 窗口 → 关闭“将窗口拖到屏幕边缘时平铺”。TinyWindow 不依赖屏幕边缘，关闭后拖拽体验最干净。")
                    .foregroundStyle(.secondary)
                Button("打开“桌面与程序坞”设置") { SystemTilingAdvisor.openDesktopDockSettings() }
            }

            if let count = model.wtLayoutCount {
                card(number: "3", title: "导入 Window Tidy 布局", done: model.importDone) {
                    Text("检测到旧版 Window Tidy 的 \(count) 个布局，可一键原样迁入（含 Option 键与标题偏好）。")
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("一键导入") { model.performImport() }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.importDone)
                        if let message = model.importMessage {
                            Text(message).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("完成") { model.finish() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560)
    }

    private func card(number: String, title: String, done: Bool,
                      @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: done ? "checkmark.circle.fill" : "\(number).circle")
                    .foregroundStyle(done ? .green : .secondary)
                    .font(.title3)
                Text(title).font(.headline)
            }
            content()
                .padding(.leading, 30)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }
}
