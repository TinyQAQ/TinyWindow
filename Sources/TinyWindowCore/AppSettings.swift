import Foundation

/// When the layout pads are visible during a window drag.
public enum PadVisibilityMode: String, Codable, CaseIterable, Sendable {
    /// Pads appear whenever a window drag is detected.
    case always
    /// Pads appear only while the Option key is held.
    case holdOptionToShow
    /// Pads appear by default; holding Option hides them.
    case optionHides
}

/// Which screen edge the pad strip is centered on.
public enum PadEdge: String, Codable, CaseIterable, Sendable {
    case bottom
    case top
    case left
    case right
}

/// Engine-relevant behavior settings. App-only preferences (first-run flags,
/// import bookkeeping) live in the app target's PreferencesStore.
public struct AppSettings: Equatable, Sendable {
    public var enabled: Bool
    public var padVisibilityMode: PadVisibilityMode
    public var padEdge: PadEdge
    public var showPadTitles: Bool
    /// Merge same-grid, non-overlapping layouts into one pad (WT AutoGroupLayouts).
    public var groupPads: Bool
    /// Points the cursor must travel from mouse-down before drag
    /// identification starts (avoids flicker on sloppy clicks).
    public var minimumDragDistance: Double
    public var blacklistBundleIDs: [String]

    public init(enabled: Bool = true,
                padVisibilityMode: PadVisibilityMode = .always,
                padEdge: PadEdge = .bottom,
                showPadTitles: Bool = true,
                groupPads: Bool = true,
                minimumDragDistance: Double = 8,
                blacklistBundleIDs: [String] = []) {
        self.enabled = enabled
        self.padVisibilityMode = padVisibilityMode
        self.padEdge = padEdge
        self.showPadTitles = showPadTitles
        self.groupPads = groupPads
        self.minimumDragDistance = minimumDragDistance
        self.blacklistBundleIDs = blacklistBundleIDs
    }
}
