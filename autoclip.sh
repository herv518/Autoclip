#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ROOT_DIR}/.env"

if [[ -f "${ENV_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
fi

INPUT_VIDEO="${INPUT_VIDEO:-}"
OUTPUT_VIDEO="${OUTPUT_VIDEO:-output/final.mp4}"
OVERLAY_TEXT="${OVERLAY_TEXT:-}"
DATA_FILE="${DATA_FILE:-}"

TEXT_SIZE="${TEXT_SIZE:-54}"
TEXT_COLOR="${TEXT_COLOR:-white}"
TEXT_BOX_COLOR="${TEXT_BOX_COLOR:-0x00000099}"
TEXT_BOX_PADDING="${TEXT_BOX_PADDING:-18}"
TEXT_MARGIN_BOTTOM="${TEXT_MARGIN_BOTTOM:-80}"
TEXT_FONT_FILE="${TEXT_FONT_FILE:-}"

LOGO_SIZE="${LOGO_SIZE:-180}"
LOGO_MARGIN="${LOGO_MARGIN:-40}"
LOGO_SPACING="${LOGO_SPACING:-20}"
LOGOS_DEFAULT="${LOGOS:-}"
LOGO_PREFLIGHT="${LOGO_PREFLIGHT:-true}"
PREFLIGHT_STRICT="${PREFLIGHT_STRICT:-false}"
LOGO_MIN_DIM="${LOGO_MIN_DIM:-120}"
LOGO_MAX_ASPECT="${LOGO_MAX_ASPECT:-6}"

UPLOAD_AFTER_RENDER="${UPLOAD_AFTER_RENDER:-false}"
SFTP_HOST="${SFTP_HOST:-}"
SFTP_PORT="${SFTP_PORT:-22}"
SFTP_USER="${SFTP_USER:-}"
SFTP_REMOTE_DIR="${SFTP_REMOTE_DIR:-}"
SFTP_REMOTE_FILENAME="${SFTP_REMOTE_FILENAME:-}"
FETCH_ID="${FETCH_ID:-}"
FETCH_URL="${FETCH_URL:-}"
FETCH_SCRIPT="${FETCH_SCRIPT:-${ROOT_DIR}/fetch_data.sh}"
FETCH_MAX_BULLETS="${FETCH_MAX_BULLETS:-2}"
FETCH_TIMEOUT="${FETCH_TIMEOUT:-20}"
FETCH_UA="${FETCH_UA:-Mozilla/5.0}"

usage() {
  cat <<'USAGE'
Usage: ./autoclip.sh --input input.mp4 [options]
   or: ./autoclip.sh --demo [options]

Options:
  -i, --input <file>        Input video (required unless INPUT_VIDEO is in .env)
  -o, --output <file>       Output video path (default: output/final.mp4)
  -t, --text <text>         Text overlay for the video
  -d, --data-file <file>    TXT data file to auto-build overlay (Ueberschrift/Bullets or PS/Baujahr/Preis)
      --fetch-id <id>       Fetch web data for one ID before render
      --fetch-url <url>     URL or template with {ID} for fetch_data.sh
      --fetch-script <file> Fetch helper script (default: ./fetch_data.sh)
      --fetch-max-bullets <n>  Max bullets taken from web fetch (default: 2)
      --fetch-timeout <sec> HTTP timeout for web fetch (default: 20)
      --fetch-ua <string>   User-Agent for web fetch
  -l, --logo <file>         Add one logo overlay (repeatable)
      --logos <a,b,c>       Comma-separated logo list (alternative to --logo)
      --demo                Run fixed repo demo (sample input + data + logos)
      --upload              Force SFTP upload after render
      --no-upload           Force skip SFTP upload
  -h, --help                Show help
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
  local brew_hint="${2:-}"
  if command -v "$cmd" >/dev/null 2>&1; then
    return 0
  fi
  if [[ -n "$brew_hint" ]] && command -v brew >/dev/null 2>&1; then
    die "'$cmd' is not installed. Install with: brew install $brew_hint"
  fi
  if [[ -n "$brew_hint" ]]; then
    die "'$cmd' is not installed. Install Homebrew or install manually (recommended: brew install $brew_hint)."
  fi
  die "'$cmd' is not installed."
}

validate_sftp_batch_value() {
  local value="$1"
  [[ "$value" != *$'\n'* && "$value" != *$'\r'* && "$value" != *'"'* ]]
}

escape_drawtext() {
  printf '%s' "$1" | sed \
    -e 's/\\/\\\\/g' \
    -e "s/'/\\\\\\\\'/g" \
    -e 's/:/\\:/g' \
    -e 's/%/\\%/g'
}

escape_filter_value() {
  printf '%s' "$1" | sed \
    -e 's/\\/\\\\/g' \
    -e 's/:/\\:/g'
}

is_truthy() {
  local lowered
  lowered="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "${lowered}" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

trim_value() {
  printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

normalize_data_key() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -e 's/[[:space:]_-]//g'
}

to_lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

is_integer() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

logo_preflight_issue_count=0

record_logo_preflight_issue() {
  warn "$1"
  logo_preflight_issue_count=$((logo_preflight_issue_count + 1))
}

logo_has_alpha_channel() {
  local logo="$1"
  local channels=""
  local pix_fmt=""

  if command -v identify >/dev/null 2>&1; then
    channels="$(identify -quiet -format '%[channels]' "${logo}" 2>/dev/null || true)"
    channels="$(to_lower "${channels}")"
    [[ -n "${channels}" && "${channels}" == *a* ]]
    return
  fi

  if command -v ffprobe >/dev/null 2>&1; then
    pix_fmt="$(ffprobe -v error -select_streams v:0 -show_entries stream=pix_fmt -of csv=p=0 "${logo}" 2>/dev/null || true)"
    pix_fmt="$(to_lower "${pix_fmt}")"
    [[ -n "${pix_fmt}" && "${pix_fmt}" == *a* ]]
    return
  fi

  return 1
}

run_logo_preflight() {
  local logo="$1"
  local dims=""
  local width=""
  local height=""
  local extension=""
  local ext_lower=""

  if ! command -v ffprobe >/dev/null 2>&1; then
    warn "ffprobe not found. Logo preflight skipped."
    return
  fi

  dims="$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0:s=x "${logo}" 2>/dev/null || true)"
  if [[ "${dims}" != *x* ]]; then
    record_logo_preflight_issue "Could not read dimensions for '${logo}'."
  else
    width="${dims%x*}"
    height="${dims#*x}"
    if is_integer "${width}" && is_integer "${height}"; then
      if (( width < LOGO_MIN_DIM || height < LOGO_MIN_DIM )); then
        record_logo_preflight_issue "Logo '${logo}' is only ${width}x${height}px (recommended: at least ${LOGO_MIN_DIM}px on both sides)."
      fi
      if (( width > height * LOGO_MAX_ASPECT || height > width * LOGO_MAX_ASPECT )); then
        record_logo_preflight_issue "Logo '${logo}' has an extreme aspect ratio (${width}:${height}); overlay may look distorted or tiny."
      fi
    else
      record_logo_preflight_issue "Unexpected logo dimensions for '${logo}': ${dims}"
    fi
  fi

  extension="${logo##*.}"
  ext_lower="$(to_lower "${extension}")"
  if [[ "${ext_lower}" == "png" ]] && ! logo_has_alpha_channel "${logo}"; then
    record_logo_preflight_issue "PNG logo '${logo}' seems to have no alpha channel. This often causes visible white backgrounds."
  fi
}

build_overlay_from_data_file() {
  local file="$1"
  local headline=""
  local bullet1=""
  local bullet2=""
  local ps=""
  local baujahr=""
  local preis=""
  local line raw_key raw_val key value lowered candidate existing
  local overlay_parts=()
  local legacy_parts=()
  local bullet_lines=()
  local is_duplicate="false"

  [[ -f "${file}" ]] || die "Data file not found: ${file}"

  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="$(trim_value "${line}")"
    [[ -z "${line}" ]] && continue
    [[ "${line}" == \#* ]] && continue

    if [[ "${line}" =~ ^([^:=]+)[:=][[:space:]]*(.*)$ ]]; then
      raw_key="${BASH_REMATCH[1]}"
      raw_val="${BASH_REMATCH[2]}"
    else
      if [[ "${line}" =~ ^[-*][[:space:]]*(.+)$ ]]; then
        value="$(trim_value "${BASH_REMATCH[1]}")"
        [[ -n "${value}" ]] && bullet_lines+=("${value}")
      fi
      continue
    fi

    key="$(normalize_data_key "${raw_key}")"
    value="$(trim_value "${raw_val}")"
    [[ -z "${value}" ]] && continue

    case "${key}" in
      ueberschrift|uberschrift|headline|title|h1|titel)
        headline="${value}"
        ;;
      bullet|bullet1|point1|slogan|tagline|claim)
        bullet1="${value}"
        ;;
      bullet2|point2|slogan2|tagline2|claim2)
        bullet2="${value}"
        ;;
      bullet3|point3|slogan3|tagline3|claim3)
        bullet_lines+=("${value}")
        ;;
      ps|leistung|horsepower)
        ps="${value}"
        ;;
      baujahr|jahr|erstzulassung|ez)
        baujahr="${value}"
        ;;
      preis|price|kaufpreis)
        preis="${value}"
        ;;
    esac
  done < "${file}"

  if [[ -n "${headline}" ]]; then
    overlay_parts+=("${headline}")
  fi

  for candidate in "${bullet1}" "${bullet2}" "${bullet_lines[@]}"; do
    candidate="$(trim_value "${candidate}")"
    [[ -n "${candidate}" ]] || continue

    is_duplicate="false"
    for existing in "${overlay_parts[@]}"; do
      if [[ "$(to_lower "${existing}")" == "$(to_lower "${candidate}")" ]]; then
        is_duplicate="true"
        break
      fi
    done
    if [[ "${is_duplicate}" == "true" ]]; then
      continue
    fi

    overlay_parts+=("${candidate}")
    if (( ${#overlay_parts[@]} >= 3 )); then
      break
    fi
  done

  if (( ${#overlay_parts[@]} > 0 )); then
    local web_result="${overlay_parts[0]}"
    local web_idx
    for ((web_idx = 1; web_idx < ${#overlay_parts[@]}; web_idx++)); do
      web_result="${web_result} | ${overlay_parts[web_idx]}"
    done
    printf '%s' "${web_result}"
    return 0
  fi

  if [[ -n "${ps}" ]]; then
    lowered="$(printf '%s' "${ps}" | tr '[:upper:]' '[:lower:]')"
    if [[ "${lowered}" != *ps* ]]; then
      ps="${ps} PS"
    fi
  fi

  if [[ -n "${baujahr}" ]]; then
    baujahr="Baujahr ${baujahr}"
  fi

  if [[ -n "${preis}" ]]; then
    lowered="$(printf '%s' "${preis}" | tr '[:upper:]' '[:lower:]')"
    if [[ "${lowered}" != preis* ]]; then
      preis="Preis ${preis}"
    fi
  fi

  [[ -n "${ps}" ]] && legacy_parts+=("${ps}")
  [[ -n "${baujahr}" ]] && legacy_parts+=("${baujahr}")
  [[ -n "${preis}" ]] && legacy_parts+=("${preis}")

  if [[ ${#legacy_parts[@]} -eq 0 ]]; then
    die "Data file '${file}' has no parsable values for Ueberschrift/Bullets or PS/Baujahr/Preis"
  fi

  local result="${legacy_parts[0]}"
  local i
  for ((i = 1; i < ${#legacy_parts[@]}; i++)); do
    result="${result} | ${legacy_parts[i]}"
  done
  printf '%s' "${result}"
}

logos=()
upload_override=""
demo_mode="false"
output_set_from_cli="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--input)
      [[ $# -ge 2 ]] || die "Missing value for $1"
      INPUT_VIDEO="$2"
      shift 2
      ;;
    -o|--output)
      [[ $# -ge 2 ]] || die "Missing value for $1"
      OUTPUT_VIDEO="$2"
      output_set_from_cli="true"
      shift 2
      ;;
    -t|--text)
      [[ $# -ge 2 ]] || die "Missing value for $1"
      OVERLAY_TEXT="$2"
      shift 2
      ;;
    -d|--data-file)
      [[ $# -ge 2 ]] || die "Missing value for $1"
      DATA_FILE="$2"
      shift 2
      ;;
    --fetch-id)
      [[ $# -ge 2 ]] || die "Missing value for $1"
      FETCH_ID="$2"
      shift 2
      ;;
    --fetch-url)
      [[ $# -ge 2 ]] || die "Missing value for $1"
      FETCH_URL="$2"
      shift 2
      ;;
    --fetch-script)
      [[ $# -ge 2 ]] || die "Missing value for $1"
      FETCH_SCRIPT="$2"
      shift 2
      ;;
    --fetch-max-bullets)
      [[ $# -ge 2 ]] || die "Missing value for $1"
      FETCH_MAX_BULLETS="$2"
      shift 2
      ;;
    --fetch-timeout)
      [[ $# -ge 2 ]] || die "Missing value for $1"
      FETCH_TIMEOUT="$2"
      shift 2
      ;;
    --fetch-ua)
      [[ $# -ge 2 ]] || die "Missing value for $1"
      FETCH_UA="$2"
      shift 2
      ;;
    -l|--logo)
      [[ $# -ge 2 ]] || die "Missing value for $1"
      logos+=("$2")
      shift 2
      ;;
    --logos)
      [[ $# -ge 2 ]] || die "Missing value for $1"
      IFS=',' read -r -a parsed <<< "$2"
      for item in "${parsed[@]}"; do
        [[ -n "${item}" ]] && logos+=("${item}")
      done
      shift 2
      ;;
    --demo)
      demo_mode="true"
      shift
      ;;
    --upload)
      upload_override="true"
      shift
      ;;
    --no-upload)
      upload_override="false"
      shift
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

require_cmd ffmpeg ffmpeg

if is_truthy "${demo_mode}"; then
  INPUT_VIDEO="${ROOT_DIR}/assets/videos/nexora-22222-ohne-logo.mp4"
  DATA_FILE="${ROOT_DIR}/fahrzeugdaten.txt"
  OVERLAY_TEXT=""
  logos=(
    "${ROOT_DIR}/Nexora/logos/auto-forge.png"
    "${ROOT_DIR}/Nexora/logos/finanz-forge.png"
  )
  if [[ "${output_set_from_cli}" != "true" ]]; then
    OUTPUT_VIDEO="${ROOT_DIR}/output/demo-repo.mp4"
  fi
  if [[ -z "${upload_override}" ]]; then
    upload_override="false"
  fi
  echo "Info: Demo mode enabled (repo sample input, data and logos)."
fi

if [[ ${#logos[@]} -eq 0 && -n "${LOGOS_DEFAULT}" ]]; then
  IFS=',' read -r -a parsed_env <<< "${LOGOS_DEFAULT}"
  for item in "${parsed_env[@]}"; do
    [[ -n "${item}" ]] && logos+=("${item}")
  done
fi

if [[ -n "${FETCH_ID}" || -n "${FETCH_URL}" ]]; then
  [[ -n "${FETCH_ID}" ]] || die "--fetch-url requires --fetch-id"
  [[ -n "${FETCH_URL}" ]] || die "--fetch-id requires --fetch-url"
  [[ -f "${FETCH_SCRIPT}" ]] || die "Fetch script not found: ${FETCH_SCRIPT}"
  [[ -x "${FETCH_SCRIPT}" ]] || die "Fetch script is not executable: ${FETCH_SCRIPT}"

  if [[ ! "${FETCH_MAX_BULLETS}" =~ ^[0-9]+$ ]] || (( FETCH_MAX_BULLETS < 1 )); then
    die "FETCH_MAX_BULLETS must be a positive integer (got '${FETCH_MAX_BULLETS}')"
  fi

  if [[ -z "${DATA_FILE}" ]]; then
    DATA_FILE="${ROOT_DIR}/fahrzeugdaten.txt"
    echo "Info: DATA_FILE not set. Using ${DATA_FILE} for fetched data."
  fi

  echo "Info: Running fetch step for ID ${FETCH_ID}..."
  "${FETCH_SCRIPT}" \
    --id "${FETCH_ID}" \
    --url "${FETCH_URL}" \
    --output "${DATA_FILE}" \
    --max-bullets "${FETCH_MAX_BULLETS}" \
    --timeout "${FETCH_TIMEOUT}" \
    --user-agent "${FETCH_UA}"
fi

if [[ -n "${OVERLAY_TEXT}" && -n "${DATA_FILE}" ]]; then
  echo "Info: OVERLAY_TEXT is set. DATA_FILE overlay generation is skipped."
elif [[ -n "${DATA_FILE}" ]]; then
  OVERLAY_TEXT="$(build_overlay_from_data_file "${DATA_FILE}")"
  echo "Info: Overlay text generated from ${DATA_FILE}: ${OVERLAY_TEXT}"
fi

[[ -n "${INPUT_VIDEO}" ]] || die "Missing input video. Use --input or INPUT_VIDEO in .env"
[[ -f "${INPUT_VIDEO}" ]] || die "Input video not found: ${INPUT_VIDEO}"

for logo in "${logos[@]}"; do
  [[ -f "${logo}" ]] || die "Logo not found: ${logo}"
done

if (( ${#logos[@]} > 0 )) && is_truthy "${LOGO_PREFLIGHT}"; then
  for logo in "${logos[@]}"; do
    run_logo_preflight "${logo}"
  done
  if (( logo_preflight_issue_count > 0 )); then
    warn "Logo preflight found ${logo_preflight_issue_count} issue(s)."
    if is_truthy "${PREFLIGHT_STRICT}"; then
      die "Preflight strict mode is enabled (PREFLIGHT_STRICT=true). Please fix the warnings above."
    fi
    warn "Continue anyway (set PREFLIGHT_STRICT=true to stop on warnings)."
  else
    echo "Info: Logo preflight passed."
  fi
fi

mkdir -p "$(dirname "${OUTPUT_VIDEO}")"

ffmpeg_cmd=(ffmpeg -y -hide_banner -loglevel info -i "${INPUT_VIDEO}")

for logo in "${logos[@]}"; do
  ffmpeg_cmd+=(-i "${logo}")
done

filter_parts=()
base_label="v0"

if [[ -n "${OVERLAY_TEXT}" ]]; then
  text_escaped="$(escape_drawtext "${OVERLAY_TEXT}")"
  drawtext_filter="[0:v]drawtext=text='${text_escaped}':fontsize=${TEXT_SIZE}:fontcolor=${TEXT_COLOR}:x=(w-text_w)/2:y=h-text_h-${TEXT_MARGIN_BOTTOM}:box=1:boxcolor=${TEXT_BOX_COLOR}:boxborderw=${TEXT_BOX_PADDING}"
  if [[ -n "${TEXT_FONT_FILE}" ]]; then
    drawtext_filter="${drawtext_filter}:fontfile=$(escape_filter_value "${TEXT_FONT_FILE}")"
  fi
  drawtext_filter="${drawtext_filter}[${base_label}]"
  filter_parts+=("${drawtext_filter}")
else
  filter_parts+=("[0:v]null[${base_label}]")
fi

final_label="${base_label}"
logo_input_idx=1
logo_idx=1

for _logo in "${logos[@]}"; do
  logo_label="logo${logo_idx}"
  next_label="vlogo${logo_idx}"
  y_expr="${LOGO_MARGIN}+$((${logo_idx}-1))*(${LOGO_SIZE}+${LOGO_SPACING})"

  filter_parts+=("[${logo_input_idx}:v]scale=${LOGO_SIZE}:${LOGO_SIZE}:force_original_aspect_ratio=decrease,pad=${LOGO_SIZE}:${LOGO_SIZE}:(ow-iw)/2:(oh-ih)/2:color=0x00000000[${logo_label}]")
  filter_parts+=("[${final_label}][${logo_label}]overlay=main_w-overlay_w-${LOGO_MARGIN}:${y_expr}[${next_label}]")

  final_label="${next_label}"
  logo_input_idx=$((logo_input_idx + 1))
  logo_idx=$((logo_idx + 1))
done

filter_complex="$(IFS=';'; echo "${filter_parts[*]}")"

ffmpeg_cmd+=(
  -filter_complex "${filter_complex}"
  -map "[${final_label}]"
  -map "0:a?"
  -c:v libx264
  -preset medium
  -crf 20
  -c:a copy
  -movflags +faststart
  "${OUTPUT_VIDEO}"
)

echo "Rendering video to ${OUTPUT_VIDEO}"
"${ffmpeg_cmd[@]}"
echo "Render complete."

upload_enabled="${UPLOAD_AFTER_RENDER}"
if [[ -n "${upload_override}" ]]; then
  upload_enabled="${upload_override}"
fi

if is_truthy "${upload_enabled}"; then
  [[ -n "${SFTP_HOST}" ]] || die "SFTP_HOST is required for upload"
  [[ -n "${SFTP_USER}" ]] || die "SFTP_USER is required for upload"
  require_cmd sftp

  remote_name="${SFTP_REMOTE_FILENAME:-$(basename "${OUTPUT_VIDEO}")}"
  validate_sftp_batch_value "${SFTP_REMOTE_DIR}" || die "SFTP_REMOTE_DIR contains forbidden characters"
  validate_sftp_batch_value "${remote_name}" || die "SFTP_REMOTE_FILENAME contains forbidden characters"

  batch_file="$(mktemp)"
  trap 'rm -f "${batch_file:-}"' EXIT

  {
    if [[ -n "${SFTP_REMOTE_DIR}" ]]; then
      printf 'cd "%s"\n' "${SFTP_REMOTE_DIR}"
    fi
    printf 'put "%s" "%s"\n' "${OUTPUT_VIDEO}" "${remote_name}"
  } > "${batch_file}"

  echo "Uploading via SFTP to ${SFTP_USER}@${SFTP_HOST}:${SFTP_REMOTE_DIR:-.}/${remote_name}"
  sftp -P "${SFTP_PORT}" -b "${batch_file}" "${SFTP_USER}@${SFTP_HOST}"
  rm -f "${batch_file}"
  trap - EXIT
  echo "Upload complete."
else
  echo "SFTP upload skipped."
fi
