#!/usr/bin/env python3
"""AutoClip TUI (dependency-free, curses based)."""

from __future__ import annotations

import curses
import os
import re
import shlex
import subprocess
import threading
import time
from collections import deque
from pathlib import Path
from typing import Deque

ROOT = Path(__file__).resolve().parent
AUTOCLIP = ROOT / "autoclip"
WATCH_LOG = ROOT / "watch_input_frames.log"
RUN_LOG_DIR = ROOT / ".tmp" / "watch_runs"
PID_FILE = ROOT / ".tmp" / "watch.pid"
OUTPUT_DIR = ROOT / "Output"

STATE_FILTERS = ["all", "fail", "run", "ok", "warn", "unk"]
MP4_FILTERS = ["all", "no", "yes"]
KNOWN_COMMANDS = {
    "render",
    "watch",
    "logs",
    "jobs",
    "ui",
    "dashboard",
    "status",
    "doctor",
    "interactive",
    "shortcuts",
    "help",
}

HERO_BANNER = [
    "    AAA   U   U TTTTT  OOO   CCCC  L      III  PPPP ",
    "   A   A  U   U   T   O   O C      L       I   P   P",
    "   AAAAA  U   U   T   O   O C      L       I   PPPP ",
    "   A   A  U   U   T   O   O C      L       I   P    ",
    "   A   A   UUU    T    OOO   CCCC  LLLLL  III  P    ",
]

HERO_SHADOW: list[str] = []


def safe_process_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def get_branch() -> str:
    try:
        out = subprocess.check_output(
            ["git", "-C", str(ROOT), "rev-parse", "--abbrev-ref", "HEAD"],
            stderr=subprocess.DEVNULL,
            text=True,
        ).strip()
        return out or "unknown"
    except Exception:
        return "unknown"


def get_watcher_state() -> str:
    if not PID_FILE.exists():
        return "off"
    try:
        raw = PID_FILE.read_text(encoding="utf-8", errors="ignore").strip()
        pid = int(raw)
    except Exception:
        return "off"
    return f"on(pid={pid})" if safe_process_alive(pid) else "off"


def output_counts() -> tuple[int, int]:
    mp4 = len(list(OUTPUT_DIR.glob("*.mp4"))) if OUTPUT_DIR.exists() else 0
    webm = len(list(OUTPUT_DIR.glob("*.webm"))) if OUTPUT_DIR.exists() else 0
    return mp4, webm


def latest_outputs(limit: int = 3) -> list[str]:
    if not OUTPUT_DIR.exists():
        return []
    rows: list[tuple[float, str]] = []
    for p in OUTPUT_DIR.glob("*.mp4"):
        try:
            rows.append((p.stat().st_mtime, p.name))
        except OSError:
            continue
    rows.sort(key=lambda x: x[0], reverse=True)
    return [name for _mtime, name in rows[: max(1, limit)]]


def classify_state(log_file: Path, age: int, run_id: str) -> str:
    if not log_file.exists():
        return "UNK"
    try:
        text = log_file.read_text(encoding="utf-8", errors="ignore").lower()
    except Exception:
        text = ""

    if any(token in text for token in ("fehlgeschlagen", "failed", "error:", "abbruch", "traceback")):
        state = "FAIL"
    elif "[+] fertig:" in text:
        state = "OK"
    elif age <= 120:
        state = "RUN"
    else:
        state = "UNK"

    out = OUTPUT_DIR / f"{run_id}.mp4"
    if state == "OK" and (not out.exists() or out.stat().st_size <= 0):
        state = "OK?"
    return state


def state_matches(state: str, flt: str) -> bool:
    if flt == "all":
        return True
    if flt == "ok":
        return state in {"OK", "OK?"}
    if flt == "fail":
        return state == "FAIL"
    if flt == "run":
        return state == "RUN"
    if flt == "warn":
        return state == "OK?"
    if flt == "unk":
        return state == "UNK"
    return True


def mp4_matches(mp4: str, flt: str) -> bool:
    if flt == "all":
        return True
    return mp4 == flt


