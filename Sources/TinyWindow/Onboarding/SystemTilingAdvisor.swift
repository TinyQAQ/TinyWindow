import AppKit

/// Advisory check for macOS's built-in drag-to-edge tiling. TinyWindow never
/// depends on screen edges, but the OS tiling preview visually fights the pads,
/// so we recommend turning it off. Read-only: we never touch system settings.
enum SystemTilingAdvisor {
    /// Missing key = OS default = ON (verified on macOS 26.5.2).
    static var edgeTilingEnabled: Bool {
        (CFPreferencesCopyAppValue(
            "EnableTilingByEdgeDrag" as CFString,
            "com.apple.WindowManager" as CFString) as? Bool) ?? true
    }

    static func openDesktopDockSettings() {
        // Desktop & Dock pane; falls back to System Settings root if the
        // anchor ever changes in a point release.
        let url = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")!
        if !NSWorkspace.shared.open(url) {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
        }
    }
}
