import AppKit
import SwiftUI
import Combine

enum SessionState: Equatable {
    case stopped, running, paused
}

/// Central observable state — the Swift analogue of the `App` class in main.py.
final class AppModel: ObservableObject {
    @Published var slots: [Slot]
    @Published var arranging = false
    @Published var magnetEnabled: Bool {
        didSet {
            slotManager.updateMagnetEnabled(magnetEnabled)
            Store.updateSettings { $0.magnetEnabled = magnetEnabled }
        }
    }
    @Published var statusText: String = t("status_stopped")
    @Published var dotColor: Color = Palette.dim
    @Published var occupiedSlotIds: Set<Int> = []

    @Published var sessionState: SessionState = .stopped
    @Published var sessionElapsedText = "00:00:00"

    @Published var autostartEnabled: Bool
    @Published var presets: [String: [Slot]] = Store.loadPresets()
    @Published var selectedPreset: String?

    @Published var activeAlert: AlertInfo?

    let slotManager: SlotManager

    private var sessionElapsed: TimeInterval = 0
    private var sessionMonotonicStart: TimeInterval?
    private var sessionWallStart: Date?
    private var timerLoop: Timer?

    var bankrollWindow: NSWindowController?
    var slotEditorWindow: NSWindowController?
    var bankrollEntryWindow: NSWindowController?
    var bankrollPromptWindow: NSWindowController?

    init() {
        let loadedSlots = Store.loadConfig()
        let settings = Store.loadSettings()
        slots = loadedSlots
        magnetEnabled = settings.magnetEnabled
        selectedPreset = settings.lastPreset
        autostartEnabled = Autostart.isEnabled()

        let manager = SlotManager(slots: loadedSlots, magnetEnabled: settings.magnetEnabled)
        slotManager = manager
        manager.onStatusChange = { [weak self] status in self?.handleStatusChange(status) }

        refreshPresets()
    }

    // MARK: - Arranging

    func toggleArranging() {
        if arranging {
            slotManager.stop()
            arranging = false
            dotColor = Palette.dim
            statusText = t("status_stopped")
            occupiedSlotIds = []
        } else {
            WindowManager.invalidateTargetCache()
            slotManager.updateSlots(slots)
            slotManager.start()
            arranging = true
            dotColor = Palette.accent
            statusText = t("status_starting")
        }
    }

    func rearrange() {
        guard arranging else { return }
        slotManager.rearrange()
    }

    func swapSlots(_ a: Int, _ b: Int) {
        guard arranging else { return }
        slotManager.swapSlots(a, b)
    }

    private func handleStatusChange(_ status: ArrangementStatus) {
        if arranging {
            statusText = t("status_arranging", ["n": status.tableCount])
            dotColor = status.tableCount > 0 ? Palette.green : Palette.accent
            occupiedSlotIds = status.occupiedSlotIds
        }
    }

    // MARK: - Session timer

    func timerToggle() {
        if sessionState == .running { timerPause() } else { timerResume() }
    }

    func timerResume() {
        guard sessionState != .running else { return }
        if sessionState == .stopped {
            sessionElapsed = 0
            sessionWallStart = Date()
        }
        sessionMonotonicStart = ProcessInfo.processInfo.systemUptime
        sessionState = .running
        startTimerLoop()
        renderTimer()
    }

    func timerPause() {
        guard sessionState == .running else { return }
        sessionElapsed += ProcessInfo.processInfo.systemUptime - (sessionMonotonicStart ?? ProcessInfo.processInfo.systemUptime)
        sessionMonotonicStart = nil
        sessionState = .paused
        stopTimerLoop()
        renderTimer()
    }

    func timerStop() {
        guard sessionState != .stopped else { return }
        if sessionState == .running {
            sessionElapsed += ProcessInfo.processInfo.systemUptime - (sessionMonotonicStart ?? ProcessInfo.processInfo.systemUptime)
        }
        let completedElapsed = sessionElapsed
        let completedStart = sessionWallStart
        sessionMonotonicStart = nil
        sessionState = .stopped
        stopTimerLoop()
        sessionElapsed = 0
        sessionWallStart = nil
        renderTimer()

        if let wallStart = completedStart, completedElapsed > 0 {
            showBankrollPrompt(start: wallStart, end: Date(), elapsed: completedElapsed)
        }
    }

