import Foundation
import CoreGraphics

/// The single place where "layout + destination screen" becomes a window rect.
/// Both the drag-drop path and the menu-bar direct-apply path go through here.
public enum LayoutResolver {
    /// - Parameter vis: the destination screen's visible frame in Quartz coordinates.
    public static func targetRect(for layout: Layout, visibleFrameQ vis: QRect) -> QRect {
        switch layout.kind {
        case .grid(let spec):
            return QRect(rawQuartz: GridMath.rect(for: spec, in: vis.rawQuartz))
        case .fixed(let spec):
            let w = min(max(1, spec.width), vis.width).rounded()
            let h = min(max(1, spec.height), vis.height).rounded()
            var x = spec.centerX ? vis.minX + (vis.width - w) / 2 : vis.minX + spec.positionX
            var y = spec.centerY ? vis.minY + (vis.height - h) / 2 : vis.minY + spec.positionY
            x = min(max(x, vis.minX), vis.maxX - w).rounded()
            y = min(max(y, vis.minY), vis.maxY - h).rounded()
            return QRect(x: x, y: y, width: w, height: h)
        }
    }
}
