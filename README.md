Ein frisches, aufgeräumtes Tool für Verkaufs-Reels:  
[![macOS-only](https://img.shields.io/badge/macOS-only-blue.svg)](https://github.com/herv518/carclip)
**Bilder (pro Fahrzeug-ID) → Sonderausstattung → Kurztext → Voice → MP4-Reel**

## Ordnerstruktur

- `Input-Frames/<ID>/...jpg`  
  Deine Bilder pro Fahrzeug-ID (Ordnername = Autonummer).  

- `Vehicle-Equipment/<ID>.txt`  
  Scrape-/Fetcher-Ergebnis (Sonderausstattung + Meta).  

- `Vehicle-Text/<ID>.txt`  
  KI-Kurzbeschreibung (2–4 Sätze).  

- `Voice/<ID>.wav`  
  Voiceover (macOS „say“).  

- `Output/<ID>.mp4`  
  Finales Reel (H.264+AAC) mit Top-Bar + Marquee.  

- `Output/<ID>.webm`  
  Optionales Reel (VP9+Opus), kompatibel zum Fleetmarkt-Flow.  

Zusatz: `.cache/`, `.tmp/`, `metadata/ids.txt` (auto-generiert, alle IDs gesammelt).

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

- `metadata/ids.txt` (anpassbar über `IDS_FILE` in `config.sh`)

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
