import Foundation

/// Decodable mirror of Window Tidy's `Layouts.data` (a plain XML plist).
/// Two entry eras exist in real files: old entries carry only the grid fields;
/// newer entries add LayoutType, fixed-size fields, hotkeys and ScreenID.
/// Everything except the Layouts array is optional.
public struct WTLegacyDocument: Decodable, Sendable {
    public struct Entry: Decodable, Sendable {
        public var name: String?
        public var gridX: Int?
        public var gridY: Int?
        public var startX: Int?
        public var startY: Int?
        public var endX: Int?
        public var endY: Int?
        /// 0 (or absent) = grid layout; anything else = fixed-size layout.
        public var layoutType: Int?
        public var width: Double?
        public var height: Double?
        public var positionX: Double?
        public var positionY: Double?
        public var centreX: Bool?
        public var centreY: Bool?
        public var quickLayoutKeyCode: Int?
        public var quickLayoutKeyFlags: Int?
        public var screenID: Int?

        enum CodingKeys: String, CodingKey {
            case name = "Name"
            case gridX = "GridX"
            case gridY = "GridY"
            case startX = "StartX"
            case startY = "StartY"
            case endX = "EndX"
            case endY = "EndY"
            case layoutType = "LayoutType"
            case width = "Width"
            case height = "Height"
            case positionX = "PositionX"
            case positionY = "PositionY"
            case centreX = "CentreX"
            case centreY = "CentreY"
            case quickLayoutKeyCode = "QuickLayoutKeyCode"
            case quickLayoutKeyFlags = "QuickLayoutKeyFlags"
            case screenID = "ScreenID"
        }
    }

    public var enabled: Bool?
    public var optionButton: Int?
    public var showTitles: Bool?
    public var autoGroupLayouts: Bool?
    public var layouts: [Entry]

    enum CodingKeys: String, CodingKey {
        case enabled = "Enabled"
        case optionButton = "OptionButton"
        case showTitles = "ShowTitles"
        case autoGroupLayouts = "AutoGroupLayouts"
        case layouts = "Layouts"
    }
}
