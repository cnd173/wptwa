import json
import os
import sys
import winreg
import win32api

REG_KEY = r"Software\CDPLayout"
MAX_SLOTS = 7

AUTOSTART_KEY  = r"Software\Microsoft\Windows\CurrentVersion\Run"
AUTOSTART_NAME = "CDPLayout"


def _data_dir():
    """Writable directory for plain files (e.g. the session CSV log)."""
    appdata = os.environ.get("APPDATA") or os.path.expanduser("~")
    path = os.path.join(appdata, "CDPLayout")
    os.makedirs(path, exist_ok=True)
    return path


SESSION_LOG_FILE = os.path.join(_data_dir(), "session_log.csv")


# ── Registry helpers ──────────────────────────────────────────

def _reg_get(name, default=None):
    try:
        key = winreg.OpenKey(winreg.HKEY_CURRENT_USER, REG_KEY)
        value, _ = winreg.QueryValueEx(key, name)
        winreg.CloseKey(key)
        return json.loads(value)
    except Exception:
        return default


def _reg_set(name, data):
    key = winreg.CreateKey(winreg.HKEY_CURRENT_USER, REG_KEY)
    winreg.SetValueEx(key, name, 0, winreg.REG_SZ, json.dumps(data, ensure_ascii=False))
    winreg.CloseKey(key)


# ── Screen / slots ────────────────────────────────────────────

def get_screen_size():
    w = win32api.GetSystemMetrics(0)
    h = win32api.GetSystemMetrics(1)
    return w, h


def default_slots():
    w, h = get_screen_size()
    cols, rows = 3, 2
    sw, sh = w // cols, int(h / 2.5)
    slots = []
    for r in range(rows):
        for c in range(cols):
            slots.append({
                "id": r * cols + c + 1,
                "x": c * sw,
                "y": r * sh,
                "width": sw,
                "height": sh,
            })
    return slots


# ── Config (slot layout) ──────────────────────────────────────

def load_config():
    data = _reg_get("config")
    if isinstance(data, list) and data:
        return data
    slots = default_slots()
    save_config(slots)
    return slots


def save_config(slots):
    _reg_set("config", slots)


# ── Presets ───────────────────────────────────────────────────

def load_presets():
    return _reg_get("presets", {})


def save_preset(name, slots):
    presets = load_presets()
    presets[name] = slots
    _reg_set("presets", presets)


def delete_preset(name):
    presets = load_presets()
    presets.pop(name, None)
    _reg_set("presets", presets)


# ── Settings (last preset, etc.) ──────────────────────────────

def load_settings():
    return _reg_get("settings", {})


def save_settings(data):
    settings = load_settings()
    settings.update(data)
    _reg_set("settings", settings)


# ── Autostart with Windows ────────────────────────────────────

def is_autostart_enabled():
    try:
        key = winreg.OpenKey(winreg.HKEY_CURRENT_USER, AUTOSTART_KEY)
        winreg.QueryValueEx(key, AUTOSTART_NAME)
        winreg.CloseKey(key)
        return True
    except Exception:
        return False


def set_autostart(enabled):
    """Requires a frozen (PyInstaller) executable; no-op when run from source."""
    if not getattr(sys, "frozen", False):
        return
    key = winreg.CreateKey(winreg.HKEY_CURRENT_USER, AUTOSTART_KEY)
    try:
        if enabled:
            winreg.SetValueEx(key, AUTOSTART_NAME, 0, winreg.REG_SZ,
                              f'"{sys.executable}"')
        else:
            try:
                winreg.DeleteValue(key, AUTOSTART_NAME)
            except FileNotFoundError:
                pass
    finally:
        winreg.CloseKey(key)
