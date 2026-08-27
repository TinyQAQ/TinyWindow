import CoreGraphics
import TinyWindowCore

func runLayoutResolverChecks() {
    print("— LayoutResolver")
    // A secondary-display-like visible frame with a non-zero origin.
    let vis = QRect(x: -2560, y: 0, width: 2560, height: 1415)

    // Full-span grid layout fills the visible frame.
    let full = Layout(name: "Full",
                      kind: .grid(.init(columns: 6, rows: 6, cellX: 0, cellY: 0, cellW: 6, cellH: 6)))
    expect(LayoutResolver.targetRect(for: full, visibleFrameQ: vis) == vis, "full span == visibleFrame")

    // The classic Centre layout is inset symmetrically (±1 pt rounding).
    let centre = Layout(name: "Centre",
                        kind: .grid(.init(columns: 6, rows: 6, cellX: 1, cellY: 1, cellW: 4, cellH: 4)))
    let c = LayoutResolver.targetRect(for: centre, visibleFrameQ: vis)
    expect(abs((c.minX - vis.minX) - (vis.maxX - c.maxX)) <= 1, "centre symmetric horizontally")
    expect(abs((c.minY - vis.minY) - (vis.maxY - c.maxY)) <= 1, "centre symmetric vertically")

    // Fixed layout centered on both axes.
    let fixedCentered = Layout(name: "F",
                               kind: .fixed(.init(width: 1024, height: 768, centerX: true, centerY: true)))
    let fc = LayoutResolver.targetRect(for: fixedCentered, visibleFrameQ: vis)
    expect(fc.width == 1024 && fc.height == 768, "fixed keeps its size")
    expect(abs(fc.midX - vis.midX) <= 1 && abs(fc.midY - vis.midY) <= 1, "fixed centered")

    // Fixed layout positioned from the top-left corner.
    let fixedPositioned = Layout(name: "F",
                                 kind: .fixed(.init(width: 800, height: 600, centerX: false, centerY: false,
                                                    positionX: 40, positionY: 20)))
    let fp = LayoutResolver.targetRect(for: fixedPositioned, visibleFrameQ: vis)
    expect(fp.minX == vis.minX + 40 && fp.minY == vis.minY + 20, "fixed positioned from top-left")

    // Fixed layout larger than the screen is clamped into the visible frame.
    let oversized = Layout(name: "F",
                           kind: .fixed(.init(width: 9000, height: 9000, centerX: true, centerY: true)))
    let fo = LayoutResolver.targetRect(for: oversized, visibleFrameQ: vis)
    expect(fo.width == vis.width && fo.height == vis.height, "oversized clamped to screen size")
    expect(fo.minX == vis.minX && fo.minY == vis.minY, "oversized clamped to screen origin")
}
