import Foundation

/// Direct port of window_manager.py's classification rules.
/// Table titles look like "HLB7110 - 0.05/0.10/0.20(0.05) - NLHE"; the lobby title is dynamic
/// (shows current time), so we positively identify tables/history and treat everything else
/// as lobby.
enum WindowClassifier {
    static let historyKeywords = ["hand history", "handhistory", "hand-history"]
    static let tableGameTypes = [" - nlhe", " - plo", " - ofc", " - mtt", " - sng"]

    enum Kind: Equatable {
        case lobby, history, table
    }

    static func classify(title: String) -> Kind {
        let t = title.lowercased()
        if historyKeywords.contains(where: { t.contains($0) }) {
            return .history
        }
        if t.hasPrefix("hl") || tableGameTypes.contains(where: { t.hasSuffix($0) }) {
            return .table
        }
        return .lobby
    }
}

/// Explicit compatibility allowlist. Matching by exact bundle identifier prevents this app
/// from touching unrelated processes whose names happen to contain "wpt" or "poker".
enum TargetPokerClient {
    static let supportedBundleIdentifiers: Set<String> = [
        "com.wptglobal.wptg",
    ]

    static func supports(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return supportedBundleIdentifiers.contains(bundleIdentifier)
    }
}
