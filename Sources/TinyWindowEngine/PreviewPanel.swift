import AppKit

/// Highlights the drop target rect on the destination screen while a pad is
/// hovered. Same non-activating, mouse-transparent configuration as the strip,
/// one level below it so the strip always renders on top.
@MainActor
final class PreviewPanel {
    private let panel: NSPanel

    init() {
        panel = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.level = .statusBar
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
        panel.contentView = PreviewView()
    }

    func show(frameC: CGRect) {
        panel.setFrame(frameC, display: true)
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.alphaValue = 0
        panel.orderOut(nil)
    }

    func close() {
        panel.orderOut(nil)
        panel.close()
    }
}

private final class PreviewView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let accent = NSColor.controlAccentColor
        let rect = bounds.insetBy(dx: 1.5, dy: 1.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        accent.withAlphaComponent(0.18).setFill()
        path.fill()
        accent.withAlphaComponent(0.9).setStroke()
        path.lineWidth = 2.5
        path.stroke()
    }
}