def collect_jobs(limit: int, state_filter: str, mp4_filter: str) -> list[dict[str, object]]:
    if not RUN_LOG_DIR.exists():
        return []

    now = int(time.time())
    rows: list[dict[str, object]] = []
    for path in RUN_LOG_DIR.glob("*.log"):
        run_id = path.stem
        if not run_id.isdigit():
            continue
        try:
            mtime = int(path.stat().st_mtime)
        except OSError:
            mtime = 0
        age = max(0, now - mtime)
        state = classify_state(path, age, run_id)
        out_file = OUTPUT_DIR / f"{run_id}.mp4"
        mp4 = "yes" if out_file.exists() and out_file.stat().st_size > 0 else "no"
        if not state_matches(state, state_filter):
            continue
        if not mp4_matches(mp4, mp4_filter):
            continue
        rows.append(
            {
                "mtime": mtime,
                "id": run_id,
                "state": state,
                "age": age,
                "mp4": mp4,
                "file": path,
            }
        )
    rows.sort(key=lambda x: int(x["mtime"]), reverse=True)
    return rows[:limit]


def format_age(seconds: int) -> str:
    if seconds < 60:
        return f"{seconds}s"
    if seconds < 3600:
        return f"{seconds // 60}m"
    if seconds < 86400:
        return f"{seconds // 3600}h"
    return f"{seconds // 86400}d"


def tail_lines(path: Path, limit: int) -> list[str]:
    if not path.exists():
        return [f"(warte auf Log-Datei: {path})"]
    try:
        lines = path.read_text(encoding="utf-8", errors="ignore").splitlines()
    except Exception as exc:
        return [f"(konnte {path.name} nicht lesen: {exc})"]
    if not lines:
        return ["(Log ist leer)"]
    return lines[-max(1, limit) :]


class CommandRunner:
    def __init__(self) -> None:
        self.output: Deque[str] = deque(maxlen=800)
        self._lock = threading.Lock()
        self._proc: subprocess.Popen[str] | None = None
        self._thread: threading.Thread | None = None

    def is_running(self) -> bool:
        return self._proc is not None and self._proc.poll() is None

    def add_line(self, line: str) -> None:
        with self._lock:
            self.output.append(line.rstrip("\n"))

    def get_lines(self, limit: int) -> list[str]:
        with self._lock:
            return list(self.output)[-max(1, limit) :]

    def clear(self) -> None:
        with self._lock:
            self.output.clear()

    def start(self, command_line: str) -> tuple[bool, str]:
        if self.is_running():
            return False, "command already running"

        try:
            args = shlex.split(command_line)
        except ValueError as exc:
            return False, f"parse error: {exc}"
        if not args:
            return False, "empty command"

        full_cmd = ["bash", str(AUTOCLIP), *args]
        self.add_line(f"$ {' '.join(full_cmd)}")

        try:
            proc = subprocess.Popen(
                full_cmd,
                cwd=ROOT,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
            )
        except Exception as exc:
            return False, f"failed to start command: {exc}"

        self._proc = proc

        def _reader() -> None:
            assert proc.stdout is not None
            for line in proc.stdout:
                self.add_line(line.rstrip("\n"))
            code = proc.wait()
            self.add_line(f"[command exited with code {code}]")

        self._thread = threading.Thread(target=_reader, daemon=True)
        self._thread.start()
        return True, "command started"

    def stop(self) -> None:
        if self._proc is None:
            return
        if self._proc.poll() is None:
            try:
                self._proc.terminate()
            except Exception:
                pass


def cycle(values: list[str], current: str) -> str:
    try:
        idx = values.index(current)
    except ValueError:
        return values[0]
    return values[(idx + 1) % len(values)]


def clamp(n: int, low: int, high: int) -> int:
    return max(low, min(high, n))


