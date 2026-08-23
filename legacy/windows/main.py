import collections
import csv
import os
import re
import subprocess
import sys
import threading
import time
import tkinter as tk
from datetime import datetime
from tkinter import messagebox, simpledialog, ttk

import psutil
import pystray
from PIL import Image, ImageDraw

from config import (load_config, save_config, default_slots, get_screen_size,
                    MAX_SLOTS, load_presets, save_preset, delete_preset,
                    load_settings, save_settings, REG_KEY, SESSION_LOG_FILE,
                    is_autostart_enabled, set_autostart)
from slot_manager import LOBBY_SLOT_IDX, HISTORY_SLOT_IDX, SlotManager
from window_manager import get_wpt_pids
from i18n import t, get_language, set_language

# ── Palette ───────────────────────────────────────────────────
BG      = "#141422"
SURFACE = "#1e1e2e"
CARD    = "#252538"
ACCENT  = "#3b82f6"
GREEN   = "#22c55e"
RED     = "#ef4444"
TEXT    = "#f8fafc"
DIM     = "#64748b"
BORDER  = "#2e2e48"
YELLOW      = "#f59e0b"
SLOT_COLORS = ["#3b82f6", "#8b5cf6", "#06b6d4", "#f59e0b", "#10b981", "#f43f5e"]

PV_W, PV_H = 260, 146   # preview canvas size (≈16:9)


# ── Helpers ───────────────────────────────────────────────────

def _make_tray_image():
    img = Image.new("RGB", (64, 64), color=(20, 20, 34))
    d = ImageDraw.Draw(img)
    d.rectangle([6, 6, 58, 58], fill=(59, 130, 246))
    d.text((22, 20), "W", fill=(248, 250, 252))
    return img


def _lighten(hex_color, amt=22):
    r = min(255, int(hex_color[1:3], 16) + amt)
    g = min(255, int(hex_color[3:5], 16) + amt)
    b = min(255, int(hex_color[5:7], 16) + amt)
    return f"#{r:02x}{g:02x}{b:02x}"


def _btn(parent, text, cmd, bg, fg=TEXT, width=None,
         font=("Segoe UI", 9, "bold"), padx=12, pady=7):
    kw = dict(text=text, command=cmd, bg=bg, fg=fg, relief="flat",
              activebackground=_lighten(bg), activeforeground=fg,
              cursor="hand2", font=font, padx=padx, pady=pady)
    if width:
        kw["width"] = width
    b = tk.Button(parent, **kw)
    b.bind("<Enter>", lambda e: b.config(bg=_lighten(bg)))
    b.bind("<Leave>", lambda e: b.config(bg=bg))
    return b


# ── Monitor helpers ───────────────────────────────────────────

_OWN_PID = os.getpid()
PING_HISTORY    = 60
MONITOR_MS      = 2000   # UI refresh interval


def _do_ping(host):
    try:
        out = subprocess.check_output(
            ["ping", "-n", "1", "-w", "2000", host],
            stderr=subprocess.DEVNULL,
            creationflags=subprocess.CREATE_NO_WINDOW,
        ).decode("cp850", errors="ignore")
        m = re.search(r"[=<](\d+)ms", out)
        return int(m.group(1)) if m else None
    except Exception:
        return None


def _detect_wpt_server():
    for pid in get_wpt_pids():
        try:
            for c in psutil.Process(pid).connections(kind="inet"):
                if c.status == "ESTABLISHED" and c.raddr:
                    ip = c.raddr.ip
                    if not (ip.startswith("127.") or ip.startswith("192.168.")
                            or ip.startswith("10.") or ip == "::1"):
                        return ip
        except Exception:
            pass
    return "wptglobal.com"


def _proc_stats(keyword):
    for proc in psutil.process_iter(["pid", "name", "cpu_percent", "memory_info"]):
        try:
            if keyword in proc.info["name"].lower() and proc.info["pid"] != _OWN_PID:
                return proc.cpu_percent(interval=None), \
                       proc.info["memory_info"].rss // (1024 * 1024)
        except Exception:
            pass
    return None, None


def _own_stats():
    try:
        p = psutil.Process(_OWN_PID)
        return p.cpu_percent(interval=None), p.memory_info().rss // (1024 * 1024)
    except Exception:
        return 0.0, 0


# ── Monitor window ────────────────────────────────────────────

