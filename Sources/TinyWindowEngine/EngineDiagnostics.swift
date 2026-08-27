import Foundation
import os

/// Opt-in diagnostic logging for bug reports:
///   defaults write com.tinyqaq.TinyWindow debugLogging -bool YES   (+ relaunch)
///   log show --last 5m --predicate 'subsystem == "com.tinyqaq.TinyWindow"'
/// Off by default; log volume is a handful of lines per drag.
enum EngineDiagnostics {
    /// Written once at engine start/config; benign cross-thread reads.
    nonisolated(unsafe) static var enabled = false

    private static let logger = Logger(subsystem: "com.tinyqaq.TinyWindow", category: "engine")
    private static let fileQueue = DispatchQueue(label: "com.tinyqaq.TinyWindow.diag")
    static let fileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/TinyWindow/debug.log")

    static func log(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        let text = message()
        logger.notice("\(text, privacy: .public)")
        let line = "\(String(format: "%.3f", Date().timeIntervalSince1970)) \(text)\n"
        fileQueue.async {
            let fm = FileManager.default
            try? fm.createDirectory(at: fileURL.deletingLastPathComponent(),
                                    withIntermediateDirectories: true)
            if let handle = FileHandle(forWritingAtPath: fileURL.path) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: fileURL)
            }
        }
    }

    /// Called at engine start: cap the file so it never grows unbounded.
    static func rotateIfNeeded() {
        fileQueue.async {
            let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
            if let size = attributes?[.size] as? Int, size > 1_000_000 {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
    }
}
