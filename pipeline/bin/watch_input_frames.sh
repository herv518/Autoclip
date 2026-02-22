#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

die() {
  echo "[!] $*" >&2
  exit 1
}

to_abs_path() {
  local p="$1"
  if [[ -z "$p" ]]; then
    echo ""
    return 0
  fi
  if [[ "$p" == /* ]]; then
    echo "$p"
  else
    echo "$ROOT/$p"
  fi
}

to_display_path() {
  local p="$1"
  if [[ -z "$p" ]]; then
    echo ""
    return 0
  fi
  if [[ "$p" == "$ROOT" ]]; then
    echo "."
    return 0
  fi
  case "$p" in
    "$ROOT"/*)
      echo ".${p#"$ROOT"}"
      ;;
    "$HOME"/*)
      echo "~${p#"$HOME"}"
      ;;
    *)
      echo "$p"
      ;;
  esac
}

is_uint() {
  local v="$1"
  [[ "$v" =~ ^[0-9]+$ ]]
}

is_valid_vehicle_id() {
  local v="$1"
  [[ "$v" =~ ^[0-9]+$ ]]
}

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

if [[ -f "$ROOT/config.sh" ]]; then
  # shellcheck source=/dev/null
  source "$ROOT/config.sh"
fi

# Lokale Overrides (nicht committen)
for env_file in "${LOCAL_ENV_FILE:-}" ".mail.env" ".fax.env" ".watch.env"; do
  [[ -n "${env_file:-}" ]] || continue
  if [[ -f "$ROOT/$env_file" ]]; then
    # shellcheck source=/dev/null
    source "$ROOT/$env_file"
  fi
done

INPUT_DIR="$(to_abs_path "${INPUT_FRAMES_DIR:-Input-Frames}")"
OUT_DIR_ABS="$(to_abs_path "${OUT_DIR:-Output}")"
TMP_DIR_REL="${TMP_DIR:-.tmp}"
TMP_DIR_ABS="$(to_abs_path "$TMP_DIR_REL")"
IDS_FILE_ABS="$(to_abs_path "${IDS_FILE:-metadata/ids.txt}")"
ID_EXTRACT_SCRIPT="$ROOT/bin/extract_ids.sh"

WATCH_LOG_FILE="${WATCH_LOG_FILE:-watch_input_frames.log}"
LOG_FILE="$(to_abs_path "$WATCH_LOG_FILE")"
WATCH_PID_FILE="${WATCH_PID_FILE:-$TMP_DIR_REL/watch.pid}"
PID_FILE="$(to_abs_path "$WATCH_PID_FILE")"
WATCH_LOCK_DIR_VAL="${WATCH_LOCK_DIR:-$TMP_DIR_REL/watch_input_frames.lock}"
WATCH_LOCK_DIR="$(to_abs_path "$WATCH_LOCK_DIR_VAL")"
RUN_LOG_DIR="$TMP_DIR_ABS/watch_runs"
STATE_DIR="$TMP_DIR_ABS/watch_state"
DONE_DIR="$STATE_DIR/done"
FAIL_DIR="$STATE_DIR/fail"
SKIPLOG_DIR="$STATE_DIR/skiplog"

WATCH_POLL_SEC="${WATCH_POLL_SEC:-5}"
WATCH_STABLE_SEC="${WATCH_STABLE_SEC:-8}"
WATCH_FAIL_COOLDOWN_SEC="${WATCH_FAIL_COOLDOWN_SEC:-60}"
WATCH_ONESHOT="${WATCH_ONESHOT:-0}"
WATCH_DRY_RUN="${WATCH_DRY_RUN:-0}"

UPLOAD_INBOX_DIR_ABS=""
if [[ -n "${UPLOAD_INBOX_DIR:-}" ]]; then
  UPLOAD_INBOX_DIR_ABS="$(to_abs_path "$UPLOAD_INBOX_DIR")"
fi
UPLOAD_ARCHIVE_DIR_VAL="${UPLOAD_ARCHIVE_DIR:-$TMP_DIR_REL/upload_archive}"
UPLOAD_ARCHIVE_DIR_ABS="$(to_abs_path "$UPLOAD_ARCHIVE_DIR_VAL")"
UPLOAD_MOVE_TO_ARCHIVE="${UPLOAD_MOVE_TO_ARCHIVE:-1}"

if ! command -v python3 >/dev/null 2>&1; then
  die "python3 fehlt. Installiere es (empfohlen: brew install python)."
fi
if ! is_uint "$WATCH_POLL_SEC"; then
  die "WATCH_POLL_SEC muss eine nicht-negative Zahl sein (aktuell: $WATCH_POLL_SEC)."
fi
if ! is_uint "$WATCH_STABLE_SEC"; then
  die "WATCH_STABLE_SEC muss eine nicht-negative Zahl sein (aktuell: $WATCH_STABLE_SEC)."
fi
if ! is_uint "$WATCH_FAIL_COOLDOWN_SEC"; then
  die "WATCH_FAIL_COOLDOWN_SEC muss eine nicht-negative Zahl sein (aktuell: $WATCH_FAIL_COOLDOWN_SEC)."
fi

mkdir -p "$TMP_DIR_ABS" "$RUN_LOG_DIR" "$DONE_DIR" "$FAIL_DIR" "$SKIPLOG_DIR"
mkdir -p "$(dirname "$LOG_FILE")" "$(dirname "$PID_FILE")"

log() {
  local stamp msg
  stamp="$(date +"%Y-%m-%d %H:%M:%S")"
  msg="[$stamp] $*"
  echo "$msg"
  printf '%s\n' "$msg" >>"$LOG_FILE" 2>/dev/null || true
}

refresh_id_registry() {
  if [[ ! -x "$ID_EXTRACT_SCRIPT" ]]; then
    return 0
  fi
  if ! "$ID_EXTRACT_SCRIPT" --input-dir "$INPUT_DIR" --out "$IDS_FILE_ABS" --quiet; then
    if should_log_throttled "id_registry_fail" 120; then
      log "⚠️ ID-Registry konnte nicht aktualisiert werden: $(to_display_path "$IDS_FILE_ABS")"
    fi
  fi
}

should_log_throttled() {
  local key="$1"
  local interval="${2:-60}"
  local f="$SKIPLOG_DIR/${key}.ts"
  local now last
  now="$(date +%s)"
  last="$(cat "$f" 2>/dev/null || echo 0)"
  if (( now - last >= interval )); then
    printf '%s\n' "$now" >"$f" 2>/dev/null || true
    return 0
  fi
  return 1
}

dir_image_stats() {
  local dir="$1"
  python3 - "$dir" <<'PY'
import sys
from pathlib import Path

dir_path = Path(sys.argv[1])
exts = {".jpg", ".jpeg", ".png", ".JPG", ".JPEG", ".PNG"}
count = 0
latest = 0

if dir_path.is_dir():
    for p in dir_path.iterdir():
        if not p.is_file():
            continue
        if p.suffix not in exts and p.suffix.lower() not in {".jpg", ".jpeg", ".png"}:
            continue
        count += 1
        try:
            m = int(p.stat().st_mtime)
        except OSError:
            continue
        if m > latest:
            latest = m

print(f"{count} {latest}")
PY
}

copy_images_into_input() {
  local source_dir="$1"
  local target_dir="$2"
  local copied=0
  local skipped=0
  local failed=0
  local source_file base_name target_file

  mkdir -p "$target_dir"

  while IFS= read -r -d '' source_file; do
    base_name="$(basename "$source_file")"
    target_file="$target_dir/$base_name"

    if [[ -e "$target_file" ]]; then
      skipped=$((skipped + 1))
      continue
    fi

    if cp "$source_file" "$target_file"; then
      copied=$((copied + 1))
    else
      failed=$((failed + 1))
    fi
  done < <(
    find "$source_dir" -maxdepth 1 -type f \
      \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) \
      -print0
  )

  printf '%s %s %s\n' "$copied" "$skipped" "$failed"
}

import_upload_inbox_once() {
  [[ -n "$UPLOAD_INBOX_DIR_ABS" ]] || return 0

  if [[ ! -d "$UPLOAD_INBOX_DIR_ABS" ]]; then
    if should_log_throttled "missing_upload_inbox" 60; then
      log "ℹ️ Upload-Inbox fehlt: $(to_display_path "$UPLOAD_INBOX_DIR_ABS")"
    fi
    return 0
  fi

  while IFS= read -r source_dir; do
    [[ -d "$source_dir" ]] || continue

    local id
    id="$(basename "$source_dir")"

    if ! is_valid_vehicle_id "$id"; then
      if should_log_throttled "invalid_upload_id_${id//[^A-Za-z0-9_]/_}" 120; then
        log "⚠️ Upload-Ordner ignoriert (ungültige ID): $(to_display_path "$source_dir")"
      fi
      continue
    fi

    local stats count newest now
    stats="$(dir_image_stats "$source_dir")"
    count="$(awk '{print $1}' <<<"$stats")"
    newest="$(awk '{print $2}' <<<"$stats")"

    if [[ -z "$count" || "$count" -eq 0 || -z "$newest" || "$newest" -eq 0 ]]; then
      continue
    fi

    now="$(date +%s)"
    if (( now - newest < WATCH_STABLE_SEC )); then
      continue
    fi

    local import_stats copied skipped failed
    local target_dir="$INPUT_DIR/$id"
    import_stats="$(copy_images_into_input "$source_dir" "$target_dir")"
    copied="$(awk '{print $1}' <<<"$import_stats")"
    skipped="$(awk '{print $2}' <<<"$import_stats")"
    failed="$(awk '{print $3}' <<<"$import_stats")"

    if (( failed > 0 )); then
      log "⚠️ Upload-Import unvollständig: $id (copied=$copied, skipped=$skipped, failed=$failed)"
      continue
    fi

    if (( copied > 0 || skipped > 0 )); then
      log "📥 Upload importiert: $id (copied=$copied, skipped=$skipped)"
    fi

    if [[ "$UPLOAD_MOVE_TO_ARCHIVE" == "1" ]]; then
      mkdir -p "$UPLOAD_ARCHIVE_DIR_ABS"
      local archive_dir
      archive_dir="$UPLOAD_ARCHIVE_DIR_ABS/${id}_$(date +%Y%m%d_%H%M%S)"
      if mv "$source_dir" "$archive_dir" 2>/dev/null; then
        log "🗄️ Upload archiviert: $(to_display_path "$archive_dir")"
      else
        local processed_dir
        processed_dir="${source_dir}.processed.$(date +%s)"
        if mv "$source_dir" "$processed_dir" 2>/dev/null; then
          log "🗄️ Upload markiert: $(to_display_path "$processed_dir")"
        else
          log "⚠️ Upload konnte nicht archiviert werden: $(to_display_path "$source_dir")"
        fi
      fi
    fi
  done < <(find "$UPLOAD_INBOX_DIR_ABS" -mindepth 1 -maxdepth 1 -type d | sort)
}

acquire_watch_lock() {
  local lock_pid
  if mkdir "$WATCH_LOCK_DIR" 2>/dev/null; then
    printf '%s\n' "$$" >"$WATCH_LOCK_DIR/pid"
    return 0
  fi

  lock_pid="$(cat "$WATCH_LOCK_DIR/pid" 2>/dev/null || true)"
  if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
    log "Watcher läuft bereits (PID $lock_pid) - beende diesen Start."
    exit 0
  fi

  safe_rm_dir "$WATCH_LOCK_DIR" 2>/dev/null || true
  if mkdir "$WATCH_LOCK_DIR" 2>/dev/null; then
    printf '%s\n' "$$" >"$WATCH_LOCK_DIR/pid"
    return 0
  fi

  log "FEHLER: Konnte keinen exklusiven Watcher-Lock setzen."
  exit 1
}

release_watch_lock() {
  local lock_pid
  rm -f "$PID_FILE" 2>/dev/null || true
  lock_pid="$(cat "$WATCH_LOCK_DIR/pid" 2>/dev/null || true)"
  if [[ -z "$lock_pid" || "$lock_pid" == "$$" ]]; then
    safe_rm_dir "$WATCH_LOCK_DIR" 2>/dev/null || true
  fi
}

mark_done() {
  local id="$1"
  local newest="$2"
  printf '%s\n' "$newest" >"$DONE_DIR/$id.done"
}

process_id_dir() {
  local dir="$1"
  local id
  id="$(basename "$dir")"
  if ! is_valid_vehicle_id "$id"; then
    if should_log_throttled "invalid_input_id_${id//[^A-Za-z0-9_]/_}" 120; then
      log "⚠️ Input-Ordner ignoriert (ungültige ID): $(to_display_path "$dir")"
    fi
    return 0
  fi

  local stats count newest now
  stats="$(dir_image_stats "$dir")"
  count="$(awk '{print $1}' <<<"$stats")"
  newest="$(awk '{print $2}' <<<"$stats")"

  if [[ -z "$count" || "$count" -eq 0 || -z "$newest" || "$newest" -eq 0 ]]; then
    if should_log_throttled "empty_${id}" 60; then
      log "ℹ️ keine Bilder (noch): $id"
    fi
    return 0
  fi

  local done_file="$DONE_DIR/$id.done"
  local done_mtime=0
  if [[ -f "$done_file" ]]; then
    done_mtime="$(cat "$done_file" 2>/dev/null || echo 0)"
  fi

  if (( newest <= done_mtime )); then
    return 0
  fi

  now="$(date +%s)"
  if (( now - newest < WATCH_STABLE_SEC )); then
    if should_log_throttled "unstable_${id}" 30; then
      log "⏳ warte auf stabile Dateien: $id (letzte Änderung vor $((now-newest))s)"
    fi
    return 0
  fi

  local fail_file="$FAIL_DIR/$id.fail"
  if [[ -f "$fail_file" ]]; then
    local last_fail=0
    last_fail="$(cat "$fail_file" 2>/dev/null || echo 0)"
    if (( now - last_fail < WATCH_FAIL_COOLDOWN_SEC )); then
      return 0
    fi
  fi

  local run_log="$RUN_LOG_DIR/$id.log"
  log "🚀 Pipeline trigger: $id ($count Bilder, log: $(to_display_path "$run_log"))"

  if [[ "$WATCH_DRY_RUN" == "1" ]]; then
    {
      echo "[$(date +"%Y-%m-%d %H:%M:%S")] DRY_RUN: ./run.sh $id"
    } >>"$run_log" 2>&1
    mark_done "$id" "$newest"
    log "✅ DRY_RUN fertig: $id"
    return 0
  fi

  if ! { echo "[$(date +"%Y-%m-%d %H:%M:%S")] ./run.sh $id"; "$ROOT/run.sh" "$id"; } >>"$run_log" 2>&1; then
    log "⚠️ Render fehlgeschlagen: $id (cooldown ${WATCH_FAIL_COOLDOWN_SEC}s)"
    printf '%s\n' "$now" >"$fail_file"
    return 0
  fi

  if [[ ! -s "$OUT_DIR_ABS/$id.mp4" ]]; then
    log "⚠️ Output fehlt trotz Run: $(to_display_path "$OUT_DIR_ABS/$id.mp4") (cooldown ${WATCH_FAIL_COOLDOWN_SEC}s)"
    printf '%s\n' "$now" >"$fail_file"
    return 0
  fi

  # Nach erfolgreichem Lauf neuesten Stand als erledigt markieren.
  stats="$(dir_image_stats "$dir")"
  newest="$(awk '{print $2}' <<<"$stats")"
  mark_done "$id" "$newest"
  rm -f "$fail_file"
  log "✅ Pipeline fertig: $id"
}

scan_once() {
  import_upload_inbox_once

  if [[ ! -d "$INPUT_DIR" ]]; then
    log "ℹ️ Input-Ordner fehlt: $(to_display_path "$INPUT_DIR")"
    return 0
  fi

  refresh_id_registry

  while IFS= read -r dir; do
    [[ -d "$dir" ]] || continue
    process_id_dir "$dir"
  done < <(find "$INPUT_DIR" -mindepth 1 -maxdepth 1 -type d | sort)
}

acquire_watch_lock
printf '%s\n' "$$" >"$PID_FILE"
trap 'release_watch_lock' EXIT

log "👀 Watcher gestartet (poll=${WATCH_POLL_SEC}s, stable=${WATCH_STABLE_SEC}s, dry_run=${WATCH_DRY_RUN})"
log "Input:  $(to_display_path "$INPUT_DIR")"
log "Output: $(to_display_path "$OUT_DIR_ABS")"
log "IDs:    $(to_display_path "$IDS_FILE_ABS")"
log "PID:    $(to_display_path "$PID_FILE")"
if [[ -n "$UPLOAD_INBOX_DIR_ABS" ]]; then
  log "Upload-Inbox: $(to_display_path "$UPLOAD_INBOX_DIR_ABS") (move_to_archive=${UPLOAD_MOVE_TO_ARCHIVE}, archive=$(to_display_path "$UPLOAD_ARCHIVE_DIR_ABS"))"
else
  log "Upload-Inbox: AUS"
fi

while true; do
  scan_once
  if [[ "$WATCH_ONESHOT" == "1" ]]; then
    break
  fi
  sleep "$WATCH_POLL_SEC"
done
