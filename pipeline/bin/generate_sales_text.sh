#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  ./bin/generate_sales_text.sh [--input-file file] [--out file] "bullets"

Examples:
  ./bin/generate_sales_text.sh "Kilometerstand: 45.000 km\nErstzulassung: 2023\nUnfallfrei"
  ./bin/generate_sales_text.sh --input-file Vehicle-Equipment/12345.txt --out Vehicle-Text/12345.txt

Env:
  AI_TEXT_PROVIDER   ollama (default) | openai
  AI_TEXT_MODEL      local model for Ollama (default: gemma3:2b)
  AI_TEXT_MAX_WORDS  max output words (default: 50)
  AI_TEXT_LINE_RANGE target line count hint (default: 3-4)
  OPENAI_MODEL       model for OpenAI provider (default: gpt-4.1-mini)
USAGE
}

die() {
  echo "Error: $*" >&2
  exit 1
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

AI_TEXT_PROVIDER="${AI_TEXT_PROVIDER:-ollama}"
AI_TEXT_MODEL="${AI_TEXT_MODEL:-gemma3:2b}"
AI_TEXT_MAX_WORDS="${AI_TEXT_MAX_WORDS:-50}"
AI_TEXT_LINE_RANGE="${AI_TEXT_LINE_RANGE:-3-4}"
AI_TEXT_TONE="${AI_TEXT_TONE:-enthusiastisch, ehrlich}"
OPENAI_MODEL="${OPENAI_MODEL:-gpt-4.1-mini}"
OPENAI_API_URL="${OPENAI_API_URL:-https://api.openai.com/v1/chat/completions}"
OPENAI_TEMPERATURE="${OPENAI_TEMPERATURE:-0.4}"

input_file=""
output_file=""
declare -a text_parts=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--input-file)
      shift
      [[ $# -gt 0 ]] || die "Missing value for --input-file"
      input_file="$1"
      ;;
    -o|--out)
      shift
      [[ $# -gt 0 ]] || die "Missing value for --out"
      output_file="$1"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      while [[ $# -gt 0 ]]; do
        text_parts+=("$1")
        shift
      done
      break
      ;;
    *)
      text_parts+=("$1")
      ;;
  esac
  shift
done

source_text=""
if [[ -n "$input_file" ]]; then
  [[ -f "$input_file" ]] || die "Input file not found: $input_file"
  source_text="$(cat "$input_file")"
fi

if (( ${#text_parts[@]} > 0 )); then
  if [[ -n "$source_text" ]]; then
    source_text+=$'\n'
  fi
  source_text+="${text_parts[*]}"
fi

source_text="$(printf '%s' "$source_text" | tr -d '\r')"
if [[ -z "$(trim_value "$source_text")" ]]; then
  die "No input text found. Provide positional text or --input-file."
fi

build_prompt() {
  local input_text="$1"
  cat <<EOF2
Du bist Verkaufsprofi fuer ein deutsches Autohaus.
Schreibe einen verkausfstarken Fahrzeugtext auf Deutsch.

Regeln:
- Maximal ${AI_TEXT_MAX_WORDS} Woerter
- Ziel: ${AI_TEXT_LINE_RANGE} kurze Zeilen
- Ton: ${AI_TEXT_TONE}
- Keine erfundenen Fakten
- Keine Emojis, keine Hashtags
- Konkrete Ausstattung nur nennen, wenn sie in den Daten steht

Fahrzeugdaten:
${input_text}

Gib nur den finalen Text aus.
EOF2
}

run_with_ollama() {
  local prompt="$1"

  require_cmd ollama

  if ! ollama list >/dev/null 2>&1; then
    die "Ollama daemon not reachable. Start Ollama and retry."
  fi

  if ! ollama show "$AI_TEXT_MODEL" >/dev/null 2>&1; then
    die "Model '$AI_TEXT_MODEL' not found locally. Run: ollama pull $AI_TEXT_MODEL"
  fi

  ollama run "$AI_TEXT_MODEL" "$prompt"
}

run_with_openai() {
  local prompt="$1"
  local payload=""
  local response=""

  require_cmd curl
  require_cmd python3

  if [[ -z "${OPENAI_API_KEY:-}" ]]; then
    die "OPENAI_API_KEY is required for AI_TEXT_PROVIDER=openai"
  fi

  payload="$(python3 - "$prompt" "$OPENAI_MODEL" "$OPENAI_TEMPERATURE" <<'PY'
import json
import sys

prompt = sys.argv[1]
model = sys.argv[2]
temperature = float(sys.argv[3])

payload = {
    "model": model,
    "temperature": temperature,
    "messages": [
        {
            "role": "user",
            "content": prompt,
        }
    ],
}

print(json.dumps(payload, ensure_ascii=False))
PY
)"

  response="$(curl -fsS "$OPENAI_API_URL" \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$payload")"

  python3 - "$response" <<'PY'
import json
import sys

obj = json.loads(sys.argv[1])
if "error" in obj:
    msg = obj.get("error", {}).get("message", "OpenAI request failed")
    raise SystemExit(msg)

choices = obj.get("choices") or []
if not choices:
    raise SystemExit("OpenAI returned no choices")

message = choices[0].get("message") or {}
content = message.get("content", "")
if isinstance(content, list):
    text_parts = []
    for part in content:
        if isinstance(part, dict) and part.get("type") == "text":
            text_parts.append(part.get("text", ""))
    content = "\n".join([p for p in text_parts if p])

if not isinstance(content, str) or not content.strip():
    raise SystemExit("OpenAI returned empty content")

print(content.strip())
PY
}

normalize_output() {
  local raw_text="$1"
  python3 - "$AI_TEXT_MAX_WORDS" "$raw_text" <<'PY'
import math
import re
import sys

max_words = max(10, int(sys.argv[1]))
raw = sys.argv[2].replace("\r", "\n")
lines = [ln.strip(" -\t") for ln in raw.splitlines() if ln.strip()]
flat = " ".join(lines)
flat = re.sub(r"\s+", " ", flat).strip()
if not flat:
    print("")
    raise SystemExit

tokens = flat.split()
if len(tokens) > max_words:
    tokens = tokens[:max_words]

line_count = 4 if len(tokens) >= 28 else 3
chunk_size = max(1, math.ceil(len(tokens) / line_count))
rebuilt = []
for idx in range(0, len(tokens), chunk_size):
    rebuilt.append(" ".join(tokens[idx : idx + chunk_size]))

rebuilt = [ln.strip() for ln in rebuilt if ln.strip()]
if len(rebuilt) > 4:
    rebuilt = rebuilt[:4]

while len(rebuilt) < 3 and len(rebuilt) > 0:
    i = max(range(len(rebuilt)), key=lambda x: len(rebuilt[x].split()))
    words = rebuilt[i].split()
    if len(words) < 3:
        break
    mid = max(1, len(words) // 2)
    rebuilt[i : i + 1] = [" ".join(words[:mid]), " ".join(words[mid:])]

print("\n".join(rebuilt))
PY
}

prompt="$(build_prompt "$source_text")"
raw_output=""

case "$AI_TEXT_PROVIDER" in
  ollama)
    if ! raw_output="$(run_with_ollama "$prompt")"; then
      exit 1
    fi
    ;;
  openai)
    if ! raw_output="$(run_with_openai "$prompt")"; then
      exit 1
    fi
    ;;
  *)
    die "Unsupported AI_TEXT_PROVIDER='$AI_TEXT_PROVIDER' (allowed: ollama, openai)"
    ;;
esac

final_text="$(normalize_output "$raw_output")"
if [[ -z "$(trim_value "$final_text")" ]]; then
  die "Model returned empty output"
fi

if [[ -n "$output_file" ]]; then
  mkdir -p "$(dirname "$output_file")"
  printf '%s\n' "$final_text" > "$output_file"
fi

printf '%s\n' "$final_text"
