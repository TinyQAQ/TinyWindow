import AppKit

// Classic AppKit bootstrap (an SPM executable can't combine `main.swift` with
// @main, and the SwiftUI App lifecycle brings settings-scene problems in an
// LSUIElement app — see docs/ARCHITECTURE.md).

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
MainMenuBuilder.install(into: app)
app.run()
