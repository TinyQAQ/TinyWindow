import Foundation
import CoreGraphics
import TinyWindowCore

/// Owns the CGEventTap and its dedicated thread + run loop. The tap is
/// listen-only and its mask deliberately excludes mouseMoved: an idle system
/// delivers zero events to this process. Events are forwarded synchronously to
/// the DragSessionController on the tap thread.
final class EventTapService: @unchecked Sendable {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapRunLoop: CFRunLoop?
    private var thread: Thread?
    private var controller: DragSessionController?
    private let ready = DispatchSemaphore(value: 0)

    var isRunning: Bool { tap != nil }

    var tapEnabled: Bool {
        guard let tap else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    /// Returns false when the tap cannot be created (Accessibility not granted).
    func start(controller: DragSessionController) -> Bool {
        guard tap == nil else { return true }
        // Pure-mouse mask, deliberately: flagsChanged is a KEYBOARD-class
        // event, and listening to any keyboard event silently requires the
        // separate Input Monitoring permission on modern macOS — without it
        // the tap looks healthy but receives NOTHING. Option-key state is
        // read from the mouse events' own flags plus a cheap flagsState poll.
        let mask: CGEventMask =
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: tinyWindowTapCallback,
            userInfo: Unmanaged.passUnretained(controller).toOpaque())
        else { return false }

        self.controller = controller // keeps the refcon target alive
        self.tap = tap
        let thread = Thread { [self] in
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            self.runLoopSource = source
            self.tapRunLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            self.ready.signal()
            CFRunLoopRun()
        }
        thread.name = "TinyWindow.EventTap"
        thread.qualityOfService = .userInteractive
        self.thread = thread
        thread.start()
        // Wait (milliseconds) until the run loop is set up so perform() is valid.
        ready.wait()
        return true
    }

    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source = runLoopSource, let runLoop = tapRunLoop {
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
            CFRunLoopStop(runLoop)
        }
        self.tap = nil
        self.runLoopSource = nil
        self.tapRunLoop = nil
        self.thread = nil
        self.controller = nil
    }

    func reenable() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    /// Runs a block on the tap thread — how resolver results and watchdog
    /// checks reach the tap-thread-confined state machine.
    func perform(_ block: @escaping @Sendable () -> Void) {
        guard let runLoop = tapRunLoop else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue, block)
        CFRunLoopWakeUp(runLoop)
    }
}

private func tinyWindowTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<DragSessionController>.fromOpaque(refcon).takeUnretainedValue()
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        EngineDiagnostics.log("tap: DISABLED by \(type == .tapDisabledByTimeout ? "timeout" : "user input")")
        controller.tapWasDisabled()
    case .leftMouseDown, .leftMouseDragged, .leftMouseUp:
        // NX_SUBTYPE_MOUSE_TOUCH (3): pointer events synthesized from trackpad
        // touches — distinguishes three-finger drags from physical-button drags.
        controller.handleMouse(
            type,
            location: QPoint(rawQuartz: event.location),
            optionDown: event.flags.contains(.maskAlternate),
            isTouch: event.getIntegerValueField(.mouseEventSubtype) == 3)
    default:
        break
    }
    return Unmanaged.passUnretained(event)
}
