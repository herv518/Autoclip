#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

APPLY=0
DAYS="${DAYS:-14}"

usage() {
  cat <<'EOF'
Usage: tidy.sh [--apply] [--days N]

Options:
  --apply    Actually delete files (default: dry-run only)
  --days N   Delete artifacts older than N days (default: 14)
  --help     Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)
      APPLY=1
      shift
      ;;
    --days)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --days"
        exit 1
      fi
      DAYS="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

if ! [[ "$DAYS" =~ ^[0-9]+$ ]]; then
  echo "--days must be a non-negative integer"
  exit 1
fi

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

TMP_DIR_ABS="$(to_abs_path "${TMP_DIR:-.tmp}")"
WATCH_PID_FILE_ABS="$(to_abs_path "${WATCH_PID_FILE:-${TMP_DIR:-.tmp}/watch.pid}")"
WATCH_LOCK_DIR_ABS="$(to_abs_path "${WATCH_LOCK_DIR:-${TMP_DIR:-.tmp}/watch_input_frames.lock}")"
RUN_LOG_DIR="$TMP_DIR_ABS/watch_runs"

planned=0
changed=0

report_remove() {
  local path="$1"
  local reason="$2"
  planned=$((planned + 1))
  if (( APPLY == 1 )); then
    if [[ -d "$path" ]]; then
      rm -rf "$path"
    else
      rm -f "$path"
    fi
    echo "[DEL]  $path ($reason)"
    changed=$((changed + 1))
  else
    echo "[PLAN] $path ($reason)"
  fi
}

echo "Tidy mode: $([[ "$APPLY" == "1" ]] && echo apply || echo dry-run)"
echo "Age threshold: $DAYS day(s)"
echo "Tmp dir: $TMP_DIR_ABS"
echo

if [[ -f "$WATCH_PID_FILE_ABS" ]]; then
  pid="$(cat "$WATCH_PID_FILE_ABS" 2>/dev/null || true)"
  if [[ -z "$pid" ]] || ! kill -0 "$pid" 2>/dev/null; then
    report_remove "$WATCH_PID_FILE_ABS" "stale watcher PID file"
  fi
fi

if [[ -d "$WATCH_LOCK_DIR_ABS" ]]; then
  lock_pid="$(cat "$WATCH_LOCK_DIR_ABS/pid" 2>/dev/null || true)"
  if [[ -z "$lock_pid" ]] || ! kill -0 "$lock_pid" 2>/dev/null; then
    report_remove "$WATCH_LOCK_DIR_ABS" "stale watcher lock"
  fi
fi

if [[ -d "$RUN_LOG_DIR" ]]; then
  while IFS= read -r -d '' f; do
    report_remove "$f" "old watcher run log"
  done < <(find "$RUN_LOG_DIR" -type f -name '*.log' -mtime +"$DAYS" -print0)
fi

if [[ -d "$TMP_DIR_ABS" ]]; then
  while IFS= read -r -d '' f; do
    report_remove "$f" "old temp artifact"
  done < <(
    find "$TMP_DIR_ABS" -type f \
      \( -name 'slideshow_*.txt' -o -name 'overlay_*.txt' -o -name 'tts_*.txt' -o -name 'voice_*.aiff' -o -name 'fax_*.txt' \) \
      -mtime +"$DAYS" -print0
  )
fi

echo
if (( APPLY == 1 )); then
  echo "Done. Removed $changed item(s)."
else
  echo "Dry-run complete. Planned removals: $planned item(s)."
  echo "Run with --apply to execute cleanup."
fi
