import AppKit
import ApplicationServices

/// Permission gate — the one macOS permission this app needs (covers reading/moving other
/// apps' windows and the global mouse monitor used for manual-drag detection). Window titles
/// are read through this same Accessibility API rather than CGWindowListCopyWindowInfo, so
/// Screen Recording permission is never required.
enum Accessibility {
    static func isTrusted(promptIfNeeded: Bool = false) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let opts = [key: promptIfNeeded] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Thin wrapper around a single AXUIElement window, mirroring the role an HWND plays in the
/// Windows build's window_manager.py. Identity/equality is based on CFEqual over the
/// underlying accessibility object, which stays stable across repeated attribute queries for
/// the same real window (unlike the Swift wrapper instance itself).
final class AXWindow: Hashable {
    let element: AXUIElement
    let pid: pid_t

    init(element: AXUIElement, pid: pid_t) {
        self.element = element
        self.pid = pid
    }

    static func == (lhs: AXWindow, rhs: AXWindow) -> Bool {
        CFEqual(lhs.element, rhs.element)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(CFHash(element))
    }

    var title: String? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value)
        guard err == .success, let str = value as? String else { return nil }
        return str
    }

    var isMinimized: Bool {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, kAXMinimizedAttribute as CFString, &value)
        guard err == .success, let flag = value as? Bool else { return false }
        return flag
    }

    /// True while this AXUIElement still resolves to a live window (false once closed/gone).
    var isAlive: Bool {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &value) == .success
    }

    func position() -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &value) == .success,
              let axValue = value else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(axValue as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    func size() -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &value) == .success,
              let axValue = value else { return nil }
        var s = CGSize.zero
        guard AXValueGetValue(axValue as! AXValue, .cgSize, &s) else { return nil }
        return s
    }

    /// Analogous to get_window_pos in window_manager.py.
    func frame() -> WindowRect? {
        guard let p = position(), let s = size() else { return nil }
        return WindowRect(x: Int(p.x), y: Int(p.y), width: Int(s.width), height: Int(s.height))
    }

    @discardableResult
    private func setPosition(_ point: CGPoint) -> Bool {
        var p = point
        guard let axValue = AXValueCreate(.cgPoint, &p) else { return false }
        return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, axValue) == .success
    }

    @discardableResult
    private func setSize(_ size: CGSize) -> Bool {
        var s = size
        guard let axValue = AXValueCreate(.cgSize, &s) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, axValue) == .success
    }

    /// Move+resize, restoring from minimized first — mirrors move_window in window_manager.py.
    /// Returns the rect actually observed right after, which can differ from `rect`: some
    /// windows (WPT's poker tables in particular) silently clamp/ignore a size they won't
    /// accept while still honoring the position, so the caller reads this back to learn the
    /// window's natural size instead of assuming the request took effect.
    @discardableResult
    func moveAndResize(_ rect: WindowRect) -> WindowRect? {
        if isMinimized {
            AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, false as CFTypeRef)
        }
        setPosition(CGPoint(x: rect.x, y: rect.y))
        setSize(CGSize(width: rect.width, height: rect.height))
        return frame()
    }
}

enum AXAppWindows {
    /// All top-level windows exposed by the Accessibility API for a given pid.
    static func windows(forPID pid: pid_t) -> [AXWindow] {
        let appElement = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)
        guard err == .success, let windows = value as? [AXUIElement] else { return [] }
        return windows.map { AXWindow(element: $0, pid: pid) }
    }
}
