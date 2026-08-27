import SwiftUI
import TinyWindowCore

/// SwiftUI declares its own `Layout` protocol; in this module the name always
/// means our model type.
typealias Layout = TinyWindowCore.Layout

/// Bridges the settings window to the composition root: layouts write through
/// to the store + engine; preference bindings write through to UserDefaults.
@MainActor
final class SettingsModel: ObservableObject {
    private unowned let environment: AppEnvironment
    private var suppressPersist = false

    @Published var layouts: [Layout] = [] {
        didSet {
            guard !suppressPersist else { return }
            environment.updateLayouts(layouts)
        }
    }

    init(environment: AppEnvironment) {
        self.environment = environment
        refreshFromEnvironment()
        environment.layoutsDidChangeExternally = { [weak self] in
            self?.refreshFromEnvironment()
        }
    }

    func refreshFromEnvironment() {
        suppressPersist = true
        layouts = environment.layouts
        suppressPersist = false
    }

    // MARK: - Preference bindings

    private func prefBinding<T>(_ keyPath: ReferenceWritableKeyPath<PreferencesStore, T>) -> Binding<T> {
        Binding(
            get: { self.environment.prefs[keyPath: keyPath] },
            set: {
                self.environment.prefs[keyPath: keyPath] = $0
                self.objectWillChange.send()
            })
    }

    var enabled: Binding<Bool> { prefBinding(\.enabled) }
    var padVisibilityMode: Binding<PadVisibilityMode> { prefBinding(\.padVisibilityMode) }
    var padEdge: Binding<PadEdge> { prefBinding(\.padEdge) }
    var showPadTitles: Binding<Bool> { prefBinding(\.showPadTitles) }
    var groupPads: Binding<Bool> { prefBinding(\.groupPads) }
    var minimumDragDistance: Binding<Double> { prefBinding(\.minimumDragDistance) }
    var blacklist: Binding<[String]> { prefBinding(\.blacklistBundleIDs) }

    var launchAtLogin: Binding<Bool> {
        Binding(
            get: { LaunchAtLogin.isEnabled },
            set: {
                LaunchAtLogin.setEnabled($0)
                self.objectWillChange.send()
            })
    }

    // MARK: - Layout operations

    func binding(for id: UUID) -> Binding<Layout>? {
        guard layouts.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: {
                self.layouts.first { $0.id == id }
                    ?? Layout(name: "?", kind: .grid(.init(columns: 6, rows: 6,
                                                           cellX: 0, cellY: 0, cellW: 3, cellH: 6)))
            },
            set: { newValue in
                guard let index = self.layouts.firstIndex(where: { $0.id == id }) else { return }
                self.layouts[index] = newValue
            })
    }

    @discardableResult
    func addLayout() -> UUID {
        let layout = Layout(name: "新布局",
                            kind: .grid(.init(columns: 6, rows: 6, cellX: 0, cellY: 0, cellW: 3, cellH: 6)))
        layouts.append(layout)
        return layout.id
    }

    func deleteLayouts(ids: Set<UUID>) {
        layouts.removeAll { ids.contains($0.id) }
    }

    func moveLayouts(from source: IndexSet, to destination: Int) {
        layouts.move(fromOffsets: source, toOffset: destination)
    }

}
