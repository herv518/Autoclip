#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

ID="${1:-12345}"
EMAIL_TO="${2:-}"
SMTP_USER="${3:-$EMAIL_TO}"
SMTP_HOST="${SMTP_HOST:-smtp-mail.outlook.com}"
SMTP_PORT="${SMTP_PORT:-587}"
SMTP_TLS="${SMTP_TLS:-1}"
SMTP_USE_SSL="${SMTP_USE_SSL:-0}"
EMAIL_FROM="${EMAIL_FROM:-$SMTP_USER}"

if [[ -z "$EMAIL_TO" ]]; then
  echo "Usage: ./ops/setup/mail_test_qr.sh <ID> <EMAIL_TO> [SMTP_USER]"
  echo "Beispiel: ./ops/setup/mail_test_qr.sh 12345 test@example.com"
  exit 1
fi

echo "Mail-Test für ID: $ID"
echo "Empfänger: $EMAIL_TO"
echo "SMTP-User: $SMTP_USER"
echo "SMTP-Host: $SMTP_HOST:$SMTP_PORT (TLS=$SMTP_TLS SSL=$SMTP_USE_SSL)"
echo "Hinweis: App-Passwort kann per Copy/Paste eingegeben werden."
echo "Hinweis: Falls es in Gruppen angezeigt wird, ohne Leerzeichen eingeben."
echo

read -r -s -p "SMTP Passwort (oder App-Passwort): " SMTP_PASS
echo
if [[ "$SMTP_PASS" == *[[:space:]]* ]]; then
  SMTP_PASS="${SMTP_PASS//[[:space:]]/}"
  echo "[i] Leerzeichen aus Passwort entfernt."
fi
if [[ -z "${SMTP_PASS:-}" ]]; then
  echo "[!] Kein Passwort eingegeben. Abbruch."
  exit 1
fi

AUTO_EMAIL_QR=1 \
EMAIL_TO="$EMAIL_TO" \
EMAIL_FROM="$EMAIL_FROM" \
SMTP_HOST="$SMTP_HOST" \
SMTP_PORT="$SMTP_PORT" \
SMTP_TLS="$SMTP_TLS" \
SMTP_USE_SSL="$SMTP_USE_SSL" \
SMTP_USER="$SMTP_USER" \
SMTP_PASS="$SMTP_PASS" \
./run.sh "$ID"

unset SMTP_PASS
echo
echo "Fertig. Passwort wurde nicht gespeichert."
