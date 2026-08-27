import Foundation
import CoreGraphics

// MARK: - Quartz-space phantom types
//
// Two global coordinate systems span all displays:
//   * Quartz (top-left origin, +y downward): CGEvent locations, CGWindowList
//     bounds, ALL Accessibility positions, CGDisplayBounds.
//   * Cocoa (bottom-left origin, +y upward): NSScreen frames, NSWindow/NSPanel.
// The engine speaks Quartz exclusively; Cocoa exists only at the AppKit
// boundary. QPoint/QRect make a missing conversion a compile error instead of
// a window teleporting to the wrong half of the wrong display.

/// A point in Quartz global coordinates (top-left origin, +y downward).
public struct QPoint: Hashable, Sendable, Codable {
    public var x: CGFloat
    public var y: CGFloat

    public init(x: CGFloat, y: CGFloat) {
        self.x = x
        self.y = y
    }

    /// Wraps a CGPoint that is ALREADY in Quartz coordinates (e.g. CGEvent.location).
    public init(rawQuartz p: CGPoint) {
        self.init(x: p.x, y: p.y)
    }

    /// The underlying CGPoint, still in Quartz coordinates.
    public var rawQuartz: CGPoint { CGPoint(x: x, y: y) }

    public func distance(to other: QPoint) -> CGFloat {
        let dx = x - other.x
        let dy = y - other.y
        return (dx * dx + dy * dy).squareRoot()
    }
}

/// A rect in Quartz global coordinates (top-left origin, +y downward).
public struct QRect: Hashable, Sendable, Codable {
    public var x: CGFloat
    public var y: CGFloat
    public var width: CGFloat
    public var height: CGFloat

    public init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// Wraps a CGRect that is ALREADY in Quartz coordinates (e.g. kCGWindowBounds).
    public init(rawQuartz r: CGRect) {
        self.init(x: r.origin.x, y: r.origin.y, width: r.size.width, height: r.size.height)
    }

    /// The underlying CGRect, still in Quartz coordinates.
    public var rawQuartz: CGRect { CGRect(x: x, y: y, width: width, height: height) }

    public var minX: CGFloat { x }
    public var minY: CGFloat { y }
    public var maxX: CGFloat { x + width }
    public var maxY: CGFloat { y + height }
    public var midX: CGFloat { x + width / 2 }
    public var midY: CGFloat { y + height / 2 }
    public var origin: QPoint { QPoint(x: x, y: y) }
    public var center: QPoint { QPoint(x: midX, y: midY) }
    public var isEmpty: Bool { width <= 0 || height <= 0 }

    /// Matches CGRect.contains semantics: max edges are excluded.
    public func contains(_ p: QPoint) -> Bool {
        p.x >= minX && p.x < maxX && p.y >= minY && p.y < maxY
    }

    public func insetBy(dx: CGFloat, dy: CGFloat) -> QRect {
        QRect(rawQuartz: rawQuartz.insetBy(dx: dx, dy: dy))
    }

    public func intersects(_ other: QRect) -> Bool {
        rawQuartz.intersects(other.rawQuartz)
    }
}

// MARK: - Conversion

public enum CoordinateSpace {
    /// The y-flip pivot is the height of the PRIMARY screen — the one whose
    /// Cocoa frame origin is (0, 0) — never "the screen the cursor is on".
    public static func primaryHeight(cocoaScreenFrames frames: [CGRect]) -> CGFloat {
        (frames.first { $0.origin == .zero } ?? frames.first ?? .zero).height
    }

    public static func quartz(fromCocoa p: CGPoint, primaryHeight H: CGFloat) -> QPoint {
        QPoint(x: p.x, y: H - p.y)
    }

    public static func cocoa(fromQuartz p: QPoint, primaryHeight H: CGFloat) -> CGPoint {
        CGPoint(x: p.x, y: H - p.y)
    }

    public static func quartz(fromCocoa r: CGRect, primaryHeight H: CGFloat) -> QRect {
        QRect(x: r.minX, y: H - r.maxY, width: r.width, height: r.height)
    }

    public static func cocoa(fromQuartz r: QRect, primaryHeight H: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: H - r.maxY, width: r.width, height: r.height)
    }
}
