# OPS Structure

This folder keeps operational commands grouped by purpose.

Main wrapper:

- `./autoclip`: unified CLI scaffold for render/watch/status/logs/doctor
- `./autoclip ui`: fullscreen TUI (jobs + logs + command runner)
- `./autoclip` (ohne Argumente): interaktiver Prompt mit Shortcuts und History
- Prompt zeigt Branch/Watcher-Status live und färbt Statusausgaben im Terminal
- `./autoclip dashboard ...`: live Status+Log Panel (watch/run logs, Refresh via `--interval`)
- Dashboard Keybinds: `+/-`, `1`, `2`, `r`, `h`, `q`
- `./autoclip jobs ...`: compact run-job monitor (snapshot + watch mode)
- Jobs Filters: `--state ...`, `--mp4 ...`, `--only-fail`, `--only-run`, `--missing-mp4`
- Jobs Keybinds: `1-9`, `j/k`, `+/-`, `f`, `m`, `l`, `s`, `d`, `h`, `q`

## Start

- `ops/start/watcher_start.sh`: starts the watcher (same behavior as `./start`)
- `ops/start/watcher_stop.sh`: stops the watcher
- `ops/start/render_once.sh <ID> [SOURCE_URL]`: runs one render job
- `ops/start/watch_smoke.sh`: one dry-run watcher scan

## Maintenance

- `ops/maintenance/healthcheck.sh`: checks runtime readiness and watcher state
- `ops/maintenance/tidy.sh [--apply] [--days N]`: cleans stale temp/log artifacts

`tidy.sh` is dry-run by default. Use `--apply` to actually delete.

## Setup

- `ops/setup/setup_auto_email.sh`: interactive SMTP/keychain setup
- `ops/setup/setup_auto_fax.sh`: interactive fax mode setup
- `ops/setup/mail_test_qr.sh`: one-off SMTP test run

## Data Fetch

- `bin/extract_ids.sh`: collects all IDs from `Input-Frames/` into one registry file
- `bin/fetch_equipment.sh`: fetches one ID from URL/template/base-site crawl
- `bin/fetch_equipment_from_ids.sh`: fetches all IDs from the registry file

## Deploy

- `ops/deploy/preflight.sh`: validates scripts and required tools
- `ops/deploy/bundle.sh [OUT_DIR]`: creates a clean demo bundle archive

The bundle excludes runtime data and local env files.
