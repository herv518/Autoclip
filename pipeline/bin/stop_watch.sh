#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

is_uint() {
  local v="$1"
  [[ "$v" =~ ^[0-9]+$ ]]
}

to_abs_path() {
  local p="$1"
  if [[ "$p" == /* ]]; then
    echo "$p"
  else
    echo "$ROOT/$p"
  fi
}

if [[ -f "$ROOT/config.sh" ]]; then
  # shellcheck source=/dev/null
  source "$ROOT/config.sh"
fi

for env_file in "${LOCAL_ENV_FILE:-}" ".mail.env" ".fax.env" ".watch.env"; do
  [[ -n "${env_file:-}" ]] || continue
  if [[ -f "$ROOT/$env_file" ]]; then
    # shellcheck source=/dev/null
    source "$ROOT/$env_file"
  fi
done

TMP_DIR_REL="${TMP_DIR:-.tmp}"
WATCH_PID_FILE="${WATCH_PID_FILE:-$TMP_DIR_REL/watch.pid}"
WATCH_LOCK_DIR="${WATCH_LOCK_DIR:-$TMP_DIR_REL/watch_input_frames.lock}"
PID_FILE="$(to_abs_path "$WATCH_PID_FILE")"
LOCK_DIR="$(to_abs_path "$WATCH_LOCK_DIR")"
TMP_DIR_ABS="$(to_abs_path "${TMP_DIR:-.tmp}")"

safe_rm_dir() {
  local p="$1"
  [[ -n "$p" ]] || return 1
  [[ "$p" != "/" ]] || return 1
  case "$p" in
    "$TMP_DIR_ABS"/*|"$TMP_DIR_ABS")
      rm -rf "$p"
      ;;
    *)
      echo "[!] Refuse rm -rf outside TMP_DIR: $p" >&2
      return 1
      ;;
  esac
}

stop_pid_file() {
  local label="$1"
  local pid_file="$2"

  if [[ ! -f "$pid_file" ]]; then
    echo "Kein $label gefunden (PID-Datei fehlt): $pid_file"
    return 0
  fi

  local pid
  pid="$(cat "$pid_file" 2>/dev/null || true)"
  if [[ -z "$pid" ]]; then
    echo "PID-Datei leer: $pid_file"
    rm -f "$pid_file"
    return 0
  fi
  if ! is_uint "$pid"; then
    echo "Ungültige PID in Datei: $pid_file ($pid)"
    rm -f "$pid_file"
    return 0
  fi

  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" || true
    echo "$label gestoppt (PID $pid)."
  else
    echo "Kein laufender Prozess für PID $pid. Entferne PID-Datei."
  fi

  rm -f "$pid_file"
}

stop_pid_file "Watcher" "$PID_FILE"

# Fallback: ggf. alte Prozesse ohne PID-Datei stoppen
extra_pids="$(pgrep -f "$ROOT/bin/watch_input_frames.sh" 2>/dev/null || true)"
if [[ -n "$extra_pids" ]]; then
  while IFS= read -r ep; do
    [[ -n "$ep" ]] || continue
    if is_uint "$ep"; then
      kill "$ep" 2>/dev/null || true
    fi
  done <<< "$extra_pids"
  echo "Watcher per Prozesssuche gestoppt ($extra_pids)."
fi

safe_rm_dir "$LOCK_DIR" 2>/dev/null || true
