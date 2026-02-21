#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

OUT_DIR_ARG="${1:-.tmp/dist}"
if [[ "$OUT_DIR_ARG" == /* ]]; then
  OUT_DIR="$OUT_DIR_ARG"
else
  OUT_DIR="$ROOT/$OUT_DIR_ARG"
fi

mkdir -p "$OUT_DIR"

timestamp="$(date +%Y%m%d_%H%M%S)"
bundle_name="carclip-demo-${timestamp}.tar.gz"
bundle_path="$OUT_DIR/$bundle_name"

tmp_bundle="$(mktemp "/tmp/${bundle_name}.XXXX")"

echo "[+] Running preflight..."
"$ROOT/ops/deploy/preflight.sh"

echo "[+] Building clean demo bundle..."
tar -czf "$tmp_bundle" \
  --exclude='./.git' \
  --exclude='./.tmp' \
  --exclude='./.cache' \
  --exclude='./Input-Frames' \
  --exclude='./Output' \
  --exclude='./Voice' \
  --exclude='./Vehicle-Equipment' \
  --exclude='./Vehicle-Text' \
  --exclude='./metadata' \
  --exclude='./*.log' \
  --exclude='./.mail.env' \
  --exclude='./.fax.env' \
  --exclude='./.watch.env' \
  --exclude='./.DS_Store' \
  --exclude='./*/.DS_Store' \
  -C "$ROOT" .

mv "$tmp_bundle" "$bundle_path"
echo "[+] Bundle created: $bundle_path"
du -h "$bundle_path" | awk '{print "[+] Size: "$1}'
