import Foundation
import TinyWindowCore

/// UserDefaults-backed preferences. Engine-relevant values are exposed
/// together as `appSettings`; `onChange` fires after every mutation so the
/// composition root can push a fresh EngineConfiguration.
@MainActor
final class PreferencesStore {
    private let defaults: UserDefaults
    var onChange: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private enum Key: String {
        case enabled
        case padVisibilityMode
        case padEdge
        case showPadTitles
        case minimumDragDistance
        case blacklistBundleIDs
        case wtImportPromptShown
        case lastWTImportHash
        case suppressTilingAdvisory
        case legacyWTWarningShown
        case firstRunCompleted
    }

    var appSettings: AppSettings {
        AppSettings(enabled: enabled,
                    padVisibilityMode: padVisibilityMode,
                    padEdge: padEdge,
                    showPadTitles: showPadTitles,
                    minimumDragDistance: minimumDragDistance,
                    blacklistBundleIDs: blacklistBundleIDs)
    }

    var enabled: Bool {
        get { defaults.object(forKey: Key.enabled.rawValue) as? Bool ?? true }
        set { set(newValue, .enabled) }
    }

    var padVisibilityMode: PadVisibilityMode {
        get {
            (defaults.string(forKey: Key.padVisibilityMode.rawValue))
                .flatMap(PadVisibilityMode.init(rawValue:)) ?? .always
        }
        set { set(newValue.rawValue, .padVisibilityMode) }
    }

    var padEdge: PadEdge {
        get {
            (defaults.string(forKey: Key.padEdge.rawValue))
                .flatMap(PadEdge.init(rawValue:)) ?? .bottom
        }
        set { set(newValue.rawValue, .padEdge) }
    }

    var showPadTitles: Bool {
        get { defaults.object(forKey: Key.showPadTitles.rawValue) as? Bool ?? true }
        set { set(newValue, .showPadTitles) }
    }

    var minimumDragDistance: Double {
        get { defaults.object(forKey: Key.minimumDragDistance.rawValue) as? Double ?? 8 }
        set { set(newValue, .minimumDragDistance) }
    }

    var blacklistBundleIDs: [String] {
        get { defaults.stringArray(forKey: Key.blacklistBundleIDs.rawValue) ?? [] }
        set { set(newValue, .blacklistBundleIDs) }
    }

    // MARK: - App-only bookkeeping (not part of AppSettings)

    var wtImportPromptShown: Bool {
        get { defaults.bool(forKey: Key.wtImportPromptShown.rawValue) }
        set { set(newValue, .wtImportPromptShown) }
    }

    var lastWTImportHash: String? {
        get { defaults.string(forKey: Key.lastWTImportHash.rawValue) }
        set { set(newValue, .lastWTImportHash) }
    }

    var suppressTilingAdvisory: Bool {
        get { defaults.bool(forKey: Key.suppressTilingAdvisory.rawValue) }
        set { set(newValue, .suppressTilingAdvisory) }
    }

    var legacyWTWarningShown: Bool {
        get { defaults.bool(forKey: Key.legacyWTWarningShown.rawValue) }
        set { set(newValue, .legacyWTWarningShown) }
    }

    var firstRunCompleted: Bool {
        get { defaults.bool(forKey: Key.firstRunCompleted.rawValue) }
        set { set(newValue, .firstRunCompleted) }
    }

    private func set(_ value: Any?, _ key: Key) {
        defaults.set(value, forKey: key.rawValue)
        onChange?()
    }
}
