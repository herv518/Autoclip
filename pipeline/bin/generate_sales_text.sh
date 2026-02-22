#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  ./bin/generate_sales_text.sh [--input-file file] [--facts-file file] [--out file] "bullets"

Examples:
  ./bin/generate_sales_text.sh "Kilometerstand: 45.000 km\nErstzulassung: 2023\nUnfallfrei"
  ./bin/generate_sales_text.sh --input-file Vehicle-Equipment/12345.txt --out Vehicle-Text/12345.txt
  ./bin/generate_sales_text.sh --input-file Vehicle-Equipment/12345.txt --facts-file Vehicle-Facts/12345.json --out Vehicle-Text/12345.txt

Env:
  AI_TEXT_PROVIDER   ollama (default) | openai
  AI_TEXT_MODEL      local model for Ollama (default: gemma3:2b)
  AI_TEXT_MAX_WORDS  max output words (default: 50)
  AI_TEXT_LINE_RANGE target line count hint (default: 3-4)
  AI_TEXT_AGENT_MODE 0/1, nutzt Wally/Trixi/Herbie Prompt-Workflow (default: 0)
  AI_TEXT_AGENT_PREFIX Prefix fuer Agentenmodus (default: Wally:)
  AI_TEXT_AGENT_DEBUG 0/1, schreibt internen Agenten-Workflow in Datei (default: 0)
  AI_TEXT_AGENT_DEBUG_FILE Pfad fuer Debug-Ausgabe (optional)
  AI_TEXT_AGENT_WALLY Rollenname Agent 1 (default: Wally)
  AI_TEXT_AGENT_TRIXI Rollenname Agent 2 (default: Trixi)
  AI_TEXT_AGENT_HERBIE Rollenname Agent 3 (default: Herbie)
  AI_TEXT_AGENT_STYLE Schreibstil fuer Agentenmodus
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
AI_TEXT_AGENT_MODE="${AI_TEXT_AGENT_MODE:-0}"
AI_TEXT_AGENT_PREFIX="${AI_TEXT_AGENT_PREFIX:-Wally:}"
AI_TEXT_AGENT_DEBUG="${AI_TEXT_AGENT_DEBUG:-0}"
AI_TEXT_AGENT_DEBUG_FILE="${AI_TEXT_AGENT_DEBUG_FILE:-}"
AI_TEXT_AGENT_WALLY="${AI_TEXT_AGENT_WALLY:-Wally}"
AI_TEXT_AGENT_TRIXI="${AI_TEXT_AGENT_TRIXI:-Trixi}"
AI_TEXT_AGENT_HERBIE="${AI_TEXT_AGENT_HERBIE:-Herbie}"
AI_TEXT_AGENT_STYLE="${AI_TEXT_AGENT_STYLE:-klar, direkt, mit einem Schuss Humor}"
OPENAI_MODEL="${OPENAI_MODEL:-gpt-4.1-mini}"
OPENAI_API_URL="${OPENAI_API_URL:-https://api.openai.com/v1/chat/completions}"
OPENAI_TEMPERATURE="${OPENAI_TEMPERATURE:-0.4}"
OPENAI_MAX_COMPLETION_TOKENS="${OPENAI_MAX_COMPLETION_TOKENS:-180}"

