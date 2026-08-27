import CoreGraphics
import TinyWindowCore

func runCoordinateSpaceChecks() {
    print("— CoordinateSpace")

    // Screen configurations as Cocoa frames; the primary is the one at origin zero.
    let configs: [[CGRect]] = [
        // Dual 5K side by side, secondary LEFT of primary (negative x) — the dev machine.
        [CGRect(x: 0, y: 0, width: 2560, height: 1440),
         CGRect(x: -2560, y: 0, width: 2560, height: 1440)],
        // Secondary ABOVE the primary.
        [CGRect(x: 0, y: 0, width: 2560, height: 1440),
         CGRect(x: 300, y: 1440, width: 1920, height: 1080)],
        // Secondary BELOW the primary (negative Cocoa y).
        [CGRect(x: 0, y: 0, width: 2560, height: 1440),
         CGRect(x: -500, y: -1080, width: 1920, height: 1080)],
    ]

    for config in configs {
        let H = CoordinateSpace.primaryHeight(cocoaScreenFrames: config)
        expect(H == 1440, "primaryHeight picks the origin-zero screen")
        for frame in config {
            let quartz = CoordinateSpace.quartz(fromCocoa: frame, primaryHeight: H)
            expect(CoordinateSpace.cocoa(fromQuartz: quartz, primaryHeight: H) == frame,
                   "rect round-trip identity for \(frame)")
        }
    }

    let H: CGFloat = 1440
    for p in [CGPoint(x: 0, y: 0), CGPoint(x: -2000, y: 700), CGPoint(x: 2559, y: 1439)] {
        let q = CoordinateSpace.quartz(fromCocoa: p, primaryHeight: H)
        expect(CoordinateSpace.cocoa(fromQuartz: q, primaryHeight: H) == p,
               "point round-trip identity for \(p)")
    }

    // Known values.
    expect(CoordinateSpace.quartz(fromCocoa: CGPoint(x: 0, y: 1440), primaryHeight: H)
           == QPoint(x: 0, y: 0), "primary Cocoa top-left is Quartz origin")
    let above = CGRect(x: 0, y: 1440, width: 2560, height: 1440)
    expect(CoordinateSpace.quartz(fromCocoa: above, primaryHeight: H)
           == QRect(x: 0, y: -1440, width: 2560, height: 1440),
           "screen above primary has negative Quartz y")
    let left = CGRect(x: -2560, y: 0, width: 2560, height: 1440)
    expect(CoordinateSpace.quartz(fromCocoa: left, primaryHeight: H)
           == QRect(x: -2560, y: 0, width: 2560, height: 1440),
           "equal-height left screen maps to identical numbers")

    // QRect.contains excludes max edges, like CGRect.
    let rect = QRect(x: 0, y: 0, width: 100, height: 100)
    expect(rect.contains(QPoint(x: 0, y: 0)), "contains min corner")
    expect(rect.contains(QPoint(x: 99.9, y: 99.9)), "contains interior")
    expect(!rect.contains(QPoint(x: 100, y: 50)), "excludes maxX edge")
    expect(!rect.contains(QPoint(x: 50, y: 100)), "excludes maxY edge")
}
