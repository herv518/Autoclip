#!/usr/bin/env bash
# Sanitized example config (no real values)

# --- Brand / Text ---
BRAND_NAME="${BRAND_NAME:-Autohaus Beispiel}"

CTA_LINES=(
  "Jetzt unverbindlich anfragen"
  "Top gepflegter Gebrauchtwagen"
  "Probefahrt nach Terminvereinbarung"
)

# --- Verzeichnisse ---
INPUT_FRAMES_DIR="Input-Frames"
EQUIP_DIR="Vehicle-Equipment"
TEXT_DIR="Vehicle-Text"
VOICE_DIR="Voice"
OUT_DIR="Output"
CACHE_DIR=".cache"
TMP_DIR=".tmp"
ID_REGISTRY_DIR="${ID_REGISTRY_DIR:-metadata}"     # Sammelordner für ID-Listen
IDS_FILE="${IDS_FILE:-$ID_REGISTRY_DIR/ids.txt}"   # alle IDs gesammelt in einer Datei
LOCAL_ENV_FILE="${LOCAL_ENV_FILE:-.mail.env}" # lokale Overrides (z. B. Mail), nicht committen

# --- Watcher (Input-Frames -> Auto-Render) ---
WATCH_POLL_SEC="${WATCH_POLL_SEC:-5}"               # Scan-Intervall
WATCH_STABLE_SEC="${WATCH_STABLE_SEC:-8}"           # Datei muss so lange unverändert sein
WATCH_FAIL_COOLDOWN_SEC="${WATCH_FAIL_COOLDOWN_SEC:-60}" # Wartezeit nach Fehler
WATCH_DRY_RUN="${WATCH_DRY_RUN:-0}"                 # 1 = nur loggen, nicht rendern
WATCH_ONESHOT="${WATCH_ONESHOT:-0}"                 # 1 = ein Scan-Durchlauf (Smoke-Test)
WATCH_LOG_FILE="${WATCH_LOG_FILE:-watch_input_frames.log}"
WATCH_PID_FILE="${WATCH_PID_FILE:-.tmp/watch.pid}"
WATCH_LOCK_DIR="${WATCH_LOCK_DIR:-.tmp/watch_input_frames.lock}"

# Optionaler Mitarbeiter-Upload-Ordner (Outlook/OneDrive/Dropbox/etc.)
# Erwartet Struktur: <UPLOAD_INBOX_DIR>/<ID>/*.jpg
UPLOAD_INBOX_DIR="${UPLOAD_INBOX_DIR:-}"            # leer = aus
UPLOAD_ARCHIVE_DIR="${UPLOAD_ARCHIVE_DIR:-.tmp/upload_archive}"
UPLOAD_MOVE_TO_ARCHIVE="${UPLOAD_MOVE_TO_ARCHIVE:-1}" # 1 = nach Import verschieben

