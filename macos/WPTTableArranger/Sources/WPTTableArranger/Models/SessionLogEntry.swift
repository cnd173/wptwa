import Foundation

/// Mirrors the session_log.csv row shape written by config.py's original Windows build,
/// so old logs stay readable if the user ever diffs the two.
struct SessionLogEntry {
    var date: String
    var start: String
    var end: String
    var durationHMS: String
    var durationSec: Int
    var buyIn: Double?
    var cashOut: Double?
    var profit: Double?
    var note: String

    static let csvHeader = ["date", "start", "end", "duration_hms", "duration_sec",
                             "buy_in", "cash_out", "profit", "note"]
}