def resolve_user_command(raw: str, watcher_state: str) -> tuple[str | None, str]:
    text = raw.strip()
    if not text:
        return None, "Bitte schreibe kurz, was du tun willst. Beispiel: video fuer 12345 erstellen"

    lowered = " ".join(text.lower().split())
    parts = lowered.split()
    first = parts[0] if parts else ""

    # 1) numeric shortcut: "1223" -> "render 1223"
    if text.isdigit():
        cmd = f"render {text}"
        return cmd, f"ID erkannt. Starte Video fuer {text}."

    # 2) parse id once for command + natural language handling
    id_match = re.search(r"\b(\d{4,7})\b", lowered)
    vehicle_id = id_match.group(1) if id_match else None
    url_match = re.search(r"(https?://\S+)", text, flags=re.IGNORECASE)
    source_url = ""
    if url_match:
        source_url = url_match.group(1).rstrip(".,);")

    # 3) existing command style (with a few beginner-friendly corrections)
    if first in KNOWN_COMMANDS:
        if first == "render" and not vehicle_id:
            return None, "Bitte gib eine ID an, z. B. 'render 12345'."
        if first == "watch" and len(parts) == 1:
            if watcher_state.startswith("on("):
                return "watch status", "Watcher laeuft bereits. Zeige Status."
            return "watch start", "Starte Watcher."
        if first == "jobs" and len(parts) > 1 and not any(p.startswith("-") for p in parts[1:]):
            # phrases like "jobs anzeigen" should be treated as natural language
            pass
        else:
            return text, f"Verstanden: {text}"

    if any(word in lowered for word in ("hilfe", "help", "was geht", "was kann", "befehle", "fragen")):
        return "help", "Zeige Hilfe."

    if "watch" in lowered or "watcher" in lowered or "ueberwachung" in lowered:
        if any(word in lowered for word in ("status", "laeuft", "an?", "aktiv")):
            return "watch status", "Pruefe Watcher-Status."
        if any(word in lowered for word in ("stop", "stopp", "aus", "beenden", "deaktiv", "pause")):
            return "watch stop", "Stoppe Watcher."
        if any(word in lowered for word in ("start", "an", "aktivier", "weiter")):
            return "watch start", "Starte Watcher."
        if watcher_state.startswith("on("):
            return "watch status", "Watcher laeuft bereits. Zeige Status."
        return "watch start", "Starte Watcher."

    if any(word in lowered for word in ("dashboard", "monitor", "live", "uebersicht", "konsole")):
        return "dashboard watch --lines 18 --interval 1", "Oeffne Live-Dashboard."

    if any(word in lowered for word in ("jobs", "laeufe", "runs", "letzte")):
        return "jobs --watch --limit 10 --interval 1", "Oeffne Jobmonitor."

    if any(word in lowered for word in ("status", "gesundheit", "health")):
        return "status", "Zeige Systemstatus."

    if any(word in lowered for word in ("render", "video", "clip", "reel", "erstell", "erzeug", "baue")):
        if vehicle_id:
            cmd = f"render {vehicle_id}"
            if source_url:
                cmd = f"{cmd} {source_url}"
            return cmd, f"Starte Video-Render fuer ID {vehicle_id}."
        return None, "Dafuer brauche ich eine ID, z. B. 'video fuer 12345 erstellen'."

    if vehicle_id:
        cmd = f"render {vehicle_id}"
        if source_url:
            cmd = f"{cmd} {source_url}"
        return cmd, f"ID {vehicle_id} erkannt. Ich starte den Render."

    if lowered in {"start", "go", "los"}:
        if watcher_state.startswith("on("):
            return "watch status", "Watcher laeuft bereits. Zeige Status."
        return "watch start", "Starte Watcher."

    return None, (
        "Ich habe das nicht verstanden. Beispiele: "
        "'video fuer 12345 erstellen', 'watcher starten', 'jobs anzeigen', 'status'."
    )


def friendly_runner_message(msg: str) -> str:
    if msg == "command already running":
        return "Es laeuft bereits ein Befehl. Bitte kurz warten."
    if msg.startswith("parse error"):
        return "Eingabe konnte nicht gelesen werden. Bitte pruefe Anfuehrungszeichen."
    if msg == "empty command":
        return "Leere Eingabe."
    return msg


def draw_box(stdscr: curses.window, y: int, x: int, h: int, w: int, attr: int = 0) -> None:
    if h < 2 or w < 2:
        return
    try:
        if attr:
            stdscr.attron(attr)
        stdscr.hline(y, x, curses.ACS_HLINE, w)
        stdscr.hline(y + h - 1, x, curses.ACS_HLINE, w)
        stdscr.vline(y, x, curses.ACS_VLINE, h)
        stdscr.vline(y, x + w - 1, curses.ACS_VLINE, h)
        stdscr.addch(y, x, curses.ACS_ULCORNER)
        stdscr.addch(y, x + w - 1, curses.ACS_URCORNER)
        stdscr.addch(y + h - 1, x, curses.ACS_LLCORNER)
        stdscr.addch(y + h - 1, x + w - 1, curses.ACS_LRCORNER)
        if attr:
            stdscr.attroff(attr)
    except curses.error:
        return


