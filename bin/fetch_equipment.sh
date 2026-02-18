#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ -f "$ROOT_DIR/config.sh" ]]; then
  # shellcheck source=/dev/null
  source "$ROOT_DIR/config.sh"
fi

for env_file in "${LOCAL_ENV_FILE:-}" ".mail.env" ".fax.env" ".watch.env"; do
  [[ -n "${env_file:-}" ]] || continue
  if [[ -f "$ROOT_DIR/$env_file" ]]; then
    # shellcheck source=/dev/null
    source "$ROOT_DIR/$env_file"
  fi
done

ID="${1:-}"
SOURCE_URL_INPUT="${2:-${SOURCE_URL:-}}"
EQUIP_DIR="${EQUIP_DIR:-Vehicle-Equipment}"
UA="${UA:-Mozilla/5.0}"
FETCH_TIMEOUT="${FETCH_TIMEOUT:-20}"
FETCH_MAX_PAGES="${FETCH_MAX_PAGES:-140}"
FETCH_MAX_LINKS_PER_PAGE="${FETCH_MAX_LINKS_PER_PAGE:-180}"

usage() {
  cat <<'USAGE'
Usage:
  ./bin/fetch_equipment.sh <ID> <URL_OR_BASE_URL>

Examples:
  ./bin/fetch_equipment.sh 12345 "https://example.com/dealer"
  ./bin/fetch_equipment.sh 12345 "https://example.com/fahrzeug/{ID}"
USAGE
}

if [[ -z "$ID" || -z "$SOURCE_URL_INPUT" ]]; then
  usage
  exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "[!] python3 fehlt - Fetch nicht möglich." >&2
  exit 1
fi

mkdir -p "$ROOT_DIR/$EQUIP_DIR"
OUT_FILE="$ROOT_DIR/$EQUIP_DIR/$ID.txt"

python3 - "$ID" "$SOURCE_URL_INPUT" "$OUT_FILE" "$UA" "$FETCH_TIMEOUT" "$FETCH_MAX_PAGES" "$FETCH_MAX_LINKS_PER_PAGE" <<'PY'
import datetime
import html
import re
import sys
from collections import deque
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urldefrag, urljoin, urlparse
from urllib.request import Request, urlopen

id_value = sys.argv[1].strip()
source_input = sys.argv[2].strip()
out_file = Path(sys.argv[3])
ua = sys.argv[4]
timeout = float(sys.argv[5])
max_pages = max(1, int(sys.argv[6]))
max_links_per_page = max(10, int(sys.argv[7]))

resolved_source = source_input.replace("{ID}", id_value)
timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")

if not resolved_source.startswith(("http://", "https://")):
    raise SystemExit(f"FETCH_ERROR: unsupported URL (need http/https): {resolved_source}")

if id_value.isdigit():
    id_pattern = re.compile(rf"(?<!\d){re.escape(id_value)}(?!\d)")
else:
    id_pattern = re.compile(re.escape(id_value), re.IGNORECASE)

binary_exts = {
    ".jpg", ".jpeg", ".png", ".gif", ".webp", ".svg", ".ico",
    ".pdf", ".zip", ".rar", ".7z",
    ".mp4", ".webm", ".mov", ".avi", ".mkv",
    ".mp3", ".wav", ".ogg",
    ".woff", ".woff2", ".ttf", ".eot",
    ".css", ".js", ".map", ".json", ".xml",
}


def domain_root(host: str) -> str:
    parts = [p for p in host.lower().split(".") if p]
    if len(parts) >= 2:
        return ".".join(parts[-2:])
    return host.lower()


base_parsed = urlparse(resolved_source)
base_host = (base_parsed.hostname or "").lower()
base_domain = domain_root(base_host) if base_host else ""


def allowed_host(host: str) -> bool:
    host_l = (host or "").lower()
    if not host_l:
        return False
    if host_l == base_host:
        return True
    if base_domain and host_l.endswith("." + base_domain):
        return True
    return False