class MonitorWindow(tk.Toplevel):
    GRAPH_W, GRAPH_H = 400, 80

    def __init__(self, parent):
        super().__init__(parent)
        self.title(t("monitor_title"))
        self.resizable(False, False)
        self.configure(bg=BG)
        self.attributes("-topmost", True)

        self._pings      = collections.deque(maxlen=PING_HISTORY)
        self._loss       = 0
        self._total      = 0
        self._target     = None
        self._after_id   = None
        self._closed     = False

        self._build()
        self.protocol("WM_DELETE_WINDOW", self._on_close)

        # Warm up cpu_percent (first call always returns 0.0)
        psutil.Process(_OWN_PID).cpu_percent(interval=None)
        _proc_stats("wpt")

        self._detect()
        self._tick()

    # ── Build UI ──────────────────────────────────────────────

    def _build(self):
        hdr = tk.Frame(self, bg=SURFACE, padx=16, pady=10)
        hdr.pack(fill="x")
        tk.Label(hdr, text=t("monitor_title"), bg=SURFACE, fg=TEXT,
                 font=("Segoe UI", 12, "bold")).pack(side="left")
        self._server_var = tk.StringVar(value=t("monitor_detecting"))
        tk.Label(hdr, textvariable=self._server_var, bg=SURFACE, fg=DIM,
                 font=("Segoe UI", 8)).pack(side="right")

        body = tk.Frame(self, bg=BG, padx=16, pady=12)
        body.pack(fill="both")

        # ── Network section ───────────────────────────────────
        tk.Label(body, text=t("monitor_network"), bg=BG, fg=DIM,
                 font=("Segoe UI", 7, "bold")).pack(anchor="w", pady=(0, 4))

        self._graph = tk.Canvas(body, width=self.GRAPH_W, height=self.GRAPH_H,
                                bg=BG, highlightthickness=1,
                                highlightbackground=BORDER)
        self._graph.pack(pady=(0, 6))

        stat_row = tk.Frame(body, bg=BG)
        stat_row.pack(fill="x", pady=(0, 10))

        self._ping_var = tk.StringVar(value=t("ping_placeholder"))
        self._ping_lbl = tk.Label(stat_row, textvariable=self._ping_var,
                                   bg=BG, fg=TEXT, font=("Segoe UI", 22, "bold"))
        self._ping_lbl.pack(side="left", padx=(0, 16))

        detail = tk.Frame(stat_row, bg=BG)
        detail.pack(side="left")
        self._avg_var  = tk.StringVar(value=t("avg_placeholder"))
        self._max_var  = tk.StringVar(value=t("max_placeholder"))
        self._loss_var = tk.StringVar(value=t("loss_placeholder"))
        for v in (self._avg_var, self._max_var, self._loss_var):
            tk.Label(detail, textvariable=v, bg=BG, fg=DIM,
                     font=("Segoe UI", 8)).pack(anchor="w")

        # ── Process section ───────────────────────────────────
        tk.Frame(body, bg=BORDER, height=1).pack(fill="x", pady=(0, 8))
        tk.Label(body, text=t("monitor_processes"), bg=BG, fg=DIM,
                 font=("Segoe UI", 7, "bold")).pack(anchor="w", pady=(0, 6))

        grid = tk.Frame(body, bg=BG)
        grid.pack(fill="x")

        for c, (hd, w) in enumerate([("", 16), (t("col_cpu"), 8), (t("col_ram"), 10)]):
            tk.Label(grid, text=hd, bg=BG, fg=DIM, width=w,
                     font=("Segoe UI", 8, "bold"), anchor="w").grid(row=0, column=c, padx=4)

        self._wpt_cpu = tk.StringVar(value="—")
        self._wpt_ram = tk.StringVar(value="—")
        tk.Label(grid, text=t("proc_wpt"), bg=BG, fg=ACCENT, width=16,
                 font=("Segoe UI", 9), anchor="w").grid(row=1, column=0, padx=4, pady=2)
        tk.Label(grid, textvariable=self._wpt_cpu, bg=BG, fg=TEXT, width=8,
                 font=("Segoe UI", 9), anchor="w").grid(row=1, column=1, padx=4)
        tk.Label(grid, textvariable=self._wpt_ram, bg=BG, fg=TEXT, width=10,
                 font=("Segoe UI", 9), anchor="w").grid(row=1, column=2, padx=4)

        self._app_cpu = tk.StringVar(value="—")
        self._app_ram = tk.StringVar(value="—")
        tk.Label(grid, text=t("proc_app"), bg=BG, fg=GREEN, width=16,
                 font=("Segoe UI", 9), anchor="w").grid(row=2, column=0, padx=4, pady=2)
        tk.Label(grid, textvariable=self._app_cpu, bg=BG, fg=TEXT, width=8,
                 font=("Segoe UI", 9), anchor="w").grid(row=2, column=1, padx=4)
        tk.Label(grid, textvariable=self._app_ram, bg=BG, fg=TEXT, width=10,
                 font=("Segoe UI", 9), anchor="w").grid(row=2, column=2, padx=4)

    # ── Data collection ───────────────────────────────────────

    def _detect(self):
        def run():
            target = _detect_wpt_server()
            self._target = target
            if not self._closed:
                self.after(0, self._server_var.set, t("monitor_pinging", target=target))
        threading.Thread(target=run, daemon=True).start()

    def _tick(self):
        if self._closed:
            return
        threading.Thread(target=self._collect, daemon=True).start()
        self._after_id = self.after(MONITOR_MS, self._tick)

    def _collect(self):
        ping  = _do_ping(self._target) if self._target else None
        self._total += 1
        if ping is None:
            self._loss += 1
        else:
            self._pings.append(ping)

        wpt_cpu, wpt_ram = _proc_stats("wpt")
        app_cpu, app_ram = _own_stats()

        if not self._closed:
            self.after(0, self._update, ping, wpt_cpu, wpt_ram, app_cpu, app_ram)

    def _update(self, ping, wpt_cpu, wpt_ram, app_cpu, app_ram):
        # Ping label
        if ping is not None:
            color = GREEN if ping < 50 else (YELLOW if ping < 100 else RED)
            self._ping_var.set(f"{ping} ms")
        else:
            color = RED
            self._ping_var.set(t("ping_timeout"))
        self._ping_lbl.config(fg=color)

        if self._pings:
            avg = int(sum(self._pings) / len(self._pings))
            self._avg_var.set(t("avg_ms", v=avg))
            self._max_var.set(t("max_ms", v=max(self._pings)))
        loss_pct = int(self._loss / max(1, self._total) * 100)
        self._loss_var.set(t("loss_pct", pct=loss_pct, loss=self._loss, total=self._total))

        self._draw_graph()

        self._wpt_cpu.set(f"{wpt_cpu:.1f}%" if wpt_cpu is not None else "—")
        self._wpt_ram.set(f"{wpt_ram} MB"   if wpt_ram is not None else "—")
        self._app_cpu.set(f"{app_cpu:.1f}%")
        self._app_ram.set(f"{app_ram} MB")

    def _draw_graph(self):
        W, H = self.GRAPH_W, self.GRAPH_H
        c = self._graph
        c.delete("all")
        c.create_rectangle(0, 0, W, H, fill=BG, outline="")

        if len(self._pings) < 2:
            c.create_text(W // 2, H // 2, text=t("graph_collecting"),
                          fill=DIM, font=("Segoe UI", 9))
            return

        pings = list(self._pings)
        peak  = max(max(pings), 1)

        def y_of(ms):
            return H - max(2, int(ms / peak * (H - 4)))

        # Reference lines at 50 ms and 100 ms
        for ref_ms, label in ((50, "50ms"), (100, "100ms")):
            if peak > ref_ms:
                yr = y_of(ref_ms)
                c.create_line(0, yr, W, yr, fill=BORDER, dash=(3, 5))
                c.create_text(W - 2, yr - 2, text=label,
                              fill=DIM, font=("Segoe UI", 6), anchor="se")

        # Ping line
        step   = W / max(PING_HISTORY - 1, 1)
        offset = PING_HISTORY - len(pings)
        pts    = []
        for i, p in enumerate(pings):
            pts += [int((i + offset) * step), y_of(p)]

        last_color = GREEN if pings[-1] < 50 else (YELLOW if pings[-1] < 100 else RED)
        if len(pts) >= 4:
            c.create_line(*pts, fill=last_color, width=1, smooth=True)

        # Latest dot
        c.create_oval(pts[-2]-3, pts[-1]-3, pts[-2]+3, pts[-1]+3,
                      fill=last_color, outline="")

    def _on_close(self):
        self._closed = True
        if self._after_id:
            self.after_cancel(self._after_id)
        self.destroy()


# ── Bankroll ──────────────────────────────────────────────────

def _parse_amount(s):
    s = s.strip()
    if not s:
        return None
    try:
        return float(s)
    except ValueError:
        return None


def _read_bankroll_rows():
    rows = []
    if not os.path.exists(SESSION_LOG_FILE):
        return rows
    with open(SESSION_LOG_FILE, newline="") as f:
        for d in csv.DictReader(f):
            rows.append({
                "date":          d.get("date", ""),
                "duration_hms":  d.get("duration_hms", ""),
                "buy_in":        _parse_amount(d.get("buy_in", "")),
                "cash_out":      _parse_amount(d.get("cash_out", "")),
                "profit":        _parse_amount(d.get("profit", "")),
                "note":          d.get("note", ""),
            })
    return rows


