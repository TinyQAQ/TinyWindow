import AppKit
import TinyWindowCore

/// One screen's pad overlay: a borderless, non-activating panel that never
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
        panel.contentView = stripView
    }

    func present(geometry: PadStripGeometry) {
        fadeGeneration += 1
        panel.setFrame(geometry.panelFrameC, display: false)
        stripView.update(geometry: geometry)
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
        panel.setFrame(CGRect(x: 0, y: 0, width: 200, height: 140), display: true)
        panel.orderFrontRegardless()
        panel.orderOut(nil)
    }

    func close() {
        panel.orderOut(nil)
        panel.close()
    }
}

/// Hand-drawn Window Tidy-style pads: translucent mini screens with grid
/// lines, each covered region filled; the hovered region lights up.
final class PadStripView: NSView {
    override var isFlipped: Bool { true }

    /// Region hues for grouped pads — high mutual contrast on the dark body.
    static let regionPalette: [NSColor] = [
        .systemBlue, .systemGreen, .systemOrange, .systemPurple,
        .systemTeal, .systemPink, .systemYellow, .systemIndigo,
    ]

    private var pads: [PadRender] = []
    private var titleHeight: CGFloat = 0

    var hoveredLayoutID: UUID? {
        didSet { if hoveredLayoutID != oldValue { needsDisplay = true } }
    }

    func update(geometry: PadStripGeometry) {
        pads = geometry.pads
        titleHeight = geometry.titleHeight
        hoveredLayoutID = nil
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        for pad in pads {
            let padHovered = pad.regions.contains { $0.layoutID == hoveredLayoutID }

            // Mini screen body.
            let body = NSBezierPath(roundedRect: pad.frameLocal, xRadius: 8, yRadius: 8)
            NSColor(calibratedRed: 0.09, green: 0.13, blue: 0.20, alpha: padHovered ? 0.78 : 0.62).setFill()
            body.fill()
            NSColor.white.withAlphaComponent(padHovered ? 0.65 : 0.38).setStroke()
            body.lineWidth = padHovered ? 2 : 1.2
            body.stroke()

            // Grid lines.
            let inner = pad.frameLocal.insetBy(dx: 1.5, dy: 1.5)
            if let columns = pad.gridColumns, let rows = pad.gridRows,
               columns > 1 || rows > 1 {
                let gridPath = NSBezierPath()
                gridPath.lineWidth = 0.5
                for i in 1..<max(1, columns) {
                    let x = inner.minX + GridMath.boundary(i, count: columns, length: inner.width)
                    gridPath.move(to: CGPoint(x: x, y: inner.minY))
                    gridPath.line(to: CGPoint(x: x, y: inner.maxY))
                }
                for i in 1..<max(1, rows) {
                    let y = inner.minY + GridMath.boundary(i, count: rows, length: inner.height)
                    gridPath.move(to: CGPoint(x: inner.minX, y: y))
                    gridPath.line(to: CGPoint(x: inner.maxX, y: y))
                }
                NSColor.white.withAlphaComponent(0.14).setStroke()
                gridPath.stroke()
            }

            // Regions: distinct hue per region so grouped pads read at a
            // glance ("which layouts live in this pad").
            for (regionIndex, region) in pad.regions.enumerated() {
                let hovered = region.layoutID == hoveredLayoutID
                let hue = Self.regionPalette[regionIndex % Self.regionPalette.count]
                let path = NSBezierPath(roundedRect: region.rectLocal.insetBy(dx: 1, dy: 1),
                                        xRadius: 4, yRadius: 4)
                hue.withAlphaComponent(hovered ? 0.95 : 0.60).setFill()
                path.fill()
                hue.withAlphaComponent(hovered ? 1.0 : 0.9).setStroke()
                path.lineWidth = hovered ? 1.5 : 1
                path.stroke()
                if hovered {
                    // White ring so the active choice pops on any hue.
                    let ring = NSBezierPath(roundedRect: region.rectLocal.insetBy(dx: -0.5, dy: -0.5),
                                            xRadius: 5, yRadius: 5)
                    NSColor.white.withAlphaComponent(0.95).setStroke()
                    ring.lineWidth = 2
                    ring.stroke()
                }
            }

            // Label: the hovered layout's name wins over the group label.
            if titleHeight > 0 {
                let hoveredName = pad.regions.first { $0.layoutID == hoveredLayoutID }?.name
                let text = hoveredName ?? pad.label
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .center
                paragraph.lineBreakMode = .byTruncatingTail
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 12, weight: padHovered ? .semibold : .medium),
                    .foregroundColor: NSColor.white.withAlphaComponent(padHovered ? 1.0 : 0.82),
                    .paragraphStyle: paragraph,
                ]
                let titleRect = CGRect(x: pad.frameLocal.minX - 30,
                                       y: pad.frameLocal.maxY + 3,
                                       width: pad.frameLocal.width + 60,
                                       height: titleHeight - 3)
                (text as NSString).draw(in: titleRect, withAttributes: attributes)
            }
        }
    }
}
