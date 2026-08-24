import Foundation

/// Conservative WPT window classification rules.
///
/// Unknown windows must never be moved. WPT can expose cashier, authentication, security and
/// transient dialog windows through AX alongside its lobby and tables, so classification uses
/// positive matches and returns `.ignored` for everything else.
enum WindowClassifier {
    static let historyKeywords = ["hand history", "handhistory", "hand-history"]
    static let tableGameTypes = [" - nlhe", " - plo", " - ofc", " - mtt", " - sng"]

    enum Kind: Equatable {
        case lobby, history, table, ignored
    }

    static func classify(title: String) -> Kind {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if historyKeywords.contains(where: { t.contains($0) }) {
            return .history
        }
        if hasTableIdentifierPrefix(t) || tableGameTypes.contains(where: { t.hasSuffix($0) }) {
            return .table
        }
        if t == "wpt global" || isDynamicLobbyTitle(t) {
            return .lobby
        }
        return .ignored
    }

    private static func hasTableIdentifierPrefix(_ title: String) -> Bool {
        guard let token = title.split(separator: " ", maxSplits: 1).first,
              token.count >= 4,
              token.hasPrefix("hl") else { return false }
        return token.dropFirst(2).allSatisfy { $0.isLetter || $0.isNumber }
    }

    /// Current WPT lobby titles look like "15:13 Indochina Time". Keep this deliberately
    /// narrow: a future title change should make the window ignored until the adapter is
    /// updated, not make an unrelated dialog movable.
    private static func isDynamicLobbyTitle(_ title: String) -> Bool {
        guard title.hasSuffix(" time"),
              let first = title.split(separator: " ", maxSplits: 1).first else { return false }
        let parts = first.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else { return false }
        return (0...23).contains(hour) && (0...59).contains(minute)
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
