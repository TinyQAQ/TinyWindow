import Foundation
import CoreGraphics
import TinyWindowCore

/// Pure geometry for one strip presentation on one screen: the panel frame
/// (Cocoa, for AppKit), per-pad cell rects (top-left-origin local, for the
/// flipped drawing view), and global Quartz hit rects (for the tap thread).
struct PadStripGeometry {
    let stripFrameC: CGRect
    let padCellsTopLocal: [CGRect]
    let titleHeight: CGFloat
    let hits: [PadHit]

    static func compute(layouts: [Layout], settings: AppSettings,
                        screen: ScreenSnapshot, primaryHeight: CGFloat) -> PadStripGeometry? {
        let count = layouts.count
        guard count > 0 else { return nil }

        let vertical = settings.padEdge == .left || settings.padEdge == .right
        let titleHeight: CGFloat = settings.showPadTitles ? 14 : 0
        var padSide: CGFloat = 56
        var gap: CGFloat = 8
        var inset: CGFloat = 12
        let margin: CGFloat = 16

        func mainAxisLength() -> CGFloat {
            let cell = vertical ? padSide + titleHeight : padSide
            return CGFloat(count) * cell + CGFloat(count - 1) * gap + 2 * inset
        }

        // Shrink uniformly if the strip would exceed the screen.
        let available = (vertical ? screen.visibleC.height : screen.visibleC.width) - 2 * margin
        if mainAxisLength() > available, available > 0 {
            let scale = max(0.4, available / mainAxisLength())
            padSide = (padSide * scale).rounded()
            gap = (gap * scale).rounded()
            inset = (inset * scale).rounded()
        }

        let cellW = padSide
        let cellH = padSide + titleHeight
        let stripW = vertical
            ? cellW + 2 * inset
            : CGFloat(count) * cellW + CGFloat(count - 1) * gap + 2 * inset
        let stripH = vertical
            ? CGFloat(count) * cellH + CGFloat(count - 1) * gap + 2 * inset
            : cellH + 2 * inset

        let vis = screen.visibleC
        let origin: CGPoint
        switch settings.padEdge {
        case .bottom:
            origin = CGPoint(x: (vis.midX - stripW / 2).rounded(), y: (vis.minY + margin).rounded())
        case .top:
            origin = CGPoint(x: (vis.midX - stripW / 2).rounded(), y: (vis.maxY - margin - stripH).rounded())
        case .left:
            origin = CGPoint(x: (vis.minX + margin).rounded(), y: (vis.midY - stripH / 2).rounded())
        case .right:
            origin = CGPoint(x: (vis.maxX - margin - stripW).rounded(), y: (vis.midY - stripH / 2).rounded())
        }
        let stripFrameC = CGRect(x: origin.x, y: origin.y, width: stripW, height: stripH)

        var cells: [CGRect] = []
        var hits: [PadHit] = []
        for (index, layout) in layouts.enumerated() {
            let cell: CGRect = vertical
                ? CGRect(x: inset, y: inset + CGFloat(index) * (cellH + gap), width: cellW, height: cellH)
                : CGRect(x: inset + CGFloat(index) * (cellW + gap), y: inset, width: cellW, height: cellH)
            cells.append(cell)
            // top-local → Cocoa-local → Cocoa-global → Quartz, outset by slop.
            let cocoaLocal = CGRect(x: cell.minX, y: stripH - cell.maxY,
                                    width: cell.width, height: cell.height)
            let cocoaGlobal = cocoaLocal.offsetBy(dx: stripFrameC.minX, dy: stripFrameC.minY)
            let quartz = CoordinateSpace.quartz(fromCocoa: cocoaGlobal, primaryHeight: primaryHeight)
            hits.append(PadHit(layoutID: layout.id, rectQ: quartz.insetBy(dx: -6, dy: -6)))
        }

        return PadStripGeometry(stripFrameC: stripFrameC,
                                padCellsTopLocal: cells,
                                titleHeight: titleHeight,
                                hits: hits)
    }
}
