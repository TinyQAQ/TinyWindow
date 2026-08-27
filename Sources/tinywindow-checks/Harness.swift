import Foundation

/// 30-line check harness. Single-threaded by construction.
enum Checks {
    nonisolated(unsafe) static var failures = 0
    nonisolated(unsafe) static var passes = 0

    static func summaryAndExit() -> Never {
        if failures == 0 {
            print("✔ All \(passes) checks passed")
            exit(0)
        } else {
            print("✖ \(failures) of \(passes + failures) checks FAILED")
            exit(1)
        }
    }
}

func expect(_ condition: @autoclosure () -> Bool,
            _ message: @autoclosure () -> String = "",
            file: StaticString = #filePath, line: UInt = #line) {
    if condition() {
        Checks.passes += 1
    } else {
        Checks.failures += 1
        let name = URL(fileURLWithPath: "\(file)").lastPathComponent
        print("FAIL \(name):\(line) \(message())")
    }
}

func fail(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
    expect(false, message, file: file, line: line)
}