class BankrollPromptDialog(tk.Toplevel):
    """Shown automatically when a session ends — asks for buy-in/cash-out."""

    def __init__(self, parent, start, end, elapsed, on_result):
        super().__init__(parent)
        self.title(t("session_ended_title"))
        self.resizable(False, False)
        self.configure(bg=BG)
        self.transient(parent)
        self.attributes("-topmost", True)
        self.grab_set()

        self._start, self._end, self._elapsed = start, end, elapsed
        self._on_result = on_result
        self._done = False

        total = int(elapsed)
        hms = f"{total // 3600:02d}:{(total % 3600) // 60:02d}:{total % 60:02d}"

        hdr = tk.Frame(self, bg=SURFACE, padx=16, pady=10)
        hdr.pack(fill="x")
        tk.Label(hdr, text=t("session_ended_title"), bg=SURFACE, fg=TEXT,
                 font=("Segoe UI", 12, "bold")).pack(side="left")

        body = tk.Frame(self, bg=BG, padx=16, pady=12)
        body.pack(fill="both")
        tk.Label(body, text=t("played_for", hms=hms), bg=BG, fg=DIM,
                 font=("Segoe UI", 9)).pack(anchor="w", pady=(0, 10))

        grid = tk.Frame(body, bg=BG)
        grid.pack(fill="x")
        self._buyin_var   = tk.StringVar()
        self._cashout_var = tk.StringVar()
        for r, (label, var) in enumerate([(t("col_buyin"), self._buyin_var),
                                          (t("col_cashout"), self._cashout_var)]):
            tk.Label(grid, text=label, bg=BG, fg=TEXT, width=8, anchor="w",
                     font=("Segoe UI", 9)).grid(row=r, column=0, pady=4, sticky="w")
            tk.Entry(grid, textvariable=var, width=12, bg=CARD, fg=TEXT,
                     insertbackground=TEXT, relief="flat", highlightthickness=1,
                     highlightbackground=BORDER, highlightcolor=ACCENT,
                     font=("Segoe UI", 9)).grid(row=r, column=1, pady=4, padx=(6, 0))

        tk.Label(body, text=t("note_optional"), bg=BG, fg=DIM,
                 font=("Segoe UI", 8)).pack(anchor="w", pady=(8, 2))
        self._note_var = tk.StringVar()
        tk.Entry(body, textvariable=self._note_var, bg=CARD, fg=TEXT,
                 insertbackground=TEXT, relief="flat", highlightthickness=1,
                 highlightbackground=BORDER, highlightcolor=ACCENT,
                 font=("Segoe UI", 9)).pack(fill="x")

        bar = tk.Frame(self, bg=SURFACE, padx=16, pady=10)
        bar.pack(fill="x", side="bottom")
        _btn(bar, t("skip"), self._skip, CARD,
             font=("Segoe UI", 9, "bold"), padx=10, pady=6).pack(side="left")
        _btn(bar, t("save"), self._save, GREEN, width=8,
             font=("Segoe UI", 9, "bold"), padx=10, pady=6).pack(side="right")

        self.protocol("WM_DELETE_WINDOW", self._skip)

    def _save(self):
        buy_in   = _parse_amount(self._buyin_var.get())
        cash_out = _parse_amount(self._cashout_var.get())
        self._finish(buy_in, cash_out, self._note_var.get().strip())

    def _skip(self):
        self._finish(None, None, "")

    def _finish(self, buy_in, cash_out, note):
        if self._done:
            return
        self._done = True
        self._on_result(self._start, self._end, self._elapsed, buy_in, cash_out, note)
        self.destroy()


class BankrollWindow(tk.Toplevel):
    def __init__(self, parent):
        super().__init__(parent)
        self.title(t("bankroll_title"))
        self.resizable(False, False)
        self.configure(bg=BG)
        self.attributes("-topmost", True)

        rows = _read_bankroll_rows()

        hdr = tk.Frame(self, bg=SURFACE, padx=16, pady=10)
        hdr.pack(fill="x")
        tk.Label(hdr, text=t("bankroll_title"), bg=SURFACE, fg=TEXT,
                 font=("Segoe UI", 12, "bold")).pack(side="left")

        body = tk.Frame(self, bg=BG, padx=16, pady=12)
        body.pack(fill="both", expand=True)

        profits = [r["profit"] for r in rows if r["profit"] is not None]
        total_profit = sum(profits) if profits else 0.0
        wins = sum(1 for p in profits if p > 0)
        win_rate = (wins / len(profits) * 100) if profits else 0

        summary = tk.Frame(body, bg=BG)
        summary.pack(fill="x", pady=(0, 10))
        color = GREEN if total_profit >= 0 else RED
        tk.Label(summary, text=f"{total_profit:+.2f}", bg=BG, fg=color,
                 font=("Segoe UI", 20, "bold")).pack(side="left", padx=(0, 16))
        detail = tk.Frame(summary, bg=BG)
        detail.pack(side="left")
        tk.Label(detail, text=t("sessions_tracked", n=len(profits)), bg=BG, fg=DIM,
                 font=("Segoe UI", 8)).pack(anchor="w")
        tk.Label(detail, text=t("win_rate", v=f"{win_rate:.0f}"), bg=BG, fg=DIM,
                 font=("Segoe UI", 8)).pack(anchor="w")

        style = ttk.Style(self)
        style.theme_use("clam")
        style.configure("Bankroll.Treeview", background=CARD, fieldbackground=CARD,
                        foreground=TEXT, rowheight=22, font=("Segoe UI", 8),
                        borderwidth=0)
        style.configure("Bankroll.Treeview.Heading", background=SURFACE, foreground=DIM,
                        font=("Segoe UI", 8, "bold"), borderwidth=0)
        style.map("Bankroll.Treeview", background=[("selected", ACCENT)])

        cols = ("date", "duration", "buyin", "cashout", "profit", "note")
        headers = {"date": t("col_date"), "duration": t("col_time"), "buyin": t("col_buyin"),
                  "cashout": t("col_cashout"), "profit": t("col_profit"), "note": t("col_note")}
        widths = {"date": 80, "duration": 60, "buyin": 60, "cashout": 65,
                 "profit": 65, "note": 130}

        if not rows:
            tk.Label(body, text=t("no_sessions"), bg=BG, fg=DIM,
                     font=("Segoe UI", 9)).pack(pady=20)
        else:
            tree = ttk.Treeview(body, columns=cols, show="headings", height=10,
                                style="Bankroll.Treeview")
            for c in cols:
                tree.heading(c, text=headers[c])
                tree.column(c, width=widths[c], anchor="center" if c != "note" else "w")

            for r in reversed(rows):
                profit_str = f"{r['profit']:+.2f}" if r["profit"] is not None else "—"
                tree.insert("", "end", values=(
                    r["date"], r["duration_hms"],
                    f"{r['buy_in']:.2f}" if r["buy_in"] is not None else "—",
                    f"{r['cash_out']:.2f}" if r["cash_out"] is not None else "—",
                    profit_str, r["note"],
                ))
            tree.pack(fill="both", expand=True)