def safe_addstr(stdscr: curses.window, y: int, x: int, text: str, attr: int = 0) -> None:
    try:
        stdscr.addstr(y, x, text, attr)
    except curses.error:
        pass


def centered_x(width: int, text: str) -> int:
    return max(0, (width - len(text)) // 2)


def fit(text: str, width: int) -> str:
    if width <= 0:
        return ""
    if len(text) <= width:
        return text
    if width <= 1:
        return text[:width]
    return text[: width - 1] + "…"


def run(stdscr: curses.window) -> None:
    try:
        curses.curs_set(0)
    except curses.error:
        pass
    stdscr.nodelay(True)
    stdscr.timeout(180)
    try:
        curses.use_default_colors()
        curses.start_color()
        curses.init_pair(1, curses.COLOR_CYAN, -1)
        curses.init_pair(2, curses.COLOR_GREEN, -1)
        curses.init_pair(3, curses.COLOR_YELLOW, -1)
        curses.init_pair(4, curses.COLOR_RED, -1)
        curses.init_pair(5, curses.COLOR_MAGENTA, -1)
    except curses.error:
        pass

    banner_title = "AutoClip - cline-movies"
    bootline = "WILLKOMMEN. ALLES IST EINFACH."
    source = "watch"  # watch | run | cmd
    state_filter = "all"
    mp4_filter = "all"
    limit = 8
    log_lines = 18
    refresh_sec = 1
    selected = 0
    help_on = True
    note = ""
    command_mode = False
    command_buffer = ""
    runner = CommandRunner()
    jobs: list[dict[str, object]] = []
    next_refresh = 0.0

    while True:
        now = time.monotonic()
        if now >= next_refresh:
            jobs = collect_jobs(limit, state_filter, mp4_filter)
            if jobs:
                selected = clamp(selected, 0, len(jobs) - 1)
            else:
                selected = 0
            next_refresh = now + refresh_sec

        h, w = stdscr.getmaxyx()
        stdscr.erase()
        if h < 28 or w < 96:
            safe_addstr(stdscr, 1, 2, "FENSTER ZU KLEIN.", curses.color_pair(4) | curses.A_BOLD)
            safe_addstr(stdscr, 3, 2, "Bitte Fenster groesser ziehen (mindestens 96x28).", curses.color_pair(3))
            safe_addstr(stdscr, 5, 2, "SO STARTEST DU:", curses.color_pair(5) | curses.A_BOLD)
            safe_addstr(stdscr, 6, 2, f"1) cd {ROOT}", curses.color_pair(1))
            safe_addstr(stdscr, 7, 2, "2) bash ./autoclip ui", curses.color_pair(1))
            safe_addstr(stdscr, 9, 2, "q = beenden", curses.color_pair(2))
            stdscr.refresh()
            key = stdscr.getch()
            if key in (ord("q"), ord("Q")):
                break
            continue

        branch = get_branch()
        watcher = get_watcher_state()
        mp4_count, webm_count = output_counts()
        recent_mp4 = latest_outputs(3)
        tstamp = time.strftime("%Y-%m-%d %H:%M:%S")

        # Top bar
        safe_addstr(stdscr, 0, 2, "o", curses.color_pair(4) | curses.A_BOLD)
        safe_addstr(stdscr, 0, 4, "o", curses.color_pair(3) | curses.A_BOLD)
        safe_addstr(stdscr, 0, 6, "o", curses.color_pair(2) | curses.A_BOLD)
        safe_addstr(stdscr, 0, centered_x(w, banner_title), banner_title, curses.color_pair(5) | curses.A_BOLD)
        safe_addstr(stdscr, 0, max(2, w - len(tstamp) - 2), tstamp, curses.color_pair(1))

        # Prompt/boot line
        safe_addstr(stdscr, 1, 2, ">>>", curses.color_pair(5) | curses.A_BOLD)
        safe_addstr(stdscr, 1, 6, "autoclip", curses.color_pair(2) | curses.A_BOLD)
        safe_addstr(stdscr, 1, 16, bootline, curses.color_pair(3))

        # Hero banner + shadow
        hero_y = 3
        for i, line in enumerate(HERO_BANNER):
            attr = curses.color_pair(5 if i < 2 else 1) | curses.A_BOLD
            safe_addstr(stdscr, hero_y + i, centered_x(w, line), line, attr)
        for i, line in enumerate(HERO_SHADOW):
            safe_addstr(stdscr, hero_y + len(HERO_BANNER) + i, centered_x(w, line), line, curses.color_pair(5))

        info_y = hero_y + len(HERO_BANNER) + len(HERO_SHADOW) + 1
        if help_on:
            safe_addstr(stdscr, info_y, 2, fit("SO GEHT ES (SEHR EINFACH):", w - 4), curses.color_pair(5) | curses.A_BOLD)
            safe_addstr(stdscr, info_y + 1, 2, fit("1) DRUECKE ENTER ODER ':'", w - 4), curses.color_pair(3) | curses.A_BOLD)
            safe_addstr(stdscr, info_y + 2, 2, fit("2) SCHREIBE: video fuer 12345 erstellen", w - 4), curses.color_pair(1) | curses.A_BOLD)
            safe_addstr(stdscr, info_y + 3, 2, fit("3) DRUECKE ENTER", w - 4), curses.color_pair(2) | curses.A_BOLD)
            safe_addstr(stdscr, info_y + 4, 2, fit("SCHNELLTASTEN: V=VIDEO  W=WATCHER  R=NEU  H=HILFE  Q=ENDE", w - 4), curses.color_pair(3))
            safe_addstr(
                stdscr,
                info_y + 5,
                2,
                fit(
                    f"START (TERMINAL): cd {ROOT}  &&  bash ./autoclip ui",
                    w - 4,
                ),
                curses.color_pair(1),
            )
            safe_addstr(
                stdscr,
                info_y + 6,
                2,
                fit("WICHTIG: LINKS = NUR WATCHER-JOBS. MANUELLER RENDER ERSCHEINT RECHTS.", w - 4),
                curses.color_pair(3),
            )
            safe_addstr(
                stdscr,
                info_y + 7,
                2,
                fit("ECHTE WEBDATEN: render 12345 https://deine-seite.de/fahrzeug/12345", w - 4),
                curses.color_pair(3),
            )
            safe_addstr(
                stdscr,
                info_y + 8,
                2,
                fit("ODER als Satz: video fuer 12345 erstellen https://deine-seite.de/...", w - 4),
                curses.color_pair(3),
            )
            body_y = info_y + 10
        else:
            safe_addstr(stdscr, info_y, 2, fit("H DRUECKEN = HILFE EINBLENDEN", w - 4), curses.color_pair(3))
            safe_addstr(
                stdscr,
                info_y + 1,
                2,
                fit(
                    f"STATUS: watch={watcher}  videos mp4={mp4_count} webm={webm_count}  filter={state_filter}/{mp4_filter}",
                    w - 4,
                ),
                curses.color_pair(1),
            )
            body_y = info_y + 3
        footer_h = 1
        input_h = 3
        body_h = h - body_y - input_h - footer_h - 1
        left_w = (w - 1) // 2
        right_x = left_w + 1
        right_w = w - right_x

        draw_box(stdscr, body_y, 0, body_h, left_w, curses.color_pair(1))
        draw_box(stdscr, body_y, right_x, body_h, right_w, curses.color_pair(1))

        safe_addstr(stdscr, body_y, 3, "[ 1) WATCHER-JOBS ]", curses.color_pair(1) | curses.A_BOLD)
        if source == "watch":
            rt = f"[ 2) LIVE-LOG (WATCHER) | {WATCH_LOG.name} ]"
        elif source == "run":
            if jobs:
                rt = f"[ 2) LOG VOM JOB {jobs[selected]['id']} ]"
            else:
                rt = "[ 2) LOG VOM JOB ]"
        else:
            running = "LAEUFT" if runner.is_running() else "BEREIT"
            rt = f"[ 2) BEFEHLS-AUSGABE ({running}) ]"
        safe_addstr(stdscr, body_y, right_x + 3, fit(rt, right_w - 6), curses.color_pair(1) | curses.A_BOLD)

        # Left pane table
        row_y = body_y + 1
        safe_addstr(stdscr, row_y, 2, fit("#  ID      STATUS ZEIT MP4", left_w - 4), curses.A_BOLD)
        row_y += 1
        if not jobs:
            safe_addstr(stdscr, row_y, 2, fit("Noch keine WATCHER-Jobs gefunden.", left_w - 4), curses.color_pair(3) | curses.A_BOLD)
            row_y += 1
            safe_addstr(stdscr, row_y, 2, fit("Das ist normal, wenn du manuell renderst.", left_w - 4), curses.color_pair(1))
            row_y += 1
            safe_addstr(stdscr, row_y, 2, fit("Druecke W fuer Auto-Modus (Watcher).", left_w - 4), curses.color_pair(2))
            row_y += 1
            safe_addstr(stdscr, row_y, 2, fit("Manuell gestartet? Dann steht es rechts im Log.", left_w - 4), curses.color_pair(1))
            row_y += 1
            if recent_mp4:
                safe_addstr(
                    stdscr,
                    row_y,
                    2,
                    fit(f"Fertige Videos im Output: {mp4_count}", left_w - 4),
                    curses.color_pair(5),
                )
                row_y += 1
                safe_addstr(stdscr, row_y, 2, fit("Letzte:", left_w - 4), curses.color_pair(3))
                for name in recent_mp4:
                    row_y += 1
                    safe_addstr(stdscr, row_y, 4, fit(f"- {name}", left_w - 6), curses.color_pair(1))
        else:
            max_rows = body_h - 3
            for idx, job in enumerate(jobs[:max_rows]):
                line = f"{idx+1:>2} {job['id']:<7} {job['state']:<5} {format_age(int(job['age'])):<4} {job['mp4']}"
                attr = curses.A_REVERSE if idx == selected else curses.A_NORMAL
                color = 0
                if job["state"] == "FAIL":
                    color = curses.color_pair(4)
                elif job["state"] in {"OK", "OK?"}:
                    color = curses.color_pair(2 if job["state"] == "OK" else 3)
                elif job["state"] == "RUN":
                    color = curses.color_pair(1)
                safe_addstr(stdscr, row_y + idx, 2, fit(line, left_w - 4), attr | color)

        # Right pane log
        if source == "watch":
            lines = tail_lines(WATCH_LOG, min(body_h - 2, log_lines))
        elif source == "run":
            if jobs:
                log_path = Path(str(jobs[selected]["file"]))
                lines = tail_lines(log_path, min(body_h - 2, log_lines))
            else:
                lines = ["(kein Run ausgewaehlt)"]
        else:
            lines = runner.get_lines(min(body_h - 2, log_lines))
            if not lines:
                lines = ["(noch keine Befehlsausgabe)"]

        max_log = body_h - 2
        for i, line in enumerate(lines[:max_log]):
            safe_addstr(stdscr, body_y + 1 + i, right_x + 2, fit(line, right_w - 4))

        # Bottom command bar
        input_y = h - footer_h - input_h
        draw_box(stdscr, input_y, 0, input_h, w, curses.color_pair(1))
        if command_mode:
            try:
                curses.curs_set(1)
            except curses.error:
                pass
            safe_addstr(stdscr, input_y + 1, 2, ">", curses.color_pair(5) | curses.A_BOLD)
            safe_addstr(stdscr, input_y + 1, 4, "SCHREIBE HIER (z.B. video fuer 12345 erstellen): ", curses.color_pair(1))
            prompt_w = len("SCHREIBE HIER (z.B. video fuer 12345 erstellen): ") + 4
            shown = fit(command_buffer, max(1, w - prompt_w - 4))
            safe_addstr(stdscr, input_y + 1, prompt_w, shown)
            try:
                stdscr.move(input_y + 1, min(w - 2, prompt_w + len(shown)))
            except curses.error:
                pass
        else:
            try:
                curses.curs_set(0)
            except curses.error:
                pass
            safe_addstr(
                stdscr,
                input_y + 1,
                2,
                fit("ENTER oder ':' = schreiben | V = Video | W = Watcher an/aus", w - 4),
                curses.color_pair(1),
            )
            if note:
                safe_addstr(stdscr, input_y + 1, max(2, w - len(note) - 4), fit(note, w // 2), curses.color_pair(3))

        # Footer
        footer_y = h - 1
        cwd_short = str(ROOT).replace(str(Path.home()), "~")
        footer_left = f"{cwd_short} ({branch})"
        footer_mid = f"watch:{watcher}"
        footer_right = f"source={source} state={state_filter} mp4={mp4_filter}"
        safe_addstr(stdscr, footer_y, 1, fit(footer_left, max(1, w // 3 - 2)), curses.color_pair(1))
        safe_addstr(stdscr, footer_y, max(1, w // 3), fit(footer_mid, max(1, w // 3 - 2)), curses.color_pair(4 if watcher == "off" else 2))
        safe_addstr(stdscr, footer_y, max(1, (2 * w) // 3), fit(footer_right, max(1, w // 3 - 2)), curses.color_pair(5))

        stdscr.refresh()

        key = stdscr.getch()
        if key == -1:
            continue

        if command_mode:
            if key in (27,):  # ESC
                command_mode = False
                command_buffer = ""
                note = "Eingabe abgebrochen."
            elif key in (curses.KEY_BACKSPACE, 127, 8):
                command_buffer = command_buffer[:-1]
            elif key in (10, 13, curses.KEY_ENTER):
                user_text = command_buffer.strip()
                command_mode = False
                command_buffer = ""
                if user_text:
                    normalized = user_text.lower()
                    if normalized in {"clear", "cls"}:
                        runner.clear()
                        source = "cmd"
                        note = "Ausgabe geleert."
                    else:
                        resolved, explanation = resolve_user_command(user_text, watcher)
                        source = "cmd"
                        if not resolved:
                            note = explanation
                            runner.add_line(f"> {user_text}")
                            runner.add_line(f"[hinweis] {explanation}")
                        else:
                            if resolved != user_text:
                                runner.add_line(f"[interpretiert] {user_text} -> {resolved}")
                            ok, msg = runner.start(resolved)
                            if ok:
                                note = explanation
                            else:
                                note = friendly_runner_message(msg)
                else:
                    note = "Leere Eingabe."
            elif 32 <= key < 127:
                command_buffer += chr(key)
            continue

        if key in (ord("q"), ord("Q")):
            break
        if key in (10, 13, curses.KEY_ENTER):
            command_mode = True
            command_buffer = ""
            note = "Schreibe jetzt kurz, was du willst."
            continue
        if key == ord(":"):
            command_mode = True
            note = ""
            continue
        if key in (ord("v"), ord("V")):
            command_mode = True
            command_buffer = "video fuer "
            note = "ID ergaenzen und Enter druecken."
            continue
        if key in (ord("w"), ord("W")):
            target = "watch stop" if watcher.startswith("on(") else "watch start"
            ok, msg = runner.start(target)
            source = "cmd"
            if ok:
                note = "Stoppe Watcher." if target.endswith("stop") else "Starte Watcher."
            else:
                note = friendly_runner_message(msg)
            continue
        if key in (ord("h"), ord("H"), ord("?")):
            help_on = not help_on
        elif key in (ord("j"), curses.KEY_DOWN):
            if jobs:
                selected = clamp(selected + 1, 0, len(jobs) - 1)
        elif key in (ord("k"), curses.KEY_UP):
            if jobs:
                selected = clamp(selected - 1, 0, len(jobs) - 1)
        elif key == ord("1"):
            source = "watch"
        elif key == ord("2"):
            source = "run"
        elif key == ord("3"):
            source = "cmd"
        elif key == ord("f"):
            state_filter = cycle(STATE_FILTERS, state_filter)
            next_refresh = 0
        elif key == ord("m"):
            mp4_filter = cycle(MP4_FILTERS, mp4_filter)
            next_refresh = 0
        elif key == ord("+"):
            limit = min(30, limit + 1)
            next_refresh = 0
        elif key == ord("-"):
            limit = max(1, limit - 1)
            next_refresh = 0
        elif key == ord("["):
            log_lines = max(8, log_lines - 1)
        elif key == ord("]"):
            log_lines = min(120, log_lines + 1)
        elif key in (ord("r"), ord("R")):
            next_refresh = 0
            note = "Neu geladen."
        elif key in (ord("d"), ord("D")) and jobs:
            run_id = str(jobs[selected]["id"])
            ok, msg = runner.start(f"dashboard run {run_id} --lines {log_lines} --interval 1")
            source = "cmd"
            note = "Dashboard gestartet." if ok else friendly_runner_message(msg)
        elif key in (ord("l"), ord("L")) and jobs:
            source = "run"

    runner.stop()


def main() -> None:
    curses.wrapper(run)


if __name__ == "__main__":
    main()
