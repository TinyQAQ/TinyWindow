import Foundation
import ApplicationServices
import TinyWindowCore

/// Thin Sendable wrapper — AXUIElement is a CF token that may be messaged from
/// any single thread; TinyWindow confines all AX calls to the axQueue (plus
/// trust checks, which are safe anywhere).
struct AXElement: @unchecked Sendable {
    let raw: AXUIElement
}

/// All Accessibility calls in the app go through here.
/// Every call is a synchronous mach IPC into the target app — never call these
/// on the tap thread or the main thread (trust checks excepted).
enum AX {
    static let systemWide = AXElement(raw: AXUIElementCreateSystemWide())

    /// Setting the timeout on the system-wide element sets the process-global
    /// default: a hung app costs at most this long per call.
    static func configureGlobalTimeout(seconds: Float = 0.25) {
        AXUIElementSetMessagingTimeout(systemWide.raw, seconds)
    }

    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    static func promptForTrust() -> Bool {
        // Raw key: kAXTrustedCheckOptionPrompt is a mutable global CFString and
        // trips Swift 6 concurrency checking.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Hit testing & hierarchy

    static func element(at point: QPoint) -> AXElement? {
        var element: AXUIElement?
        let error = AXUIElementCopyElementAtPosition(
            systemWide.raw, Float(point.x), Float(point.y), &element)
        guard error == .success, let element else { return nil }
        return AXElement(raw: element)
    }

    /// The AXWindow containing an element: the element itself, its
    /// kAXWindowAttribute, or a walk up the parent chain.
    static func window(containing element: AXElement) -> AXElement? {
        if role(of: element) == kAXWindowRole { return element }
        if let window = elementAttribute(element, kAXWindowAttribute) { return window }
        var current = element
        for _ in 0..<20 {
            guard let parent = elementAttribute(current, kAXParentAttribute) else { return nil }
            if role(of: parent) == kAXWindowRole { return parent }
            current = parent
        }
        return nil
    }

    static func role(of element: AXElement) -> String? {
        guard let ref = copyAttribute(element, kAXRoleAttribute),
              CFGetTypeID(ref) == CFStringGetTypeID() else { return nil }
        return (ref as! CFString) as String
    }

    static func pid(of element: AXElement) -> pid_t? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element.raw, &pid) == .success else { return nil }
        return pid
    }

    static func appElement(pid: pid_t) -> AXElement {
        AXElement(raw: AXUIElementCreateApplication(pid))
    }

    /// Focused window of an app, falling back to main window, then first window.
    static func focusedWindow(pid: pid_t) -> AXElement? {
        let app = appElement(pid: pid)
        if let window = elementAttribute(app, kAXFocusedWindowAttribute) { return window }
        if let window = elementAttribute(app, kAXMainWindowAttribute) { return window }
        if let ref = copyAttribute(app, kAXWindowsAttribute),
           CFGetTypeID(ref) == CFArrayGetTypeID(),
           let array = ref as? [AnyObject] {
            for item in array where CFGetTypeID(item) == AXUIElementGetTypeID() {
                return AXElement(raw: item as! AXUIElement)
            }
        }
        return nil
    }

    // MARK: - Geometry

    static func position(of element: AXElement) -> QPoint? {
        guard let value = axValueAttribute(element, kAXPositionAttribute) else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(value, .cgPoint, &point) else { return nil }
        return QPoint(rawQuartz: point)
    }

    static func size(of element: AXElement) -> CGSize? {
        guard let value = axValueAttribute(element, kAXSizeAttribute) else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(value, .cgSize, &size) else { return nil }
        return size
    }

    static func frame(of element: AXElement) -> QRect? {
        guard let position = position(of: element), let size = size(of: element) else { return nil }
        return QRect(x: position.x, y: position.y, width: size.width, height: size.height)
    }

    @discardableResult
    static func setPosition(_ position: QPoint, of element: AXElement) -> AXError {
        var point = position.rawQuartz
        guard let value = AXValueCreate(.cgPoint, &point) else { return .failure }
        return AXUIElementSetAttributeValue(element.raw, kAXPositionAttribute as CFString, value)
    }

    @discardableResult
    static func setSize(_ size: CGSize, of element: AXElement) -> AXError {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return .failure }
        return AXUIElementSetAttributeValue(element.raw, kAXSizeAttribute as CFString, value)
    }

    /// Per-element timeout override; 0 restores the process-global default.
    static func setMessagingTimeout(_ element: AXElement, seconds: Float) {
        AXUIElementSetMessagingTimeout(element.raw, seconds)
    }

    // MARK: - Misc attributes

    static func boolAttribute(_ element: AXElement, _ name: String) -> Bool? {
        guard let ref = copyAttribute(element, name),
              CFGetTypeID(ref) == CFBooleanGetTypeID() else { return nil }
        return CFBooleanGetValue((ref as! CFBoolean))
    }

    @discardableResult
    static func setBoolAttribute(_ element: AXElement, _ name: String, _ value: Bool) -> AXError {
        AXUIElementSetAttributeValue(
            element.raw, name as CFString,
            (value ? kCFBooleanTrue : kCFBooleanFalse) as CFTypeRef)
    }

    // MARK: - Plumbing

    private static func copyAttribute(_ element: AXElement, _ name: String) -> CFTypeRef? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element.raw, name as CFString, &ref) == .success else {
            return nil
        }
        return ref
    }

    private static func elementAttribute(_ element: AXElement, _ name: String) -> AXElement? {
        guard let ref = copyAttribute(element, name),
              CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        return AXElement(raw: (ref as! AXUIElement))
    }

    private static func axValueAttribute(_ element: AXElement, _ name: String) -> AXValue? {
        guard let ref = copyAttribute(element, name),
              CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
        return (ref as! AXValue)
    }
}