class BankrollEntryDialog(tk.Toplevel):
    """Manual bankroll entry — not tied to a live session timer."""

    def __init__(self, parent, on_save):
        super().__init__(parent)
        self.title(t("add_entry_title"))
        self.resizable(False, False)
        self.configure(bg=BG)
        self.transient(parent)
        self.attributes("-topmost", True)
        self.grab_set()

        self._on_save = on_save

        hdr = tk.Frame(self, bg=SURFACE, padx=16, pady=10)
        hdr.pack(fill="x")
        tk.Label(hdr, text=t("add_entry_title"), bg=SURFACE, fg=TEXT,
                 font=("Segoe UI", 12, "bold")).pack(side="left")

        body = tk.Frame(self, bg=BG, padx=16, pady=12)
        body.pack(fill="both")

        grid = tk.Frame(body, bg=BG)
        grid.pack(fill="x")
        self._date_var    = tk.StringVar(value=datetime.now().strftime("%Y-%m-%d"))
        self._buyin_var   = tk.StringVar()
        self._cashout_var = tk.StringVar()
        for r, (label, var) in enumerate([(t("col_date"), self._date_var),
                                          (t("col_buyin"), self._buyin_var),
                                          (t("col_cashout"), self._cashout_var)]):
            tk.Label(grid, text=label, bg=BG, fg=TEXT, width=8, anchor="w",
                     font=("Segoe UI", 9)).grid(row=r, column=0, pady=4, sticky="w")
            tk.Entry(grid, textvariable=var, width=14, bg=CARD, fg=TEXT,
                     insertbackground=TEXT, relief="flat", highlightthickness=1,
                     highlightbackground=BORDER, highlightcolor=ACCENT,
                     font=("Segoe UI", 9)).grid(row=r, column=1, pady=4, padx=(6, 0))

        tk.Label(body, text=t("note_optional"), bg=BG, fg=DIM,
                 font=("Segoe UI", 8)).pack(anchor="w", pady=(8, 2))
        self._note_var = tk.StringVar()
        tk.Entry(body, textvariable=self._note_var, bg=CARD, fg=TEXT,
                 insertbackground=TEXT, relief="flat", highlightthickness=1,
                 highlightbackground=BORDER, highlightcolor=ACCENT,
                 font=("Segoe UI", 9)).pack(fill="x")

        bar = tk.Frame(self, bg=SURFACE, padx=16, pady=10)
        bar.pack(fill="x", side="bottom")
        _btn(bar, t("cancel"), self.destroy, CARD,
             font=("Segoe UI", 9, "bold"), padx=10, pady=6).pack(side="left")
        _btn(bar, t("save"), self._save, GREEN, width=8,
             font=("Segoe UI", 9, "bold"), padx=10, pady=6).pack(side="right")

    def _save(self):
        try:
            date_obj = datetime.strptime(self._date_var.get().strip(), "%Y-%m-%d").date()
        except ValueError:
            messagebox.showerror(t("invalid_value_title"), t("invalid_date_msg"), parent=self)
            return
        buy_in   = _parse_amount(self._buyin_var.get())
        cash_out = _parse_amount(self._cashout_var.get())
        note = self._note_var.get().strip()
        self._on_save(date_obj, buy_in, cash_out, note)
        self.destroy()


# ── Preview canvas ────────────────────────────────────────────

