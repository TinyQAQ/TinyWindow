// Generates assets/icon-1024.png — a placeholder app icon drawn in code so the
// repo needs no binary design assets. Run: swift scripts/gen-icon.swift
import AppKit

let pixels = 1024
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
else { fatalError("bitmap rep") }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let accent = NSColor(calibratedRed: 0.30, green: 0.63, blue: 1.00, alpha: 1)

// Background: rounded dark slate square with a subtle vertical gradient.
let bgRect = CGRect(x: 64, y: 64, width: 896, height: 896)
let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: 200, yRadius: 200)
NSGradient(colors: [
    NSColor(calibratedRed: 0.16, green: 0.18, blue: 0.26, alpha: 1),
    NSColor(calibratedRed: 0.06, green: 0.07, blue: 0.12, alpha: 1),
])!.draw(in: bgPath, angle: -90)

// Mini screen.
let screenRect = CGRect(x: 208, y: 296, width: 608, height: 432)
let screenPath = NSBezierPath(roundedRect: screenRect, xRadius: 40, yRadius: 40)
NSColor.white.withAlphaComponent(0.10).setFill()
screenPath.fill()
NSColor.white.withAlphaComponent(0.85).setStroke()
screenPath.lineWidth = 20
screenPath.stroke()

// Left half: filled accent pad.
let inset: CGFloat = 34
let gap: CGFloat = 22
let innerRect = screenRect.insetBy(dx: inset, dy: inset)
let halfWidth = (innerRect.width - gap) / 2
let leftHalf = CGRect(x: innerRect.minX, y: innerRect.minY,
                      width: halfWidth, height: innerRect.height)
accent.setFill()
NSBezierPath(roundedRect: leftHalf, xRadius: 22, yRadius: 22).fill()

// Right side: two stacked quarter pads, outlined.
let quarterHeight = (innerRect.height - gap) / 2
for row in 0..<2 {
    let quarter = CGRect(x: innerRect.minX + halfWidth + gap,
                         y: innerRect.minY + CGFloat(row) * (quarterHeight + gap),
                         width: halfWidth, height: quarterHeight)
    let path = NSBezierPath(roundedRect: quarter, xRadius: 22, yRadius: 22)
    accent.withAlphaComponent(0.25).setFill()
    path.fill()
    accent.setStroke()
    path.lineWidth = 12
    path.stroke()
}

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
try! FileManager.default.createDirectory(atPath: "assets", withIntermediateDirectories: true)
try! png.write(to: URL(fileURLWithPath: "assets/icon-1024.png"))
print("Wrote assets/icon-1024.png")
