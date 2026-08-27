// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "TinyWindow",
    platforms: [.macOS("26.0")],
    targets: [
        // Pure logic: models, grid math, coordinate conversion, persistence, importer.
        // No AppKit — fully unit-testable headless.
        .target(name: "TinyWindowCore"),
        // Drag detection (CGEventTap), AX window control, per-screen overlay panels.
        .target(name: "TinyWindowEngine", dependencies: ["TinyWindowCore"]),
        // App shell: status item, onboarding, SwiftUI settings.
        .executableTarget(name: "TinyWindow", dependencies: ["TinyWindowCore", "TinyWindowEngine"]),
        // The check suite is a plain executable (`make test`) because the
        // Command Line Tools ship no usable XCTest/Swift Testing runner —
        // one dialect that runs identically on dev machines and CI.
        .executableTarget(name: "tinywindow-checks",
                          dependencies: ["TinyWindowCore"],
                          resources: [.copy("Fixtures")]),
    ]
)
