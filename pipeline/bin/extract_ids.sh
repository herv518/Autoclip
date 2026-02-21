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

INPUT_DIR_DEFAULT="${INPUT_FRAMES_DIR:-Input-Frames}"
OUT_FILE_DEFAULT="${IDS_FILE:-metadata/ids.txt}"

INPUT_DIR="$INPUT_DIR_DEFAULT"
OUT_FILE="$OUT_FILE_DEFAULT"
QUIET=0

usage() {
  cat <<'USAGE'
Usage: ./bin/extract_ids.sh [options]

Examples:
  ./bin/extract_ids.sh
  ./bin/extract_ids.sh --input-dir Input-Frames --out metadata/ids.txt

Options:
  --input-dir DIR   Scan source image folders from DIR
  --out FILE        Write unique IDs (one per line) to FILE
  --quiet, -q       Suppress status output
  --help, -h        Show this help
USAGE
}

to_abs_path() {
  local p="$1"
  if [[ "$p" == /* ]]; then
    echo "$p"
  else
    echo "$ROOT_DIR/$p"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input-dir)
      if [[ $# -lt 2 ]]; then
        echo "[!] Missing value for --input-dir" >&2
        exit 2
      fi
      INPUT_DIR="$2"
      shift 2
      ;;
    --out)
      if [[ $# -lt 2 ]]; then
        echo "[!] Missing value for --out" >&2
        exit 2
      fi
      OUT_FILE="$2"
      shift 2
      ;;
    --quiet|-q)
      QUIET=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "[!] Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if ! command -v python3 >/dev/null 2>&1; then
  echo "[!] python3 fehlt - ID-Extraktion nicht möglich." >&2
  exit 1
fi

INPUT_DIR_ABS="$(to_abs_path "$INPUT_DIR")"
OUT_FILE_ABS="$(to_abs_path "$OUT_FILE")"

mkdir -p "$(dirname "$OUT_FILE_ABS")"

TMP_IDS="$(mktemp "/tmp/carclip_ids.XXXXXX")"
cleanup() {
  rm -f "$TMP_IDS" 2>/dev/null || true
}
trap cleanup EXIT

python3 - "$INPUT_DIR_ABS" "$TMP_IDS" <<'PY'
import os
import re
import sys
from pathlib import Path

input_dir = Path(sys.argv[1])
out_file = Path(sys.argv[2])

ids = set()
image_exts = {".jpg", ".jpeg", ".png", ".webp", ".JPG", ".JPEG", ".PNG", ".WEBP"}

if input_dir.is_dir():
    for child in input_dir.iterdir():
        if child.is_dir():
            dir_id = None
            if re.fullmatch(r"\d{4,7}", child.name or ""):
                dir_id = child.name
            else:
                m = re.search(r"\d{4,7}", child.name or "")
                if m:
                    dir_id = m.group(0)

            if dir_id:
                ids.add(dir_id)
                continue

            # Fallback: derive ID from image prefix (<ID>_x_timestamp.jpg)
            for f in child.iterdir():
                if not f.is_file():
                    continue
                if f.suffix not in image_exts and f.suffix.lower() not in {".jpg", ".jpeg", ".png", ".webp"}:
                    continue
                stem = f.stem
                prefix = stem.split("_", 1)[0]
                if re.fullmatch(r"\d{4,7}", prefix or ""):
                    ids.add(prefix)

sorted_ids = sorted(ids, key=lambda x: (len(x), int(x)))
out_file.write_text("\n".join(sorted_ids) + ("\n" if sorted_ids else ""), encoding="utf-8")
PY

if [[ -f "$OUT_FILE_ABS" ]] && cmp -s "$TMP_IDS" "$OUT_FILE_ABS"; then
  chmod 0644 "$OUT_FILE_ABS" 2>/dev/null || true
  if [[ "$QUIET" != "1" ]]; then
    count="$(wc -l < "$OUT_FILE_ABS" | tr -d ' ')"
    echo "[=] IDs unverändert: $OUT_FILE_ABS ($count IDs)"
  fi
  exit 0
fi

mv "$TMP_IDS" "$OUT_FILE_ABS"
chmod 0644 "$OUT_FILE_ABS" 2>/dev/null || true
trap - EXIT

if [[ "$QUIET" != "1" ]]; then
  count="$(wc -l < "$OUT_FILE_ABS" | tr -d ' ')"
  echo "[+] IDs extrahiert: $OUT_FILE_ABS ($count IDs)"
fi
