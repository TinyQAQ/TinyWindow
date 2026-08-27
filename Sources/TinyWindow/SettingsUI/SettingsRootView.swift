import SwiftUI
import UniformTypeIdentifiers
import TinyWindowCore

struct SettingsRootView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        TabView {
            GeneralTab(model: model)
                .tabItem { Label("通用", systemImage: "gearshape") }
            LayoutsTab(model: model)
                .tabItem { Label("布局", systemImage: "rectangle.3.group") }
            ImportTab(model: model)
                .tabItem { Label("导入", systemImage: "square.and.arrow.down") }
        }
        .frame(minWidth: 640, minHeight: 480)
    }
}

// MARK: - General

struct GeneralTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                Toggle("启用拖拽布局", isOn: model.enabled)
                Toggle("登录时启动", isOn: model.launchAtLogin)
            }
            Section("拖拽行为") {
                Picker("Layout pad 显示方式", selection: model.padVisibilityMode) {
                    Text("拖动窗口时始终显示").tag(PadVisibilityMode.always)
                    Text("按住 ⌥ Option 才显示").tag(PadVisibilityMode.holdOptionToShow)
                    Text("默认显示，按住 ⌥ 隐藏").tag(PadVisibilityMode.optionHides)
                }
                Picker("Pad 出现位置", selection: model.padEdge) {
                    Text("屏幕底部").tag(PadEdge.bottom)
                    Text("屏幕顶部").tag(PadEdge.top)
                    Text("屏幕左侧").tag(PadEdge.left)
                    Text("屏幕右侧").tag(PadEdge.right)
                }
                Toggle("显示布局名称", isOn: model.showPadTitles)
                HStack {
                    Text("触发拖动距离")
                    Slider(value: model.minimumDragDistance, in: 4...30, step: 1)
                    Text("\(Int(model.minimumDragDistance.wrappedValue)) pt")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
            }
            Section {
                BlacklistEditor(model: model)
            } header: {
                Text("黑名单")
            } footer: {
                Text("拖动这些 App 的窗口时不会出现 layout pad。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct BlacklistEditor: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        let list = model.blacklist.wrappedValue
        VStack(alignment: .leading, spacing: 6) {
            if list.isEmpty {
                Text("（空）").foregroundStyle(.secondary)
            }
            ForEach(list, id: \.self) { bundleID in
                HStack {
                    Text(bundleID).font(.callout)
                    Spacer()
                    Button {
                        model.blacklist.wrappedValue.removeAll { $0 == bundleID }
                    } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            Button("添加 App…") { pickApp() }
        }
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK else { return }
            let ids = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
            Task { @MainActor in
                var current = model.blacklist.wrappedValue
                for id in ids where !current.contains(id) { current.append(id) }
                model.blacklist.wrappedValue = current
            }
        }
    }
}
