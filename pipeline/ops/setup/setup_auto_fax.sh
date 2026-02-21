#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

FAX_ENV_FILE="${1:-.fax.env}"
if [[ "$FAX_ENV_FILE" == /* || "$FAX_ENV_FILE" == *".."* ]]; then
  echo "[!] Unsicherer Zielpfad für FAX_ENV_FILE: $FAX_ENV_FILE"
  exit 2
fi
umask 077

echo "Dauerhaftes Fax-Setup (QR Versand)"
echo
echo "Modus:"
echo "  1) dry_run       (ohne Geraet, schreibt Testdatei)"
echo "  2) email_gateway (Fax via Provider-Mailadresse)"
read -r -p "Auswahl [1]: " mode_choice
mode_choice="${mode_choice:-1}"

FAX_MODE="dry_run"
MODE_PRESET_EMAIL=""
if [[ "$mode_choice" == *"@"* ]]; then
  FAX_MODE="email_gateway"
  MODE_PRESET_EMAIL="$mode_choice"
  echo "[i] E-Mailadresse erkannt -> Modus 'email_gateway'."
else
  case "$mode_choice" in
    1|dry|dry_run) FAX_MODE="dry_run" ;;
    2|email|email_gateway|gateway) FAX_MODE="email_gateway" ;;
    *)
      echo "[!] Ungueltige Auswahl. Bitte 1 oder 2 eingeben."
      exit 1
      ;;
  esac
fi

FAX_TO=""
FAX_EMAIL_TO="$MODE_PRESET_EMAIL"
FAX_GATEWAY_DOMAIN=""
FAX_DRY_RUN_FILE=".tmp/fax_{ID}.txt"

if [[ "$FAX_MODE" == "email_gateway" ]]; then
  read -r -p "Faxnummer (z. B. +49401234567): " FAX_TO
  if [[ -n "$FAX_EMAIL_TO" ]]; then
    echo "[i] Direkte Fax-Mailadresse: $FAX_EMAIL_TO"
  else
    read -r -p "Direkte Fax-Mailadresse (optional): " FAX_EMAIL_TO
  fi
  if [[ -z "$FAX_EMAIL_TO" ]]; then
    read -r -p "Fax-Gateway Domain (optional, z. B. fax.example.com): " FAX_GATEWAY_DOMAIN
  fi
  if [[ -z "$FAX_EMAIL_TO" && ( -z "$FAX_TO" || -z "$FAX_GATEWAY_DOMAIN" ) ]]; then
    echo "[!] Fuer email_gateway brauchst du FAX_EMAIL_TO ODER FAX_TO + FAX_GATEWAY_DOMAIN."
    exit 1
  fi
else
  read -r -p "Dry-Run Datei [.tmp/fax_{ID}.txt]: " input_dry_file
  if [[ -z "${input_dry_file:-}" ]]; then
    FAX_DRY_RUN_FILE=".tmp/fax_{ID}.txt"
  else
    FAX_DRY_RUN_FILE="$input_dry_file"
  fi
  if [[ "$FAX_DRY_RUN_FILE" == "./ops/setup/setup_auto_fax.sh" || "$FAX_DRY_RUN_FILE" == "./setup_auto_fax.sh" || "$FAX_DRY_RUN_FILE" == "setup_auto_fax.sh" ]]; then
    echo "[i] Skriptpfad als Dateiname erkannt, setze auf Standard: .tmp/fax_{ID}.txt"
    FAX_DRY_RUN_FILE=".tmp/fax_{ID}.txt"
  fi
fi

{
  echo "# Lokal erzeugt von setup_auto_fax.sh"
  echo "# Nicht committen."
  printf 'AUTO_FAX_QR=%q\n' "1"
  printf 'FAX_MODE=%q\n' "$FAX_MODE"
  printf 'FAX_TO=%q\n' "$FAX_TO"
  printf 'FAX_EMAIL_TO=%q\n' "$FAX_EMAIL_TO"
  printf 'FAX_GATEWAY_DOMAIN=%q\n' "$FAX_GATEWAY_DOMAIN"
  printf 'FAX_DRY_RUN_FILE=%q\n' "$FAX_DRY_RUN_FILE"
} > "$ROOT_DIR/$FAX_ENV_FILE"
chmod 600 "$ROOT_DIR/$FAX_ENV_FILE"

echo
echo "[+] Fax-Config gespeichert: $ROOT_DIR/$FAX_ENV_FILE"
if [[ "$FAX_MODE" == "dry_run" ]]; then
  echo "[+] Test ohne Geraet: ./run.sh 12345"
else
  echo "[+] Fax-Gateway aktiv: ./run.sh 12345"
fi