input_file=""
facts_file=""
output_file=""
declare -a text_parts=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--input-file)
      shift
      [[ $# -gt 0 ]] || die "Missing value for --input-file"
      input_file="$1"
      ;;
    --facts-file)
      shift
      [[ $# -gt 0 ]] || die "Missing value for --facts-file"
      facts_file="$1"
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

build_facts_context() {
  local src="$1"
  python3 - "$src" <<'PY'
import json
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
obj = json.loads(path.read_text(encoding="utf-8", errors="ignore"))

facts = obj.get("facts") or {}
quality = obj.get("quality") or {}
source = obj.get("source") or {}

def clean_text(value):
    if value is None:
        return ""
    txt = str(value).strip()
    txt = re.sub(r"\s+", " ", txt)
    return txt

def fmt_price(value):
    if value is None:
        return ""
    try:
        return f"{int(value):,}".replace(",", ".") + " EUR"
    except Exception:
        return ""

lines = []
id_value = clean_text(obj.get("id"))
if id_value:
    lines.append(f"ID: {id_value}")

make = clean_text(facts.get("marke"))
model = clean_text(facts.get("modell"))
if make:
    lines.append(f"Marke: {make}")
if model:
    lines.append(f"Modell: {model}")

km = facts.get("kilometerstand_km")
if isinstance(km, int):
    lines.append(f"Kilometerstand: {km:,} km".replace(",", "."))

ez = clean_text(facts.get("erstzulassung"))
if ez:
    lines.append(f"Erstzulassung: {ez}")

price = fmt_price(facts.get("preis_eur"))
if price:
    lines.append(f"Preis: {price}")

features = facts.get("top_features")
if isinstance(features, list) and features:
    lines.append("Top-Features:")
    count = 0
    for feature in features:
        feat = clean_text(feature)
        if not feat:
            continue
        lines.append(f"- {feat}")
        count += 1
        if count >= 6:
            break

status = clean_text(quality.get("status"))
if status:
    lines.append(f"Fakten-Qualitaet: {status}")

detail_match = quality.get("is_detail_match")
if detail_match is False:
    lines.append("Hinweis: Quelle ist evtl. keine Fahrzeug-Detailseite.")

match_url = clean_text(source.get("match_url"))
if match_url:
    lines.append(f"Quelle: {match_url}")

print("\n".join(lines).strip())
PY
}

facts_text=""
if [[ -n "$facts_file" ]]; then
  [[ -f "$facts_file" ]] || die "Facts file not found: $facts_file"
  facts_text="$(build_facts_context "$facts_file")"
fi

if [[ -z "$(trim_value "$source_text")" ]] && [[ -z "$(trim_value "$facts_text")" ]]; then
  die "No input found. Provide --input-file, --facts-file or positional text."
fi

build_prompt() {
  local input_text="$1"
  local facts_block="$2"

  if [[ -z "$(trim_value "$facts_block")" ]]; then
    facts_block="(Keine strukturierten Vehicle-Facts vorhanden.)"
  fi
  if [[ -z "$(trim_value "$input_text")" ]]; then
    input_text="(Keine Rohdaten vorhanden.)"
  fi

  if [[ "${AI_TEXT_AGENT_MODE:-0}" = "1" ]]; then
    if [[ "${AI_TEXT_AGENT_DEBUG:-0}" = "1" ]]; then
      cat <<EOF2
Du bist ${AI_TEXT_AGENT_WALLY}, der Autotexter fuer ein deutsches Autohaus.
Arbeite mit deiner Crew:
- ${AI_TEXT_AGENT_WALLY}: zerlegt Aufgabe in 3 Schritte
- ${AI_TEXT_AGENT_TRIXI}: schnellster Weg / pragmatischer Hack
- ${AI_TEXT_AGENT_HERBIE}: Sinn-Check, Vollstaendigkeit, keine erfundenen Fakten

Nutze NUR die Daten unten. Nichts erfinden.
Keine Emojis, keine Hashtags.
Finaler Text: maximal ${AI_TEXT_MAX_WORDS} Woerter, Ziel ${AI_TEXT_LINE_RANGE} Zeilen, Ton ${AI_TEXT_TONE}.
Schreibstil: ${AI_TEXT_AGENT_STYLE}.

WICHTIG: Antworte EXAKT in diesem Format:
[WALLY]
...deine 3 Schritte...
[/WALLY]
[TRIXI]
...schneller Weg/Hack...
[/TRIXI]
[HERBIE]
...Sinn-Check und fehlende Punkte...
[/HERBIE]
[FINAL]
${AI_TEXT_AGENT_PREFIX} ...finaler Fahrzeugtext...
[/FINAL]

Strukturierte Vehicle-Facts:
${facts_block}

Rohdaten:
${input_text}
EOF2
      return 0
    fi

    cat <<EOF2
Du bist ${AI_TEXT_AGENT_WALLY}, der Autotexter fuer ein deutsches Autohaus.
Arbeite intern mit deiner Crew, gib aber NUR das finale Ergebnis aus.

Interner Ablauf (nicht ausgeben):
1) ${AI_TEXT_AGENT_WALLY}: Aufgabe in 3 Schritte zerlegen
2) ${AI_TEXT_AGENT_TRIXI}: schnellster Weg + sinnvoller Hack
3) ${AI_TEXT_AGENT_HERBIE}: Sinn-Check, Vollstaendigkeit, keine erfundenen Fakten

Ausgabe-Regeln:
- Gib ausschliesslich den finalen Text aus, keine Analyse, keine Erklaerungen
- Erste Worte muessen exakt beginnen mit: ${AI_TEXT_AGENT_PREFIX}
- Maximal ${AI_TEXT_MAX_WORDS} Woerter
- Ziel: ${AI_TEXT_LINE_RANGE} kurze Zeilen
- Ton: ${AI_TEXT_TONE}
- Schreibstil: ${AI_TEXT_AGENT_STYLE}
- Keine Emojis, keine Hashtags
- Keine Halluzinationen
- Nur Daten verwenden, die unten stehen

Strukturierte Vehicle-Facts:
${facts_block}

Rohdaten:
${input_text}
EOF2
    return 0
  fi

  cat <<EOF2
Du bist Verkaufsprofi fuer ein deutsches Autohaus.
Schreibe einen verkaufsstarken Fahrzeugtext auf Deutsch.

Regeln:
- Maximal ${AI_TEXT_MAX_WORDS} Woerter
- Ziel: ${AI_TEXT_LINE_RANGE} kurze Zeilen
- Ton: ${AI_TEXT_TONE}
- Keine erfundenen Fakten
- Keine Emojis, keine Hashtags
- Konkrete Ausstattung nur nennen, wenn sie in den Daten steht

Strukturierte Vehicle-Facts:
${facts_block}

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

  payload="$(python3 - "$prompt" "$OPENAI_MODEL" "$OPENAI_TEMPERATURE" "$OPENAI_MAX_COMPLETION_TOKENS" <<'PY'
import json
import sys

prompt = sys.argv[1]
model = sys.argv[2]
temperature = float(sys.argv[3])
max_completion_tokens = int(sys.argv[4])

payload = {
    "model": model,
    "temperature": temperature,
    "max_completion_tokens": max_completion_tokens,
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
  python3 - \
    "$AI_TEXT_MAX_WORDS" \
    "$raw_text" \
    "$AI_TEXT_AGENT_MODE" \
    "$AI_TEXT_AGENT_PREFIX" \
    "$AI_TEXT_AGENT_DEBUG" \
    "$AI_TEXT_AGENT_DEBUG_FILE" <<'PY'
from datetime import datetime, timezone
import math
from pathlib import Path
import re
import sys

max_words = max(10, int(sys.argv[1]))
raw_original = sys.argv[2]
agent_mode = sys.argv[3] == "1"
agent_prefix = sys.argv[4].strip()
agent_debug = sys.argv[5] == "1"
agent_debug_file = sys.argv[6].strip()

raw = raw_original.replace("\r", "\n")
raw = re.sub(r"\x1b\[[0-9;?]*[ -/]*[@-~]", "", raw)
raw = re.sub(r"\x1b\][^\x07]*(?:\x07|\x1b\\)", "", raw)
raw = re.sub(r"[⠁-⣿]", "", raw)
raw = re.sub(r"[ \t]+\n", "\n", raw)
raw = re.sub(r"\n{3,}", "\n\n", raw).strip()

def extract_block(tag_name, text):
    m = re.search(
        rf"\[{re.escape(tag_name)}\]\s*(.*?)\s*\[/{re.escape(tag_name)}\]",
        text,
        flags=re.IGNORECASE | re.DOTALL,
    )
    if not m:
        return ""
    return m.group(1).strip()

agent_blocks = {
    "wally": extract_block("WALLY", raw),
    "trixi": extract_block("TRIXI", raw),
    "herbie": extract_block("HERBIE", raw),
    "final": extract_block("FINAL", raw),
}

base_text = raw
if agent_mode and agent_debug and agent_blocks["final"]:
    base_text = agent_blocks["final"]

lines = [ln.strip(" -\t") for ln in base_text.splitlines() if ln.strip()]
flat = " ".join(lines)
flat = re.sub(r"\s+", " ", flat).strip()
if not flat:
    print("")
    raise SystemExit

if agent_mode and agent_prefix:
    flat = re.sub(r'^[\"\']+', "", flat)
    flat = re.sub(rf"^{re.escape(agent_prefix)}\s*", "", flat, flags=re.IGNORECASE)
    flat = f"{agent_prefix} {flat}".strip()

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

final_out = "\n".join(rebuilt)

if agent_mode and agent_debug and agent_debug_file:
    try:
        report = []
        report.append(f"generated_at_utc: {datetime.now(timezone.utc).replace(microsecond=0).isoformat()}")
        report.append("mode: agent_debug")
        report.append("")
        report.append("[WALLY]")
        report.append(agent_blocks["wally"] or "(nicht vom Modell geliefert)")
        report.append("[/WALLY]")
        report.append("")
        report.append("[TRIXI]")
        report.append(agent_blocks["trixi"] or "(nicht vom Modell geliefert)")
        report.append("[/TRIXI]")
        report.append("")
        report.append("[HERBIE]")
        report.append(agent_blocks["herbie"] or "(nicht vom Modell geliefert)")
        report.append("[/HERBIE]")
        report.append("")
        report.append("[FINAL_RAW]")
        report.append(agent_blocks["final"] or "(kein [FINAL]-Block geliefert)")
        report.append("[/FINAL_RAW]")
        report.append("")
        report.append("[FINAL_NORMALIZED]")
        report.append(final_out)
        report.append("[/FINAL_NORMALIZED]")
        report.append("")
        report.append("[RAW_MODEL_OUTPUT]")
        report.append(raw)
        report.append("[/RAW_MODEL_OUTPUT]")
        dbg = Path(agent_debug_file)
        dbg.parent.mkdir(parents=True, exist_ok=True)
        dbg.write_text("\n".join(report).strip() + "\n", encoding="utf-8")
    except Exception:
        pass

print(final_out)
PY
}

prompt="$(build_prompt "$source_text" "$facts_text")"
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
