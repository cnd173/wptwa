import Foundation

struct ArrangementStatus: Equatable {
    let tableCount: Int
    let totalWindowCount: Int
    let occupiedSlotIds: Set<Int>
}

/// Port of slot_manager.py. All mutable state is only ever touched on `queue`, which plays
/// the same role as the Python version's `threading.RLock`.
///
/// Note on coordinates: AXPositionAttribute uses a top-left-origin space (y grows downward),
/// same convention the slot grid is defined in, so slot rects can be applied to AX windows
/// with no coordinate flip — unlike NSScreen.frame, which is bottom-left-origin Cocoa space
/// (only used here to read width/height, never as an origin).
final class SlotManager {
    static let lobbySlotIdx = 0    // Slot 1 -> lobby
    static let historySlotIdx = 3  // Slot 4 -> hand history (all stack here)

    private static let pollInterval: TimeInterval = 2.0
    private static let lostGrace = 3 // polls a window can be absent before its slot is freed

    let queue = DispatchQueue(label: "io.github.cnd173.pokertablearranger.slotmanager")

    private var slots: [Slot]
    private var assignments: [AXWindow: Int] = [:]       // window -> slot id
    private var setRects: [AXWindow: WindowRect] = [:]    // position + natural size last observed
    private var actualRects: [AXWindow: WindowRect] = [:] // rect actually observed right after
    var lostPolls: [AXWindow: Int] = [:]

    private var running = false
    private var pollTimer: DispatchSourceTimer?

    private var magnetEnabled: Bool
    var onStatusChange: ((ArrangementStatus) -> Void)?

    var dragWatcher: DragWatcher?

    init(slots: [Slot], magnetEnabled: Bool, onStatusChange: ((ArrangementStatus) -> Void)? = nil) {
        self.slots = slots
        self.magnetEnabled = magnetEnabled
        self.onStatusChange = onStatusChange
    }

    func updateSlots(_ newSlots: [Slot]) {
        queue.sync {
            slots = newSlots
            setRects.removeAll()
            actualRects.removeAll()
        }
    }

    func updateMagnetEnabled(_ enabled: Bool) {
        queue.async { [weak self] in self?.magnetEnabled = enabled }
    }

    func start() {
        var alreadyRunning = false
        queue.sync {
            alreadyRunning = running
            running = true
        }
        guard !alreadyRunning else { return }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: Self.pollInterval)
        timer.setEventHandler { [weak self] in self?.poll() }
        timer.resume()
        pollTimer = timer

