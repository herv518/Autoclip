#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

HOST="${TIPS_HOST:-127.0.0.1}"
PORT="${TIPS_PORT:-8787}"
URL="http://${HOST}:${PORT}/auto-clip-tips.html"
LOG_DIR="$ROOT_DIR/.tmp"
LOG_FILE="$LOG_DIR/tips_server.log"

mkdir -p "$LOG_DIR"

if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "[i] Tips-Server laeuft bereits auf ${HOST}:${PORT}"
else
  echo "[+] Starte Tips-Server auf ${HOST}:${PORT} ..."
  nohup python3 "$ROOT_DIR/auto_clip_tips_server.py" > "$LOG_FILE" 2>&1 &
  sleep 1
  if ! lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "[!] Server konnte nicht gestartet werden. Log:"
    tail -n 60 "$LOG_FILE" || true
    exit 1
  fi
fi

echo "[+] Oeffne ${URL}"
open "$URL"
echo "[+] Fertig. Video-Button ist jetzt direkt nutzbar."
