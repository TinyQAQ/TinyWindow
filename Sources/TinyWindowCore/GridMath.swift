import Foundation
import CoreGraphics

public enum GridMath {
    /// Boundary offset of grid line `i` (0...count) within a length.
    /// Rounding the ENDPOINTS (not the widths) guarantees that adjacent
    /// layouts — e.g. left half and right half — share the exact same pixel
    /// edge, with no 1-px gaps or overlaps, and that boundaries are monotone
    /// and cover [0, length] exactly.
    public static func boundary(_ i: Int, count: Int, length: CGFloat) -> CGFloat {
        guard count > 0 else { return 0 }
        return (CGFloat(i) * length / CGFloat(count)).rounded()
    }

    /// Rect covered by a grid cell range inside a container rect.
    /// The container is treated as TOP-LEFT-origin (Quartz-style, or a flipped
    /// view's local space): row 0 is at minY, which is the top.
    public static func rect(for spec: Layout.GridSpec, in container: CGRect) -> CGRect {
        let s = spec.normalized()
        let x0 = container.minX + boundary(s.cellX, count: s.columns, length: container.width)
        let x1 = container.minX + boundary(s.cellX + s.cellW, count: s.columns, length: container.width)
        let y0 = container.minY + boundary(s.cellY, count: s.rows, length: container.height)
        let y1 = container.minY + boundary(s.cellY + s.cellH, count: s.rows, length: container.height)
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }
}