def decode_bytes(raw: bytes, content_type: str) -> str:
    charset = None
    m = re.search(r"charset=([A-Za-z0-9._-]+)", content_type or "", flags=re.I)
    if m:
        charset = m.group(1)

    for enc in (charset, "utf-8", "cp1252", "latin-1"):
        if not enc:
            continue
        try:
            return raw.decode(enc, errors="replace")
        except Exception:
            pass
    return raw.decode("utf-8", errors="replace")


def fetch_html(url: str):
    req = Request(
        url,
        headers={
            "User-Agent": ua,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        },
    )
    with urlopen(req, timeout=timeout) as resp:
        raw = resp.read()
        ctype = resp.headers.get("Content-Type", "")
    return decode_bytes(raw, ctype), ctype


class LinkParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = []

    def handle_starttag(self, tag, attrs):
        if tag.lower() != "a":
            return
        for key, value in attrs:
            if key.lower() == "href" and value:
                self.links.append(value.strip())
                return


def normalize_link(current_url: str, href: str) -> str | None:
    if not href:
        return None
    if href.startswith(("mailto:", "tel:", "javascript:")):
        return None
    full = urljoin(current_url, href)
    full, _frag = urldefrag(full)
    p = urlparse(full)
    if p.scheme not in {"http", "https"}:
        return None
    if not allowed_host(p.hostname or ""):
        return None

    path_l = (p.path or "").lower()
    for ext in binary_exts:
        if path_l.endswith(ext):
            return None
    return full


def html_to_text(page_html: str) -> str:
    page = re.sub(r"(?is)<(script|style|noscript).*?>.*?</\1>", " ", page_html)
    page = re.sub(r"(?is)<[^>]+>", "\n", page)
    page = html.unescape(page)
    page = re.sub(r"[ \t\r\f\v]+", " ", page)
    page = re.sub(r"\n+", "\n", page)
    return page.strip()


def score_candidate(url: str, plain_text: str, hit_count: int) -> int:
    score = hit_count * 100
    url_l = url.lower()
    for token in ("fahrzeug", "auto", "angebote", "inventory", "vehicle", "detail", "gebrauchtwagen"):
        if token in url_l:
            score += 8
    if id_pattern.search(url):
        score += 40
    if hit_count <= 1 and not id_pattern.search(url):
        score -= 30
    # Favor pages where the ID is present repeatedly in visible text.
    if hit_count >= 3:
        score += 20
    return score


def extract_equipment_items(page_html: str):
    page = re.sub(r"(?is)<(script|style|noscript).*?>.*?</\1>", " ", page_html)
    items = []

    # 1) Structured list items
    for block in re.finditer(r"(?is)<(ul|ol)[^>]*>(.*?)</\1>", page):
        for li in re.findall(r"(?is)<li[^>]*>(.*?)</li>", block.group(2)):
            txt = re.sub(r"(?is)<[^>]+>", " ", li)
            txt = html.unescape(txt)
            txt = re.sub(r"\s+", " ", txt).strip(" \t\r\n-•*")
            if 3 <= len(txt) <= 140:
                items.append(txt)

    # 2) Text lines following known headings
    plain = html_to_text(page_html)
    lines = [ln.strip() for ln in plain.splitlines() if ln.strip()]
    heading_tokens = ("ausstattung", "sonderausstattung", "merkmale", "features")
    blocklist = ("datenschutz", "impressum", "cookie", "agb", "kontakt")

    for i, line in enumerate(lines):
        ll = line.lower()
        if any(h in ll for h in heading_tokens):
            for cand in lines[i + 1 : i + 40]:
                s = cand.strip(" -•*\t")
                if not (3 <= len(s) <= 140):
                    continue
                sl = s.lower()
                if any(b in sl for b in blocklist):
                    continue
                items.append(s)

    # Dedupe / normalize
    nav_stop = {
        "fahrzeuge", "unternehmen", "partner", "aktuelles", "bewertung", "anfahrt",
        "impressum", "datenschutz", "agb", "kontakt", "weiterlesen",
        "privatsphäre einstellungen", "normal", "false",
    }
    clean = []
    seen = set()
    for s in items:
        norm = re.sub(r"\s+", " ", s).strip(" \t\r\n-•*")
        if not norm:
            continue
        if norm.lower() in nav_stop:
            continue
        key = norm.lower()
        if key in seen:
            continue
        seen.add(key)
        clean.append(norm)
    return clean[:60]


