from config import load_settings

STRINGS = {
    "en": {
        # Bankroll
        "bankroll_title":       "Bankroll",
        "sessions_tracked":     "{n} session(s) tracked",
        "win_rate":             "win rate {v}%",
        "no_sessions":          "No sessions logged yet.",
        "col_date":             "Date",
        "col_time":             "Time",
        "col_buyin":            "Buy-in",
        "col_cashout":          "Cash-out",
        "col_profit":           "Profit",
        "col_note":             "Note",
        "add_entry_btn":        "＋  Add Entry",
        "add_entry_title":      "Add Entry",
        "invalid_date_msg":     "Date must be in YYYY-MM-DD format.",
        "cancel":               "Cancel",

        # Bankroll prompt
        "session_ended_title": "Session ended",
        "played_for":          "Played for {hms}",
        "note_optional":       "Note (optional)",
        "skip":                "Skip",
        "save":                "Save",

        # Slot editor
        "edit_slots_title":    "Edit Slots",
        "max_n":               "max {n}",
        "preview_label":       "Preview",
        "add_slot":            "+ Add",
        "remove_slot":         "− Remove",
        "grid_3x2":            "3×2 Grid",
        "invalid_value_title": "Invalid value",
        "invalid_value_msg":   "Slot {n} has non-integer fields.",
        "max_reached_title":   "Maximum reached",
        "max_reached_msg":     "Maximum {n} slots allowed.",

        # Main window
        "brand_sub":           "Table\nArranger",
        "slots_configured":    "{n} slot(s) configured",
        "drag_to_swap":        "drag to swap",
        "magnet":              "🧲 Magnet",
        "status_stopped":      "Stopped",
        "status_starting":     "Starting…",
        "status_arranging":    "Arranging {n} table(s)",
        "session_label":       "SESSION",
        "start_arranging":     "▶  Start Arranging",
        "stop_arranging":      "■  Stop Arranging",
        "btn_slots":           "⚙ Slots",
        "btn_reset":           "⟳ Reset",
        "btn_bankroll":        "💰 Bankroll",
        "btn_log_entry":       "📝 Log",
        "start_with_windows":  "Start with Windows",
        "presets_label":       "PRESETS",
        "load_btn":            "Load",
        "save_as_preset":      "＋  Save as preset",
        "save_preset_title":   "Save Preset",
        "save_preset_prompt":  "Enter preset name:",
        "delete_preset_title": "Delete Preset",
        "delete_preset_msg":   'Delete preset "{name}"?',
        "not_available_title": "Not available",
        "autostart_unavailable_msg": "\"Start with Windows\" only works in the packaged "
                                     "CDPLayout.exe, not when running from source.",
        "session_not_saved_title": "Session not saved",
        "session_not_saved_msg": "Could not write to session_log.csv — it may be open in "
                                 "another program (e.g. Excel). Close it and the next "
                                 "session will save normally.",
        "no_presets":          "(no presets saved)",
    },
    "vi": {
        # Bankroll
        "bankroll_title":       "Bankroll",
        "sessions_tracked":     "{n} session đã ghi nhận",
        "win_rate":             "tỷ lệ thắng {v}%",
        "no_sessions":          "Chưa có session nào được ghi nhận.",
        "col_date":             "Ngày",
        "col_time":             "Giờ",
        "col_buyin":            "Buy-in",
        "col_cashout":          "Cash-out",
        "col_profit":           "Lời/Lỗ",
        "col_note":             "Ghi chú",
        "add_entry_btn":        "＋  Thêm mục",
        "add_entry_title":      "Thêm mục",
        "invalid_date_msg":     "Ngày phải theo định dạng YYYY-MM-DD.",
        "cancel":               "Hủy",

        # Bankroll prompt
        "session_ended_title": "Session đã kết thúc",
        "played_for":          "Đã chơi {hms}",
        "note_optional":       "Ghi chú (tuỳ chọn)",
        "skip":                "Bỏ qua",
        "save":                "Lưu",

        # Slot editor
        "edit_slots_title":    "Chỉnh Slot",
        "max_n":               "tối đa {n}",
        "preview_label":       "Xem trước",
        "add_slot":            "+ Thêm",
        "remove_slot":         "− Xoá",
        "grid_3x2":            "Lưới 3×2",
        "invalid_value_title": "Giá trị không hợp lệ",
        "invalid_value_msg":   "Slot {n} có ô không phải số nguyên.",
        "max_reached_title":   "Đã đạt giới hạn",
        "max_reached_msg":     "Tối đa {n} slot được phép.",

        # Main window
        "brand_sub":           "Sắp Bàn\nTự Động",
        "slots_configured":    "Đã cấu hình {n} slot",
        "drag_to_swap":        "kéo để đổi chỗ",
        "magnet":              "🧲 Nam châm",
        "status_stopped":      "Đã dừng",
        "status_starting":     "Đang khởi động…",
        "status_arranging":    "Đang sắp xếp {n} bàn",
        "session_label":       "PHIÊN",
        "start_arranging":     "▶  Bắt Đầu Sắp Xếp",
        "stop_arranging":      "■  Dừng Sắp Xếp",
        "btn_slots":           "⚙ Slot",
        "btn_reset":           "⟳ Làm Mới",
        "btn_bankroll":        "💰 Bankroll",
        "btn_log_entry":       "📝 Ghi",
        "start_with_windows":  "Khởi động cùng Windows",
        "presets_label":       "PRESET",
        "load_btn":            "Tải",
        "save_as_preset":      "＋  Lưu preset mới",
        "save_preset_title":   "Lưu Preset",
        "save_preset_prompt":  "Nhập tên preset:",
        "delete_preset_title": "Xoá Preset",
        "delete_preset_msg":   'Xoá preset "{name}"?',
        "not_available_title": "Không khả dụng",
        "autostart_unavailable_msg": "\"Khởi động cùng Windows\" chỉ hoạt động trong bản "
                                     "CDPLayout.exe đã đóng gói, không hoạt động khi chạy "
                                     "từ source.",
        "session_not_saved_title": "Chưa lưu được session",
        "session_not_saved_msg": "Không thể ghi vào session_log.csv — file có thể đang mở "
                                 "ở chương trình khác (vd: Excel). Đóng file lại, session "
                                 "tiếp theo sẽ lưu bình thường.",
        "no_presets":          "(chưa có preset nào)",
    },
}

_CURRENT_LANG = load_settings().get("language", "vi")
if _CURRENT_LANG not in STRINGS:
    _CURRENT_LANG = "vi"


def get_language():
    return _CURRENT_LANG


def set_language(code):
    global _CURRENT_LANG
    if code in STRINGS:
        _CURRENT_LANG = code


def t(key, **kwargs):
    s = STRINGS.get(_CURRENT_LANG, STRINGS["en"]).get(key, key)
    return s.format(**kwargs) if kwargs else s
