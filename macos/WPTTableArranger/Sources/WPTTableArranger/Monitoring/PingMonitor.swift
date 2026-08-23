import Foundation

/// Port of the ping/server-detection half of MonitorWindow in main.py.
/// macOS `ping` uses `-t timeout` for an overall deadline in seconds (unlike Linux, where
/// `-t` sets TTL) and `-c count` for packet count — the BSD ping analogue of Windows'
/// `ping -n 1 -w 2000`.
final class PingMonitor {
    static let historyLimit = 60

    private(set) var pings: [Int] = []
    private(set) var loss = 0
    private(set) var total = 0
    private(set) var target: String?

    func detectServer(completion: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let host = Self.detectWPTServer()
            DispatchQueue.main.async { [weak self] in
                self?.target = host
                completion(host)
            }
        }
    }

    private static func detectWPTServer() -> String {
        for pid in WindowManager.targetPIDs() {
            let output = ShellRunner.run("/usr/sbin/lsof", ["-a", "-p", String(pid), "-i", "-n", "-P"])
            for line in output.split(separator: "\n") {
                guard line.contains("ESTABLISHED"), let arrowRange = line.range(of: "->") else { continue }
                let after = line[arrowRange.upperBound...]
                guard let colonRange = after.range(of: ":") else { continue }
                let ip = String(after[after.startIndex..<colonRange.lowerBound])
                if !isPrivateOrLoopback(ip) {
                    return ip
                }
            }
        }
        return "wptglobal.com"
    }

    private static func isPrivateOrLoopback(_ ip: String) -> Bool {
        if ip == "::1" || ip.hasPrefix("127.") || ip.hasPrefix("192.168.") || ip.hasPrefix("10.") {
            return true
        }
        if ip.hasPrefix("172.") {
            let parts = ip.split(separator: ".")
            if parts.count > 1, let second = Int(parts[1]), (16...31).contains(second) {
                return true
            }
        }
        return false
    }

    /// Blocking (~1s worst case) — call from a background queue.
    @discardableResult
    func pingOnce() -> Int? {
        total += 1
        guard let target else { loss += 1; return nil }
        let output = ShellRunner.run("/sbin/ping", ["-c", "1", "-t", "1", target])
        guard let ms = Self.parsePing(output) else {
            loss += 1
            return nil
        }
        pings.append(ms)
        if pings.count > Self.historyLimit { pings.removeFirst() }
        return ms
    }

    private static func parsePing(_ output: String) -> Int? {
        guard let range = output.range(of: #"time[=<](\d+(\.\d+)?)"#, options: .regularExpression) else {
            return nil
        }
        let match = output[range]
        guard let eqIdx = match.firstIndex(where: { $0 == "=" || $0 == "<" }) else { return nil }
        let numberPart = match[match.index(after: eqIdx)...]
        return Double(numberPart).map { Int($0.rounded()) }
    }

    func reset() {
        pings.removeAll()
        loss = 0
        total = 0
    }
}