def crawl_for_id(start_url: str):
    queue = deque([start_url])
    visited = set()
    scanned = 0
    candidates = []
    first_html = None

    while queue and scanned < max_pages:
        url = queue.popleft()
        if url in visited:
            continue
        visited.add(url)
        scanned += 1

        try:
            page_html, ctype = fetch_html(url)
        except Exception:
            continue

        if first_html is None:
            first_html = (url, page_html)

        # Accept HTML-ish responses only.
        if "html" not in (ctype or "").lower() and "<html" not in page_html[:500].lower():
            continue

        plain = html_to_text(page_html)
        hit_count = len(id_pattern.findall(plain))
        if hit_count > 0 or id_pattern.search(url):
            score = score_candidate(url, plain, hit_count)
            candidates.append((score, hit_count, url, page_html))

        parser = LinkParser()
        try:
            parser.feed(page_html)
        except Exception:
            parser.links = []

        added = 0
        for href in parser.links:
            normalized = normalize_link(url, href)
            if not normalized or normalized in visited:
                continue
            if id_pattern.search(normalized):
                queue.appendleft(normalized)
            else:
                queue.append(normalized)
            added += 1
            if added >= max_links_per_page:
                break

    if candidates:
        candidates.sort(key=lambda x: (x[0], x[1], len(x[2])), reverse=True)
        best = candidates[0]
        return {
            "match_url": best[2],
            "match_html": best[3],
            "hit_count": best[1],
            "pages_scanned": scanned,
            "search_mode": "crawl",
            "found": True,
        }

    if first_html:
        return {
            "match_url": first_html[0],
            "match_html": first_html[1],
            "hit_count": 0,
            "pages_scanned": scanned,
            "search_mode": "crawl",
            "found": False,
        }

    raise RuntimeError("Keine Seite abrufbar.")


def direct_fetch(url: str):
    page_html, _ctype = fetch_html(url)
    plain = html_to_text(page_html)
    hit_count = len(id_pattern.findall(plain))
    return {
        "match_url": url,
        "match_html": page_html,
        "hit_count": hit_count,
        "pages_scanned": 1,
        "search_mode": "direct",
        "found": hit_count > 0 or id_pattern.search(url) is not None,
    }


try:
    if id_pattern.search(resolved_source):
        result = direct_fetch(resolved_source)
    else:
        result = crawl_for_id(resolved_source)
except Exception as exc:
    print(f"FETCH_ERROR: {exc}", file=sys.stderr)
    sys.exit(1)

equipment = extract_equipment_items(result["match_html"])
if result["search_mode"] == "crawl" and not result["found"]:
    # Avoid writing unrelated homepage/navigation lines when no ID match was found.
    equipment = []

with out_file.open("w", encoding="utf-8", newline="\n") as fh:
    fh.write(f"ID: {id_value}\n")
    fh.write(f"SOURCE_INPUT: {source_input}\n")
    fh.write(f"MATCH_URL: {result['match_url']}\n")
    fh.write(f"SEARCH_MODE: {result['search_mode']}\n")
    fh.write(f"PAGES_SCANNED: {result['pages_scanned']}\n")
    fh.write(f"ID_TREFFER: {result['hit_count']}\n")
    fh.write(f"Zeitpunkt: {timestamp}\n")
    fh.write("---\n")
    if equipment:
        for row in equipment:
            fh.write(f"- {row}\n")
    elif result["found"]:
        fh.write("- Seite mit ID gefunden, aber keine klaren Ausstattungspunkte erkannt.\n")
    else:
        fh.write("- Keine Seite mit passender ID gefunden (Fallback auf Startseite).\n")

print(
    f"FETCH_OK mode={result['search_mode']} pages={result['pages_scanned']} "
    f"hits={result['hit_count']} url={result['match_url']}"
)
PY

line_count="$(wc -l < "$OUT_FILE" | tr -d ' ')"
echo "[+] Fetch OK: $OUT_FILE ($line_count Zeilen)"
