import Foundation

/// Fields carried over from a Window Tidy import that v1 does not act on,
/// preserved so deferred features (per-layout hotkeys, per-screen binding)
/// can pick them up later without re-importing.
public struct LegacyWTFields: Hashable, Codable, Sendable {
    /// -1 means no hotkey bound.
    public var quickLayoutKeyCode: Int
    public var quickLayoutKeyFlags: Int
    /// 0 means "any screen".
    public var screenID: Int

    public init(quickLayoutKeyCode: Int = -1, quickLayoutKeyFlags: Int = 0, screenID: Int = 0) {
        self.quickLayoutKeyCode = quickLayoutKeyCode
        self.quickLayoutKeyFlags = quickLayoutKeyFlags
        self.screenID = screenID
    }
}
