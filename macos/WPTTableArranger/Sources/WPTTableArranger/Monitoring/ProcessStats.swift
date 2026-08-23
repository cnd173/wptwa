import Foundation

/// Port of _proc_stats/_own_stats in main.py — psutil replaced with a `ps` shell-out.
enum ProcessStats {
    static func stats(pid: pid_t) -> (cpu: Double, ramMB: Int)? {
        let output = ShellRunner.run("/bin/ps", ["-o", "%cpu=,rss=", "-p", String(pid)])
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2, let cpu = Double(parts[0]), let rssKB = Double(parts[1]) else { return nil }
        return (cpu, Int(rssKB / 1024))
    }

    static func wptStats() -> (cpu: Double, ramMB: Int)? {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        for pid in WindowManager.targetPIDs() where pid != ownPID {
            if let s = stats(pid: pid) { return s }
        }
        return nil
    }

    static func ownStats() -> (cpu: Double, ramMB: Int) {
        stats(pid: ProcessInfo.processInfo.processIdentifier) ?? (0.0, 0)
    }
}