    private func showBankrollPrompt(start: Date, end: Date, elapsed: TimeInterval) {
        let controller = PanelWindowController(
            title: t("session_ended_title"), width: 280, height: 300,
            content: BankrollPromptView(elapsed: elapsed) { [weak self] buyIn, cashOut, note in
                self?.logSession(start: start, end: end, seconds: elapsed, buyIn: buyIn, cashOut: cashOut, note: note)
            }
        )
        bankrollPromptWindow = controller
        controller.show()
    }

    private func startTimerLoop() {
        timerLoop?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.renderTimer() }
        RunLoop.main.add(timer, forMode: .common)
        timerLoop = timer
    }

    private func stopTimerLoop() {
        timerLoop?.invalidate()
        timerLoop = nil
    }

    private func renderTimer() {
        let total: Int
        if sessionState == .running, let start = sessionMonotonicStart {
            total = Int(sessionElapsed + (ProcessInfo.processInfo.systemUptime - start))
        } else {
            total = Int(sessionElapsed)
        }
        sessionElapsedText = String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    // MARK: - Session log

    func logSession(start: Date, end: Date, seconds: TimeInterval, buyIn: Double?, cashOut: Double?, note: String) {
        let total = Int(seconds)
        let hms = String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
        let profit: Double? = (buyIn != nil && cashOut != nil) ? cashOut! - buyIn! : nil

        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm:ss"

        let entry = SessionLogEntry(
            date: dateFmt.string(from: start), start: timeFmt.string(from: start),
            end: timeFmt.string(from: end), durationHMS: hms, durationSec: total,
            buyIn: buyIn, cashOut: cashOut, profit: profit, note: note
        )
        do {
            try Store.appendSessionLog(entry)
        } catch {
            activeAlert = AlertInfo(title: t("session_not_saved_title"), message: t("session_not_saved_msg"))
        }
    }

    // MARK: - Slots / editor

    func updateSlots(_ newSlots: [Slot]) {
        guard let normalized = SlotLayoutValidator.normalized(newSlots) else { return }
        slots = normalized
        if arranging { slotManager.updateSlots(normalized) }
    }

    // MARK: - Presets

    func refreshPresets(select: String? = nil) {
        presets = Store.loadPresets()
        let lastUsed = Store.loadSettings().lastPreset
        if let select, presets[select] != nil {
            selectedPreset = select
        } else if let lastUsed, presets[lastUsed] != nil {
            selectedPreset = lastUsed
        } else if let current = selectedPreset, presets[current] == nil {
            selectedPreset = presets.keys.sorted().first
        } else if selectedPreset == nil {
            selectedPreset = presets.keys.sorted().first
        }
    }

    func savePreset(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Store.savePreset(trimmed, slots: slots)
        refreshPresets(select: trimmed)
    }

    func loadSelectedPreset() {
        guard let name = selectedPreset,
              let presetSlots = presets[name],
              let normalized = SlotLayoutValidator.normalized(presetSlots) else { return }
        slots = normalized
        Store.saveConfig(normalized)
        Store.updateSettings { $0.lastPreset = name }
        if arranging { slotManager.updateSlots(normalized) }
    }

    func deleteSelectedPreset() {
        guard let name = selectedPreset else { return }
        Store.deletePreset(name)
        refreshPresets()
    }

    // MARK: - Autostart

    func setAutostart(_ enabled: Bool) {
        guard Autostart.isRunningFromBundledApp else {
            autostartEnabled = false
            activeAlert = AlertInfo(title: t("not_available_title"), message: t("autostart_unavailable_msg"))
            return
        }
        if let err = Autostart.setEnabled(enabled) {
            autostartEnabled = Autostart.isEnabled()
            activeAlert = AlertInfo(title: t("not_available_title"), message: err)
        } else {
            autostartEnabled = enabled
        }
    }
}
