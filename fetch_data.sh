#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ID=""
URL_INPUT=""
OUT_FILE="${ROOT_DIR}/fahrzeugdaten.txt"
MAX_BULLETS="${FETCH_MAX_BULLETS:-2}"
FETCH_TIMEOUT="${FETCH_TIMEOUT:-20}"
USER_AGENT="${FETCH_UA:-Mozilla/5.0}"

HEADLINE=""
BULLETS=()

usage() {
  cat <<'USAGE'
Usage:
  ./fetch_data.sh --id <ID> --url <URL_OR_TEMPLATE> [options]

Options:
  --id <ID>                Vehicle ID used for {ID} replacement
  --url <URL_OR_TEMPLATE>  URL or template (e.g. https://example.com/car/{ID})
  --output <file>          Output data file (default: fahrzeugdaten.txt)
  --max-bullets <n>        Number of bullet points to keep (default: 2)
  --timeout <sec>          curl timeout in seconds (default: 20)
  --user-agent <string>    User-Agent for HTTP request
  -h, --help               Show help
USAGE
}

die() {
  echo "Error: $*" >&2
  exit 1
}

warn() {
  echo "Warning: $*" >&2
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    die "'$cmd' is not installed."
  fi
}

trim_value() {
  printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

normalize_line() {
  printf '%s' "$1" | sed -E \
    -e 's/<[^>]*>/ /g' \
    -e 's/&nbsp;/ /g' \
    -e 's/&amp;/\&/g' \
    -e 's/&quot;/"/g' \
    -e 's/&#34;/"/g' \
    -e 's/[[:space:]]+/ /g' \
    -e 's/^[[:space:]]+//' \
    -e 's/[[:space:]]+$//'
}

contains_bullet() {
  local needle="$1"
  local needle_lower existing
  needle_lower="$(printf '%s' "$needle" | tr '[:upper:]' '[:lower:]')"

  for existing in "${BULLETS[@]}"; do
    if [[ "$(printf '%s' "$existing" | tr '[:upper:]' '[:lower:]')" == "$needle_lower" ]]; then
      return 0
    fi
  done
  return 1
}

add_bullet() {
  local raw="$1"
  local cleaned
  cleaned="$(normalize_line "$raw")"
  cleaned="$(trim_value "$cleaned")"
  [[ -n "$cleaned" ]] || return 0
  (( ${#cleaned} >= 3 )) || return 0
  (( ${#cleaned} <= 180 )) || return 0

  if contains_bullet "$cleaned"; then
    return 0
  fi

  BULLETS+=("$cleaned")
}

extract_with_pup() {
  local html_file="$1"
  local raw=""

  HEADLINE="$(pup 'h1 text{}' < "$html_file" 2>/dev/null | awk 'NF { print; exit }' || true)"
  HEADLINE="$(normalize_line "$HEADLINE")"

  if [[ -z "$HEADLINE" ]]; then
    HEADLINE="$(pup 'title text{}' < "$html_file" 2>/dev/null | awk 'NF { print; exit }' || true)"
    HEADLINE="$(normalize_line "$HEADLINE")"
  fi

  while IFS= read -r raw; do
    add_bullet "$raw"
    if (( ${#BULLETS[@]} >= MAX_BULLETS )); then
      break
    fi
  done < <(pup 'ul li text{}' < "$html_file" 2>/dev/null || true)
}

extract_with_awk() {
  local html_file="$1"
  local raw=""

  HEADLINE="$(awk '
    BEGIN { RS="</[Hh]1>" }
    {
      line = $0
      if (line ~ /<[Hh]1[^>]*>/) {
        sub(/^.*<[Hh]1[^>]*>/, "", line)
        print line
        exit
      }
    }
  ' "$html_file" || true)"
  HEADLINE="$(normalize_line "$HEADLINE")"

  if [[ -z "$HEADLINE" ]]; then
    HEADLINE="$(awk '
      BEGIN { RS="</[Tt][Ii][Tt][Ll][Ee]>" }
      {
        line = $0
        if (line ~ /<[Tt][Ii][Tt][Ll][Ee][^>]*>/) {
          sub(/^.*<[Tt][Ii][Tt][Ll][Ee][^>]*>/, "", line)
          print line
          exit
        }
      }
    ' "$html_file" || true)"
    HEADLINE="$(normalize_line "$HEADLINE")"
  fi

  while IFS= read -r raw; do
    add_bullet "$raw"
    if (( ${#BULLETS[@]} >= MAX_BULLETS )); then
      break
    fi
  done < <(awk '
    BEGIN { RS="</[Ll][Ii]>" }
    {
      line = $0
      if (line ~ /<[Ll][Ii][^>]*>/) {
        sub(/^.*<[Ll][Ii][^>]*>/, "", line)
        print line
      }
    }
  ' "$html_file" || true)
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --id)
      [[ $# -ge 2 ]] || die "Missing value for $1"
      ID="$2"
      shift 2
      ;;
    --url)
      [[ $# -ge 2 ]] || die "Missing value for $1"
      URL_INPUT="$2"
      shift 2
      ;;
    --output)
      [[ $# -ge 2 ]] || die "Missing value for $1"
      OUT_FILE="$2"
      shift 2
      ;;
    --max-bullets)
      [[ $# -ge 2 ]] || die "Missing value for $1"
      MAX_BULLETS="$2"
      shift 2
      ;;
    --timeout)
      [[ $# -ge 2 ]] || die "Missing value for $1"
      FETCH_TIMEOUT="$2"
      shift 2
      ;;
    --user-agent)
      [[ $# -ge 2 ]] || die "Missing value for $1"
      USER_AGENT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

[[ -n "$ID" ]] || die "--id is required"
[[ -n "$URL_INPUT" ]] || die "--url is required"
[[ "$MAX_BULLETS" =~ ^[0-9]+$ ]] || die "--max-bullets must be an integer"
(( MAX_BULLETS >= 1 )) || die "--max-bullets must be >= 1"
[[ "$FETCH_TIMEOUT" =~ ^[0-9]+([.][0-9]+)?$ ]] || die "--timeout must be numeric"

require_cmd curl
require_cmd awk
require_cmd sed

RESOLVED_URL="${URL_INPUT//\{ID\}/${ID}}"
if [[ ! "$RESOLVED_URL" =~ ^https?:// ]]; then
  die "Resolved URL must start with http:// or https:// (got: ${RESOLVED_URL})"
fi

tmp_html="$(mktemp)"
trap 'rm -f "$tmp_html"' EXIT

curl -fsSL --compressed \
  --connect-timeout "$FETCH_TIMEOUT" \
  --max-time "$FETCH_TIMEOUT" \
  -A "$USER_AGENT" \
  "$RESOLVED_URL" \
  -o "$tmp_html"

if command -v pup >/dev/null 2>&1; then
  extract_with_pup "$tmp_html"
  parser_name="pup"
else
  warn "pup not found; using awk fallback parser."
  extract_with_awk "$tmp_html"
  parser_name="awk"
fi

if [[ -z "$HEADLINE" ]]; then
  HEADLINE="Fahrzeug ${ID}"
fi

mkdir -p "$(dirname "$OUT_FILE")"

{
  echo "# auto-generated by fetch_data.sh on $(date '+%Y-%m-%d %H:%M:%S')"
  echo "ID=${ID}"
  echo "URL=${RESOLVED_URL}"
  echo "Ueberschrift=${HEADLINE}"
  idx=1
  for bullet in "${BULLETS[@]}"; do
    (( idx > MAX_BULLETS )) && break
    echo "Bullet${idx}=${bullet}"
    idx=$((idx + 1))
  done
} > "$OUT_FILE"

if (( ${#BULLETS[@]} == 0 )); then
  warn "No bullet points detected on page."
fi

echo "Fetch OK: parser=${parser_name} url=${RESOLVED_URL}"
echo "Data file written: ${OUT_FILE}"
if (( ${#BULLETS[@]} > 0 )); then
  echo "Bullets captured: ${#BULLETS[@]}"
fi
