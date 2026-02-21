#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ -f "$ROOT_DIR/config.sh" ]]; then
  # shellcheck source=/dev/null
  source "$ROOT_DIR/config.sh"
fi

for env_file in "${LOCAL_ENV_FILE:-}" ".mail.env" ".fax.env" ".watch.env"; do
  [[ -n "${env_file:-}" ]] || continue
  if [[ -f "$ROOT_DIR/$env_file" ]]; then
    # shellcheck source=/dev/null
    source "$ROOT_DIR/$env_file"
  fi
done

SOURCE_BASE="${1:-${SOURCE_URL:-}}"
IDS_FILE_PATH="${2:-${IDS_FILE:-metadata/ids.txt}}"

to_abs_path() {
  local p="$1"
  if [[ "$p" == /* ]]; then
    echo "$p"
  else
    echo "$ROOT_DIR/$p"
  fi
}

usage() {
  cat <<'USAGE'
Usage:
  ./bin/fetch_equipment_from_ids.sh <SOURCE_BASE_OR_TEMPLATE> [IDS_FILE]

Examples:
  ./bin/fetch_equipment_from_ids.sh "https://example.com/dealer" metadata/ids.txt
  ./bin/fetch_equipment_from_ids.sh "https://example.com/fahrzeug/{ID}" metadata/ids.txt
USAGE
}

if [[ -z "$SOURCE_BASE" ]]; then
  usage
  exit 2
fi
if [[ "$SOURCE_BASE" != *"{ID}"* ]] && [[ ! "$SOURCE_BASE" =~ ^https?:// ]]; then
  echo "[!] SOURCE_BASE muss mit http:// oder https:// beginnen (oder '{ID}' enthalten)." >&2
  exit 2
fi

IDS_FILE_ABS="$(to_abs_path "$IDS_FILE_PATH")"
if [[ ! -s "$IDS_FILE_ABS" ]]; then
  echo "[!] IDs-Datei fehlt oder leer: $IDS_FILE_ABS"
  exit 1
fi

if [[ ! -x "$ROOT_DIR/bin/fetch_equipment.sh" ]]; then
  echo "[!] Script fehlt oder nicht ausführbar: $ROOT_DIR/bin/fetch_equipment.sh"
  exit 1
fi

ok=0
fail=0

while IFS= read -r id; do
  [[ -n "$id" ]] || continue
  if [[ ! "$id" =~ ^[0-9]+$ ]]; then
    echo "[!] Ungültige ID übersprungen: $id"
    continue
  fi

  echo "[>] Fetch für ID: $id"
  if "$ROOT_DIR/bin/fetch_equipment.sh" "$id" "$SOURCE_BASE"; then
    ok=$((ok + 1))
  else
    fail=$((fail + 1))
  fi
done < "$IDS_FILE_ABS"

echo "[+] Fertig. Erfolgreich: $ok, Fehlgeschlagen: $fail"
if (( fail > 0 )); then
  exit 1
fi