# --- Video Settings ---
W="${W:-1080}"
H="${H:-810}"
FPS="${FPS:-30}"
BAR_H="${BAR_H:-106}"
TEXT_Y="${TEXT_Y:-31}"
FONT="${FONT:-Arial}"
MARQUEE_SPEED="${MARQUEE_SPEED:-220}"
TEXT_SIZE="${TEXT_SIZE:-44}"
TEXT_COLOR="${TEXT_COLOR:-white}"
TEXT_BG="${TEXT_BG:-black@0.6}"
SHOW_OVERLAY="${SHOW_OVERLAY:-1}"    # 1 = Top-Bar mit Fahrzeugdaten einblenden
SHOW_TOP_BAR="${SHOW_TOP_BAR:-1}"            # 1 = halbtransparente Bar hinter Marquee-Text
SHOW_ID_IN_OVERLAY="${SHOW_ID_IN_OVERLAY:-0}" # 1 = "ID <nr>" vor Overlay-Text
OVERLAY_USE_CTA="${OVERLAY_USE_CTA:-1}"      # 1 = zufaellige CTA-Linie im Overlay
OVERLAY_EQUIP_COUNT="${OVERLAY_EQUIP_COUNT:-2}" # Anzahl Ausstattungspunkte im Overlay
OVERLAY_MAX_LEN="${OVERLAY_MAX_LEN:-320}"    # Harte Text-Begrenzung für den Lauftext
SHOW_BOTTOM_LOGOS="${SHOW_BOTTOM_LOGOS:-1}"  # 1 = Brand-Logos unten einblenden
SHOW_BOTTOM_BAR="${SHOW_BOTTOM_BAR:-0}"      # 1 = dunkler Balken hinter den Logos
ASSETS_DIR="${ASSETS_DIR:-assets}"           # Asset-Ordner
LOGO_LEFT_FILE="${LOGO_LEFT_FILE:-}"         # optional: linker Logo-Pfad
LOGO_CENTER_FILE="${LOGO_CENTER_FILE:-}"     # optional: mittlerer Logo-Pfad
LOGO_RIGHT_FILE="${LOGO_RIGHT_FILE:-}"       # optional: rechter Logo-Pfad
BOTTOM_BAR_H="${BOTTOM_BAR_H:-106}"          # Hoehe des unteren Logo-Bereichs (wenn SHOW_BOTTOM_BAR=1)
BOTTOM_BAR_COLOR="${BOTTOM_BAR_COLOR:-black@0.45}"
BOTTOM_MARGIN="${BOTTOM_MARGIN:-24}"         # Abstand unten
BOTTOM_LEFT_MARGIN="${BOTTOM_LEFT_MARGIN:-36}"
BOTTOM_RIGHT_MARGIN="${BOTTOM_RIGHT_MARGIN:-24}"
BOTTOM_LEFT_W="${BOTTOM_LEFT_W:-220}"        # Boxbreite links
BOTTOM_LEFT_H="${BOTTOM_LEFT_H:-90}"         # Boxhoehe links
BOTTOM_CENTER_W="${BOTTOM_CENTER_W:-520}"    # Boxbreite mitte
BOTTOM_CENTER_H="${BOTTOM_CENTER_H:-92}"     # Boxhoehe mitte
BOTTOM_RIGHT_W="${BOTTOM_RIGHT_W:-110}"      # Boxbreite rechts
BOTTOM_RIGHT_H="${BOTTOM_RIGHT_H:-110}"      # Boxhoehe rechts
BOTTOM_GENERIC_W="${BOTTOM_GENERIC_W:-280}"  # Fallback-Logobox (gleichmaessig)
BOTTOM_GENERIC_H="${BOTTOM_GENERIC_H:-82}"   # Fallback-Logobox (gleichmaessig)
BOTTOM_GENERIC_GAP="${BOTTOM_GENERIC_GAP:-32}"
DUR_PER_IMG="${DUR_PER_IMG:-5}"      # fallback, wenn keine Audio-Dauer
GENERATE_WEBM="${GENERATE_WEBM:-1}"  # zusaetzlich Output/<ID>.webm erzeugen
SCALE_FLAGS="${SCALE_FLAGS:-lanczos}" # bessere Resize-Qualitaet beim Skalieren
X264_CRF="${X264_CRF:-20}"            # niedriger = bessere MP4-Qualitaet (Datei groesser)
X264_PRESET="${X264_PRESET:-slow}"    # slower = bessere Effizienz
X264_TUNE="${X264_TUNE:-stillimage}"  # passt gut zu Slideshow-Content
AAC_BR="${AAC_BR:-160k}"              # Audio-Bitrate für MP4
VP9_CRF="${VP9_CRF:-28}"
VP9_CPU_USED="${VP9_CPU_USED:-6}"
OPUS_BR="${OPUS_BR:-96k}"
FALLBACK_DUR="${FALLBACK_DUR:-8.0}"
VIDEO_PAD="${VIDEO_PAD:-0.5}"
VIDEO_TPAD="${VIDEO_TPAD:-2.0}"
USE_TPAD="${USE_TPAD:-0}"            # 1 = letzten Frame (VIDEO_TPAD) halten
FADE_IN_DUR="${FADE_IN_DUR:-0.7}"
FADE_OUT_DUR="${FADE_OUT_DUR:-0.0}"

# --- TTS ---
TTS_VOICE="${TTS_VOICE:-Anna}"
TTS_SPEED="${TTS_SPEED:-1.0}"
OUT_AR="${OUT_AR:-48000}"
OUT_AC="${OUT_AC:-2}"

