import AppKit
import SwiftUI

/// Small non-resizable, floating NSWindow hosting SwiftUI content — replaces tkinter's
/// `resizable(False, False)` + `attributes('-topmost', True)` Toplevel windows.
final class PanelWindowController: NSWindowController {
    convenience init<Content: View>(title: String, width: CGFloat, height: CGFloat, content: Content) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()
        window.contentView = NSHostingView(rootView: content.frame(width: width, height: height))
        self.init(window: window)
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
