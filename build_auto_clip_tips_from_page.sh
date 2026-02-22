#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  ./build_auto_clip_tips_from_page.sh \
    --url "https://grokipedia.com/page/Auto-Clip" \
    --section-target "Input Preparation and Photo Handling" \
    --marker-text "The input preparation ..." \
    --recommendation "Hier steht deine Empfehlung"

Options:
  --url               Zielseite
  --section-target    Abschnitt/Ueberschrift, der angepasst werden soll
  --marker-text       Exakter Marker-Text aus der Seite
  --recommendation    Deine vorgeschlagene Aenderung
  --voice             Stimme fuer TTS (default: Anna)
  --no-ai             KI-Agentenumschreibung deaktivieren
  --no-webm           nur MP4 erzeugen
  -h, --help          Hilfe anzeigen
USAGE
}

die() {
  echo "[!] $*" >&2
  exit 1
}

require_cmd() {
  local c="$1"
  command -v "$c" >/dev/null 2>&1 || die "Missing command: $c"
}

json_escape() {
  python3 - "$1" <<'PY'
import json
import sys
print(json.dumps(sys.argv[1], ensure_ascii=False))
PY
}

URL=""
SECTION_TARGET=""
MARKER_TEXT=""
RECOMMENDATION=""
TTS_VOICE="${TTS_VOICE:-Anna}"
USE_AI=1
NO_WEBM=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url)
      shift
      [[ $# -gt 0 ]] || die "Missing value for --url"
      URL="$1"
      ;;
    --section-target)
      shift
      [[ $# -gt 0 ]] || die "Missing value for --section-target"
      SECTION_TARGET="$1"
      ;;
    --marker-text)
      shift
      [[ $# -gt 0 ]] || die "Missing value for --marker-text"
      MARKER_TEXT="$1"
      ;;
    --recommendation)
      shift
      [[ $# -gt 0 ]] || die "Missing value for --recommendation"
      RECOMMENDATION="$1"
      ;;
    --voice)
      shift
      [[ $# -gt 0 ]] || die "Missing value for --voice"
      TTS_VOICE="$1"
      ;;
    --no-ai)
      USE_AI=0
      ;;
    --no-webm)
      NO_WEBM=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
  shift
done

[[ -n "$URL" ]] || die "--url is required"
[[ -n "$SECTION_TARGET" ]] || die "--section-target is required"
[[ -n "$MARKER_TEXT" ]] || die "--marker-text is required"
[[ -n "$RECOMMENDATION" ]] || die "--recommendation is required"

require_cmd curl
require_cmd python3

RAW_HTML=""
if ! RAW_HTML="$(curl -fsSL "$URL" 2>/dev/null)"; then
  echo "[!] Seite nicht erreichbar: $URL"
  echo "[!] Fahre mit Empfehlungstext ohne Seiten-Check fort."
fi

analysis="$(
python3 - "$SECTION_TARGET" "$MARKER_TEXT" "$RAW_HTML" <<'PY'
import html
import json
import re
import sys

section_target = sys.argv[1].strip()
marker_text = sys.argv[2].strip()
raw_html = sys.argv[3]

def normalize(s):
    return re.sub(r"\s+", " ", (s or "").strip()).lower()

# basic html->text transform, robust enough for page checks
text = re.sub(r"(?is)<(script|style|noscript)[^>]*>.*?</\1>", " ", raw_html)
text = re.sub(r"(?s)<[^>]+>", " ", text)
text = html.unescape(text)
text = re.sub(r"\s+", " ", text).strip()

n_text = normalize(text)
n_section = normalize(section_target)
n_marker = normalize(marker_text)

section_found = bool(n_section and n_section in n_text)
marker_found = bool(n_marker and n_marker in n_text)

status = "ok" if section_found and marker_found else "partial"

out = {
    "status": status,
    "section_found": section_found,
    "marker_found": marker_found,
    "page_text_length": len(text),
}
print(json.dumps(out, ensure_ascii=False))
PY
)"

section_found="$(
python3 - "$analysis" <<'PY'
import json,sys
obj=json.loads(sys.argv[1])
print("1" if obj.get("section_found") else "0")
PY
)"

marker_found="$(
python3 - "$analysis" <<'PY'
import json,sys
obj=json.loads(sys.argv[1])
print("1" if obj.get("marker_found") else "0")
PY
)"

page_text_length="$(
python3 - "$analysis" <<'PY'
import json,sys
obj=json.loads(sys.argv[1])
print(str(obj.get("page_text_length", 0)))
PY
)"

if [[ "$section_found" = "1" ]]; then
  section_status="gefunden"
else
  section_status="nicht eindeutig gefunden"
fi

if [[ "$marker_found" = "1" ]]; then
  marker_status="gefunden"
else
  marker_status="nicht eindeutig gefunden"
fi

spoken_text="Deine Idee ist Gold wert. Seite: ${URL}. Abschnitt: ${SECTION_TARGET} (${section_status}). Marker: ${marker_status}. Thema deiner Empfehlung: ${RECOMMENDATION}. Erklaere diese Aenderung klar, konkret und nur fuer genau diese Stelle in Grokipedia."

mkdir -p assets/videos
cat > assets/videos/auto-clip-tips-page-context.json <<JSON
{
  "url": $(json_escape "$URL"),
  "section_target": $(json_escape "$SECTION_TARGET"),
  "marker_text": $(json_escape "$MARKER_TEXT"),
  "recommendation": $(json_escape "$RECOMMENDATION"),
  "section_found": $([[ "$section_found" = "1" ]] && echo true || echo false),
  "marker_found": $([[ "$marker_found" = "1" ]] && echo true || echo false),
  "page_text_length": $page_text_length
}
JSON

cmd=(./build_auto_clip_tips_video.sh --text "$spoken_text" --voice "$TTS_VOICE" --min-duration 26 --frame-sec 0.16)
if [[ "$USE_AI" = "1" ]]; then
  cmd+=(--ai)
fi
if [[ "$NO_WEBM" = "1" ]]; then
  cmd+=(--no-webm)
fi

echo "[+] Context gespeichert: assets/videos/auto-clip-tips-page-context.json"
echo "[+] Baue Video aus Seitenkontext ..."
if [[ "$USE_AI" = "1" ]]; then
  TIPS_AI_PROVIDER="ollama" TIPS_AI_MODEL="qwen2.5:7b" "${cmd[@]}"
else
  "${cmd[@]}"
fi
