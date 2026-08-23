import Foundation
import AppKit

struct AppSettings: Codable {
    var language: String = "vi"
    var magnetEnabled: Bool = true
    var lastPreset: String? = nil
}

/// JSON-file-backed replacement for winreg in config.py. Everything lives under
/// ~/Library/Application Support/PokerTableArranger/.
enum Store {
    static let dataDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("PokerTableArranger", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static var configFile: URL { dataDir.appendingPathComponent("config.json") }
    static var presetsFile: URL { dataDir.appendingPathComponent("presets.json") }
    static var settingsFile: URL { dataDir.appendingPathComponent("settings.json") }
    static var sessionLogFile: URL { dataDir.appendingPathComponent("session_log.csv") }

    // MARK: - Generic JSON helpers

    private static func loadJSON<T: Decodable>(_ url: URL, as type: T.Type) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func saveJSON<T: Encodable>(_ value: T, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - Slot config (mirrors load_config/save_config)

    static func loadConfig() -> [Slot] {
        if let slots = loadJSON(configFile, as: [Slot].self), !slots.isEmpty {
            return slots
        }
        let screen = NSScreen.main?.frame.size ?? CGSize(width: 1920, height: 1080)
        let slots = defaultSlots(screenWidth: Int(screen.width), screenHeight: Int(screen.height))
        saveConfig(slots)
        return slots
    }

    static func saveConfig(_ slots: [Slot]) {
        saveJSON(slots, to: configFile)
    }

    // MARK: - Presets (mirrors load_presets/save_preset/delete_preset)

    static func loadPresets() -> [String: [Slot]] {
        loadJSON(presetsFile, as: [String: [Slot]].self) ?? [:]
    }

    static func savePreset(_ name: String, slots: [Slot]) {
        var presets = loadPresets()
        presets[name] = slots
        saveJSON(presets, to: presetsFile)
    }

    static func deletePreset(_ name: String) {
        var presets = loadPresets()
        presets.removeValue(forKey: name)
        saveJSON(presets, to: presetsFile)
    }

    // MARK: - Settings (mirrors load_settings/save_settings)

    static func loadSettings() -> AppSettings {
        loadJSON(settingsFile, as: AppSettings.self) ?? AppSettings()
    }

    static func saveSettings(_ settings: AppSettings) {
        saveJSON(settings, to: settingsFile)
    }

    static func updateSettings(_ mutate: (inout AppSettings) -> Void) {
        var settings = loadSettings()
        mutate(&settings)
        saveSettings(settings)
    }

    // MARK: - Session log CSV (mirrors _log_session / _read_bankroll_rows in main.py)

    static func appendSessionLog(_ entry: SessionLogEntry) throws {
        let isNew = !FileManager.default.fileExists(atPath: sessionLogFile.path)
        let handle: FileHandle
        if isNew {
            FileManager.default.createFile(atPath: sessionLogFile.path, contents: nil)
        }
        handle = try FileHandle(forWritingTo: sessionLogFile)
        defer { try? handle.close() }
        handle.seekToEndOfFile()

        var lines = ""
        if isNew {
            lines += CSVCodec.row(SessionLogEntry.csvHeader) + "\n"
        }
        lines += CSVCodec.row([
            entry.date, entry.start, entry.end, entry.durationHMS, String(entry.durationSec),
            entry.buyIn.map { String($0) } ?? "",
            entry.cashOut.map { String($0) } ?? "",
            entry.profit.map { String($0) } ?? "",
            entry.note,
        ]) + "\n"

        guard let data = lines.data(using: .utf8) else { return }
        handle.write(data)
    }

    static func readSessionLogRows() -> [SessionLogEntry] {
        guard let content = try? String(contentsOf: sessionLogFile, encoding: .utf8) else { return [] }
        let rows = CSVCodec.parse(content)
        guard rows.count > 1 else { return [] }
        let header = rows[0]
        func col(_ row: [String], _ name: String) -> String {
            guard let idx = header.firstIndex(of: name), idx < row.count else { return "" }
            return row[idx]
        }
        return rows.dropFirst().compactMap { row -> SessionLogEntry? in
            guard !row.isEmpty else { return nil }
            return SessionLogEntry(
                date: col(row, "date"),
                start: col(row, "start"),
                end: col(row, "end"),
                durationHMS: col(row, "duration_hms"),
                durationSec: Int(col(row, "duration_sec")) ?? 0,
                buyIn: Double(col(row, "buy_in")),
                cashOut: Double(col(row, "cash_out")),
                profit: Double(col(row, "profit")),
                note: col(row, "note")
            )
        }
    }
}

// MARK: - Minimal CSV read/write (no external dependency)

enum CSVCodec {
    static func field(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    static func row(_ fields: [String]) -> String {
        fields.map(field).joined(separator: ",")
    }

    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var field = ""
        var row: [String] = []
        var inQuotes = false
        var iterator = text.makeIterator()
        var pending: Character? = nil

        func nextChar() -> Character? {
            if let p = pending { pending = nil; return p }
            return iterator.next()
        }

        while let c = nextChar() {
            if inQuotes {
                if c == "\"" {
                    if let n = nextChar() {
                        if n == "\"" {
                            field.append("\"")
                        } else {
                            inQuotes = false
                            pending = n
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(c)
                }
            } else {
                switch c {
                case "\"":
                    inQuotes = true
                case ",":
                    row.append(field)
                    field = ""
                case "\n":
                    row.append(field)
                    field = ""
                    rows.append(row)
                    row = []
                case "\r":
                    continue
                default:
                    field.append(c)
                }
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows.filter { !($0.count == 1 && $0[0].isEmpty) }
    }
}
