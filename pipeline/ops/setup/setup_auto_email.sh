#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

MAIL_ENV_FILE="${1:-.mail.env}"
if [[ "$MAIL_ENV_FILE" == /* || "$MAIL_ENV_FILE" == *".."* ]]; then
  echo "[!] Unsicherer Zielpfad für MAIL_ENV_FILE: $MAIL_ENV_FILE"
  exit 2
fi
umask 077

if ! command -v security >/dev/null 2>&1; then
  echo "[!] macOS 'security' fehlt. Dieses Setup ist für macOS-Keychain gedacht."
  exit 1
fi

echo "Dauerhaftes E-Mail-Setup (QR Versand)"
echo

read -r -p "Empfänger (EMAIL_TO): " EMAIL_TO
if [[ -z "${EMAIL_TO:-}" ]]; then
  echo "[!] EMAIL_TO darf nicht leer sein."
  exit 1
fi

read -r -p "SMTP User/Absender Login (z. B. dein@gmail.com): " SMTP_USER
if [[ -z "${SMTP_USER:-}" ]]; then
  echo "[!] SMTP_USER darf nicht leer sein."
  exit 1
fi

read -r -p "SMTP Host [smtp.gmail.com]: " SMTP_HOST
SMTP_HOST="${SMTP_HOST:-smtp.gmail.com}"

read -r -p "SMTP Port [587]: " SMTP_PORT
SMTP_PORT="${SMTP_PORT:-587}"

read -r -p "STARTTLS (1/0) [1]: " SMTP_TLS
SMTP_TLS="${SMTP_TLS:-1}"

read -r -p "SMTPS SSL (1/0) [0]: " SMTP_USE_SSL
SMTP_USE_SSL="${SMTP_USE_SSL:-0}"

read -r -p "Keychain Service Name [carclip-smtp]: " SMTP_KEYCHAIN_SERVICE
SMTP_KEYCHAIN_SERVICE="${SMTP_KEYCHAIN_SERVICE:-carclip-smtp}"

read -r -s -p "SMTP/App-Passwort: " SMTP_PASS
echo

if [[ -z "${SMTP_PASS:-}" ]]; then
  echo "[!] Kein Passwort eingegeben."
  exit 1
fi

if [[ "$SMTP_PASS" == *[[:space:]]* ]]; then
  SMTP_PASS="${SMTP_PASS//[[:space:]]/}"
  echo "[i] Leerzeichen aus Passwort entfernt."
fi

security add-generic-password \
  -U \
  -a "$SMTP_USER" \
  -s "$SMTP_KEYCHAIN_SERVICE" \
  -w "$SMTP_PASS" >/dev/null

{
  echo "# Lokal erzeugt von setup_auto_email.sh"
  echo "# Nicht committen."
  printf 'AUTO_EMAIL_QR=%q\n' "1"
  printf 'EMAIL_TO=%q\n' "$EMAIL_TO"
  printf 'EMAIL_FROM=%q\n' "$SMTP_USER"
  printf 'SMTP_HOST=%q\n' "$SMTP_HOST"
  printf 'SMTP_PORT=%q\n' "$SMTP_PORT"
  printf 'SMTP_USER=%q\n' "$SMTP_USER"
  printf 'SMTP_TLS=%q\n' "$SMTP_TLS"
  printf 'SMTP_USE_SSL=%q\n' "$SMTP_USE_SSL"
  printf 'USE_MACOS_KEYCHAIN=%q\n' "1"
  printf 'SMTP_KEYCHAIN_SERVICE=%q\n' "$SMTP_KEYCHAIN_SERVICE"
  printf 'SMTP_PASS_KEYCHAIN_ACCOUNT=%q\n' "$SMTP_USER"
} > "$ROOT_DIR/$MAIL_ENV_FILE"
chmod 600 "$ROOT_DIR/$MAIL_ENV_FILE"

unset SMTP_PASS

echo
echo "[+] Fertig eingerichtet."
echo "[+] Lokale Mail-Config: $ROOT_DIR/$MAIL_ENV_FILE"
echo "[+] Passwort liegt im macOS-Keychain (Service: $SMTP_KEYCHAIN_SERVICE, Account: $SMTP_USER)"
echo
echo "Ab jetzt reicht:"
echo "  ./run.sh 12345"