        let watcher = DragWatcher(slotManager: self)
        dragWatcher = watcher
        watcher.start()
    }

    func stop() {
        queue.sync {
            running = false
            assignments.removeAll()
            setRects.removeAll()
            actualRects.removeAll()
            lostPolls.removeAll()
        }
        pollTimer?.cancel()
        pollTimer = nil
        dragWatcher?.stop()
        dragWatcher = nil
    }

    func getOccupiedSlotIds() -> Set<Int> {
        queue.sync { Set(assignments.values) }
    }

    /// Force re-apply all positions immediately (clears position memory).
    func rearrange() {
        queue.sync {
            setRects.removeAll()
            actualRects.removeAll()
        }
        poll()
    }

    func swapSlots(_ idxA: Int, _ idxB: Int) {
        queue.sync {
            guard idxA < slots.count, idxB < slots.count else { return }
            let slotA = slots[idxA]
            let slotB = slots[idxB]

            let windowsA = assignments.filter { $0.value == slotA.id }.map { $0.key }
            let windowsB = assignments.filter { $0.value == slotB.id }.map { $0.key }

            for w in windowsA {
                assignments[w] = slotB.id
                setRects.removeValue(forKey: w)
                actualRects.removeValue(forKey: w)
            }
            for w in windowsB {
                assignments[w] = slotA.id
                setRects.removeValue(forKey: w)
                actualRects.removeValue(forKey: w)
            }
            for w in windowsA { applyPosition(w, slotB) }
            for w in windowsB { applyPosition(w, slotA) }
        }
    }

    // MARK: - Core poll (must be called on `queue`, or via the timer which already is)

    private func poll() {
        let classified = WindowManager.classifiedWindows()
        let lobbySet = Set(classified.lobby)
        let historySet = Set(classified.history)
        let tableSet = Set(classified.table)
        let allCurrent = lobbySet.union(historySet).union(tableSet)

        func runPoll() {
            // Remove closed windows — with a grace period so brief disappearances (e.g. the
            // game hiding a window during resize) don't free the slot prematurely.
            for window in Array(assignments.keys) {
                if !allCurrent.contains(window) {
                    lostPolls[window, default: 0] += 1
                    if lostPolls[window]! > Self.lostGrace {
                        assignments.removeValue(forKey: window)
                        setRects.removeValue(forKey: window)
                        actualRects.removeValue(forKey: window)
                        lostPolls.removeValue(forKey: window)
                    }
                } else {
                    lostPolls.removeValue(forKey: window)
                }
            }

            let lobbySlot = slots.count > Self.lobbySlotIdx ? slots[Self.lobbySlotIdx] : nil
            let historySlot = slots.count > Self.historySlotIdx ? slots[Self.historySlotIdx] : nil
            // Slot 1 (lobby) and slot 4 (hand history) are always reserved — tables only
            // ever fill the remaining slots.
            let reservedIds = Set([lobbySlot, historySlot].compactMap { $0?.id })

            // Re-classify windows whose title changed since they were first assigned. A
            // brand-new table can briefly show a placeholder title while it loads, get
            // mistaken for the lobby, and lock into the reserved slot forever — this evicts
            // it once its real title comes through so it can claim a proper table slot below.
            for (window, slotId) in assignments where reservedIds.contains(slotId) && tableSet.contains(window) {
                assignments.removeValue(forKey: window)
                setRects.removeValue(forKey: window)
                actualRects.removeValue(forKey: window)
            }

            // 1. Lobby -> slot 1
            for window in lobbySet where assignments[window] == nil {
                if let lobbySlot { assignments[window] = lobbySlot.id }
            }

            // 2. Hand history -> slot 4 (stack)
            for window in historySet where assignments[window] == nil {
                if let historySlot { assignments[window] = historySlot.id }
            }

            // 3. Tables -> remaining free slots
            var tableUsed = Set(assignments.filter { tableSet.contains($0.key) }.map { $0.value })
            for window in tableSet where assignments[window] == nil {
                if let slot = nextFreeTableSlot(reservedIds: reservedIds, usedIds: tableUsed) {
                    assignments[window] = slot.id
                    tableUsed.insert(slot.id)
                }
            }

            // Apply positions (only when needed)
            for (window, slotId) in assignments {
                if let slot = slotBy(id: slotId), window.isAlive {
                    applyPosition(window, slot)
                }
            }
        }

        queue.async { [weak self] in
            guard let self, self.running else { return }
            runPoll()
            let status = ArrangementStatus(
                tableCount: self.assignments.keys.filter { tableSet.contains($0) }.count,
                totalWindowCount: self.assignments.count,
                occupiedSlotIds: Set(self.assignments.values)
            )
            DispatchQueue.main.async { self.onStatusChange?(status) }
        }
    }

    /// Move hwnd-equivalent to slot only if we haven't already placed it there. Caller must be
    /// on `queue`.
    ///
    /// Slot width/height define layout and drop areas only. Window size remains entirely under
    /// the poker client's control; this method writes AXPosition but never AXSize.
    func applyPosition(_ window: AXWindow, _ slot: Slot) {
        guard let current = window.frame() else { return }
        let target = WindowRect(x: slot.x, y: slot.y, width: current.width, height: current.height)
        if setRects[window] == target { return } // already placed — never touch a live window again

        let actual = window.movePreservingSize(toX: target.x, y: target.y)
        setRects[window] = target
        guard let actual else { return }
        actualRects[window] = actual
    }

    // MARK: - Slot helpers

    private func nextFreeTableSlot(reservedIds: Set<Int>, usedIds: Set<Int>) -> Slot? {
        slots.first { !reservedIds.contains($0.id) && !usedIds.contains($0.id) }
    }

    func slotBy(id: Int) -> Slot? {
        slots.first { $0.id == id }
    }

    func slotAtPoint(_ x: Double, _ y: Double) -> Slot? {
        slots.first {
            let left = Double($0.x)
            let top = Double($0.y)
            return left <= x && x <= left + Double($0.width) &&
                top <= y && y <= top + Double($0.height)
        }
    }

    func nearestSlotToPoint(_ x: Double, _ y: Double) -> Slot? {
        var best: Slot?
        var bestDist = Double.greatestFiniteMagnitude
        for slot in slots {
            let cx = Double(slot.x) + Double(slot.width) / 2
            let cy = Double(slot.y) + Double(slot.height) / 2
            let d = (cx - x) * (cx - x) + (cy - y) * (cy - y)
            if d < bestDist { best = slot; bestDist = d }
        }
        return best
    }

    // MARK: - Accessors used by DragWatcher (must run on `queue`)

    func currentAssignments() -> [AXWindow: Int] { assignments }
    func currentActualRects() -> [AXWindow: WindowRect] { actualRects }
    func isMagnetEnabledOnQueue() -> Bool { magnetEnabled }

    func assignedSlotId(for window: AXWindow) -> Int? { assignments[window] }

    func reassign(_ window: AXWindow, toSlotId slotId: Int) {
        assignments[window] = slotId
        setRects.removeValue(forKey: window)
        actualRects.removeValue(forKey: window)
    }

    func clearSetRect(for window: AXWindow) {
        setRects.removeValue(forKey: window)
    }

    func firstWindow(inSlotId slotId: Int, excluding: AXWindow) -> AXWindow? {
        assignments.first { $0.value == slotId && $0.key != excluding }?.key
    }

    func runOnQueue(_ block: @escaping () -> Void) {
        queue.async(execute: block)
    }
}
