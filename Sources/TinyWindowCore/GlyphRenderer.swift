import Foundation
import CoreGraphics

/// Colors for the layout miniature. Core has no AppKit — callers supply
/// CGColors (the overlay and the settings preview both resolve them from
/// NSColor/SwiftUI on their side, keeping one visual source of truth).
public struct GlyphStyle: Sendable {
    public var screenFill: CGColor
    public var screenStroke: CGColor
    public var regionFill: CGColor
    public var regionStroke: CGColor
    public var cornerRadius: CGFloat
    public var strokeWidth: CGFloat

    public init(screenFill: CGColor, screenStroke: CGColor,
                regionFill: CGColor, regionStroke: CGColor,
                cornerRadius: CGFloat = 4, strokeWidth: CGFloat = 1) {
        self.screenFill = screenFill
        self.screenStroke = screenStroke
        self.regionFill = regionFill
        self.regionStroke = regionStroke
        self.cornerRadius = cornerRadius
        self.strokeWidth = strokeWidth
    }
}

/// Draws a layout's miniature: a mini screen with the covered region filled.
/// Shared by the overlay pads and the settings previews so they always match.
public enum GlyphRenderer {
    /// `rect` is treated as TOP-LEFT-origin (draw in a flipped view or a
    /// SwiftUI canvas): a layout's row 0 appears at the top.
    public static func draw(_ layout: Layout, in ctx: CGContext, rect: CGRect, style: GlyphStyle) {
        guard rect.width > 4, rect.height > 4 else { return }
        let screenRect = rect.insetBy(dx: style.strokeWidth / 2, dy: style.strokeWidth / 2)
        let screenPath = CGPath(roundedRect: screenRect,
                                cornerWidth: style.cornerRadius,
                                cornerHeight: style.cornerRadius,
                                transform: nil)

        ctx.saveGState()
        ctx.setFillColor(style.screenFill)
        ctx.addPath(screenPath)
        ctx.fillPath()

        let inner = screenRect.insetBy(dx: 1.5, dy: 1.5)
        let region = regionRect(for: layout, in: inner)
        if !region.isEmpty {
            let regionPath = CGPath(roundedRect: region,
                                    cornerWidth: min(2, style.cornerRadius),
                                    cornerHeight: min(2, style.cornerRadius),
                                    transform: nil)
            ctx.setFillColor(style.regionFill)
            ctx.addPath(regionPath)
            ctx.fillPath()
            ctx.setStrokeColor(style.regionStroke)
            ctx.setLineWidth(style.strokeWidth)
            ctx.addPath(regionPath)
            ctx.strokePath()
        }

        ctx.setStrokeColor(style.screenStroke)
        ctx.setLineWidth(style.strokeWidth)
        ctx.addPath(screenPath)
        ctx.strokePath()
        ctx.restoreGState()
    }

    /// The covered region scaled into a top-left-origin container.
    public static func regionRect(for layout: Layout, in container: CGRect) -> CGRect {
        switch layout.kind {
        case .grid(let spec):
            return GridMath.rect(for: spec, in: container)
        case .fixed:
            // Preview fixed layouts against a nominal 2560×1440 screen.
            let pseudo = QRect(x: 0, y: 0, width: 2560, height: 1440)
            let target = LayoutResolver.targetRect(for: layout, visibleFrameQ: pseudo)
            let sx = container.width / pseudo.width
            let sy = container.height / pseudo.height
            return CGRect(x: container.minX + target.x * sx,
                          y: container.minY + target.y * sy,
                          width: max(2, target.width * sx),
                          height: max(2, target.height * sy))
        }
    }
}
