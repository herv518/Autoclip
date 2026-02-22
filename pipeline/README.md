Ein frisches, aufgeräumtes Tool für Verkaufs-Reels:  
[![macOS-only](https://img.shields.io/badge/macOS-only-blue.svg)](https://github.com/herv518/carclip)
**Bilder (pro Fahrzeug-ID) → Sonderausstattung → Kurztext → Voice → MP4-Reel**

## Ordnerstruktur

- `Input-Frames/<ID>/...jpg`  
  Deine Bilder pro Fahrzeug-ID (Ordnername = Autonummer).  

- `Vehicle-Equipment/<ID>.txt`  
  Scrape-/Fetcher-Ergebnis (Sonderausstattung + Meta).  

- `Vehicle-Facts/<ID>.json`
  Strukturierte Fakten aus dem Fetch-Text (z. B. Marke/Modell/KM/EZ/Preis/Top-Features).

- `Vehicle-Text/<ID>.txt`  
  KI-Kurzbeschreibung (2–4 Sätze).  

- `Voice/<ID>.wav`  
  Voiceover (macOS „say“).  

- `Output/<ID>.mp4`  
  Finales Reel (H.264+AAC) mit Top-Bar + Marquee.  

- `Output/<ID>.webm`  
  Optionales Reel (VP9+Opus), kompatibel zum Fleetmarkt-Flow.  

Zusatz: `.cache/`, `.tmp/`, `metadata/ids.txt` (lokal/privat), `metadata/ids.example.txt` (commitbare Vorlage).

## Quickstart (macOS)

1. Bilder ablegen:  
   ```bash
   mkdir -p "Input-Frames/12345"
   # Bilder rein
   ```

2. Konfiguration prüfen:  
   In `config.sh`: Layout, Speed, CTA, TTS-Voice, URL-Fetcher.

3. Requirements installieren:  
   Homebrew, FFmpeg, qrencode.

Hinweis: Clean-Repo – keine Keys, keine realen Daten. Für Demo.

## KI-Text lokal (Ollama) oder OpenAI

Standard ist lokal/offline mit Ollama. Einmalig im Repo-Root:

```bash
cd ..
./setup.sh
```

Kurztext direkt testen:

```bash
./generate_sales_text.sh "Kilometerstand: 45.000 km\nErstzulassung: 2023\nUnfallfrei"
```

In der Pipeline aktivieren (`config.sh` oder Laufzeit-Env):

```bash
AI_TEXT_ENABLED=1
AI_TEXT_PROVIDER=ollama
AI_TEXT_MODEL=gemma3:2b
AI_TEXT_MAX_WORDS=50
AI_TEXT_AGENT_MODE=0
```

Beispiel Render mit lokalem Modell:

```bash
AI_TEXT_ENABLED=1 AI_TEXT_PROVIDER=ollama AI_TEXT_MODEL=qwen2.5:7b ./run.sh 12345
```

Optionaler 3-Rollen-Agenten-Workflow fuer strengeren Text-Check:

```bash
AI_TEXT_ENABLED=1 \
AI_TEXT_PROVIDER=ollama \
AI_TEXT_MODEL=qwen2.5:7b \
AI_TEXT_AGENT_MODE=1 \
AI_TEXT_AGENT_PREFIX="Text:" \
./run.sh 12345
```

Hinweis: Wenn `Vehicle-Facts/<ID>.json` vorhanden ist, nutzt der Generator neben dem Rohtext auch strukturierte Facts (Marke/Modell/KM/EZ/Preis/Features). Bei fehlenden Daten bleibt der Regeltext-Fallback aktiv.

Interner Debug-Modus (zeigt Rollen-Schritte + Finaltext in Datei):

```bash
AI_TEXT_ENABLED=1 \
AI_TEXT_PROVIDER=ollama \
AI_TEXT_MODEL=qwen2.5:7b \
AI_TEXT_AGENT_MODE=1 \
AI_TEXT_AGENT_DEBUG=1 \
./run.sh 12345
```

Debug-Ausgabe liegt dann in:

```bash
Vehicle-Text/12345.agent.debug.txt
```

Optional statt lokal via OpenAI:

```bash
AI_TEXT_ENABLED=1 AI_TEXT_PROVIDER=openai OPENAI_API_KEY=... OPENAI_MODEL=gpt-4.1-mini ./run.sh 12345
```

## CLI-Geruest (neu)

Es gibt jetzt ein einheitliches Kommando als Wrapper um die bestehenden Scripts:

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
./autoclip agents style "klar, sachlich, praezise"
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

`./autoclip` startet einen interaktiven Prompt mit History-Datei in `.tmp/autoclip_history`.
`./autoclip ui` startet die neue Vollbild-TUI mit Header, Jobliste, Log-Panel und Command-Bar.
Der Prompt zeigt live `branch` + `watch`-Status (`autoclip[<branch>|watch:on/off]>`) und nutzt farbige Ausgabe in TTY-Terminals.
`./autoclip dashboard ...` zeigt eine laufend aktualisierte Panel-Ansicht (Status oben, Logs unten, Exit mit `Ctrl+C`).
Dashboard-Keybinds: `+/-` Zeilen, `1` watch, `2` run, `r` refresh, `h` Hilfe ein/aus, `q` beenden.
`./autoclip jobs ...` zeigt einen kompakten Jobmonitor (letzte Run-Logs + Status).
Jobs-Filter: `--state all|ok|fail|run|warn|unk`, `--mp4 all|yes|no`, Presets `--only-fail`, `--only-run`, `--missing-mp4`.
Jobs-Keybinds (watch mode): `1-9` Auswahl, `j/k` Navigation, `+/-` Limit, `f` State-Filter, `m` MP4-Filter, `l` Log-Snapshot, `s` Status-Snapshot, `d` Run-Dashboard, `h` Hilfe, `q` Quit.
UI-Keybinds (`./autoclip ui`): `:` command mode, `1/2/3` source (watch/run/cmd), `j/k` Jobauswahl, `f/m` Filter, `+/-` Limit, `[/]` Log-Zeilen, `r` refresh, `q` quit.

Das Geruest orchestriert nur vorhandene Entrypoints (`run.sh`, Watcher, Healthcheck) und ersetzt sie nicht.
`./autoclip agents ...` ist der zentrale Einstellungsbereich fuer Agenten-Workflow (Mode/Debug/Model/Prefix/Namen/Stil) und schreibt Defaults in `config.sh`.

## Ops (strukturiert)

Die Ops-Kommandos sind in `ops/` sortiert:

- `ops/start/` (Watcher starten/stoppen, einzelner Render, Smoke-Test)
- `ops/maintenance/` (Healthcheck, Cleanup)
- `ops/setup/` (interaktive SMTP/Fax Einrichtung + Mail-Test)
- `ops/deploy/` (Preflight, Bundle-Export)

Beispiele:

```bash
./ops/start/watcher_start.sh
./ops/start/watcher_stop.sh
./ops/start/render_once.sh 12345
./ops/maintenance/healthcheck.sh
./ops/setup/setup_auto_email.sh
./ops/deploy/preflight.sh
./ops/deploy/bundle.sh
```

Die bisherigen Entrypoints (`./start`, `./run.sh`, `./bin/stop_watch.sh`) bleiben unverändert.

## Auto-Watch (Input-Frames -> Auto-Render)

Sobald Bilder in `Input-Frames/<ID>/` liegen, baut der Watcher automatisch das Video.

Starten:

```bash
./start
```

Stoppen:

```bash
./bin/stop_watch.sh
```

Logs:

- `watch_input_frames.log` (Watcher)
- `.tmp/watch_runs/<ID>.log` (Render-Lauf pro Fahrzeug)

Smoke-Test (ohne echten Render):

```bash
WATCH_DRY_RUN=1 WATCH_ONESHOT=1 ./bin/watch_input_frames.sh
```

## ID Registry + Fahrzeug-Fetch

Alle IDs werden in einer gemeinsamen Datei gesammelt:

- `metadata/ids.txt` (lokal/privat, nicht versioniert; anpassbar über `IDS_FILE` in `config.sh`)
- `metadata/ids.example.txt` (Versionierte Vorlage)

Einmal lokal anlegen:

```bash
cp metadata/ids.example.txt metadata/ids.txt
```

IDs manuell aktualisieren:

```bash
./bin/extract_ids.sh
```

Fahrzeugdaten für eine ID suchen (direkte URL oder ganze Website durchsuchen):

```bash
./bin/fetch_equipment.sh 12345 "https://example.com/dealer"
```

Fahrzeugdaten für alle IDs aus der Registry holen:

```bash
./bin/fetch_equipment_from_ids.sh "https://example.com/dealer" metadata/ids.txt
```

### Optional: Mitarbeiter-Upload-Ordner (Outlook/OneDrive/Dropbox)

Du kannst einen externen Ordner überwachen lassen.  
Struktur: `<UPLOAD_INBOX_DIR>/<ID>/*.jpg`

Beispiel `.watch.env` (lokal, nicht committen):

```bash
UPLOAD_INBOX_DIR="/Pfad/zu/Team-Uploads"
UPLOAD_ARCHIVE_DIR=".tmp/upload_archive"
UPLOAD_MOVE_TO_ARCHIVE=1
WATCH_POLL_SEC=5
WATCH_STABLE_SEC=8
```

Shortcut:

```bash
cp .watch.env.example .watch.env
```

Dann:

1. Mitarbeiter legt Bilder in `Team-Uploads/12345/`.
2. Watcher kopiert die Bilder nach `Input-Frames/12345/`.
3. Watcher startet automatisch `./run.sh 12345`.

## TTS-Stimme setzen (optional)

```bash
TTS_VOICE="${TTS_VOICE:-Anna}"
```

## Warum das rockt

- Kein Abo, kein Limit
- Funktioniert offline
- Stimme "Anna" klingt gut auf Deutsch
- Wenn jemand OpenAI will, einfach Key setzen – sonst läuft's eh

## Optional: Auto-Fetch + QR Versand

```bash
# Fetch pro ID (optional, {ID} wird ersetzt)
SOURCE_URL="${SOURCE_URL:-https://example.com/fahrzeug/{ID}}"
FETCH_MAX_PAGES="${FETCH_MAX_PAGES:-140}"                # Seiten-Limit beim Crawl
FETCH_MAX_LINKS_PER_PAGE="${FETCH_MAX_LINKS_PER_PAGE:-180}" # Link-Limit pro Seite

# Overlay beim Testen abschalten (nur Bildfolge prüfen)
SHOW_OVERLAY="${SHOW_OVERLAY:-0}"

# zusätzlich WebM erzeugen (wie Fleetmarkt)
GENERATE_WEBM="${GENERATE_WEBM:-1}"

# QR automatisch drucken
AUTO_PRINT_QR="${AUTO_PRINT_QR:-0}"
PRINTER_NAME="${PRINTER_NAME:-}"   # leer = Standarddrucker

# QR automatisch per E-Mail senden (SMTP)
AUTO_EMAIL_QR="${AUTO_EMAIL_QR:-0}"
EMAIL_TO="${EMAIL_TO:-}"
SMTP_HOST="${SMTP_HOST:-}"
SMTP_PORT="${SMTP_PORT:-587}"
SMTP_USER="${SMTP_USER:-}"
SMTP_PASS="${SMTP_PASS:-}"

# QR automatisch per Fax (optional)
AUTO_FAX_QR="${AUTO_FAX_QR:-0}"
FAX_MODE="${FAX_MODE:-dry_run}"  # dry_run | email_gateway
```

## E-Mail/SMTP Setup (wichtig)

Der QR-Mailversand funktioniert nur, wenn der SMTP-Account den Login per SMTP erlaubt.

### Dauerhaft einrichten (empfohlen)

Einmal pro Nutzer ausführen:

```bash
cd ~/Desktop/carclip
./ops/setup/setup_auto_email.sh
```

Was passiert dabei:

- fragt SMTP-User, Empfänger und SMTP-Host ab
- speichert das SMTP/App-Passwort im macOS-Keychain
- schreibt lokale Mail-Config nach `.mail.env` (wird nicht committed)

Danach reicht bei jedem Render:

```bash
./run.sh 12345
```

Das App-Passwort bleibt gültig, bis es beim Mail-Anbieter widerrufen oder neu erzeugt wird.

### Schneller Test (empfohlen)

```bash
cd ~/Desktop/carclip
./ops/setup/mail_test_qr.sh 12345 test@example.com
```

Das Skript fragt dein SMTP-Passwort verdeckt ab und speichert es nicht in Dateien.

### Häufiger Outlook/Microsoft Fehler

Wenn im Log steht:

`535 5.7.139 Authentication unsuccessful, basic authentication is disabled`

dann blockt Microsoft SMTP-Login mit User/Pass für dieses Konto/Tenant.

Lösung:

1. In Microsoft 365 `Authenticated SMTP` für das Konto aktivieren (Admin nötig), oder
2. anderen SMTP-Anbieter verwenden (z. B. Gmail mit App-Passwort), oder
3. Mailversand deaktivieren (`AUTO_EMAIL_QR=0`) und QR lokal nutzen.

### Sicherheits-Hinweis

- Keine realen Zugangsdaten in `config.sh` committen.
- Für Tests nur Laufzeit-Variablen oder das `ops/setup/mail_test_qr.sh`-Prompt nutzen.
- Dauerhafte lokale Mail-Config nur in `.mail.env` halten (ist in `.gitignore`).

## Fax Setup (ohne Gerät möglich)

### Dauerhaft vorbereiten

Einmal pro Nutzer:

```bash
cd ~/Desktop/carclip
./ops/setup/setup_auto_fax.sh
```

Das erstellt eine lokale `.fax.env` (nicht im Git) und aktiviert `AUTO_FAX_QR=1`.

### Modi

- `dry_run`: Kein Faxversand, nur Testdatei in `.tmp/fax_{ID}.txt`
- `email_gateway`: Versand an Fax-Provider per E-Mail-Adresse

### Normaler Ablauf danach

```bash
./run.sh 12345
```

Wenn `FAX_MODE=dry_run`, siehst du im Log z. B.:  
`[+] Fax Dry-Run geschrieben: .tmp/fax_12345.txt`
