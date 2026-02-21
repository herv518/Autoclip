#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

SCRIPT_NAME="$(basename "$0")"

log_info() {
  echo "[+] $*"
}

log_warn() {
  echo "[!] $*" >&2
}

die() {
  log_warn "$*"
  exit 1
}

on_error() {
  local code="$1"
  local line="$2"
  log_warn "$SCRIPT_NAME failed at line $line (exit code: $code)"
  exit "$code"
}
trap 'on_error $? $LINENO' ERR

mask_email() {
  local e="$1"
  local local_part domain masked_local
  if [[ "$e" != *"@"* ]]; then
    printf '%s\n' "$e"
    return 0
  fi
  local_part="${e%%@*}"
  domain="${e#*@}"
  if [[ ${#local_part} -le 2 ]]; then
    masked_local="***"
  else
    masked_local="${local_part:0:2}***"
  fi
  printf '%s@%s\n' "$masked_local" "$domain"
}

mask_email_list() {
  local list="$1"
  local first=1
  local item trimmed
  local output=""
  local -a emails=()
  IFS=',' read -r -a emails <<< "$list"
  for item in "${emails[@]}"; do
    trimmed="$(printf '%s' "$item" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [[ -n "$trimmed" ]] || continue
    if [[ "$first" -eq 1 ]]; then
      output="$(mask_email "$trimmed")"
      first=0
    else
      output="$output, $(mask_email "$trimmed")"
    fi
  done
  printf '%s\n' "$output"
}

require_cmd() {
  local cmd="$1"
  local brew_hint="${2:-}"
  if command -v "$cmd" >/dev/null 2>&1; then
    return 0
  fi
  if [[ -n "$brew_hint" ]] && command -v brew >/dev/null 2>&1; then
    die "'$cmd' fehlt. Installiere es mit: brew install $brew_hint"
  fi
  if [[ -n "$brew_hint" ]]; then
    die "'$cmd' fehlt. Installiere Homebrew oder installiere manuell (empfohlen: brew install $brew_hint)."
  fi
  die "'$cmd' fehlt."
}

require_python_min() {
  local min_major="$1"
  local min_minor="$2"
  python3 - "$min_major" "$min_minor" <<'PY'
import sys
major_req = int(sys.argv[1])
minor_req = int(sys.argv[2])
if sys.version_info < (major_req, minor_req):
    raise SystemExit(f"python3>={major_req}.{minor_req} required, found {sys.version_info.major}.{sys.version_info.minor}")
PY
}

validate_numeric_id() {
  local id="$1"
  [[ "$id" =~ ^[0-9]+$ ]]
}

validate_http_url() {
  local url="$1"
  [[ "$url" =~ ^https?:// ]]
}

TEMP_FILES=()
register_temp_file() {
  local f="$1"
  [[ -n "$f" ]] || return 0
  TEMP_FILES+=("$f")
}

cleanup_temp_files() {
  local f
  for f in "${TEMP_FILES[@]:-}"; do
    [[ -n "$f" ]] || continue
    rm -f "$f" 2>/dev/null || true
  done
}
trap cleanup_temp_files EXIT

create_secret_tempfile() {
  local secret_value="$1"
  local secret_file
  secret_file="$(mktemp "$TMP_DIR/secret.XXXXXX")"
  chmod 600 "$secret_file"
  printf '%s' "$secret_value" > "$secret_file"
  register_temp_file "$secret_file"
  printf '%s\n' "$secret_file"
}

if [[ -f "$ROOT_DIR/config.sh" ]]; then
  # shellcheck source=/dev/null
  source "$ROOT_DIR/config.sh"
fi

# Optionale lokale Overrides (nicht für Git): z. B. .mail.env / .fax.env
LOCAL_ENV_FILES=()
if [[ -n "${LOCAL_ENV_FILE:-}" ]]; then
  LOCAL_ENV_FILES+=("$LOCAL_ENV_FILE")
fi
for _f in ".mail.env" ".fax.env"; do
  _seen=0
  for _existing in "${LOCAL_ENV_FILES[@]:-}"; do
    if [[ "$_existing" == "$_f" ]]; then
      _seen=1
      break
    fi
  done
  if [[ "$_seen" -eq 0 ]]; then
    LOCAL_ENV_FILES+=("$_f")
  fi
done
for _env in "${LOCAL_ENV_FILES[@]}"; do
  if [[ -f "$ROOT_DIR/$_env" ]]; then
    # shellcheck source=/dev/null
    source "$ROOT_DIR/$_env"
  fi
done

# Carclip - echt & einfach: Fotos + Text -> MP4 mit Voiceover
# Requirements: FFmpeg, qrencode (brew install ffmpeg qrencode)

# Konfig (mit Fallbacks; kann in config.sh überschrieben werden)
FONT="${FONT:-Arial}"
TTS_VOICE="${TTS_VOICE:-Anna}"          # macOS Stimme (deutsch)
FPS="${FPS:-30}"
WIDTH="${W:-1080}"
HEIGHT="${H:-810}"
BAR_H="${BAR_H:-106}"
TEXT_Y="${TEXT_Y:-31}"
TEXT_SIZE="${TEXT_SIZE:-44}"
TEXT_COLOR="${TEXT_COLOR:-white}"
TEXT_BG="${TEXT_BG:-black@0.6}"
MARQUEE_SPEED="${MARQUEE_SPEED:-220}"   # Pixel pro Sekunde
DUR_PER_IMG="${DUR_PER_IMG:-5}"
VIDEO_PAD="${VIDEO_PAD:-0.5}"
BRAND_NAME="${BRAND_NAME:-Carclip}"
OVERLAY_MAX_LEN="${OVERLAY_MAX_LEN:-320}"
SHOW_ID_IN_OVERLAY="${SHOW_ID_IN_OVERLAY:-0}"
OVERLAY_USE_CTA="${OVERLAY_USE_CTA:-1}"
OVERLAY_EQUIP_COUNT="${OVERLAY_EQUIP_COUNT:-2}"
INPUT_FRAMES_DIR="${INPUT_FRAMES_DIR:-Input-Frames}"
EQUIP_DIR="${EQUIP_DIR:-Vehicle-Equipment}"
TEXT_DIR="${TEXT_DIR:-Vehicle-Text}"
VOICE_DIR="${VOICE_DIR:-Voice}"
OUT_DIR="${OUT_DIR:-Output}"
TMP_DIR="${TMP_DIR:-.tmp}"
IDS_FILE="${IDS_FILE:-metadata/ids.txt}"
LOCAL_ENV_FILE="${LOCAL_ENV_FILE:-.mail.env}"
USE_MACOS_KEYCHAIN="${USE_MACOS_KEYCHAIN:-1}"
SMTP_KEYCHAIN_SERVICE="${SMTP_KEYCHAIN_SERVICE:-carclip-smtp}"
SMTP_PASS_KEYCHAIN_ACCOUNT="${SMTP_PASS_KEYCHAIN_ACCOUNT:-}"
PREFER_FETCH_TEXT="${PREFER_FETCH_TEXT:-0}"
SHOW_OVERLAY="${SHOW_OVERLAY:-1}"
SHOW_TOP_BAR="${SHOW_TOP_BAR:-1}"
SHOW_BOTTOM_LOGOS="${SHOW_BOTTOM_LOGOS:-1}"
SHOW_BOTTOM_BAR="${SHOW_BOTTOM_BAR:-0}"
GENERATE_WEBM="${GENERATE_WEBM:-1}"
ASSETS_DIR="${ASSETS_DIR:-assets}"
LOGO_LEFT_FILE="${LOGO_LEFT_FILE:-}"
LOGO_CENTER_FILE="${LOGO_CENTER_FILE:-}"
LOGO_RIGHT_FILE="${LOGO_RIGHT_FILE:-}"
BOTTOM_BAR_H="${BOTTOM_BAR_H:-106}"
BOTTOM_BAR_COLOR="${BOTTOM_BAR_COLOR:-black@0.45}"
BOTTOM_MARGIN="${BOTTOM_MARGIN:-24}"
BOTTOM_LEFT_MARGIN="${BOTTOM_LEFT_MARGIN:-36}"
BOTTOM_RIGHT_MARGIN="${BOTTOM_RIGHT_MARGIN:-24}"
BOTTOM_LEFT_W="${BOTTOM_LEFT_W:-220}"
BOTTOM_LEFT_H="${BOTTOM_LEFT_H:-90}"
BOTTOM_CENTER_W="${BOTTOM_CENTER_W:-520}"
BOTTOM_CENTER_H="${BOTTOM_CENTER_H:-92}"
BOTTOM_RIGHT_W="${BOTTOM_RIGHT_W:-110}"
BOTTOM_RIGHT_H="${BOTTOM_RIGHT_H:-110}"
BOTTOM_GENERIC_W="${BOTTOM_GENERIC_W:-280}"
BOTTOM_GENERIC_H="${BOTTOM_GENERIC_H:-82}"
BOTTOM_GENERIC_GAP="${BOTTOM_GENERIC_GAP:-32}"
SCALE_FLAGS="${SCALE_FLAGS:-lanczos}"
X264_CRF="${X264_CRF:-20}"
X264_PRESET="${X264_PRESET:-slow}"
X264_TUNE="${X264_TUNE:-stillimage}"
AAC_BR="${AAC_BR:-160k}"
USE_TPAD="${USE_TPAD:-0}"
VIDEO_TPAD="${VIDEO_TPAD:-2.0}"
FADE_IN_DUR="${FADE_IN_DUR:-0.7}"
FADE_OUT_DUR="${FADE_OUT_DUR:-0.0}"
AUTO_PRINT_QR="${AUTO_PRINT_QR:-0}"
PRINTER_NAME="${PRINTER_NAME:-}"
QR_URL="${QR_URL:-https://example.com}"
AUTO_EMAIL_QR="${AUTO_EMAIL_QR:-0}"
EMAIL_TO="${EMAIL_TO:-}"
SMTP_HOST="${SMTP_HOST:-}"
SMTP_PORT="${SMTP_PORT:-587}"
SMTP_USER="${SMTP_USER:-}"
SMTP_PASS="${SMTP_PASS:-}"
SMTP_TLS="${SMTP_TLS:-1}"
SMTP_USE_SSL="${SMTP_USE_SSL:-0}"
EMAIL_FROM="${EMAIL_FROM:-$SMTP_USER}"
EMAIL_SUBJECT_TEMPLATE="${EMAIL_SUBJECT_TEMPLATE:-Carclip QR-Code {ID}}"
EMAIL_BODY_TEMPLATE="${EMAIL_BODY_TEMPLATE:-}"
if [[ -z "$EMAIL_BODY_TEMPLATE" ]]; then
  EMAIL_BODY_TEMPLATE="Anbei der QR-Code für Fahrzeug {ID}."
fi
AUTO_FAX_QR="${AUTO_FAX_QR:-0}"
FAX_MODE="${FAX_MODE:-dry_run}" # dry_run | email_gateway
FAX_TO="${FAX_TO:-}"
FAX_EMAIL_TO="${FAX_EMAIL_TO:-}" # wenn gesetzt, wird direkt benutzt (z. B. 491234567@fax-gateway.tld)
FAX_GATEWAY_DOMAIN="${FAX_GATEWAY_DOMAIN:-}" # optional: aus FAX_TO + Domain wird Mailadresse gebaut
FAX_FROM="${FAX_FROM:-$EMAIL_FROM}"
FAX_SUBJECT_TEMPLATE="${FAX_SUBJECT_TEMPLATE:-Carclip QR Fax {ID}}"
FAX_BODY_TEMPLATE="${FAX_BODY_TEMPLATE:-}"
if [[ -z "$FAX_BODY_TEMPLATE" ]]; then
  FAX_BODY_TEMPLATE="QR-Code für Fahrzeug {ID}. Empfänger Fax: {FAX_TO}"
fi
FAX_DRY_RUN_FILE="${FAX_DRY_RUN_FILE:-}"
if [[ -z "$FAX_DRY_RUN_FILE" ]]; then
  FAX_DRY_RUN_FILE="$TMP_DIR/fax_{ID}.txt"
fi

if [[ -z "$SMTP_PASS_KEYCHAIN_ACCOUNT" ]]; then
  SMTP_PASS_KEYCHAIN_ACCOUNT="$SMTP_USER"
fi

# Beispiel-ID (oder als Argument: ./run.sh 12345 [URL])
ID="${1:-}"
if [[ -z "$ID" ]]; then
  die "Fehlende Fahrzeug-ID. Nutzung: ./run.sh <NUMERISCHE_ID> [SOURCE_URL]"
fi
if ! validate_numeric_id "$ID"; then
  die "Ungültige Fahrzeug-ID '$ID'. Erlaubt sind nur Ziffern."
fi

SOURCE_URL_RAW="${2:-${SOURCE_URL:-}}"
SOURCE_URL="${SOURCE_URL_RAW//\{ID\}/$ID}"
if [[ -n "$SOURCE_URL" ]] && ! validate_http_url "$SOURCE_URL"; then
  die "SOURCE_URL muss mit http:// oder https:// beginnen: $SOURCE_URL"
fi
if ! validate_http_url "$QR_URL"; then
  die "QR_URL muss mit http:// oder https:// beginnen: $QR_URL"
fi

INPUT_DIR="$INPUT_FRAMES_DIR/$ID"
TEXT_FILE="beschreibung.txt"
VEHICLE_TEXT_FILE="$TEXT_DIR/$ID.txt"
EQUIP_FILE="$EQUIP_DIR/$ID.txt"
TEXT_INPUT_FILE="$TEXT_FILE"
VOICE_FILE="$VOICE_DIR/${ID}.wav"
OUTPUT="$OUT_DIR/${ID}.mp4"
OUTPUT_WEBM="$OUT_DIR/${ID}.webm"
QR_FILE="$OUT_DIR/${ID}_qr.png"
FETCH_SCRIPT="$ROOT_DIR/bin/fetch_equipment.sh"
FAX_DRY_RUN_FILE="${FAX_DRY_RUN_FILE//\{ID\}/$ID}"

# Prüfe, ob Ordner da sind
mkdir -p "$INPUT_FRAMES_DIR" "$OUT_DIR" "$TMP_DIR" "$EQUIP_DIR" "$VOICE_DIR"

require_cmd ffmpeg ffmpeg
require_cmd ffprobe ffmpeg
require_cmd python3 python
if command -v python3 >/dev/null 2>&1; then
  require_python_min 3 8
fi
if ! command -v brew >/dev/null 2>&1; then
  log_warn "Homebrew nicht gefunden. Installationsempfehlungen in Fehlermeldungen nutzen."
fi
if ! command -v qrencode >/dev/null 2>&1; then
  log_warn "qrencode fehlt. QR-Generierung wird übersprungen (installierbar mit: brew install qrencode)."
fi

TMP_TEXT_FILE="$(mktemp "$TMP_DIR/tts_${ID}.XXXXXX.txt")"
OVERLAY_FILE="$(mktemp "$TMP_DIR/overlay_${ID}.XXXXXX.txt")"
TMP_VOICE_AIFF="$(mktemp "$TMP_DIR/voice_${ID}.XXXXXX.aiff")"
SLIDESHOW_LIST="$(mktemp "$TMP_DIR/slideshow_${ID}.XXXXXX.txt")"
register_temp_file "$TMP_TEXT_FILE"
register_temp_file "$OVERLAY_FILE"
register_temp_file "$TMP_VOICE_AIFF"
register_temp_file "$SLIDESHOW_LIST"

# drawtext: stabiles Font-Fallback für macOS
if [[ -n "${FONT:-}" && -f "$FONT" ]]; then
  DRAW_FONT_OPT="fontfile='$FONT'"
elif [[ -f "/System/Library/Fonts/HelveticaNeue.ttc" ]]; then
  DRAW_FONT_OPT="fontfile='/System/Library/Fonts/HelveticaNeue.ttc'"
else
  DRAW_FONT_OPT="font='Helvetica Neue'"
fi

escape_ffconcat_path() {
  local path="$1"
  printf '%s' "${path//\'/\'\\\'\'}"
}

abs_path() {
  local rel="$1"
  local dir
  dir="$(cd "$(dirname "$rel")" && pwd)"
  printf '%s/%s' "$dir" "$(basename "$rel")"
}

probe_duration() {
  local f="$1"
  if [[ ! -f "$f" ]]; then
    echo ""
    return 0
  fi
  ffprobe -v error -show_entries format=duration -of default=nk=1:nw=1 "$f" 2>/dev/null | head -n 1
}

build_text_from_equipment() {
  local src="$1"
  local dst="$2"
  awk '
    BEGIN { c=0 }
    /^ID:/ { next }
    /^URL:/ { next }
    /^Zeitpunkt:/ { next }
    /^---$/ { next }
    /^[[:space:]]*[-•*][[:space:]]*/ {
      s=$0
      sub(/^[[:space:]]*[-•*][[:space:]]*/, "", s)
      gsub(/[[:space:]]+/, " ", s)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
      if (length(s) >= 3) {
        if (s !~ /[.!?]$/) s = s "."
        print s
        c++
        if (c >= 4) exit
      }
    }
  ' "$src" > "$dst"
}

pick_random_cta() {
  if declare -p CTA_LINES >/dev/null 2>&1; then
    local count
    count="${#CTA_LINES[@]}"
    if [[ "$count" -gt 0 ]]; then
      local idx=$((RANDOM % count))
      printf '%s\n' "${CTA_LINES[$idx]}"
      return 0
    fi
  fi
  printf '%s\n' ""
}

pick_equipment_bits() {
  local equip_file="$1"
  local max_items="${2:-2}"
  if [[ ! -s "$equip_file" ]]; then
    printf '%s\n' ""
    return 0
  fi

  python3 - "$equip_file" "$max_items" <<'PY'
import os
import random
import re
import sys

path = sys.argv[1]
max_items = max(1, int(sys.argv[2]))
items = []
if os.path.exists(path):
    with open(path, "r", encoding="utf-8", errors="ignore") as fh:
        for raw in fh:
            line = raw.strip()
            if not line:
                continue
            if not re.match(r"^[\s\-•*·\u2022]+", line):
                continue
            s = re.sub(r"^[\s\-•*·\u2022]+", "", line).strip()
            if not s:
                continue
            if len(s) < 3 or len(s) > 70:
                continue
            low = s.lower()
            if low.startswith(("sonderausstattung", "serienausstattung", "interieur", "exterieur", "hinweis")):
                continue
            items.append(s)

seen = set()
uniq = []
for s in items:
    key = s.lower()
    if key in seen:
        continue
    seen.add(key)
    uniq.append(s)

random.shuffle(uniq)
print(" | ".join(uniq[:max_items]))
PY
}

pick_unique_asset() {
  local picked=""
  local candidate=""
  for candidate in "$@"; do
    [[ -n "$candidate" ]] || continue
    [[ -f "$candidate" ]] || continue

    local already=0
    local used=""
    for used in "${picked_assets[@]:-}"; do
      if [[ "$used" == "$candidate" ]]; then
        already=1
        break
      fi
    done
    if [[ "$already" -eq 0 ]]; then
      picked="$candidate"
      break
    fi
  done
  printf '%s\n' "$picked"
}

file_hash() {
  local file="$1"
  if command -v md5 >/dev/null 2>&1; then
    md5 -q "$file" 2>/dev/null || true
  elif command -v md5sum >/dev/null 2>&1; then
    md5sum "$file" 2>/dev/null | awk '{print $1}'
  else
    printf '%s\n' ""
  fi
}

load_smtp_password_from_keychain() {
  if [[ -z "${SMTP_PASS:-}" && -n "${SMTP_PASS_FILE:-}" && -f "${SMTP_PASS_FILE:-}" ]]; then
    SMTP_PASS="$(cat "$SMTP_PASS_FILE" 2>/dev/null || true)"
  fi
  if [[ -n "${SMTP_PASS:-}" ]]; then
    return 0
  fi
  if [[ "${USE_MACOS_KEYCHAIN:-1}" != "1" ]]; then
    return 0
  fi
  if ! command -v security >/dev/null 2>&1; then
    return 0
  fi

  local account="${SMTP_PASS_KEYCHAIN_ACCOUNT:-$SMTP_USER}"
  if [[ -z "$account" ]]; then
    return 0
  fi

  local pw
  if pw="$(security find-generic-password -a "$account" -s "$SMTP_KEYCHAIN_SERVICE" -w 2>/dev/null)"; then
    SMTP_PASS="$pw"
  fi
}

build_overlay_text() {
  local id="$1"
  local vehicle_text_file="$2"
  local fallback_text_file="$3"
  local equip_file="$4"
  local summary_text=""
  local equip_bits=""
  local cta=""
  local overlay=""
  local parts=()

  if [[ -s "$vehicle_text_file" ]]; then
    summary_text="$(tr '\n' ' ' < "$vehicle_text_file" | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')"
  elif [[ -s "$fallback_text_file" ]]; then
    summary_text="$(tr '\n' ' ' < "$fallback_text_file" | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')"
  fi

  if [[ -n "$summary_text" ]]; then
    summary_text="$(python3 - "$summary_text" <<'PY'
import re
import sys
s = sys.argv[1].strip()
s = re.sub(r"\s+", " ", s)
if not s:
    print("")
    raise SystemExit
parts = re.split(r"(?<=[.!?])\s+", s, maxsplit=1)
first = parts[0].strip()
print(first)
PY
)"
  fi

  equip_bits="$(pick_equipment_bits "$equip_file" "$OVERLAY_EQUIP_COUNT")"

  if [[ "${OVERLAY_USE_CTA:-1}" = "1" ]]; then
    cta="$(pick_random_cta)"
  fi

  if [[ -n "${BRAND_NAME:-}" ]]; then
    parts+=("$BRAND_NAME")
  fi
  if [[ -n "$equip_bits" ]]; then
    parts+=("$equip_bits")
  elif [[ -n "$summary_text" ]]; then
    parts+=("$summary_text")
  fi
  if [[ -n "$cta" ]]; then
    parts+=("$cta")
  fi

  if (( ${#parts[@]} == 0 )); then
    overlay="Fahrzeug $id"
  else
    overlay=""
    for part in "${parts[@]}"; do
      if [[ -z "$overlay" ]]; then
        overlay="$part"
      else
        overlay="$overlay | $part"
      fi
    done
  fi

  if [[ "${SHOW_ID_IN_OVERLAY:-0}" = "1" ]]; then
    overlay="ID $id | $overlay"
  fi

overlay="$(python3 - "$overlay" "$OVERLAY_MAX_LEN" <<'PY'
import sys
s = sys.argv[1].strip()
max_len = int(sys.argv[2])
if len(s) > max_len:
    s = s[: max_len - 1].rstrip() + "…"
print(s)
PY
)"

  printf '%s\n' "$overlay"
}

maybe_fetch_equipment() {
  # 3.5 Fetch Ausstattung (optional)
  if [[ -n "${SOURCE_URL:-}" ]]; then
    if [[ "$SOURCE_URL" == *"example.com/"* ]]; then
      echo "[i] SOURCE_URL ist Platzhalter - Fetch übersprungen"
      return 0
    fi
    echo "[+] Hole Ausstattung..."
    if [[ -x "$FETCH_SCRIPT" ]]; then
      if "$FETCH_SCRIPT" "$ID" "$SOURCE_URL"; then
        echo "[+] Ausstattung gespeichert: $EQUIP_FILE"
      else
        echo "[!] Fetch fehlgeschlagen - weiter ohne Webdaten"
      fi
    else
      echo "[!] bin/fetch_equipment.sh nicht gefunden oder nicht ausführbar"
    fi
  else
    return 0
  fi
}

refresh_id_registry() {
  local ids_script="$ROOT_DIR/bin/extract_ids.sh"
  if [[ ! -x "$ids_script" ]]; then
    echo "[i] ID-Registry-Script fehlt: $ids_script"
    return 0
  fi
  if ! "$ids_script" --input-dir "$INPUT_FRAMES_DIR" --out "$IDS_FILE" --quiet; then
    echo "[!] ID-Registry konnte nicht aktualisiert werden: $IDS_FILE"
    return 0
  fi
}

maybe_print_qr() {
  if [[ "${AUTO_PRINT_QR:-0}" != "1" ]]; then
    return 0
  fi
  if [[ ! -f "$QR_FILE" ]]; then
    echo "[!] QR-Datei fehlt - Druck übersprungen"
    return 0
  fi
  if ! command -v lp >/dev/null 2>&1; then
    echo "[!] 'lp' nicht verfügbar - Druck übersprungen"
    return 0
  fi

  echo "[+] Drucke QR-Code..."
  if [[ -n "${PRINTER_NAME:-}" ]]; then
    if lp -d "$PRINTER_NAME" "$QR_FILE" >/dev/null 2>&1; then
      echo "[+] QR an Drucker '$PRINTER_NAME' gesendet"
    else
      echo "[!] QR-Druck fehlgeschlagen (Printer: $PRINTER_NAME)"
    fi
  else
    if lp "$QR_FILE" >/dev/null 2>&1; then
      echo "[+] QR an Standarddrucker gesendet"
    else
      echo "[!] QR-Druck fehlgeschlagen (Standarddrucker)"
    fi
  fi
}

maybe_email_qr() {
  if [[ "${AUTO_EMAIL_QR:-0}" != "1" ]]; then
    return 0
  fi
  if [[ ! -f "$QR_FILE" ]]; then
    echo "[!] QR-Datei fehlt - E-Mail übersprungen"
    return 0
  fi
  if [[ -z "${EMAIL_TO:-}" ]]; then
    echo "[!] EMAIL_TO ist leer - E-Mail übersprungen"
    return 0
  fi
  load_smtp_password_from_keychain
  if [[ -z "${SMTP_HOST:-}" || -z "${SMTP_USER:-}" || -z "${SMTP_PASS:-}" ]]; then
    echo "[!] SMTP-Konfig unvollständig - E-Mail übersprungen"
    return 0
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    echo "[!] python3 fehlt - E-Mail übersprungen"
    return 0
  fi

  local subject body masked_recipients smtp_pass_file
  subject="${EMAIL_SUBJECT_TEMPLATE//\{ID\}/$ID}"
  body="${EMAIL_BODY_TEMPLATE//\{ID\}/$ID}"
  masked_recipients="$(mask_email_list "$EMAIL_TO")"
  log_info "Sende QR per E-Mail an: ${masked_recipients:-[keine gültigen Empfänger]}"
  smtp_pass_file="$(create_secret_tempfile "$SMTP_PASS")"

  if EMAIL_TO="$EMAIL_TO" \
    EMAIL_FROM="$EMAIL_FROM" \
    EMAIL_SUBJECT="$subject" \
    EMAIL_BODY="$body" \
    SMTP_HOST="$SMTP_HOST" \
    SMTP_PORT="$SMTP_PORT" \
    SMTP_USER="$SMTP_USER" \
    SMTP_PASS_FILE="$smtp_pass_file" \
    SMTP_TLS="$SMTP_TLS" \
    SMTP_USE_SSL="$SMTP_USE_SSL" \
    python3 - "$QR_FILE" <<'PY'
import os
import smtplib
import ssl
import sys
from email.message import EmailMessage
from pathlib import Path

qr_file = Path(sys.argv[1])
to_list = [x.strip() for x in os.environ.get("EMAIL_TO", "").split(",") if x.strip()]
from_addr = os.environ.get("EMAIL_FROM", "").strip() or os.environ.get("SMTP_USER", "").strip()
subject = os.environ.get("EMAIL_SUBJECT", "Carclip QR-Code")
body = os.environ.get("EMAIL_BODY", "")
host = os.environ["SMTP_HOST"]
port = int(os.environ.get("SMTP_PORT", "587"))
user = os.environ.get("SMTP_USER", "")
pass_file = os.environ.get("SMTP_PASS_FILE", "")
use_tls = os.environ.get("SMTP_TLS", "1") == "1"
use_ssl = os.environ.get("SMTP_USE_SSL", "0") == "1"

if not to_list:
    raise SystemExit("EMAIL_TO fehlt")
if not from_addr:
    raise SystemExit("EMAIL_FROM/SMTP_USER fehlt")
if not pass_file:
    raise SystemExit("SMTP_PASS_FILE fehlt")
with open(pass_file, "r", encoding="utf-8") as fh:
    password = fh.read()

msg = EmailMessage()
msg["Subject"] = subject
msg["From"] = from_addr
msg["To"] = ", ".join(to_list)
msg.set_content(body or "Anbei der QR-Code.")

with qr_file.open("rb") as fh:
    data = fh.read()
msg.add_attachment(data, maintype="image", subtype="png", filename=qr_file.name)

context = ssl.create_default_context()
if use_ssl:
    server = smtplib.SMTP_SSL(host, port, timeout=30, context=context)
else:
    server = smtplib.SMTP(host, port, timeout=30)
    server.ehlo()
    if use_tls:
        server.starttls(context=context)
        server.ehlo()

if user:
    server.login(user, password)
server.send_message(msg)
server.quit()
PY
  then
    echo "[+] E-Mail erfolgreich versendet"
  else
    echo "[!] E-Mail-Versand fehlgeschlagen"
  fi

  rm -f "$smtp_pass_file" 2>/dev/null || true
}

maybe_fax_qr() {
  if [[ "${AUTO_FAX_QR:-0}" != "1" ]]; then
    return 0
  fi
  if [[ ! -f "$QR_FILE" ]]; then
    echo "[!] QR-Datei fehlt - Fax übersprungen"
    return 0
  fi

  local mode="${FAX_MODE:-dry_run}"
  case "$mode" in
    dry_run)
      mkdir -p "$(dirname "$FAX_DRY_RUN_FILE")"
      {
        echo "FAX DRY RUN"
        echo "Zeitpunkt: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "ID: $ID"
        echo "FAX_TO: ${FAX_TO:-}"
        echo "FAX_EMAIL_TO: ${FAX_EMAIL_TO:-}"
        echo "FAX_GATEWAY_DOMAIN: ${FAX_GATEWAY_DOMAIN:-}"
        echo "QR_FILE: $QR_FILE"
      } > "$FAX_DRY_RUN_FILE"
      echo "[+] Fax Dry-Run geschrieben: $FAX_DRY_RUN_FILE"
      return 0
      ;;
    email_gateway)
      local fax_recipient="${FAX_EMAIL_TO:-}"
      local fax_to_compact="${FAX_TO//[[:space:]]/}"
      local fax_num=""

      if [[ -z "$fax_recipient" && -n "${FAX_GATEWAY_DOMAIN:-}" ]]; then
        fax_num="$(printf '%s' "$fax_to_compact" | tr -cd '0-9+')"
        if [[ -n "$fax_num" ]]; then
          fax_recipient="${fax_num}@${FAX_GATEWAY_DOMAIN}"
        fi
      fi

      if [[ -z "$fax_recipient" ]]; then
        echo "[!] FAX_EMAIL_TO oder (FAX_TO + FAX_GATEWAY_DOMAIN) fehlt - Fax übersprungen"
        return 0
      fi

      load_smtp_password_from_keychain
      if [[ -z "${SMTP_HOST:-}" || -z "${SMTP_USER:-}" || -z "${SMTP_PASS:-}" ]]; then
        echo "[!] SMTP-Konfig unvollständig - Fax übersprungen"
        return 0
      fi
      if ! command -v python3 >/dev/null 2>&1; then
        echo "[!] python3 fehlt - Fax übersprungen"
        return 0
      fi

      local fax_subject fax_body masked_fax_recipient smtp_pass_file
      fax_subject="${FAX_SUBJECT_TEMPLATE//\{ID\}/$ID}"
      fax_subject="${fax_subject//\{FAX_TO\}/$fax_to_compact}"
      fax_body="${FAX_BODY_TEMPLATE//\{ID\}/$ID}"
      fax_body="${fax_body//\{FAX_TO\}/$fax_to_compact}"
      masked_fax_recipient="$(mask_email "$fax_recipient")"
      smtp_pass_file="$(create_secret_tempfile "$SMTP_PASS")"

      log_info "Sende QR per Fax-Gateway an: $masked_fax_recipient"
      if EMAIL_TO="$fax_recipient" \
        EMAIL_FROM="$FAX_FROM" \
        EMAIL_SUBJECT="$fax_subject" \
        EMAIL_BODY="$fax_body" \
        SMTP_HOST="$SMTP_HOST" \
        SMTP_PORT="$SMTP_PORT" \
        SMTP_USER="$SMTP_USER" \
        SMTP_PASS_FILE="$smtp_pass_file" \
        SMTP_TLS="$SMTP_TLS" \
        SMTP_USE_SSL="$SMTP_USE_SSL" \
        python3 - "$QR_FILE" <<'PY'
import os
import smtplib
import ssl
import sys
from email.message import EmailMessage
from pathlib import Path

qr_file = Path(sys.argv[1])
to_list = [x.strip() for x in os.environ.get("EMAIL_TO", "").split(",") if x.strip()]
from_addr = os.environ.get("EMAIL_FROM", "").strip() or os.environ.get("SMTP_USER", "").strip()
subject = os.environ.get("EMAIL_SUBJECT", "Carclip QR Fax")
body = os.environ.get("EMAIL_BODY", "")
host = os.environ["SMTP_HOST"]
port = int(os.environ.get("SMTP_PORT", "587"))
user = os.environ.get("SMTP_USER", "")
pass_file = os.environ.get("SMTP_PASS_FILE", "")
use_tls = os.environ.get("SMTP_TLS", "1") == "1"
use_ssl = os.environ.get("SMTP_USE_SSL", "0") == "1"

if not to_list:
    raise SystemExit("EMAIL_TO fehlt")
if not from_addr:
    raise SystemExit("EMAIL_FROM/SMTP_USER fehlt")
if not pass_file:
    raise SystemExit("SMTP_PASS_FILE fehlt")
with open(pass_file, "r", encoding="utf-8") as fh:
    password = fh.read()

msg = EmailMessage()
msg["Subject"] = subject
msg["From"] = from_addr
msg["To"] = ", ".join(to_list)
msg.set_content(body or "QR Fax")

with qr_file.open("rb") as fh:
    data = fh.read()
msg.add_attachment(data, maintype="image", subtype="png", filename=qr_file.name)

context = ssl.create_default_context()
if use_ssl:
    server = smtplib.SMTP_SSL(host, port, timeout=30, context=context)
else:
    server = smtplib.SMTP(host, port, timeout=30)
    server.ehlo()
    if use_tls:
        server.starttls(context=context)
        server.ehlo()

if user:
    server.login(user, password)
server.send_message(msg)
server.quit()
PY
      then
        echo "[+] Fax-Gateway Versand erfolgreich"
      else
        echo "[!] Fax-Gateway Versand fehlgeschlagen"
      fi
      rm -f "$smtp_pass_file" 2>/dev/null || true
      return 0
      ;;
    *)
      echo "[!] Unbekannter FAX_MODE '$mode' - Fax übersprungen"
      return 0
      ;;
  esac
}

refresh_id_registry
maybe_fetch_equipment

if [[ -n "$SOURCE_URL" ]]; then
  PREFER_FETCH_TEXT=1
fi

if [[ "$PREFER_FETCH_TEXT" = "1" && -s "$EQUIP_FILE" ]]; then
  build_text_from_equipment "$EQUIP_FILE" "$TMP_TEXT_FILE"
  if [[ -s "$TMP_TEXT_FILE" ]]; then
    TEXT_INPUT_FILE="$TMP_TEXT_FILE"
  fi
elif [[ ! -s "$TEXT_FILE" && -s "$EQUIP_FILE" ]]; then
  build_text_from_equipment "$EQUIP_FILE" "$TMP_TEXT_FILE"
  if [[ -s "$TMP_TEXT_FILE" ]]; then
    TEXT_INPUT_FILE="$TMP_TEXT_FILE"
  fi
fi

# 1. Bilder zu Liste sammeln (sortiert)
shopt -s nullglob
images=(
  "$INPUT_DIR"/*.jpg
  "$INPUT_DIR"/*.JPG
  "$INPUT_DIR"/*.jpeg
  "$INPUT_DIR"/*.JPEG
  "$INPUT_DIR"/*.png
  "$INPUT_DIR"/*.PNG
)
shopt -u nullglob

if (( ${#images[@]} == 0 )); then
  echo "[!] Keine Bilder in $INPUT_DIR - Abbruch"
  exit 1
fi

IFS=$'\n' images=( $(printf '%s\n' "${images[@]}" | python3 -c 'import re,sys; xs=[l.rstrip("\n") for l in sys.stdin if l.strip()]; xs.sort(key=lambda s:[int(t) if t.isdigit() else t.lower() for t in re.split(r"(\d+)", s)]); print("\n".join(xs))') )
unset IFS

# 2. Overlay-Text (Fahrzeugdaten)
OVERLAY_TEXT="$(build_overlay_text "$ID" "$VEHICLE_TEXT_FILE" "$TEXT_INPUT_FILE" "$EQUIP_FILE")"
printf '%s\n' "$OVERLAY_TEXT" > "$OVERLAY_FILE"
if [[ "${SHOW_OVERLAY:-1}" = "1" ]]; then
  echo "[+] Overlay-Text: $OVERLAY_TEXT"
fi

# 3. TTS aus Text generieren -> Voice/<ID>.wav
IMG_COUNT=${#images[@]}
EST_TOTAL_DUR=$((IMG_COUNT * DUR_PER_IMG))

if [[ -s "$TEXT_INPUT_FILE" ]] && command -v say >/dev/null 2>&1; then
  echo "[+] TTS: Generiere Voiceover aus $TEXT_INPUT_FILE"
  if ! say -v "$TTS_VOICE" -f "$TEXT_INPUT_FILE" -o "$TMP_VOICE_AIFF" 2>/dev/null; then
    echo "[!] TTS fehlgeschlagen - fallback: stille Spur"
    ffmpeg -y -loglevel error -f lavfi -i "anullsrc=r=48000:cl=stereo" -t "$EST_TOTAL_DUR" "$VOICE_FILE"
  else
    ffmpeg -y -loglevel error -i "$TMP_VOICE_AIFF" -ar 48000 -ac 2 "$VOICE_FILE"
  fi
else
  echo "[!] Kein Textinput oder kein 'say' - stille Spur"
  ffmpeg -y -loglevel error -f lavfi -i "anullsrc=r=48000:cl=stereo" -t "$EST_TOTAL_DUR" "$VOICE_FILE"
fi

# 4. Dauer an Voice koppeln (Fleetmarkt-Style)
VOICE_DUR="$(probe_duration "$VOICE_FILE")"
if [[ -n "$VOICE_DUR" ]]; then
  TOTAL_DUR="$(python3 - "$VOICE_DUR" "$VIDEO_PAD" <<'PY'
import sys
voice = float(sys.argv[1])
pad = float(sys.argv[2])
print(f"{voice + pad:.6f}")
PY
)"
else
  TOTAL_DUR="$(python3 - "$EST_TOTAL_DUR" <<'PY'
import sys
print(f"{float(sys.argv[1]):.6f}")
PY
)"
fi

PER_IMG="$(python3 - "$TOTAL_DUR" "$IMG_COUNT" <<'PY'
import math, sys
total = float(sys.argv[1])
count = int(sys.argv[2])
per = math.ceil((total / count) * 1_000_000) / 1_000_000
print(f"{per:.6f}")
PY
)"

RENDER_DUR="$TOTAL_DUR"
if [[ "${USE_TPAD:-0}" = "1" && "${VIDEO_TPAD:-0}" != "0" && "${VIDEO_TPAD:-0}" != "0.0" ]]; then
  RENDER_DUR="$(python3 - "$TOTAL_DUR" "$VIDEO_TPAD" <<'PY'
import sys
base = float(sys.argv[1])
pad = float(sys.argv[2])
print(f"{base + pad:.6f}")
PY
)"
fi

FADE_OUT_START="$(python3 - "$RENDER_DUR" "$FADE_OUT_DUR" <<'PY'
import sys
total = float(sys.argv[1])
fade = float(sys.argv[2])
start = total - fade
if start < 0:
    start = 0.0
print(f"{start:.6f}")
PY
)"

: > "$SLIDESHOW_LIST"
for img in "${images[@]}"; do
  img_abs="$(abs_path "$img")"
  img_esc="$(escape_ffconcat_path "$img_abs")"
  printf "file '%s'\n" "$img_esc" >> "$SLIDESHOW_LIST"
  printf "duration %s\n" "$PER_IMG" >> "$SLIDESHOW_LIST"
done
# Letztes Bild ohne duration wiederholen (ffconcat-Regel)
last_index=$((IMG_COUNT - 1))
img_abs="$(abs_path "${images[$last_index]}")"
img_esc="$(escape_ffconcat_path "$img_abs")"
printf "file '%s'\n" "$img_esc" >> "$SLIDESHOW_LIST"

# 5. Brand-Assets unten laden (optional)
picked_assets=()
left_logo=""
center_logo=""
right_logo=""
generic_assets=()

if [[ "${SHOW_BOTTOM_LOGOS:-1}" = "1" ]]; then
  left_logo="$(pick_unique_asset \
    "$LOGO_LEFT_FILE" \
    "$ASSETS_DIR/logo.png" \
    "$ASSETS_DIR/logo.jpg" \
    "$ASSETS_DIR/covalex.jpg")"
  if [[ -n "$left_logo" ]]; then
    picked_assets+=("$left_logo")
  fi

  center_logo="$(pick_unique_asset \
    "$LOGO_CENTER_FILE" \
    "$ASSETS_DIR/credit.png" \
    "$ASSETS_DIR/credit.jpg" \
    "$ASSETS_DIR/credit.jpeg" \
    "$ASSETS_DIR/covalex.jpg" \
    "$ASSETS_DIR/logo.jpg")"
  if [[ -n "$center_logo" ]]; then
    picked_assets+=("$center_logo")
  fi

  right_logo="$(pick_unique_asset \
    "$LOGO_RIGHT_FILE" \
    "$ASSETS_DIR/wally.png" \
    "$ASSETS_DIR/wally.jpg")"
  if [[ -n "$right_logo" ]]; then
    picked_assets+=("$right_logo")
  fi

  if [[ -z "$left_logo" && -z "$center_logo" && -z "$right_logo" ]]; then
    shopt -s nullglob
    discovered_assets=(
      "$ASSETS_DIR"/*.png "$ASSETS_DIR"/*.PNG
      "$ASSETS_DIR"/*.jpg "$ASSETS_DIR"/*.JPG
      "$ASSETS_DIR"/*.jpeg "$ASSETS_DIR"/*.JPEG
    )
    shopt -u nullglob

    if (( ${#discovered_assets[@]} > 0 )); then
      IFS=$'\n' discovered_assets=( $(printf '%s\n' "${discovered_assets[@]}" | sort) )
      unset IFS
      for a in "${discovered_assets[@]}"; do
        generic_assets+=("$a")
        if (( ${#generic_assets[@]} >= 3 )); then
          break
        fi
      done
    fi
  fi

  if [[ -n "$left_logo" || -n "$center_logo" || -n "$right_logo" ]]; then
    echo "[+] Bottom-Assets: left='${left_logo:-none}' center='${center_logo:-none}' right='${right_logo:-none}'"
  elif (( ${#generic_assets[@]} > 0 )); then
    echo "[+] Bottom-Assets (generic): ${generic_assets[*]}"
  else
    echo "[i] Keine Assets in '$ASSETS_DIR' gefunden - Bottom-Logos aus"
  fi
fi

if [[ -n "$left_logo" && -n "$center_logo" ]]; then
  lh="$(file_hash "$left_logo")"
  ch="$(file_hash "$center_logo")"
  if [[ -n "$lh" && "$lh" == "$ch" ]]; then
    echo "[!] Hinweis: Left- und Center-Logo sind identisch. Tausche z. B. '$ASSETS_DIR/credit.png' ein."
  fi
fi

ffmpeg_inputs=(-f concat -safe 0 -i "$SLIDESHOW_LIST" -i "$VOICE_FILE")
next_input_idx=2
left_idx=""
center_idx=""
right_idx=""
generic_idxs=()

if [[ -n "$left_logo" ]]; then
  ffmpeg_inputs+=(-i "$left_logo")
  left_idx="$next_input_idx"
  next_input_idx=$((next_input_idx + 1))
fi
if [[ -n "$center_logo" ]]; then
  ffmpeg_inputs+=(-i "$center_logo")
  center_idx="$next_input_idx"
  next_input_idx=$((next_input_idx + 1))
fi
if [[ -n "$right_logo" ]]; then
  ffmpeg_inputs+=(-i "$right_logo")
  right_idx="$next_input_idx"
  next_input_idx=$((next_input_idx + 1))
fi
if (( ${#generic_assets[@]} > 0 )); then
  for a in "${generic_assets[@]}"; do
    ffmpeg_inputs+=(-i "$a")
    generic_idxs+=("$next_input_idx")
    next_input_idx=$((next_input_idx + 1))
  done
fi

FILTER_COMPLEX="[0:v]fps=$FPS,scale=$WIDTH:$HEIGHT:flags=$SCALE_FLAGS:force_original_aspect_ratio=decrease,pad=$WIDTH:$HEIGHT:(ow-iw)/2:(oh-ih)/2:color=black,setsar=1[v0]"
current_label="v0"
next_label_idx=1

if [[ "${SHOW_OVERLAY:-1}" = "1" ]]; then
  if [[ "${SHOW_TOP_BAR:-1}" = "1" ]]; then
    next_label="v$next_label_idx"
    FILTER_COMPLEX="$FILTER_COMPLEX;[$current_label]drawbox=x=0:y=0:w=$WIDTH:h=$BAR_H:color=black@0.55:t=fill[$next_label]"
    current_label="$next_label"
    next_label_idx=$((next_label_idx + 1))
  fi

  next_label="v$next_label_idx"
  FILTER_COMPLEX="$FILTER_COMPLEX;[$current_label]drawtext=$DRAW_FONT_OPT:textfile='$OVERLAY_FILE':reload=1:fontsize=$TEXT_SIZE:fontcolor=$TEXT_COLOR:shadowcolor=black@0.75:shadowx=2:shadowy=2:x=$WIDTH-mod(t*$MARQUEE_SPEED\\,$WIDTH+tw+60):y=(($BAR_H-th)/2):box=0[$next_label]"
  current_label="$next_label"
  next_label_idx=$((next_label_idx + 1))
fi

if [[ "${SHOW_BOTTOM_LOGOS:-1}" = "1" ]]; then
  if [[ "${SHOW_BOTTOM_BAR:-0}" = "1" ]] && { [[ -n "$left_idx" ]] || [[ -n "$center_idx" ]] || [[ -n "$right_idx" ]] || (( ${#generic_idxs[@]} > 0 )); }; then
    next_label="v$next_label_idx"
    FILTER_COMPLEX="$FILTER_COMPLEX;[$current_label]drawbox=x=0:y=$((HEIGHT-BOTTOM_BAR_H)):w=$WIDTH:h=$BOTTOM_BAR_H:color=$BOTTOM_BAR_COLOR:t=fill[$next_label]"
    current_label="$next_label"
    next_label_idx=$((next_label_idx + 1))
  fi

  if [[ -n "$left_idx" ]]; then
    next_label="v$next_label_idx"
    FILTER_COMPLEX="$FILTER_COMPLEX;[$left_idx:v]format=rgba,scale=$BOTTOM_LEFT_W:$BOTTOM_LEFT_H:flags=$SCALE_FLAGS:force_original_aspect_ratio=decrease,pad=$BOTTOM_LEFT_W:$BOTTOM_LEFT_H:(ow-iw)/2:(oh-ih)/2:color=0x00000000[logo_left]"
    FILTER_COMPLEX="$FILTER_COMPLEX;[$current_label][logo_left]overlay=x=$BOTTOM_LEFT_MARGIN:y=H-h-$BOTTOM_MARGIN:format=auto[$next_label]"
    current_label="$next_label"
    next_label_idx=$((next_label_idx + 1))
  fi

  if [[ -n "$center_idx" ]]; then
    next_label="v$next_label_idx"
    FILTER_COMPLEX="$FILTER_COMPLEX;[$center_idx:v]format=rgba,scale=$BOTTOM_CENTER_W:$BOTTOM_CENTER_H:flags=$SCALE_FLAGS:force_original_aspect_ratio=decrease,pad=$BOTTOM_CENTER_W:$BOTTOM_CENTER_H:(ow-iw)/2:(oh-ih)/2:color=0x00000000[logo_center]"
    FILTER_COMPLEX="$FILTER_COMPLEX;[$current_label][logo_center]overlay=x=(W-w)/2:y=H-h-$BOTTOM_MARGIN:format=auto[$next_label]"
    current_label="$next_label"
    next_label_idx=$((next_label_idx + 1))
  fi

  if [[ -n "$right_idx" ]]; then
    next_label="v$next_label_idx"
    FILTER_COMPLEX="$FILTER_COMPLEX;[$right_idx:v]format=rgba,scale=$BOTTOM_RIGHT_W:$BOTTOM_RIGHT_H:flags=$SCALE_FLAGS:force_original_aspect_ratio=decrease,pad=$BOTTOM_RIGHT_W:$BOTTOM_RIGHT_H:(ow-iw)/2:(oh-ih)/2:color=0x00000000[logo_right]"
    FILTER_COMPLEX="$FILTER_COMPLEX;[$current_label][logo_right]overlay=x=W-w-$BOTTOM_RIGHT_MARGIN:y=H-h-$BOTTOM_MARGIN:format=auto[$next_label]"
    current_label="$next_label"
    next_label_idx=$((next_label_idx + 1))
  fi

  if (( ${#generic_idxs[@]} > 0 )); then
    slot_count="${#generic_idxs[@]}"
    slot_w=$(( (WIDTH - (BOTTOM_GENERIC_GAP * (slot_count + 1))) / slot_count ))
    if (( slot_w < 120 )); then
      slot_w=120
    fi
    for idx in "${!generic_idxs[@]}"; do
      input_idx="${generic_idxs[$idx]}"
      logo_label="glogo$idx"
      FILTER_COMPLEX="$FILTER_COMPLEX;[$input_idx:v]format=rgba,scale=$slot_w:$BOTTOM_GENERIC_H:flags=$SCALE_FLAGS:force_original_aspect_ratio=decrease,pad=$slot_w:$BOTTOM_GENERIC_H:(ow-iw)/2:(oh-ih)/2:color=0x00000000[$logo_label]"

      x_base=$((BOTTOM_GENERIC_GAP + idx * (slot_w + BOTTOM_GENERIC_GAP)))
      next_label="v$next_label_idx"
      FILTER_COMPLEX="$FILTER_COMPLEX;[$current_label][$logo_label]overlay=x=$x_base+($slot_w-w)/2:y=H-h-$BOTTOM_MARGIN:format=auto[$next_label]"
      current_label="$next_label"
      next_label_idx=$((next_label_idx + 1))
    done
  fi
fi

if [[ "${USE_TPAD:-0}" = "1" && "${VIDEO_TPAD:-0}" != "0" && "${VIDEO_TPAD:-0}" != "0.0" ]]; then
  next_label="v$next_label_idx"
  FILTER_COMPLEX="$FILTER_COMPLEX;[$current_label]tpad=stop_mode=clone:stop_duration=$VIDEO_TPAD[$next_label]"
  current_label="$next_label"
  next_label_idx=$((next_label_idx + 1))
fi

if [[ "${FADE_IN_DUR:-0}" != "0" && "${FADE_IN_DUR:-0}" != "0.0" ]]; then
  next_label="v$next_label_idx"
  FILTER_COMPLEX="$FILTER_COMPLEX;[$current_label]fade=t=in:st=0:d=$FADE_IN_DUR[$next_label]"
  current_label="$next_label"
  next_label_idx=$((next_label_idx + 1))
fi

if [[ "${FADE_OUT_DUR:-0}" != "0" && "${FADE_OUT_DUR:-0}" != "0.0" ]]; then
  next_label="v$next_label_idx"
  FILTER_COMPLEX="$FILTER_COMPLEX;[$current_label]fade=t=out:st=$FADE_OUT_START:d=$FADE_OUT_DUR[$next_label]"
  current_label="$next_label"
  next_label_idx=$((next_label_idx + 1))
fi

FILTER_COMPLEX="$FILTER_COMPLEX;[$current_label]format=yuv420p[vout]"

x264_video_opts=(-c:v libx264 -crf "$X264_CRF" -preset "$X264_PRESET")
if [[ -n "${X264_TUNE:-}" ]]; then
  x264_video_opts+=(-tune "$X264_TUNE")
fi

# 6. FFmpeg: Slideshow + TTS + Marquee + Bottom-Assets
echo "[+] Render: $IMG_COUNT Bilder -> $OUTPUT (${RENDER_DUR}s)"
ffmpeg -y \
  "${ffmpeg_inputs[@]}" \
  -filter_complex "$FILTER_COMPLEX" \
  -map "[vout]" -map 1:a \
  -af "apad=pad_dur=$RENDER_DUR" \
  -t "$RENDER_DUR" \
  "${x264_video_opts[@]}" \
  -pix_fmt yuv420p \
  -color_range tv -color_primaries bt709 -color_trc bt709 -colorspace bt709 \
  -c:a aac -b:a "$AAC_BR" \
  -movflags +faststart \
  "$OUTPUT"

if [[ "${GENERATE_WEBM:-1}" = "1" ]]; then
  ffmpeg -y \
    "${ffmpeg_inputs[@]}" \
    -filter_complex "$FILTER_COMPLEX" \
    -map "[vout]" -map 1:a \
    -af "apad=pad_dur=$RENDER_DUR" \
    -t "$RENDER_DUR" \
    -c:v libvpx-vp9 -b:v 0 -crf "${VP9_CRF:-28}" -cpu-used "${VP9_CPU_USED:-6}" \
    -row-mt 1 -threads 4 -tile-columns 2 \
    -pix_fmt yuv420p \
    -color_range tv -color_primaries bt709 -color_trc bt709 -colorspace bt709 \
    -c:a libopus -b:a "${OPUS_BR:-96k}" \
    "$OUTPUT_WEBM"
fi

# 7. QR
if command -v qrencode >/dev/null 2>&1; then
  qrencode -o "$QR_FILE" "${QR_URL%/}/car/$ID"
else
  echo "[!] qrencode fehlt - QR wird übersprungen"
fi

maybe_print_qr
maybe_email_qr
maybe_fax_qr

echo "[+] Fertig: $OUTPUT"
if [[ "${GENERATE_WEBM:-1}" = "1" ]]; then
  echo "[+] WebM:  $OUTPUT_WEBM"
fi
echo "[+] Voice: $VOICE_FILE"
echo "[+] QR: $QR_FILE"
if [[ "${SHOW_OVERLAY:-1}" = "1" ]]; then
  echo "[+] Overlay: AN"
else
  echo "[+] Overlay: AUS"
fi
if [[ "${AUTO_FAX_QR:-0}" = "1" ]]; then
  echo "[+] Fax: AN ($FAX_MODE)"
else
  echo "[+] Fax: AUS"
fi
echo "Tipp: ./run.sh <ID> [URL] (z. B. ./run.sh 12345 https://example.com/fahrzeug/12345 oder ./run.sh 12345 https://example.com/dealer)"
