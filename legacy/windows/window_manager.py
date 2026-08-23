import os
import time
import win32gui
import win32process
import win32api
import win32con
import psutil

_OWN_PID          = os.getpid()
_PROCESS_KEYWORDS = ["wpt", "poker"]
_HISTORY_KEYWORDS = ["hand history", "handhistory", "hand-history"]

# Table titles after WPT update: "HLB7110 - 0.05/0.10/0.20(0.05) - NLHE"
# Lobby title is now dynamic (shows current time, e.g. "15:13 Indochina Time")
# Strategy: positively identify tables, treat everything else as lobby
_TABLE_GAME_TYPES = [" - nlhe", " - plo", " - ofc", " - mtt", " - sng"]

# ── PID cache (refreshed every 10 s, not every poll) ──────────
_wpt_pids      = set()
_last_pid_scan = 0.0
_PID_CACHE_TTL = 10.0


def _refresh_pids():
    global _wpt_pids, _last_pid_scan
    now = time.monotonic()
    if now - _last_pid_scan < _PID_CACHE_TTL:
        return
    _last_pid_scan = now
    pids = set()
    for proc in psutil.process_iter(["pid", "name"]):
        name = proc.info.get("name", "").lower()
        pid  = proc.info["pid"]
        if pid != _OWN_PID and any(k in name for k in _PROCESS_KEYWORDS):
            pids.add(pid)
    _wpt_pids = pids


def _is_visible_top_level(hwnd):
    return win32gui.IsWindowVisible(hwnd) and not win32gui.GetParent(hwnd)


def _classify(title):
    t = title.lower()
    if any(k in t for k in _HISTORY_KEYWORDS):
        return "history"
    # Tables start with "HL" table-ID prefix or end with a known game type
    if t.startswith("hl") or any(t.endswith(g) for g in _TABLE_GAME_TYPES):
        return "table"
    return "lobby"


def classify_wpt_windows():
    """Return {"lobby": [...], "history": [...], "table": [...]} of hwnds."""
    _refresh_pids()
    if not _wpt_pids:
        return {"lobby": [], "history": [], "table": []}

    result = {"lobby": [], "history": [], "table": []}

    def callback(hwnd, _):
        if not _is_visible_top_level(hwnd):
            return
        try:
            _, pid = win32process.GetWindowThreadProcessId(hwnd)
        except Exception:
            return
        if pid not in _wpt_pids:
            return
        title = win32gui.GetWindowText(hwnd)
        if not title:
            return
        result[_classify(title)].append(hwnd)

    win32gui.EnumWindows(callback, None)
    return result


def get_window_pos(hwnd):
    """Return (x, y, w, h) of the window, or None on error."""
    try:
        l, t, r, b = win32gui.GetWindowRect(hwnd)
        return (l, t, r - l, b - t)
    except Exception:
        return None


def move_window(hwnd, x, y, width, height):
    """Move and resize a window (unconditionally — caller decides when to call)."""
    try:
        placement = win32gui.GetWindowPlacement(hwnd)
        if placement[1] == win32con.SW_SHOWMINIMIZED:
            win32gui.ShowWindow(hwnd, win32con.SW_RESTORE)
        win32gui.MoveWindow(hwnd, x, y, width, height, True)
    except Exception:
        pass


def get_wpt_pids():
    _refresh_pids()
    return set(_wpt_pids)


def get_screen_size():
    return win32api.GetSystemMetrics(0), win32api.GetSystemMetrics(1)
