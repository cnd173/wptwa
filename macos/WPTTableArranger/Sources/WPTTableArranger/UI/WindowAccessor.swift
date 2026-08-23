import SwiftUI
import AppKit

/// Lets a SwiftUI view fetch a reference to its own hosting NSWindow (used so secondary
/// panel content can close itself, mirroring tkinter Toplevel.destroy()).
struct WindowAccessor: NSViewRepresentable {
    let callback: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { callback(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
