import AppKit
import TinyWindowCore

/// One screen's pad strip: a borderless, non-activating panel that never
/// receives mouse events (the drag belongs to the other app — hover is
/// hit-tested from tap coordinates by the engine).
@MainActor
final class PadStripPanel {
    private let panel: NSPanel
    private let stripView = PadStripView()
    private var fadeGeneration = 0

    var hoveredLayoutID: UUID? {
        get { stripView.hoveredLayoutID }
        set { stripView.hoveredLayoutID = newValue }
    }

    init() {
        panel = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.isMovable = false

        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 16
        container.layer?.masksToBounds = true

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.autoresizingMask = [.width, .height]
        container.addSubview(effect)

        stripView.autoresizingMask = [.width, .height]
        container.addSubview(stripView)

        panel.contentView = container
    }

    func present(geometry: PadStripGeometry, layouts: [Layout], showTitles: Bool) {
        fadeGeneration += 1
        panel.setFrame(geometry.stripFrameC, display: false)
        if let content = panel.contentView {
            for subview in content.subviews { subview.frame = content.bounds }
        }
        stripView.update(layouts: layouts, geometry: geometry, showTitles: showTitles)
        if !panel.isVisible { panel.alphaValue = 0 }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }
    }

    func hide(animated: Bool) {
        guard panel.isVisible else { return }
        fadeGeneration += 1
        guard animated else {
            panel.alphaValue = 0
            panel.orderOut(nil)
            return
        }
        let generation = fadeGeneration
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                // The token kills the hide-then-reshow race: never orderOut a
                // panel that a newer presentation already re-showed.
                guard self.fadeGeneration == generation else { return }
                self.panel.orderOut(nil)
            }
        })
    }

    /// Builds the layer tree and font caches so the first real drag has no hitch.
    func prewarm() {
        panel.alphaValue = 0
        panel.setFrame(CGRect(x: 0, y: 0, width: 120, height: 90), display: true)
        panel.orderFrontRegardless()
        panel.orderOut(nil)
    }

    func close() {
        panel.orderOut(nil)
        panel.close()
    }
}

/// Hand-drawn pad strip (deliberately not SwiftUI: instant first frame, and
/// hover repaints are a plain needsDisplay flip).
final class PadStripView: NSView {
    override var isFlipped: Bool { true }

    private var layouts: [Layout] = []
    private var cells: [CGRect] = []
    private var titleHeight: CGFloat = 0
    private var showTitles = false

    var hoveredLayoutID: UUID? {
        didSet { if hoveredLayoutID != oldValue { needsDisplay = true } }
    }

    func update(layouts: [Layout], geometry: PadStripGeometry, showTitles: Bool) {
        self.layouts = layouts
        self.cells = geometry.padCellsTopLocal
        self.titleHeight = geometry.titleHeight
        self.showTitles = showTitles
        self.hoveredLayoutID = nil
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let accent = NSColor.controlAccentColor

        for (index, layout) in layouts.enumerated() where index < cells.count {
            let cell = cells[index]
            let hovered = layout.id == hoveredLayoutID

            let cellPath = NSBezierPath(roundedRect: cell, xRadius: 10, yRadius: 10)
            (hovered ? accent.withAlphaComponent(0.30) : NSColor.white.withAlphaComponent(0.08)).setFill()
            cellPath.fill()
            if hovered {
                accent.setStroke()
                cellPath.lineWidth = 2
                cellPath.stroke()
            }

            let glyphArea = CGRect(x: cell.minX, y: cell.minY,
                                   width: cell.width, height: cell.height - titleHeight)
                .insetBy(dx: 8, dy: 7)
            let style = GlyphStyle(
                screenFill: NSColor.white.withAlphaComponent(0.12).cgColor,
                screenStroke: NSColor.white.withAlphaComponent(0.35).cgColor,
                regionFill: accent.withAlphaComponent(hovered ? 1.0 : 0.85).cgColor,
                regionStroke: accent.cgColor,
                cornerRadius: 3)
            GlyphRenderer.draw(layout, in: ctx, rect: glyphArea, style: style)

            if showTitles, titleHeight > 0 {
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .center
                paragraph.lineBreakMode = .byTruncatingTail
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 9, weight: .medium),
                    .foregroundColor: NSColor.white.withAlphaComponent(hovered ? 1.0 : 0.75),
                    .paragraphStyle: paragraph,
                ]
                let titleRect = CGRect(x: cell.minX + 2, y: cell.maxY - titleHeight - 1,
                                       width: cell.width - 4, height: titleHeight)
                (layout.name as NSString).draw(in: titleRect, withAttributes: attributes)
            }
        }
    }
}
