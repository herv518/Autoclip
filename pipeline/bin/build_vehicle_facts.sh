#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  ./bin/build_vehicle_facts.sh --id 12345 --input-file Vehicle-Equipment/12345.txt --out Vehicle-Facts/12345.json

Options:
  -i, --id           Vehicle ID (optional if present in input file)
  -f, --input-file   Source equipment text file
  -o, --out          Output JSON file (optional; prints to stdout if omitted)
  -h, --help         Show this help
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

vehicle_id=""
input_file=""
output_file=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--id)
      shift
      [[ $# -gt 0 ]] || die "Missing value for --id"
      vehicle_id="$1"
      ;;
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
    *)
      die "Unknown option: $1"
      ;;
  esac
  shift
done

[[ -n "$input_file" ]] || die "Missing --input-file"
[[ -f "$input_file" ]] || die "Input file not found: $input_file"
if [[ -n "$vehicle_id" ]] && [[ ! "$vehicle_id" =~ ^[0-9]+$ ]]; then
  die "Vehicle ID must be numeric: $vehicle_id"
fi

require_cmd python3

if [[ -n "$output_file" ]]; then
  mkdir -p "$(dirname "$output_file")"
fi

json_output="$(python3 - "$vehicle_id" "$input_file" <<'PY'
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlparse

id_arg = sys.argv[1].strip()
input_path = Path(sys.argv[2])
raw = input_path.read_text(encoding="utf-8", errors="ignore")
lines = [ln.rstrip("\n") for ln in raw.splitlines()]

headers = {}
bullets = []

for line in lines:
    m = re.match(r"^([A-Z0-9_]+):\s*(.*)$", line.strip())
    if m:
        headers[m.group(1).upper()] = m.group(2).strip()
        continue
    b = re.match(r"^\s*[-*•]\s*(.+?)\s*$", line)
    if b:
        bullets.append(b.group(1).strip())

vehicle_id = id_arg or headers.get("ID", "")
if vehicle_id and not re.fullmatch(r"\d+", vehicle_id):
    vehicle_id = ""

source_input = headers.get("SOURCE_INPUT", "")
match_url = headers.get("MATCH_URL", headers.get("URL", ""))
search_mode = headers.get("SEARCH_MODE", "")

def safe_int(value):
    if value is None:
        return None
    s = str(value).strip()
    if not s:
        return None
    if not re.fullmatch(r"-?\d+", s):
        return None
    try:
        return int(s)
    except ValueError:
        return None

pages_scanned = safe_int(headers.get("PAGES_SCANNED"))
id_hits = safe_int(headers.get("ID_TREFFER"))

def parse_number(num_text):
    digits = re.sub(r"\D+", "", num_text or "")
    if not digits:
        return None
    try:
        return int(digits)
    except ValueError:
        return None

def canonical_registration(text):
    # dd.mm.yyyy -> yyyy-mm
    m = re.search(r"\b([0-3]?\d)[./]([01]?\d)[./]((?:19|20)\d{2})\b", text)
    if m:
        year = m.group(3)
        month = int(m.group(2))
        return f"{year}-{month:02d}"
    # mm/yyyy -> yyyy-mm
    m = re.search(r"\b([01]?\d)[./]((?:19|20)\d{2})\b", text)
    if m:
        month = int(m.group(1))
        year = m.group(2)
        if 1 <= month <= 12:
            return f"{year}-{month:02d}"
    # plain year
    m = re.search(r"\b((?:19|20)\d{2})\b", text)
    if m:
        return m.group(1)
    return ""

def extract_kilometer(candidates):
    for text in candidates:
        for m in re.finditer(r"([0-9][0-9\.\s]{1,14})\s*km\b", text, flags=re.IGNORECASE):
            km = parse_number(m.group(1))
            if km is not None and 1 <= km <= 900000:
                return km
    return None

def extract_price_eur(candidates):
    # Prefer price-labeled lines.
    labeled = []
    generic = []
    for text in candidates:
        if re.search(r"(preis|vk|kaufpreis)", text, flags=re.IGNORECASE):
            labeled.append(text)
        else:
            generic.append(text)

    def scan(texts):
        for text in texts:
            for m in re.finditer(
                r"([0-9][0-9\.\s]{2,14})(?:,[0-9]{2})?\s*(?:€|eur)\b",
                text,
                flags=re.IGNORECASE,
            ):
                price = parse_number(m.group(1))
                if price is not None and 300 <= price <= 1000000:
                    return price
        return None

    price = scan(labeled)
    if price is not None:
        return price
    return scan(generic)

def parse_make_model_from_url(url, vid):
    if not url:
        return ("", "")
    path = urlparse(url).path or ""
    slug = path.rstrip("/").split("/")[-1]
    slug = re.sub(r"\.html?$", "", slug, flags=re.IGNORECASE)
    if not slug:
        return ("", "")

    if vid:
        slug = re.sub(rf"-{re.escape(vid)}$", "", slug)
    slug = slug.strip("-_")
    if not slug:
        return ("", "")

    parts = [p for p in re.split(r"[-_]+", slug) if p]
    if not parts:
        return ("", "")

    multiword_makes = {
        ("alfa", "romeo"),
        ("aston", "martin"),
        ("land", "rover"),
        ("mercedes", "benz"),
        ("rolls", "royce"),
    }

    def nice_token(token):
        token = token.strip()
        if not token:
            return ""
        lower = token.lower()
        acronyms = {
            "gti", "gtd", "gte", "tdi", "tsi", "fsi", "dsg",
            "awd", "fwd", "rwd", "suv", "ev", "phev", "hybrid",
            "4x4", "4wd", "abs", "esp", "led", "navi",
        }
        if lower in acronyms:
            return lower.upper()
        if re.fullmatch(r"\d+[a-z]{0,3}", lower):
            return lower.upper()
        return lower.capitalize()

    if len(parts) >= 2 and tuple(parts[:2]) in multiword_makes:
        make_parts = parts[:2]
        model_parts = parts[2:]
    else:
        make_parts = parts[:1]
        model_parts = parts[1:]

    make = " ".join(nice_token(p) for p in make_parts).strip()
    model = " ".join(nice_token(p) for p in model_parts).strip()
    return (make, model)

def feature_candidates_from_bullets(items):
    drop_substrings = (
        "fahrzeuge", "fahrzeugsuche", "unternehmen", "partner", "aktuelles",
        "bewertung", "anfahrt", "impressum", "datenschutz", "agb", "kontakt",
        "telefon", "probefahrt", "zwischenverkauf", "schreibfehler", "wir freuen uns",
        "ansprechpartner", "normal", "false", "status", "quelle", "url", "id:",
    )
    metric_tokens = (
        "kilometer", "erstzulassung", "fahrzeugtyp", "motor", "farbe",
        "getriebe", "herkunft", "umweltplakette", "effizienzklasse", "kraftstoffverb",
        "preis", "euro", "eur", "id treffer", "seiten", "zeitpunkt",
    )

    out = []
    seen = set()
    for raw_item in items:
        item = re.sub(r"\s+", " ", raw_item).strip(" -\t")
        if not item:
            continue
        low = item.lower()
        if len(item) < 3 or len(item) > 120:
            continue
        if any(token in low for token in drop_substrings):
            continue
        if any(token in low for token in metric_tokens):
            continue
        if re.fullmatch(r"[0-9\.\s]+", low):
            continue
        if low in seen:
            continue
        seen.add(low)
        out.append(item)
    return out

make, model = parse_make_model_from_url(match_url, vehicle_id)

header_texts = [f"{k}: {v}" for k, v in headers.items() if v]
km = extract_kilometer(bullets + header_texts)

ez = ""
for candidate in bullets + header_texts:
    if re.search(r"erstzulassung", candidate, flags=re.IGNORECASE):
        ez = canonical_registration(candidate)
        if ez:
            break
if not ez:
    for candidate in bullets:
        ez = canonical_registration(candidate)
        if ez:
            break

price = extract_price_eur(bullets + header_texts)
features = feature_candidates_from_bullets(bullets)[:8]

required = {
    "marke": bool(make),
    "modell": bool(model),
    "kilometerstand_km": km is not None,
    "erstzulassung": bool(ez),
    "preis_eur": price is not None,
    "top_features": len(features) >= 1,
}
missing_required = [key for key, ok in required.items() if not ok]

is_detail_match = bool(match_url and re.search(r"/fahrzeugangebote/.+-\d+\.html?$", match_url, flags=re.IGNORECASE))

status = "complete" if not missing_required else "partial"
if len(missing_required) >= 4:
    status = "insufficient"

result = {
    "id": vehicle_id,
    "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
    "source": {
        "input_file": str(input_path),
        "source_input": source_input,
        "match_url": match_url,
        "search_mode": search_mode,
        "pages_scanned": pages_scanned,
        "id_treffer": id_hits,
    },
    "facts": {
        "marke": make,
        "modell": model,
        "kilometerstand_km": km,
        "erstzulassung": ez,
        "preis_eur": price,
        "top_features": features,
    },
    "quality": {
        "status": status,
        "is_complete": not missing_required,
        "is_detail_match": is_detail_match,
        "missing_required": missing_required,
    },
}

print(json.dumps(result, ensure_ascii=False, indent=2))
PY
)"

if [[ -n "$output_file" ]]; then
  printf '%s\n' "$json_output" > "$output_file"
  echo "$output_file"
else
  printf '%s\n' "$json_output"
fi
