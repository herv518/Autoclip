#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

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

INPUT_DIR="$(to_abs_path "${INPUT_FRAMES_DIR:-Input-Frames}")"
OUT_DIR_ABS="$(to_abs_path "${OUT_DIR:-Output}")"
TMP_DIR_ABS="$(to_abs_path "${TMP_DIR:-.tmp}")"
IDS_FILE_ABS="$(to_abs_path "${IDS_FILE:-metadata/ids.txt}")"
WATCH_LOG_FILE_ABS="$(to_abs_path "${WATCH_LOG_FILE:-watch_input_frames.log}")"
WATCH_PID_FILE_ABS="$(to_abs_path "${WATCH_PID_FILE:-${TMP_DIR:-.tmp}/watch.pid}")"
WATCH_LOCK_DIR_ABS="$(to_abs_path "${WATCH_LOCK_DIR:-${TMP_DIR:-.tmp}/watch_input_frames.lock}")"

fail_count=0
warn_count=0

ok() {
  echo "[OK]   $*"
}

info() {
  echo "[INFO] $*"
}

warn() {
  echo "[WARN] $*"
  warn_count=$((warn_count + 1))
}

fail() {
  echo "[FAIL] $*"
  fail_count=$((fail_count + 1))
}

check_required_cmd() {
  local cmd="$1"
  if command -v "$cmd" >/dev/null 2>&1; then
    ok "command available: $cmd"
  else
    fail "missing command: $cmd"
  fi
}

check_optional_cmd() {
  local cmd="$1"
  if command -v "$cmd" >/dev/null 2>&1; then
    ok "optional command available: $cmd"
  else
    warn "optional command missing: $cmd"
  fi
}

check_script() {
  local rel="$1"
  local abs="$ROOT/$rel"
  if [[ ! -f "$abs" ]]; then
    fail "missing script: $rel"
    return
  fi
  if [[ ! -x "$abs" ]]; then
    warn "script is not executable: $rel"
  else
    ok "script executable: $rel"
  fi
}

echo "== Core Commands =="
check_required_cmd ffmpeg
check_required_cmd ffprobe
check_required_cmd python3
check_optional_cmd qrencode
check_optional_cmd say

echo
echo "== Core Scripts =="
check_script "run.sh"
check_script "start"
check_script "bin/watch_input_frames.sh"
check_script "bin/stop_watch.sh"

echo
echo "== Paths =="
if [[ -d "$INPUT_DIR" ]]; then ok "input dir: $INPUT_DIR"; else warn "input dir missing: $INPUT_DIR"; fi
if [[ -d "$OUT_DIR_ABS" ]]; then ok "output dir: $OUT_DIR_ABS"; else warn "output dir missing: $OUT_DIR_ABS"; fi
if [[ -d "$TMP_DIR_ABS" ]]; then ok "tmp dir: $TMP_DIR_ABS"; else warn "tmp dir missing: $TMP_DIR_ABS"; fi
if [[ -f "$IDS_FILE_ABS" ]]; then
  ok "ids registry: $IDS_FILE_ABS"
else
  info "ids registry not created yet: $IDS_FILE_ABS"
fi

if [[ -f "$WATCH_LOG_FILE_ABS" ]]; then
  ok "watcher log: $WATCH_LOG_FILE_ABS"
else
  info "watcher log not created yet: $WATCH_LOG_FILE_ABS"
fi

echo
echo "== Watcher State =="
if [[ -f "$WATCH_PID_FILE_ABS" ]]; then
  pid="$(cat "$WATCH_PID_FILE_ABS" 2>/dev/null || true)"
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    ok "watcher running (PID $pid)"
  elif [[ -n "$pid" ]]; then
    warn "stale watcher PID file: $WATCH_PID_FILE_ABS (PID $pid not running)"
  else
    warn "empty watcher PID file: $WATCH_PID_FILE_ABS"
  fi
else
  info "watcher not running (no PID file)"
fi

if [[ -d "$WATCH_LOCK_DIR_ABS" ]]; then
  lock_pid="$(cat "$WATCH_LOCK_DIR_ABS/pid" 2>/dev/null || true)"
  if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
    ok "watch lock active (PID $lock_pid)"
  else
    warn "stale watch lock directory: $WATCH_LOCK_DIR_ABS"
  fi
else
  info "watch lock not present"
fi

echo
echo "== Output Snapshot =="
mp4_count="$(find "$OUT_DIR_ABS" -maxdepth 1 -type f -name '*.mp4' 2>/dev/null | wc -l | tr -d ' ')"
webm_count="$(find "$OUT_DIR_ABS" -maxdepth 1 -type f -name '*.webm' 2>/dev/null | wc -l | tr -d ' ')"
ok "mp4 files: ${mp4_count:-0}"
ok "webm files: ${webm_count:-0}"

if (( fail_count > 0 )); then
  echo
  echo "Healthcheck failed: $fail_count critical issue(s), $warn_count warning(s)."
  exit 1
fi

echo
echo "Healthcheck passed: 0 critical issue(s), $warn_count warning(s)."
