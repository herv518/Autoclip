#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

fail_count=0
warn_count=0

ok() {
  echo "[OK]   $*"
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

check_script_syntax() {
  local rel="$1"
  local abs="$ROOT/$rel"

  if [[ ! -f "$abs" ]]; then
    fail "missing script: $rel"
    return
  fi

  if bash -n "$abs"; then
    ok "syntax: $rel"
  else
    fail "syntax error: $rel"
  fi
}

echo "== Commands =="
check_required_cmd bash
check_required_cmd tar
check_required_cmd ffmpeg
check_required_cmd ffprobe
check_required_cmd python3
check_optional_cmd qrencode
check_optional_cmd say

echo
echo "== Script Syntax =="
scripts=(
  "run.sh"
  "start"
  "bin/extract_ids.sh"
  "bin/fetch_equipment.sh"
  "bin/fetch_equipment_from_ids.sh"
  "bin/watch_input_frames.sh"
  "bin/stop_watch.sh"
  "ops/setup/setup_auto_email.sh"
  "ops/setup/setup_auto_fax.sh"
  "ops/setup/mail_test_qr.sh"
  "ops/start/watcher_start.sh"
  "ops/start/watcher_stop.sh"
  "ops/start/render_once.sh"
  "ops/start/watch_smoke.sh"
  "ops/maintenance/healthcheck.sh"
  "ops/maintenance/tidy.sh"
  "ops/deploy/preflight.sh"
  "ops/deploy/bundle.sh"
)

for rel in "${scripts[@]}"; do
  check_script_syntax "$rel"
done

echo
echo "== Ignore Rules =="
if [[ -f "$ROOT/.gitignore" ]]; then
  required_ignores=(".tmp/" "metadata/" ".mail.env" ".fax.env" ".watch.env" "*.log")
  for pattern in "${required_ignores[@]}"; do
    if grep -Fq "$pattern" "$ROOT/.gitignore"; then
      ok ".gitignore contains: $pattern"
    else
      warn ".gitignore missing pattern: $pattern"
    fi
  done
else
  fail "missing .gitignore"
fi

if (( fail_count > 0 )); then
  echo
  echo "Preflight failed: $fail_count critical issue(s), $warn_count warning(s)."
  exit 1
fi

echo
echo "Preflight passed: 0 critical issue(s), $warn_count warning(s)."
