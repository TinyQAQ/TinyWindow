import Foundation
import CoreGraphics
import TinyWindowCore

/// One drop region inside a pad, in panel-local top-left coordinates.
struct PadRenderRegion {
    let layoutID: UUID
    let name: String
    let rectLocal: CGRect
}

/// One pad: a mini screen (real screen's aspect ratio) showing one layout or a
/// grouped set of disjoint layouts. Matches the original Window Tidy: big pads
/// spread across a band above the chosen edge; drops land on the region under
/// the cursor.
struct PadRender {
    let frameLocal: CGRect
    let gridColumns: Int?
    let gridRows: Int?
    let label: String
    let regions: [PadRenderRegion]
    let isGrouped: Bool
}

struct PadStripGeometry {
    let panelFrameC: CGRect
    let pads: [PadRender]
    let titleHeight: CGFloat
    let hits: [PadHit]

    static func compute(layouts: [Layout], settings: AppSettings,
                        screen: ScreenSnapshot, primaryHeight: CGFloat) -> PadStripGeometry? {
        let groups = PadGrouping.groups(for: layouts, groupingEnabled: settings.groupPads)
        let count = groups.count
        guard count > 0 else { return nil }

        let vertical = settings.padEdge == .left || settings.padEdge == .right
        let titleHeight: CGFloat = settings.showPadTitles ? 18 : 0
        // Mini screens mirror the destination screen's aspect ratio.
        let aspect = max(0.5, screen.frameC.width / max(1, screen.frameC.height))
        var padW: CGFloat = 230
        var padH: CGFloat = (padW / aspect).rounded()
        var gap: CGFloat = 44
        let padding: CGFloat = 18
        let vis = screen.visibleC

        let cellMain = vertical ? padH + titleHeight : padW
        var mainLength = CGFloat(count) * cellMain + CGFloat(count - 1) * gap + 2 * padding
        let available = (vertical ? vis.height : vis.width) * 0.92
        if mainLength > available, available > 0 {
            let scale = max(0.35, available / mainLength)
            padW = max(110, (padW * scale).rounded())
            padH = (padW / aspect).rounded()
            gap = max(12, (gap * scale).rounded())
            mainLength = CGFloat(count) * (vertical ? padH + titleHeight : padW)
                + CGFloat(count - 1) * gap + 2 * padding
        }

        let panelW = vertical ? padW + 2 * padding : mainLength
        let panelH = vertical ? mainLength : padH + titleHeight + 2 * padding

        // Band position: like the original, the pads float a comfortable
        // distance in from the chosen edge, not glued to it.
        let origin: CGPoint
        switch settings.padEdge {
        case .bottom:
            origin = CGPoint(x: (vis.midX - panelW / 2).rounded(),
                             y: (vis.minY + vis.height * 0.10).rounded())
        case .top:
            origin = CGPoint(x: (vis.midX - panelW / 2).rounded(),
                             y: (vis.maxY - vis.height * 0.10 - panelH).rounded())
        case .left:
            origin = CGPoint(x: (vis.minX + vis.width * 0.05).rounded(),
                             y: (vis.midY - panelH / 2).rounded())
        case .right:
            origin = CGPoint(x: (vis.maxX - vis.width * 0.05 - panelW).rounded(),
                             y: (vis.midY - panelH / 2).rounded())
        }
        let panelFrameC = CGRect(x: origin.x, y: origin.y, width: panelW, height: panelH)

        var pads: [PadRender] = []
        var hits: [PadHit] = []

        func quartzHit(fromLocal local: CGRect) -> QRect {
            let cocoaLocal = CGRect(x: local.minX, y: panelH - local.maxY,
                                    width: local.width, height: local.height)
            let cocoaGlobal = cocoaLocal.offsetBy(dx: panelFrameC.minX, dy: panelFrameC.minY)
            return CoordinateSpace.quartz(fromCocoa: cocoaGlobal, primaryHeight: primaryHeight)
        }

        for (index, group) in groups.enumerated() {
            let frame: CGRect = vertical
                ? CGRect(x: padding, y: padding + CGFloat(index) * (padH + titleHeight + gap),
                         width: padW, height: padH)
                : CGRect(x: padding + CGFloat(index) * (padW + gap), y: padding,
                         width: padW, height: padH)
            let inner = frame.insetBy(dx: 1.5, dy: 1.5)

            var regions: [PadRenderRegion] = []
            for layout in group.layouts {
                let regionRect: CGRect
                switch layout.kind {
                case .grid(let spec):
                    regionRect = GridMath.rect(for: spec, in: inner)
                case .fixed:
                    regionRect = GlyphRenderer.regionRect(for: layout, in: inner)
                }
                regions.append(PadRenderRegion(layoutID: layout.id, name: layout.name,
                                               rectLocal: regionRect))
                if group.isGrouped {
                    // Small outset for near-misses; overlapping expansions on
                    // shared boundaries resolve by first-match, which is fine.
                    hits.append(PadHit(layoutID: layout.id,
                                       rectQ: quartzHit(fromLocal: regionRect).insetBy(dx: -4, dy: -4)))
                }
            }
            if !group.isGrouped, let only = group.layouts.first {
                // Single layout: the whole pad is the drop target.
                hits.append(PadHit(layoutID: only.id,
                                   rectQ: quartzHit(fromLocal: frame).insetBy(dx: -6, dy: -6)))
            }

            pads.append(PadRender(
                frameLocal: frame,
                gridColumns: group.gridColumns,
                gridRows: group.gridRows,
                label: group.isGrouped ? "Grouped" : (group.layouts.first?.name ?? ""),
                regions: regions,
                isGrouped: group.isGrouped))
        }

        return PadStripGeometry(panelFrameC: panelFrameC, pads: pads,
                                titleHeight: titleHeight, hits: hits)
    }
}