class PreviewCanvas(tk.Canvas):
    """Scaled visualisation of slot positions. Pass on_swap to enable drag-to-swap."""

    def __init__(self, parent, slots, on_swap=None, magnet_var=None):
        super().__init__(parent, width=PV_W, height=PV_H,
                         bg=BG, highlightthickness=1, highlightbackground=BORDER)
        self._sw, self._sh = get_screen_size()
        self._slots = slots
        self._on_swap = on_swap
        self._magnet_var = magnet_var   # tk.BooleanVar or None
        self._drag_from = None
        self._drag_to = None
        self._occupied = None   # None = unknown/don't dim; else set of occupied slot ids

        if on_swap:
            self.config(cursor="fleur")
            self.bind("<Button-1>",        self._click)
            self.bind("<B1-Motion>",       self._motion)
            self.bind("<ButtonRelease-1>", self._release)

        self.redraw(slots)

    # ── Drag helpers ──────────────────────────────────────────

    def _slot_at(self, x, y):
        sx, sy = PV_W / self._sw, PV_H / self._sh
        for i, s in enumerate(self._slots):
            x1 = int(s["x"] * sx)
            y1 = int(s["y"] * sy)
            x2 = int((s["x"] + s["width"]) * sx)
            y2 = int((s["y"] + s["height"]) * sy)
            if x1 <= x <= x2 and y1 <= y <= y2:
                return i
        return None

    def _nearest_slot(self, x, y):
        """Nearest slot by center distance — used for magnet snapping."""
        sx, sy = PV_W / self._sw, PV_H / self._sh
        best_i, best_d = None, None
        for i, s in enumerate(self._slots):
            cx = (s["x"] + s["width"] / 2) * sx
            cy = (s["y"] + s["height"] / 2) * sy
            d = (cx - x) ** 2 + (cy - y) ** 2
            if best_d is None or d < best_d:
                best_i, best_d = i, d
        return best_i

    def _target_at(self, x, y):
        target = self._slot_at(x, y)
        if target is None and self._magnet_var is not None and self._magnet_var.get():
            target = self._nearest_slot(x, y)
        return target

    def _click(self, event):
        self._drag_from = self._slot_at(event.x, event.y)
        self._drag_to = None

    def _motion(self, event):
        if self._drag_from is None:
            return
        target = self._target_at(event.x, event.y)
        if target != self._drag_to:
            self._drag_to = target
            self._draw(drag_from=self._drag_from, drag_to=self._drag_to)
            # Drag ghost: small circle following cursor
            r = 7
            self.delete("ghost")
            color = SLOT_COLORS[self._drag_from % len(SLOT_COLORS)]
            self.create_oval(event.x-r, event.y-r, event.x+r, event.y+r,
                             fill=color, outline=TEXT, width=1, tags="ghost")
            self.create_text(event.x, event.y, text=str(self._drag_from+1),
                             fill=TEXT, font=("Segoe UI", 6, "bold"), tags="ghost")

    def _release(self, event):
        if self._drag_from is None:
            return
        target = self._target_at(event.x, event.y)
        if target is not None and target != self._drag_from and self._on_swap:
            self._on_swap(self._drag_from, target)
        self._drag_from = None
        self._drag_to = None
        self.delete("ghost")
        self._draw()

    # ── Drawing ───────────────────────────────────────────────

    def redraw(self, slots):
        self._slots = slots
        self._draw()

    def set_occupied(self, occupied_ids):
        self._occupied = set(occupied_ids)
        self._draw()

    def _draw(self, drag_from=None, drag_to=None):
        self.delete("slot")
        sx, sy = PV_W / self._sw, PV_H / self._sh
        self.create_rectangle(0, 0, PV_W, PV_H, fill=BG, outline="", tags="slot")
        for i, s in enumerate(self._slots):
            x1 = int(s["x"] * sx) + 1
            y1 = int(s["y"] * sy) + 1
            x2 = max(x1 + 4, int((s["x"] + s["width"]) * sx))
            y2 = max(y1 + 4, int((s["y"] + s["height"]) * sy))
            color = SLOT_COLORS[i % len(SLOT_COLORS)]

            is_empty = self._occupied is not None and s["id"] not in self._occupied

            if i == drag_from:
                fill, outline, lw, text_color = SURFACE, color, 1, DIM
            elif i == drag_to:
                fill, outline, lw, text_color = _lighten(CARD, 18), TEXT, 2, TEXT
            elif is_empty:
                fill, outline, lw, text_color = BG, BORDER, 1, DIM
            else:
                fill, outline, lw, text_color = CARD, color, 1, color

            self.create_rectangle(x1, y1, x2, y2, fill=fill,
                                  outline=outline, width=lw, tags="slot")
            fs = max(7, min(11, (x2 - x1) // 5))
            # Special labels for reserved slots
            if i == LOBBY_SLOT_IDX:
                label = f"{i+1}\nLOBBY"
            elif i == HISTORY_SLOT_IDX:
                label = f"{i+1}\nHIST"
            else:
                label = str(i + 1)
            self.create_text((x1+x2)//2, (y1+y2)//2, text=label,
                             fill=text_color, font=("Segoe UI", fs, "bold"),
                             justify="center", tags="slot")


# ── Slot editor ───────────────────────────────────────────────

class SlotEditorWindow(tk.Toplevel):
    def __init__(self, parent, slots, on_save):
        super().__init__(parent)
        self.title(t("edit_slots_title"))
        self.resizable(False, False)
        self.grab_set()
        self.configure(bg=BG)
        self.attributes("-topmost", True)

        self._on_save = on_save
        self._slots = [s.copy() for s in slots]
        self._rows = []
        self._trace_ids = []

        self._build()

    def _build(self):
        # Header
        hdr = tk.Frame(self, bg=SURFACE, padx=16, pady=10)
        hdr.pack(fill="x")
        tk.Label(hdr, text=t("edit_slots_title"), bg=SURFACE, fg=TEXT,
                 font=("Segoe UI", 12, "bold")).pack(side="left")
        tk.Label(hdr, text=t("max_n", n=MAX_SLOTS), bg=SURFACE, fg=DIM,
                 font=("Segoe UI", 9)).pack(side="right", padx=4)

        # Body: left = rows, right = preview
        body = tk.Frame(self, bg=BG, padx=14, pady=10)
        body.pack(fill="both")

        left = tk.Frame(body, bg=BG)
        left.pack(side="left", fill="y", padx=(0, 14))

        # Column labels
        col_hdr = tk.Frame(left, bg=BG)
        col_hdr.pack(fill="x", pady=(0, 4))
        for col, (lbl, w) in enumerate([("", 2), ("X", 6), ("Y", 6), ("W", 6), ("H", 6)]):
            tk.Label(col_hdr, text=lbl, bg=BG, fg=DIM, width=w,
                     font=("Segoe UI", 8), anchor="center").grid(row=0, column=col, padx=2)

        self._list_frame = tk.Frame(left, bg=BG)
        self._list_frame.pack(fill="x")

        # Right: preview
        right = tk.Frame(body, bg=BG)
        right.pack(side="left", fill="y")
        tk.Label(right, text=t("preview_label"), bg=BG, fg=DIM,
                 font=("Segoe UI", 8)).pack(anchor="w", pady=(0, 4))
        self._preview = PreviewCanvas(right, self._slots)
        self._preview.pack()

        # Button bar
        bar = tk.Frame(self, bg=SURFACE, padx=14, pady=10)
        bar.pack(fill="x", side="bottom")
        _btn(bar, t("add_slot"), self._add_slot, CARD,
             font=("Segoe UI", 9, "bold"), padx=10, pady=6).pack(side="left", padx=(0, 5))
        _btn(bar, t("remove_slot"), self._remove_last, CARD,
             font=("Segoe UI", 9, "bold"), padx=10, pady=6).pack(side="left", padx=(0, 5))
        _btn(bar, t("grid_3x2"), self._auto_grid, CARD,
             font=("Segoe UI", 9, "bold"), padx=10, pady=6).pack(side="left")
        _btn(bar, t("save"), self._save, GREEN, width=8,
             font=("Segoe UI", 9, "bold"), padx=10, pady=6).pack(side="right")

        self._render_rows()

    def _render_rows(self):
        for var, tid in self._trace_ids:
            try:
                var.trace_remove("write", tid)
            except Exception:
                pass
        self._trace_ids.clear()

        for w in self._list_frame.winfo_children():
            w.destroy()
        self._rows.clear()

        for i, slot in enumerate(self._slots):
            color = SLOT_COLORS[i % len(SLOT_COLORS)]
            row_vars = {}
            row = tk.Frame(self._list_frame, bg=BG)
            row.pack(fill="x", pady=2)

            dot = tk.Canvas(row, width=10, height=10, bg=BG, highlightthickness=0)
            dot.create_oval(1, 1, 9, 9, fill=color, outline="")
            dot.grid(row=0, column=0, padx=(0, 6), pady=5)

            for col, key in enumerate(["x", "y", "width", "height"], start=1):
                var = tk.StringVar(value=str(slot[key]))
                tid = var.trace_add("write", lambda *_: self._on_change())
                self._trace_ids.append((var, tid))
                row_vars[key] = var
                e = tk.Entry(row, textvariable=var, width=6, justify="center",
                             bg=CARD, fg=TEXT, insertbackground=TEXT,
                             relief="flat", highlightthickness=1,
                             highlightbackground=BORDER, highlightcolor=ACCENT,
                             font=("Segoe UI", 9))
                e.grid(row=0, column=col, padx=3)

            self._rows.append(row_vars)

    def _on_change(self):
        slots = self._collect(silent=True)
        if slots:
            self._preview.redraw(slots)

    def _collect(self, silent=False):
        slots = []
        for i, row in enumerate(self._rows):
            try:
                slots.append({
                    "id": i + 1,
                    "x": int(row["x"].get()),
                    "y": int(row["y"].get()),
                    "width": int(row["width"].get()),
                    "height": int(row["height"].get()),
                })
            except ValueError:
                if not silent:
                    messagebox.showerror(t("invalid_value_title"),
                                         t("invalid_value_msg", n=i+1), parent=self)
                return None
        return slots

    def _add_slot(self):
        slots = self._collect()
        if slots is None:
            return
        if len(slots) >= MAX_SLOTS:
            messagebox.showinfo(t("max_reached_title"),
                                t("max_reached_msg", n=MAX_SLOTS), parent=self)
            return
        sw, sh = get_screen_size()
        slots.append({"id": len(slots)+1, "x": 0, "y": 0,
                      "width": sw // 3, "height": sh // 2})
        self._slots = slots
        self._render_rows()
        self._preview.redraw(self._slots)

    def _remove_last(self):
        slots = self._collect()
        if slots is None or len(slots) <= 1:
            return
        self._slots = slots[:-1]
        self._render_rows()
        self._preview.redraw(self._slots)

    def _auto_grid(self):
        self._slots = default_slots()
        self._render_rows()
        self._preview.redraw(self._slots)

    def _save(self):
        slots = self._collect()
        if slots is None:
            return
        save_config(slots)
        self._on_save(slots)
        self.destroy()


# ── Main window ───────────────────────────────────────────────

class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("CDPLayout")
        self.resizable(False, False)
        self.attributes("-topmost", True)
        self.configure(bg=BG)

        magnet_default = load_settings().get("magnet_enabled", True)
        self._slots = load_config()
        self._manager = SlotManager(self._slots, on_status_change=self._update_status,
                                    magnet_enabled=magnet_default)
        self._arranging = False

        self._magnet_var = tk.BooleanVar(value=magnet_default)
        self._magnet_var.trace_add("write", self._on_magnet_change)

        # Session timer state
        self._session_state   = "stopped"  # "stopped" | "running" | "paused"
        self._session_elapsed = 0.0
        self._session_start   = None       # time.monotonic() of last resume
        self._session_wall_start = None    # datetime.now() when this session began
        self._timer_after_id  = None
        self._prev_table_count = 0

        self._autostart_var = tk.BooleanVar(value=is_autostart_enabled())
        self._autostart_var.trace_add("write", self._on_autostart_change)

        self._monitor_win  = None
        self._bankroll_win = None

        self._build_ui()
        self._setup_tray()
        self.protocol("WM_DELETE_WINDOW", self._hide_to_tray)
        self._toggle()  # auto-start on launch

    def _build_ui(self):
        outer = tk.Frame(self, bg=BG, padx=10, pady=8)
        outer.pack(fill="both", expand=True)

        # ── Left: branding ────────────────────────────────────
        left = tk.Frame(outer, bg=BG, width=108)
        left.pack(side="left", fill="y", padx=(0, 8))
        left.pack_propagate(False)

        tk.Label(left, text="WPT", bg=BG, fg=ACCENT,
                 font=("Segoe UI", 18, "bold")).pack(anchor="w")
        tk.Label(left, text=t("brand_sub"), bg=BG, fg=TEXT,
                 font=("Segoe UI", 11, "bold"), justify="left").pack(anchor="w", pady=(0, 8))

        self._slot_info = tk.Label(left, text=self._slot_summary(),
                                   bg=BG, fg=DIM, font=("Segoe UI", 7),
                                   wraplength=104, justify="left")
        self._slot_info.pack(anchor="w")

        lang_row = tk.Frame(left, bg=BG)
        lang_row.pack(anchor="w", pady=(10, 0))
        self._lang_buttons = {}
        for code, label in [("vi", "VI"), ("en", "EN")]:
            b = tk.Button(lang_row, text=label, command=lambda c=code: self._set_language(c),
                         relief="flat", cursor="hand2", font=("Segoe UI", 8, "bold"),
                         padx=8, pady=3, width=3, fg=TEXT)
            b.pack(side="left", padx=(0, 4))
            self._lang_buttons[code] = b
        self._refresh_lang_buttons()

        # ── Middle: preview canvas ────────────────────────────
        mid = tk.Frame(outer, bg=BG)
        mid.pack(side="left", fill="y", padx=(0, 10))

        self._preview = PreviewCanvas(mid, self._slots,
                                      on_swap=self._on_swap_slots,
                                      magnet_var=self._magnet_var)
        self._preview.pack()
        tk.Label(mid, text=t("drag_to_swap"), bg=BG, fg=DIM,
                 font=("Segoe UI", 7)).pack(pady=(2, 0))

        magnet_row = tk.Frame(mid, bg=BG)
        magnet_row.pack(pady=(2, 0))
        tk.Checkbutton(magnet_row, text=t("magnet"), variable=self._magnet_var,
                       bg=BG, fg=DIM, selectcolor=CARD, activebackground=BG,
                       activeforeground=TEXT, highlightthickness=0,
                       font=("Segoe UI", 8), cursor="hand2"
                       ).pack()

        # ── Right: controls ───────────────────────────────────
        right = tk.Frame(outer, bg=BG)
        right.pack(side="left", fill="both", expand=True)

        # Status
        st = tk.Frame(right, bg=BG)
        st.pack(fill="x", pady=(0, 5))
        self._dot = tk.Canvas(st, width=10, height=10, bg=BG,
                              highlightthickness=0)
        self._dot.create_oval(1, 1, 9, 9, fill=DIM, outline="", tags="dot")
        self._dot.pack(side="left", padx=(0, 5))
        self._status_var = tk.StringVar(value=t("status_stopped"))
        tk.Label(st, textvariable=self._status_var, bg=BG, fg=DIM,
                 font=("Segoe UI", 9)).pack(side="left")

        # Session timer row
        tr = tk.Frame(right, bg=BG)
        tr.pack(fill="x", pady=(2, 4))
        tk.Label(tr, text=t("session_label"), bg=BG, fg=DIM,
                 font=("Segoe UI", 7, "bold")).pack(side="left", padx=(0, 6))
        self._timer_var = tk.StringVar(value="00:00:00")
        tk.Label(tr, textvariable=self._timer_var, bg=BG, fg=TEXT,
                 font=("Segoe UI", 9, "bold")).pack(side="left")
        self._timer_btn = _btn(tr, "▶", self._timer_toggle, CARD,
                               font=("Segoe UI", 8, "bold"), padx=6, pady=2)
        self._timer_btn.pack(side="right")

        # Buttons
        self._toggle_btn = _make_toggle_btn(right, t("start_arranging"),
                                            self._toggle, GREEN)
        self._toggle_btn.pack(fill="x", pady=(0, 4))
        btn_row = tk.Frame(right, bg=BG)
        btn_row.pack(fill="x")
        for label, cmd in [(t("btn_slots"), self._open_editor),
                           (t("btn_reset"), self._rearrange),
                           (t("btn_stats"), self._open_monitor),
                           (t("btn_bankroll"), self._open_bankroll)]:
            _btn(btn_row, label, cmd, CARD,
                 font=("Segoe UI", 8, "bold"), padx=4, pady=5
                 ).pack(side="left", fill="x", expand=True, padx=(0, 2))

        _btn(right, t("btn_log_entry"), self._open_bankroll_entry, ACCENT,
             font=("Segoe UI", 9, "bold"), padx=10, pady=6).pack(fill="x", pady=(4, 0))

        tk.Checkbutton(right, text=t("start_with_windows"), variable=self._autostart_var,
                       bg=BG, fg=DIM, selectcolor=CARD, activebackground=BG,
                       activeforeground=TEXT, highlightthickness=0,
                       font=("Segoe UI", 8), cursor="hand2", anchor="w"
                       ).pack(fill="x", pady=(4, 0))

        # Presets
        self._build_preset_section(right)

    def _slot_summary(self):
        return t("slots_configured", n=len(self._slots))

    def _update_dot(self, color):
        self._dot.itemconfig("dot", fill=color)

    # ── Language ───────────────────────────────────────────────

    def _refresh_lang_buttons(self):
        current = get_language()
        for code, btn in self._lang_buttons.items():
            btn.config(bg=ACCENT if code == current else CARD)

    def _set_language(self, code):
        if code == get_language():
            return
        set_language(code)
        save_settings({"language": code})
        for child in list(self.winfo_children()):
            child.destroy()
        self._build_ui()
        self._sync_ui_state()

    def _sync_ui_state(self):
        """Re-apply current logical state onto freshly rebuilt widgets (after a language change)."""
        if self._arranging:
            self._update_dot(GREEN if self._prev_table_count > 0 else ACCENT)
            self._status_var.set(t("status_arranging", n=self._prev_table_count))
            _reconfigure_toggle(self._toggle_btn, t("stop_arranging"), RED)
            self._preview.set_occupied(self._manager.get_occupied_slot_ids())
        else:
            self._update_dot(DIM)
            self._status_var.set(t("status_stopped"))
            _reconfigure_toggle(self._toggle_btn, t("start_arranging"), GREEN)

        self._timer_btn.config(text="‖" if self._session_state == "running" else "▶")
        self._timer_render()

    def _toggle(self):
        if self._arranging:
            self._manager.stop()
            self._arranging = False
            self._update_dot(DIM)
            self._status_var.set(t("status_stopped"))
            self._preview.set_occupied(set())
            _reconfigure_toggle(self._toggle_btn, t("start_arranging"), GREEN)
        else:
            self._manager.update_slots(self._slots)
            self._manager.start()
            self._arranging = True
            self._update_dot(ACCENT)
            self._status_var.set(t("status_starting"))
            _reconfigure_toggle(self._toggle_btn, t("stop_arranging"), RED)

    def _update_status(self, count):
        # schedule UI update on the main thread (tkinter is not thread-safe)
        self.after(0, self._apply_status, count)

    # ── Session timer ─────────────────────────────────────────

    def _timer_toggle(self):
        if self._session_state == "running":
            self._timer_pause()
        else:
            self._timer_resume()

    def _timer_resume(self):
        if self._session_state == "running":
            return
        self._session_start = time.monotonic()
        self._session_state = "running"
        self._timer_btn.config(text="‖")
        self._timer_tick()

    def _timer_pause(self):
        if self._session_state != "running":
            return
        self._session_elapsed += time.monotonic() - self._session_start
        self._session_start = None
        self._session_state = "paused"
        self._timer_btn.config(text="▶")
        if self._timer_after_id:
            self.after_cancel(self._timer_after_id)
            self._timer_after_id = None
        self._timer_render()

    def _timer_stop(self):
        if self._session_state == "running":
            self._session_elapsed += time.monotonic() - self._session_start
        self._session_start = None
        self._session_state = "stopped"
        self._timer_btn.config(text="▶")
        if self._timer_after_id:
            self.after_cancel(self._timer_after_id)
            self._timer_after_id = None
        self._timer_render()

        if self._session_wall_start is not None and self._session_elapsed > 0:
            BankrollPromptDialog(self, self._session_wall_start, datetime.now(),
                                 self._session_elapsed, self._log_session)
        self._session_wall_start = None

    def _timer_tick(self):
        if self._session_state != "running":
            return
        self._timer_render()
        self._timer_after_id = self.after(1000, self._timer_tick)

    def _timer_render(self):
        if self._session_state == "running":
            total = int(self._session_elapsed + time.monotonic() - self._session_start)
        else:
            total = int(self._session_elapsed)
        h = total // 3600
        m = (total % 3600) // 60
        s = total % 60
        self._timer_var.set(f"{h:02d}:{m:02d}:{s:02d}")

    def _apply_status(self, count):
        if self._arranging:
            self._status_var.set(t("status_arranging", n=count))
            self._update_dot(GREEN if count > 0 else ACCENT)
            self._preview.set_occupied(self._manager.get_occupied_slot_ids())

        was_tables = self._prev_table_count > 0
        now_tables = count > 0

        if not was_tables and now_tables:
            # First table opened → reset and start timer
            self._session_elapsed = 0.0
            self._session_wall_start = datetime.now()
            if self._timer_after_id:
                self.after_cancel(self._timer_after_id)
                self._timer_after_id = None
            self._session_start = time.monotonic()
            self._session_state = "running"
            self._timer_btn.config(text="‖")
            self._timer_tick()
        elif was_tables and not now_tables and self._session_state == "running":
            # All tables closed → stop but keep elapsed visible
            self._timer_stop()

        self._prev_table_count = count

    def _rearrange(self):
        if self._arranging:
            self._manager.rearrange()

    def _open_monitor(self):
        if self._monitor_win is not None and self._monitor_win.winfo_exists():
            self._monitor_win.deiconify()
            self._monitor_win.lift()
            self._monitor_win.focus_force()
            return
        self._monitor_win = MonitorWindow(self)

    def _on_swap_slots(self, idx_a, idx_b):
        if self._arranging:
            self._manager.swap_slots(idx_a, idx_b)

    def _on_magnet_change(self, *_):
        value = self._magnet_var.get()
        self._manager.magnet_enabled = value
        save_settings({"magnet_enabled": value})

    def _on_autostart_change(self, *_):
        if not getattr(sys, "frozen", False):
            messagebox.showinfo(t("not_available_title"),
                                t("autostart_unavailable_msg"), parent=self)
            return
        set_autostart(self._autostart_var.get())

    # ── System tray ────────────────────────────────────────────

    def _setup_tray(self):
        menu = pystray.Menu(
            pystray.MenuItem("Show", self._tray_show, default=True),
            pystray.MenuItem("Exit", self._tray_exit),
        )
        self._tray_icon = pystray.Icon("CDPLayout", _make_tray_image(),
                                       "CDPLayout", menu)
        threading.Thread(target=self._tray_icon.run, daemon=True).start()

    def _hide_to_tray(self):
        self.withdraw()

    def _tray_show(self, icon=None, item=None):
        self.after(0, self._show_window)

    def _show_window(self):
        self.deiconify()
        self.lift()

    def _tray_exit(self, icon=None, item=None):
        self.after(0, self._do_quit)

    def _do_quit(self):
        self._manager.stop()
        self._tray_icon.stop()
        self.destroy()

    # ── Session log ────────────────────────────────────────────

    def _log_session(self, start, end, seconds, buy_in=None, cash_out=None, note=""):
        try:
            is_new = not os.path.exists(SESSION_LOG_FILE)
            with open(SESSION_LOG_FILE, "a", newline="") as f:
                w = csv.writer(f)
                if is_new:
                    w.writerow(["date", "start", "end", "duration_hms", "duration_sec",
                               "buy_in", "cash_out", "profit", "note"])
                total = int(seconds)
                hms = f"{total // 3600:02d}:{(total % 3600) // 60:02d}:{total % 60:02d}"
                profit = (cash_out - buy_in) if (buy_in is not None and cash_out is not None) else ""
                w.writerow([start.strftime("%Y-%m-%d"), start.strftime("%H:%M:%S"),
                           end.strftime("%H:%M:%S"), hms, total,
                           buy_in if buy_in is not None else "",
                           cash_out if cash_out is not None else "",
                           profit, note])
        except OSError:
            messagebox.showwarning(t("session_not_saved_title"),
                                   t("session_not_saved_msg"), parent=self)

    def _open_bankroll(self):
        if self._bankroll_win is not None and self._bankroll_win.winfo_exists():
            self._bankroll_win.destroy()   # rebuild so it reflects the latest log
        self._bankroll_win = BankrollWindow(self)
        self._bankroll_win.lift()
        self._bankroll_win.focus_force()

    def _open_bankroll_entry(self):
        BankrollEntryDialog(self, self._on_bankroll_entry_saved)

    def _on_bankroll_entry_saved(self, date_obj, buy_in, cash_out, note):
        dt = datetime.combine(date_obj, datetime.min.time())
        self._log_session(dt, dt, 0, buy_in, cash_out, note)
        if self._bankroll_win is not None and self._bankroll_win.winfo_exists():
            self._open_bankroll()   # refresh if it's currently open

    def _open_editor(self):
        def on_save(new_slots):
            self._slots = new_slots
            self._slot_info.config(text=self._slot_summary())
            self._preview.redraw(new_slots)
            if self._arranging:
                self._manager.update_slots(new_slots)

        SlotEditorWindow(self, self._slots, on_save)


    # ── Preset section ────────────────────────────────────────

    def _build_preset_section(self, parent):
        tk.Frame(parent, bg=BORDER, height=1).pack(fill="x", pady=(6, 5))

        tk.Label(parent, text=t("presets_label"), bg=BG, fg=DIM,
                 font=("Segoe UI", 7, "bold")).pack(anchor="w", pady=(0, 3))

        # Dropdown + Load + Delete in one row
        row = tk.Frame(parent, bg=BG)
        row.pack(fill="x", pady=(0, 3))

        self._preset_var = tk.StringVar()
        self._preset_menu = tk.OptionMenu(row, self._preset_var, "")
        self._preset_menu.config(bg=CARD, fg=TEXT, relief="flat",
                                  activebackground=_lighten(CARD),
                                  activeforeground=TEXT, highlightthickness=0,
                                  cursor="hand2", font=("Segoe UI", 8),
                                  anchor="w", pady=4)
        self._preset_menu["menu"].config(bg=CARD, fg=TEXT,
                                          activebackground=ACCENT,
                                          activeforeground=TEXT,
                                          relief="flat", bd=0)
        self._preset_menu.pack(side="left", fill="x", expand=True, padx=(0, 3))

        _btn(row, t("load_btn"), self._load_preset, ACCENT,
             font=("Segoe UI", 8, "bold"), padx=7, pady=4).pack(side="left", padx=(0, 2))
        _btn(row, "✕", self._delete_preset, CARD,
             font=("Segoe UI", 8, "bold"), padx=7, pady=4).pack(side="left")

        _btn(parent, t("save_as_preset"), self._save_preset, CARD,
             font=("Segoe UI", 8, "bold"), padx=10, pady=4).pack(fill="x")

        self._refresh_presets()

    def _refresh_presets(self, select=None):
        menu = self._preset_menu["menu"]
        menu.delete(0, "end")
        presets = load_presets()
        if presets:
            for name in presets:
                menu.add_command(label=name,
                                 command=lambda n=name: self._preset_var.set(n))
            # Priority: explicit select → last used → current value → first
            last = select or load_settings().get("last_preset")
            current = self._preset_var.get()
            if select and select in presets:
                self._preset_var.set(select)
            elif last and last in presets:
                self._preset_var.set(last)
            elif current not in presets:
                self._preset_var.set(next(iter(presets)))
        else:
            menu.add_command(label=t("no_presets"), command=lambda: None)
            self._preset_var.set(t("no_presets"))

    def _save_preset(self):
        name = simpledialog.askstring(t("save_preset_title"), t("save_preset_prompt"),
                                      parent=self)
        if not name or not name.strip():
            return
        name = name.strip()
        save_preset(name, self._slots)
        self._refresh_presets(select=name)

    def _load_preset(self):
        name = self._preset_var.get()
        presets = load_presets()
        if name not in presets:
            return
        self._slots = presets[name]
        save_config(self._slots)
        save_settings({"last_preset": name})
        self._slot_info.config(text=self._slot_summary())
        self._preview.redraw(self._slots)
        if self._arranging:
            self._manager.update_slots(self._slots)

    def _delete_preset(self):
        name = self._preset_var.get()
        presets = load_presets()
        if name not in presets:
            return
        if not messagebox.askyesno(t("delete_preset_title"),
                                   t("delete_preset_msg", name=name), parent=self):
            return
        delete_preset(name)
        self._refresh_presets()


def _make_toggle_btn(parent, text, cmd, bg):
    b = tk.Button(parent, text=text, command=cmd, bg=bg, fg=TEXT,
                  relief="flat", activebackground=_lighten(bg),
                  activeforeground=TEXT, cursor="hand2",
                  font=("Segoe UI", 10, "bold"), padx=10, pady=5)
    b.bind("<Enter>", lambda e: b.config(bg=_lighten(bg)))
    b.bind("<Leave>", lambda e: b.config(bg=bg))
    return b


def _reconfigure_toggle(btn, text, bg):
    btn.config(text=text, bg=bg, activebackground=_lighten(bg))
    btn.bind("<Enter>", lambda e: btn.config(bg=_lighten(bg)))
    btn.bind("<Leave>", lambda e: btn.config(bg=bg))


if __name__ == "__main__":
    App().mainloop()
