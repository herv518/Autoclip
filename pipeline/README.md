A clean, structured tool for sales reels:  
[![macOS-only](https://img.shields.io/badge/macOS-only-blue.svg)](https://github.com/herv518/carclip)
**Images (per vehicle ID) -> equipment -> short copy -> voice -> MP4 reel**

## Folder Structure

- `Input-Frames/<ID>/...jpg`  
  Your images per vehicle ID (folder name = vehicle number).  

- `Vehicle-Equipment/<ID>.txt`  
  Scrape/fetcher output (equipment + meta data).  

- `Vehicle-Facts/<ID>.json`
  Structured facts from the fetched text (for example brand/model/km/first registration/price/top features).

- `Vehicle-Text/<ID>.txt`  
  AI short description (2-4 sentences).  

- `Voice/<ID>.wav`  
  Voiceover (macOS `say`).  

- `Output/<ID>.mp4`  
  Final reel (H.264+AAC) with top bar + marquee.  

- `Output/<ID>.webm`  
  Optional reel (VP9+Opus), compatible with the Fleetmarkt flow.  

Additional: `.cache/`, `.tmp/`, `metadata/ids.txt` (local/private), `metadata/ids.example.txt` (committable template).

## Quickstart (macOS)

1. Add images:  
   ```bash
   mkdir -p "Input-Frames/12345"
   # add images
   ```

2. Check configuration:  
   In `config.sh`: layout, speed, CTA, TTS voice, URL fetcher.

3. Install requirements:  
   Homebrew, FFmpeg, qrencode.

Note: clean repository, no keys and no real data, ready for demo use.

## Local AI Text (Ollama) or OpenAI

Default is local/offline via Ollama. Run once in repo root:

```bash
cd ..
./setup.sh
```

Test short copy directly:

```bash
./generate_sales_text.sh "Mileage: 45,000 km\nFirst registration: 2023\nAccident-free"
```

Enable in pipeline (`config.sh` or runtime env):

```bash
AI_TEXT_ENABLED=1
AI_TEXT_PROVIDER=ollama
AI_TEXT_MODEL=gemma3:2b
AI_TEXT_MAX_WORDS=50
AI_TEXT_AGENT_MODE=0
```

Example render with local model:

```bash
AI_TEXT_ENABLED=1 AI_TEXT_PROVIDER=ollama AI_TEXT_MODEL=qwen2.5:7b ./run.sh 12345
```

Optional 3-role agent workflow for stricter text review:

```bash
AI_TEXT_ENABLED=1 \
AI_TEXT_PROVIDER=ollama \
AI_TEXT_MODEL=qwen2.5:7b \
AI_TEXT_AGENT_MODE=1 \
AI_TEXT_AGENT_PREFIX="Text:" \
./run.sh 12345
```

Note: if `Vehicle-Facts/<ID>.json` exists, the generator uses those structured facts in addition to raw text. If data is missing, the rule-based fallback stays active.

Internal debug mode (shows role steps + final text in a file):

```bash
AI_TEXT_ENABLED=1 \
AI_TEXT_PROVIDER=ollama \
AI_TEXT_MODEL=qwen2.5:7b \
AI_TEXT_AGENT_MODE=1 \
AI_TEXT_AGENT_DEBUG=1 \
./run.sh 12345
```

Debug output location:

```bash
Vehicle-Text/12345.agent.debug.txt
```

Optional OpenAI mode instead of local model:

```bash
AI_TEXT_ENABLED=1 AI_TEXT_PROVIDER=openai OPENAI_API_KEY=... OPENAI_MODEL=gpt-4.1-mini ./run.sh 12345
```

## CLI Skeleton (new)

There is now a single wrapper command around the existing scripts:

```bash
./autoclip
./autoclip ui
./autoclip help
./autoclip shortcuts
./autoclip status
./autoclip agents show
./autoclip agents enable
./autoclip agents debug on
./autoclip agents model qwen2.5:7b
./autoclip agents prefix "Text:"
./autoclip agents style "clear, factual, concise"
./autoclip agents names Planner Optimizer Reviewer
./autoclip render 12345
./autoclip watch start
./autoclip watch status
./autoclip logs watch --lines 120
./autoclip logs run 12345 --follow
./autoclip jobs --limit 10
./autoclip jobs --watch --limit 10 --interval 2
./autoclip jobs --only-fail --missing-mp4 --limit 20
./autoclip jobs --state run --mp4 no --watch --interval 1
./autoclip dashboard watch --lines 20 --interval 2
./autoclip dashboard run 12345 --lines 20 --interval 2
./autoclip doctor
```

`./autoclip` starts an interactive prompt with history file in `.tmp/autoclip_history`.
`./autoclip ui` starts the full-screen TUI with header, job list, log panel, and command bar.
The prompt shows live `branch` + `watch` status (`autoclip[<branch>|watch:on/off]>`) and uses colored output in TTY terminals.
`./autoclip dashboard ...` shows a live panel view (status on top, logs below, exit with `Ctrl+C`).
Dashboard keybinds: `+/-` lines, `1` watch, `2` run, `r` refresh, `h` help on/off, `q` quit.
`./autoclip jobs ...` shows a compact job monitor (latest run logs + status).
Job filters: `--state all|ok|fail|run|warn|unk`, `--mp4 all|yes|no`, presets `--only-fail`, `--only-run`, `--missing-mp4`.
Job keybinds (watch mode): `1-9` select, `j/k` navigate, `+/-` limit, `f` state filter, `m` MP4 filter, `l` log snapshot, `s` status snapshot, `d` run dashboard, `h` help, `q` quit.
UI keybinds (`./autoclip ui`): `:` command mode, `1/2/3` source (watch/run/cmd), `j/k` job selection, `f/m` filter, `+/-` limit, `[/]` log lines, `r` refresh, `q` quit.

This skeleton orchestrates existing entrypoints only (`run.sh`, watcher, healthcheck); it does not replace them.
`./autoclip agents ...` is the central settings area for the agent workflow (mode/debug/model/prefix/names/style) and writes defaults to `config.sh`.

## Ops (structured)

Ops commands are grouped in `ops/`:

- `ops/start/` (start/stop watcher, single render, smoke test)
- `ops/maintenance/` (healthcheck, cleanup)
- `ops/setup/` (interactive SMTP/fax setup + mail test)
- `ops/deploy/` (preflight, bundle export)

Examples:

```bash
./ops/start/watcher_start.sh
./ops/start/watcher_stop.sh
./ops/start/render_once.sh 12345
./ops/maintenance/healthcheck.sh
./ops/setup/setup_auto_email.sh
./ops/deploy/preflight.sh
./ops/deploy/bundle.sh
```

Existing entrypoints (`./start`, `./run.sh`, `./bin/stop_watch.sh`) remain unchanged.

## Auto-Watch (Input-Frames -> Auto-Render)

As soon as images appear in `Input-Frames/<ID>/`, the watcher renders the video automatically.

Start:

```bash
./start
```

Stop:

```bash
./bin/stop_watch.sh
```

Logs:

- `watch_input_frames.log` (watcher)
- `.tmp/watch_runs/<ID>.log` (render run per vehicle)

Smoke test (without real rendering):

```bash
WATCH_DRY_RUN=1 WATCH_ONESHOT=1 ./bin/watch_input_frames.sh
```

## ID Registry + Vehicle Fetch

All IDs are collected in one shared file:

- `metadata/ids.txt` (local/private, not versioned; configurable via `IDS_FILE` in `config.sh`)
- `metadata/ids.example.txt` (versioned template)

Create local file once:

```bash
cp metadata/ids.example.txt metadata/ids.txt
```

Update IDs manually:

```bash
./bin/extract_ids.sh
```

Fetch vehicle data for one ID (direct URL or full-site crawl):

```bash
./bin/fetch_equipment.sh 12345 "https://example.com/dealer"
```

Fetch vehicle data for all IDs from registry:

```bash
./bin/fetch_equipment_from_ids.sh "https://example.com/dealer" metadata/ids.txt
```

### Optional: Team Upload Folder (Outlook/OneDrive/Dropbox)

You can watch an external folder.  
Structure: `<UPLOAD_INBOX_DIR>/<ID>/*.jpg`

Example `.watch.env` (local, do not commit):

```bash
UPLOAD_INBOX_DIR="/Path/to/Team-Uploads"
UPLOAD_ARCHIVE_DIR=".tmp/upload_archive"
UPLOAD_MOVE_TO_ARCHIVE=1
WATCH_POLL_SEC=5
WATCH_STABLE_SEC=8
```

Shortcut:

```bash
cp .watch.env.example .watch.env
```

Then:

1. Team member drops images into `Team-Uploads/12345/`.
2. Watcher copies images to `Input-Frames/12345/`.
3. Watcher starts `./run.sh 12345` automatically.

## Set TTS Voice (optional)

```bash
TTS_VOICE="${TTS_VOICE:-Anna}"
```

## Why This Works

- No subscription, no hard limits
- Works offline
- Voice `Anna` sounds great for German
- OpenAI is optional: set a key if needed, otherwise local flow still runs

## Optional: Auto-Fetch + QR Delivery

```bash
# Fetch per ID (optional, {ID} will be replaced)
SOURCE_URL="${SOURCE_URL:-https://example.com/fahrzeug/{ID}}"
FETCH_MAX_PAGES="${FETCH_MAX_PAGES:-140}"                # page limit for crawling
FETCH_MAX_LINKS_PER_PAGE="${FETCH_MAX_LINKS_PER_PAGE:-180}" # link limit per page

# Disable overlay for testing (image sequence only)
SHOW_OVERLAY="${SHOW_OVERLAY:-0}"

# Also generate WebM (Fleetmarkt-compatible)
GENERATE_WEBM="${GENERATE_WEBM:-1}"

# Print QR automatically
AUTO_PRINT_QR="${AUTO_PRINT_QR:-0}"
PRINTER_NAME="${PRINTER_NAME:-}"   # empty = default printer

# Send QR automatically by email (SMTP)
AUTO_EMAIL_QR="${AUTO_EMAIL_QR:-0}"
EMAIL_TO="${EMAIL_TO:-}"
SMTP_HOST="${SMTP_HOST:-}"
SMTP_PORT="${SMTP_PORT:-587}"
SMTP_USER="${SMTP_USER:-}"
SMTP_PASS="${SMTP_PASS:-}"

# Send QR automatically by fax (optional)
AUTO_FAX_QR="${AUTO_FAX_QR:-0}"
FAX_MODE="${FAX_MODE:-dry_run}"  # dry_run | email_gateway
```

## Email/SMTP Setup (important)

QR email delivery works only if the SMTP account allows SMTP login.

### Permanent Setup (recommended)

Run once per user:

```bash
cd ~/Desktop/carclip
./ops/setup/setup_auto_email.sh
```

What this does:

- asks for SMTP user, recipient, and SMTP host
- stores SMTP/app password in macOS Keychain
- writes local mail config to `.mail.env` (not committed)

After that, each render only needs:

```bash
./run.sh 12345
```

The app password stays valid until revoked or regenerated by the mail provider.

### Quick Test (recommended)

```bash
cd ~/Desktop/carclip
./ops/setup/mail_test_qr.sh 12345 test@example.com
```

The script prompts for SMTP password securely and does not store it in files.

### Common Outlook/Microsoft Error

If the log shows:

`535 5.7.139 Authentication unsuccessful, basic authentication is disabled`

Microsoft is blocking SMTP login with user/password for that account or tenant.

Fix options:

1. Enable Microsoft 365 `Authenticated SMTP` for that account (admin required), or
2. use another SMTP provider (for example Gmail with app password), or
3. disable mail delivery (`AUTO_EMAIL_QR=0`) and use QR locally.

### Security Note

- Do not commit real credentials in `config.sh`.
- For testing, use runtime variables or the `ops/setup/mail_test_qr.sh` prompt.
- Keep persistent local mail config only in `.mail.env` (already in `.gitignore`).

## Fax Setup (possible without hardware)

### Permanent Preparation

Once per user:

```bash
cd ~/Desktop/carclip
./ops/setup/setup_auto_fax.sh
```

This creates a local `.fax.env` (not in git) and enables `AUTO_FAX_QR=1`.

### Modes

- `dry_run`: no fax delivery, only a test file in `.tmp/fax_{ID}.txt`
- `email_gateway`: send via fax provider email address

### Normal Flow Afterwards

```bash
./run.sh 12345
```

If `FAX_MODE=dry_run`, log output looks like:  
`[+] Fax Dry-Run written: .tmp/fax_12345.txt`
