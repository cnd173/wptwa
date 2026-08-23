import threading
import time
import win32api
import win32con
import win32gui

from window_manager import classify_wpt_windows, move_window, get_window_pos

POLL_INTERVAL      = 2.0    # seconds — detect new/closed tables
DRAG_POLL_INTERVAL = 0.15   # seconds — watch for manual window dragging
DRAG_THRESHOLD     = 20     # px a window must move before we call it "dragged"

# Slot indices (0-based) reserved for specific window types
LOBBY_SLOT_IDX   = 0   # Slot 1 → lobby
HISTORY_SLOT_IDX = 3   # Slot 4 → hand history (all stack here)

_LOST_GRACE = 3   # polls a window can be absent before its slot is freed


class SlotManager:
    def __init__(self, slots, on_status_change=None, magnet_enabled=True):
        self._slots        = slots
        self._assignments  = {}   # hwnd -> slot_id
        self._set_rects    = {}   # hwnd -> (x, y, w, h) we told Windows to use
        self._actual_rects = {}   # hwnd -> (x, y, w, h) GetWindowRect reported right after
        self._lost_polls   = {}   # hwnd -> consecutive polls not seen
        self._on_status    = on_status_change
        self.magnet_enabled = magnet_enabled
        self._running      = False
        self._thread        = None
        self._drag_thread   = None
        self._lock          = threading.RLock()

    def update_slots(self, slots):
        with self._lock:
            self._slots = slots
            self._set_rects.clear()   # force re-apply after layout change
            self._actual_rects.clear()

    def start(self):
        if self._running:
            return
        self._running = True
        self._thread = threading.Thread(target=self._loop, daemon=True)
        self._thread.start()
        self._drag_thread = threading.Thread(target=self._drag_loop, daemon=True)
        self._drag_thread.start()

    def stop(self):
        self._running = False
        with self._lock:
            self._assignments.clear()
            self._set_rects.clear()
            self._actual_rects.clear()
            self._lost_polls.clear()

    def _loop(self):
        while self._running:
            self._poll()
            time.sleep(POLL_INTERVAL)

    # ── Core poll ─────────────────────────────────────────────

    def _poll(self):
        classified    = classify_wpt_windows()
        lobby_hwnds   = set(classified["lobby"])
        history_hwnds = set(classified["history"])
        table_hwnds   = set(classified["table"])
        all_current   = lobby_hwnds | history_hwnds | table_hwnds

        with self._lock:
            # Remove closed windows — with grace period so brief disappearances
            # (game hiding a window during resize) don't free the slot prematurely
            for hwnd in list(self._assignments):
                if hwnd not in all_current:
                    self._lost_polls[hwnd] = self._lost_polls.get(hwnd, 0) + 1
                    if self._lost_polls[hwnd] > _LOST_GRACE:
                        del self._assignments[hwnd]
                        self._set_rects.pop(hwnd, None)
                        self._actual_rects.pop(hwnd, None)
                        self._lost_polls.pop(hwnd, None)
                else:
                    self._lost_polls.pop(hwnd, None)

            lobby_slot   = self._slots[LOBBY_SLOT_IDX]   if len(self._slots) > LOBBY_SLOT_IDX   else None
            history_slot = self._slots[HISTORY_SLOT_IDX] if len(self._slots) > HISTORY_SLOT_IDX else None
            # Slot 1 (lobby) and slot 4 (hand history) are always reserved —
            # tables only ever fill slots 2, 3, 5, 6.
            reserved_ids = {s["id"] for s in [lobby_slot, history_slot] if s}

            # Re-classify windows whose title changed since they were first assigned.
            # A brand-new table can briefly show a placeholder title while it loads,
            # get mistaken for the lobby, and lock into the reserved slot forever —
            # this evicts it once its real title comes through so it can claim a
            # proper table slot below.
            for hwnd, slot_id in list(self._assignments.items()):
                if slot_id in reserved_ids and hwnd in table_hwnds:
                    del self._assignments[hwnd]
                    self._set_rects.pop(hwnd, None)
                    self._actual_rects.pop(hwnd, None)

            # 1. Lobby → slot 1
            for hwnd in lobby_hwnds:
                if hwnd not in self._assignments and lobby_slot:
                    self._assignments[hwnd] = lobby_slot["id"]

            # 2. Hand history → slot 4 (stack)
            for hwnd in history_hwnds:
                if hwnd not in self._assignments and history_slot:
                    self._assignments[hwnd] = history_slot["id"]

            # 3. Tables → remaining free slots
            table_used = {sid for h, sid in self._assignments.items() if h in table_hwnds}
            for hwnd in table_hwnds:
                if hwnd not in self._assignments:
                    slot = self._next_free_table_slot(reserved_ids, table_used)
                    if slot:
                        self._assignments[hwnd] = slot["id"]
                        table_used.add(slot["id"])

            # Apply positions (only when needed)
            for hwnd, slot_id in list(self._assignments.items()):
                slot = self._get_slot(slot_id)
                if slot and win32gui.IsWindow(hwnd):
                    self._apply_position(hwnd, slot)

        if self._on_status:
            self._on_status(len(self._assignments))

    def _apply_position(self, hwnd, slot):
        """Move hwnd to slot only if we haven't already placed it there. Caller holds lock."""
        target = (slot["x"], slot["y"], slot["width"], slot["height"])
        if self._set_rects.get(hwnd) == target:
            return  # already placed — never touch the game window again
        move_window(hwnd, *target)
        self._set_rects[hwnd] = target
        actual = get_window_pos(hwnd)
        if actual:
            self._actual_rects[hwnd] = actual

    def get_occupied_slot_ids(self):
        """Slot ids currently holding a real window — used to drive the preview UI."""
        with self._lock:
            return set(self._assignments.values())

    def rearrange(self):
        """Force re-apply all positions immediately (clears position memory)."""
        with self._lock:
            self._set_rects.clear()
            self._actual_rects.clear()
        self._poll()

    # ── Slot helpers ──────────────────────────────────────────

    def _next_free_table_slot(self, reserved_ids, used_ids):
        for slot in self._slots:
            if slot["id"] not in reserved_ids and slot["id"] not in used_ids:
                return slot
        return None

    def _get_slot(self, slot_id):
        for slot in self._slots:
            if slot["id"] == slot_id:
                return slot
        return None

    def _slot_at_point(self, x, y):
        for slot in self._slots:
            if (slot["x"] <= x <= slot["x"] + slot["width"] and
                    slot["y"] <= y <= slot["y"] + slot["height"]):
                return slot
        return None

    def _nearest_slot_to_point(self, x, y):
        best, best_d = None, None
        for slot in self._slots:
            cx = slot["x"] + slot["width"] / 2
            cy = slot["y"] + slot["height"] / 2
            d = (cx - x) ** 2 + (cy - y) ** 2
            if best_d is None or d < best_d:
                best, best_d = slot, d
        return best

    def swap_slots(self, idx_a, idx_b):
        """Swap all windows in slot index idx_a with all in idx_b (used by preview UI drag)."""
        if idx_a >= len(self._slots) or idx_b >= len(self._slots):
            return
        with self._lock:
            slot_a = self._slots[idx_a]
            slot_b = self._slots[idx_b]

            hwnds_a = [h for h, sid in self._assignments.items() if sid == slot_a["id"]]
            hwnds_b = [h for h, sid in self._assignments.items() if sid == slot_b["id"]]

            for h in hwnds_a:
                self._assignments[h] = slot_b["id"]
                self._set_rects.pop(h, None)
                self._actual_rects.pop(h, None)
            for h in hwnds_b:
                self._assignments[h] = slot_a["id"]
                self._set_rects.pop(h, None)
                self._actual_rects.pop(h, None)

            for h in hwnds_a:
                self._apply_position(h, slot_b)
            for h in hwnds_b:
                self._apply_position(h, slot_a)

    # ── Real-window drag watcher ───────────────────────────────

    def _drag_loop(self):
        dragging_hwnd = None
        while self._running:
            time.sleep(DRAG_POLL_INTERVAL)
            down = win32api.GetAsyncKeyState(win32con.VK_LBUTTON) < 0

            if dragging_hwnd is not None:
                if not win32gui.IsWindow(dragging_hwnd):
                    dragging_hwnd = None
                    continue
                if not down:
                    self._finish_drag(dragging_hwnd)
                    dragging_hwnd = None
                continue

            if down:
                dragging_hwnd = self._find_displaced_window()

    def _find_displaced_window(self):
        with self._lock:
            items = list(self._assignments.items())
            baseline = dict(self._actual_rects)
        for hwnd, _ in items:
            if not win32gui.IsWindow(hwnd):
                continue
            if win32gui.IsIconic(hwnd):
                continue  # minimized — not a drag
            base = baseline.get(hwnd)
            if not base:
                continue
            rect = get_window_pos(hwnd)
            if rect is None:
                continue
            if abs(rect[0] - base[0]) > DRAG_THRESHOLD or abs(rect[1] - base[1]) > DRAG_THRESHOLD:
                return hwnd
        return None

    def _finish_drag(self, hwnd):
        if win32gui.IsIconic(hwnd):
            return  # user minimized it — leave it alone, don't restore/reposition
        rect = get_window_pos(hwnd)
        if rect is None:
            return
        x, y, w, h = rect
        cx, cy = x + w / 2, y + h / 2

        with self._lock:
            target_slot = self._slot_at_point(cx, cy)
            if target_slot is None:
                if not self.magnet_enabled:
                    return  # leave the window wherever the user dropped it
                target_slot = self._nearest_slot_to_point(cx, cy)
                if target_slot is None:
                    return

            old_slot_id = self._assignments.get(hwnd)
            new_slot_id = target_slot["id"]

            if old_slot_id == new_slot_id:
                self._set_rects.pop(hwnd, None)
                self._apply_position(hwnd, target_slot)
                return

            other_hwnd = None
            for h, sid in self._assignments.items():
                if h != hwnd and sid == new_slot_id:
                    other_hwnd = h
                    break

            self._assignments[hwnd] = new_slot_id
            self._set_rects.pop(hwnd, None)
            self._actual_rects.pop(hwnd, None)

            if other_hwnd and old_slot_id is not None:
                self._assignments[other_hwnd] = old_slot_id
                self._set_rects.pop(other_hwnd, None)
                self._actual_rects.pop(other_hwnd, None)

            self._apply_position(hwnd, target_slot)
            if other_hwnd and old_slot_id is not None:
                old_slot = self._get_slot(old_slot_id)
                if old_slot:
                    self._apply_position(other_hwnd, old_slot)
