import AppKit
import SwiftUI

@main
struct PokerTableArrangerMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var appModel: AppModel?
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        setupStatusItem()
        showGateOrMain()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false // lives in the menu bar even with no window open, like the tray build did
    }

    // MARK: - Menu bar

    private func setupMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        let quitItem = NSMenuItem(title: "Quit Poker Table Arranger", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        appMenu.addItem(quitItem)
        appMenuItem.submenu = appMenu
        NSApp.mainMenu = mainMenu
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "rectangle.split.3x1", accessibilityDescription: "Poker Table Arranger"
        )
        let menu = NSMenu()
        let showItem = NSMenuItem(title: "Show", action: #selector(showMain), keyEquivalent: "")
        showItem.target = self
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(showItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
        item.menu = menu
        statusItem = item
    }

    // MARK: - Accessibility gate

    private func showGateOrMain() {
        if Accessibility.isTrusted(promptIfNeeded: true) {
            startMainApp()
        } else {
            showAccessibilityGate()
        }
    }

    private func showAccessibilityGate() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        window.title = "Poker Table Arranger"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: AccessibilityGateView { [weak self] in
            self?.recheckPermission()
        })
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        mainWindow = window

        permissionTimer?.invalidate()
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in self?.recheckPermission() }
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer
    }

    private func recheckPermission() {
        guard Accessibility.isTrusted(promptIfNeeded: false) else { return }
        permissionTimer?.invalidate()
        permissionTimer = nil
        mainWindow?.close()
        mainWindow = nil
        startMainApp()
    }

    // MARK: - Main app

    private func startMainApp() {
        let model = AppModel()
        appModel = model

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 320),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false
        )
        window.title = "Poker Table Arranger"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()
        window.contentView = NSHostingView(rootView: MainView(model: model))
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        mainWindow = window

        // Arrangement is deliberately opt-in. Accessibility access alone must never cause
        // this utility to move a user's live poker windows.
    }

    @objc private func showMain() {
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        appModel?.slotManager.stop()
        NSApp.terminate(nil)
    }
}

extension AppDelegate: NSWindowDelegate {
    /// Hide to the menu-bar "tray" instead of closing, mirroring _hide_to_tray in main.py.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}
