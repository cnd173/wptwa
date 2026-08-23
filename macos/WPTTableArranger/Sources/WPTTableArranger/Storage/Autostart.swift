import Foundation
import ServiceManagement

/// SMAppService-backed replacement for the winreg Run-key autostart in config.py.
/// Only works from a properly bundled .app (same "not available from source" limitation
/// the Windows build already had for unfrozen dev runs).
enum Autostart {
    static var isRunningFromBundledApp: Bool {
        Bundle.main.bundlePath.hasSuffix(".app")
    }

    static func isEnabled() -> Bool {
        guard isRunningFromBundledApp else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    /// Returns nil on success, or an error message to surface to the user.
    static func setEnabled(_ enabled: Bool) -> String? {
        guard isRunningFromBundledApp else {
            return "not_available"
        }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
