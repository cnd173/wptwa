import AppKit

struct ClassifiedWindows {
    var lobby: [AXWindow] = []
    var history: [AXWindow] = []
    var table: [AXWindow] = []

    var all: [AXWindow] { lobby + history + table }
}

/// Enumerates and classifies WPT windows by pid + AX title — the macOS analogue of
/// window_manager.py's classify_wpt_windows(), backed by NSWorkspace + the Accessibility API
/// instead of win32gui.EnumWindows.
enum WindowManager {
    private static var cachedPIDs: [pid_t] = []
    private static var lastScan: TimeInterval = 0
    private static let pidCacheTTL: TimeInterval = 10.0
    private static let cacheLock = NSLock()

    /// PIDs of explicitly supported poker clients (own process excluded).
    /// Cached for pidCacheTTL seconds so we don't rescan all running apps on every poll.
    static func targetPIDs() -> [pid_t] {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        let now = ProcessInfo.processInfo.systemUptime
        if now - lastScan < pidCacheTTL {
            return cachedPIDs
        }
        lastScan = now
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let pids = NSWorkspace.shared.runningApplications.compactMap { app -> pid_t? in
            guard app.processIdentifier != ownPID else { return nil }
            guard TargetPokerClient.supports(bundleIdentifier: app.bundleIdentifier) else { return nil }
            return app.processIdentifier
        }
        cachedPIDs = pids
        return pids
    }

    static func invalidateTargetCache() {
        cacheLock.lock()
        cachedPIDs = []
        lastScan = 0
        cacheLock.unlock()
    }

    static func classifiedWindows() -> ClassifiedWindows {
        var result = ClassifiedWindows()
        for pid in targetPIDs() {
            for win in AXAppWindows.windows(forPID: pid) {
                guard let title = win.title, !title.isEmpty else { continue }
                switch WindowClassifier.classify(title: title) {
                case .lobby: result.lobby.append(win)
                case .history: result.history.append(win)
                case .table: result.table.append(win)
                case .ignored: continue
                }
            }
        }
        return result
    }
}
