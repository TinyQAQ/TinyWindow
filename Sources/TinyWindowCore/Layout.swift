import Foundation
import CoreGraphics

/// A window layout: a named region that a window can be snapped to.
public struct Layout: Identifiable, Hashable, Sendable {
    public enum Origin: String, Codable, Sendable {
        case user
        case builtin
        case wtImport
    }

    /// Grid-region layout: an independent grid over the destination screen's
    /// visible frame, with a selected cell range. Top-left origin, `cellX/cellY`
    /// inclusive start, `cellW/cellH` extent (Window Tidy's End values are
    /// exclusive: cellW == EndX - StartX).
    public struct GridSpec: Hashable, Codable, Sendable {
        public var columns: Int
        public var rows: Int
        public var cellX: Int
        public var cellY: Int
        public var cellW: Int
        public var cellH: Int

        public init(columns: Int, rows: Int, cellX: Int, cellY: Int, cellW: Int, cellH: Int) {
            self.columns = columns
            self.rows = rows
            self.cellX = cellX
            self.cellY = cellY
            self.cellW = cellW
            self.cellH = cellH
        }

        /// Clamps the spec into a valid state (grid at least 1×1, range inside the grid).
        public func normalized() -> GridSpec {
            let cols = max(1, columns)
            let rws = max(1, rows)
            let x = min(max(0, cellX), cols - 1)
            let y = min(max(0, cellY), rws - 1)
            let w = min(max(1, cellW), cols - x)
            let h = min(max(1, cellH), rws - y)
            return GridSpec(columns: cols, rows: rws, cellX: x, cellY: y, cellW: w, cellH: h)
        }
    }

    /// Fixed-size layout: explicit point size, centered per axis or offset from
    /// the top-left corner of the destination screen's visible frame.
    public struct FixedSpec: Hashable, Codable, Sendable {
        public var width: CGFloat
        public var height: CGFloat
        public var centerX: Bool
        public var centerY: Bool
        public var positionX: CGFloat
        public var positionY: CGFloat

        public init(width: CGFloat, height: CGFloat,
                    centerX: Bool, centerY: Bool,
                    positionX: CGFloat = 0, positionY: CGFloat = 0) {
            self.width = width
            self.height = height
            self.centerX = centerX
            self.centerY = centerY
            self.positionX = positionX
            self.positionY = positionY
        }
    }

    public enum Kind: Hashable, Sendable {
        case grid(GridSpec)
        case fixed(FixedSpec)
    }

    public var id: UUID
    public var name: String
    public var kind: Kind
    public var origin: Origin
    /// Window Tidy fields preserved verbatim for deferred features
    /// (per-layout hotkeys, per-screen binding).
    public var legacy: LegacyWTFields?

    public init(id: UUID = UUID(), name: String, kind: Kind,
                origin: Origin = .user, legacy: LegacyWTFields? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.origin = origin
        self.legacy = legacy
    }
}

extension Layout: Codable {}

extension Layout.Kind: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "grid":
            self = .grid(try Layout.GridSpec(from: decoder))
        case "fixed":
            self = .fixed(try Layout.FixedSpec(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container,
                debugDescription: "Unknown layout kind '\(type)'")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .grid(let spec):
            try container.encode("grid", forKey: .type)
            try spec.encode(to: encoder)
        case .fixed(let spec):
            try container.encode("fixed", forKey: .type)
            try spec.encode(to: encoder)
        }
    }
}
