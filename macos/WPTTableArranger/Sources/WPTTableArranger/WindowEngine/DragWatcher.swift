import AppKit
import CoreGraphics

/// Watches for the user manually dragging one of the arranged windows and snaps it into
/// whichever slot it's dropped on. Port of slot_manager.py's `_drag_loop` /
/// `_find_displaced_window` / `_finish_drag`.
///
/// `CGEventSource.buttonState` is the macOS analogue of `GetAsyncKeyState(VK_LBUTTON)` — a
/// global, app-focus-independent query of the left mouse button's current hardware state.
final class DragWatcher {
    private static let pollInterval: TimeInterval = 0.15
    private static let dragThreshold = 20.0

    private weak var slotManager: SlotManager?
    private var timer: Timer?
    private var draggingWindow: AXWindow?

    init(slotManager: SlotManager) {
        self.slotManager = slotManager
    }

    func start() {
        let t = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        draggingWindow = nil
    }

    private func tick() {
        guard let slotManager else { return }
        let down = CGEventSource.buttonState(.combinedSessionState, button: .left)

        if let window = draggingWindow {
            if !window.isAlive {
                draggingWindow = nil
                return
            }
            if !down {
                draggingWindow = nil
                slotManager.runOnQueue { [weak self] in
                    self?.finishDrag(window, slotManager: slotManager)
                }
            }
            return
        }

        guard down else { return }
        slotManager.runOnQueue { [weak self] in
            guard let self, let found = self.findDisplacedWindow(slotManager: slotManager) else { return }
            DispatchQueue.main.async { self.draggingWindow = found }
        }
    }

    /// Must run on slotManager.queue.
    private func findDisplacedWindow(slotManager: SlotManager) -> AXWindow? {
        let assignments = slotManager.currentAssignments()
        let baseline = slotManager.currentActualRects()
        for (window, _) in assignments {
            guard window.isAlive, !window.isMinimized else { continue }
            guard let base = baseline[window], let rect = window.frame() else { continue }
            if abs(Double(rect.x - base.x)) > Self.dragThreshold ||
               abs(Double(rect.y - base.y)) > Self.dragThreshold {
                return window
            }
        }
        return nil
    }

    /// Must run on slotManager.queue.
    private func finishDrag(_ window: AXWindow, slotManager: SlotManager) {
        guard !window.isMinimized else { return } // user minimized it — leave alone
        guard let rect = window.frame() else { return }
        let cx = Double(rect.x) + Double(rect.width) / 2
        let cy = Double(rect.y) + Double(rect.height) / 2

        var targetSlot = slotManager.slotAtPoint(cx, cy)
        if targetSlot == nil {
            guard slotManager.magnetEnabled else { return } // leave it wherever the user dropped it
            targetSlot = slotManager.nearestSlotToPoint(cx, cy)
            guard targetSlot != nil else { return }
        }
        guard let target = targetSlot else { return }

        let oldSlotId = slotManager.assignedSlotId(for: window)
        let newSlotId = target.id

        if oldSlotId == newSlotId {
            slotManager.clearSetRect(for: window)
            slotManager.applyPosition(window, target)
            return
        }

        let otherWindow = slotManager.firstWindow(inSlotId: newSlotId, excluding: window)

        slotManager.reassign(window, toSlotId: newSlotId)

        if let otherWindow, let oldSlotId {
            slotManager.reassign(otherWindow, toSlotId: oldSlotId)
        }

        slotManager.applyPosition(window, target)
        if let otherWindow, let oldSlotId, let oldSlot = slotManager.slotBy(id: oldSlotId) {
            slotManager.applyPosition(otherWindow, oldSlot)
        }
    }
}