# --- URL / Fetcher ---
BASE_URL="${BASE_URL:-https://example.com}"
LIST_BASE="${LIST_BASE:-https://example.com/fahrzeugangebote}"
LIST_BASE_INDEX="${LIST_BASE_INDEX:-https://example.com/index.php/fahrzeugangebote}"
UA="${UA:-Mozilla/5.0}"
QR_URL="${QR_URL:-https://example.com}"
SOURCE_URL="${SOURCE_URL:-https://example.com/fahrzeug/{ID}}" # Template mit {ID} ODER Basis-URL (dann Crawl)
FETCH_TIMEOUT="${FETCH_TIMEOUT:-20}"                     # HTTP Timeout in Sekunden
FETCH_MAX_PAGES="${FETCH_MAX_PAGES:-140}"                # max. Seiten beim Crawl
FETCH_MAX_LINKS_PER_PAGE="${FETCH_MAX_LINKS_PER_PAGE:-180}" # Link-Limit pro Seite

# --- QR Auto-Print (optional) ---
AUTO_PRINT_QR="${AUTO_PRINT_QR:-0}"      # 1 = nach Rendern drucken
PRINTER_NAME="${PRINTER_NAME:-}"         # leer = Standarddrucker

# --- QR Auto-E-Mail (optional, SMTP) ---
AUTO_EMAIL_QR="${AUTO_EMAIL_QR:-0}"      # 1 = nach Rendern per Mail senden
EMAIL_TO="${EMAIL_TO:-}"                 # mehrere Empfänger per Komma
EMAIL_FROM="${EMAIL_FROM:-}"             # leer = SMTP_USER
EMAIL_SUBJECT_TEMPLATE="${EMAIL_SUBJECT_TEMPLATE:-Carclip QR-Code {ID}}"
EMAIL_BODY_TEMPLATE="${EMAIL_BODY_TEMPLATE:-}" # falls leer, nimmt run.sh: "Anbei ... {ID}."
SMTP_HOST="${SMTP_HOST:-}"               # z. B. smtp.gmail.com
SMTP_PORT="${SMTP_PORT:-587}"
SMTP_USER="${SMTP_USER:-}"
SMTP_PASS="${SMTP_PASS:-}"
SMTP_TLS="${SMTP_TLS:-1}"                # 1 = STARTTLS
SMTP_USE_SSL="${SMTP_USE_SSL:-0}"        # 1 = SMTPS (Port 465)
USE_MACOS_KEYCHAIN="${USE_MACOS_KEYCHAIN:-1}"                 # 1 = SMTP-Passwort aus macOS Keychain lesen
SMTP_KEYCHAIN_SERVICE="${SMTP_KEYCHAIN_SERVICE:-carclip-smtp}" # Keychain Service-Name
SMTP_PASS_KEYCHAIN_ACCOUNT="${SMTP_PASS_KEYCHAIN_ACCOUNT:-}"   # leer = SMTP_USER

# --- QR Auto-Fax (optional) ---
AUTO_FAX_QR="${AUTO_FAX_QR:-0}"          # 1 = nach Rendern Fax senden
FAX_MODE="${FAX_MODE:-dry_run}"          # dry_run | email_gateway
FAX_TO="${FAX_TO:-}"                     # Faxnummer (z. B. +49401234567)
FAX_EMAIL_TO="${FAX_EMAIL_TO:-}"         # direkte Fax-Gateway Mailadresse
FAX_GATEWAY_DOMAIN="${FAX_GATEWAY_DOMAIN:-}" # optional: FAX_TO@domain
FAX_FROM="${FAX_FROM:-}"                 # leer = EMAIL_FROM/SMTP_USER
FAX_SUBJECT_TEMPLATE="${FAX_SUBJECT_TEMPLATE:-Carclip QR Fax {ID}}"
FAX_BODY_TEMPLATE="${FAX_BODY_TEMPLATE:-}" # falls leer, nimmt run.sh: "... {ID} ... {FAX_TO}"
FAX_DRY_RUN_FILE="${FAX_DRY_RUN_FILE:-}"   # falls leer, nimmt run.sh: .tmp/fax_{ID}.txt
