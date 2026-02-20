# Autoclip

## About

Autoclip: Bash-Skript für Auto-Videos mit FFmpeg – Text, Logos, SFTP.

Automatische Autoverkaufs-Videos mit FFmpeg - Text, Logos und optionaler SFTP-Upload.

## Inhalt

- `index.html` Landingpage
- `autoclip.sh` Bash-Skript fuer Video-Erstellung
- `.env.example` Beispiel-Konfiguration
- `fahrzeugdaten.txt` Beispiel fuer PS/Baujahr/Preis
- `assets/videos/` Demo-Videos (Nexora 22222)
- `assets/audio/` Voice-Dateien
- `screenshots/` Vorher/Nachher Screenshots
- `Nexora/` Quellmaterial, sauber sortiert:
  - `Nexora/inputframes/22222/` Fahrzeugbilder
  - `Nexora/metadata/22222_metadata.json` Metadaten
  - `Nexora/logos/` Branding-Logos

## Voraussetzungen

- `bash` (macOS/Linux)
- `ffmpeg`
- `sftp` (OpenSSH)

## Installation

1. Konfiguration anlegen:
   ```bash
   cp .env.example .env
   ```
2. `.env` mit deinen Werten anpassen.
3. Skript ausfuehrbar machen:
   ```bash
   chmod +x autoclip.sh
   ```

## Nutzung

Beispiel mit Daten-Datei und zwei Logos:

```bash
./autoclip.sh \
  --input assets/videos/nexora-22222-ohne-logo.mp4 \
  --data-file fahrzeugdaten.txt \
  --output output/final.mp4 \
  --logo Nexora/logos/auto-forge.png \
  --logo Nexora/logos/finanz-forge.png
```

Beispielinhalt von `fahrzeugdaten.txt`:

```txt
PS=150
Baujahr=2021
Preis=18.990 EUR
```

Optionaler manueller Text (ueberschreibt `--data-file` / `DATA_FILE`):

```bash
./autoclip.sh \
  --input assets/videos/nexora-22222-ohne-logo.mp4 \
  --output output/final.mp4 \
  --text "Top Angebot diese Woche" \
  --logo Nexora/logos/auto-forge.png \
  --logo Nexora/logos/finanz-forge.png
```

Upload aktivieren:

```bash
./autoclip.sh --input /pfad/zum/input.mp4 --upload
```

Oder permanent in `.env`:

```env
UPLOAD_AFTER_RENDER=true
```

## Hinweise

- Logos werden oben rechts gestapelt.
- Logo-Preflight prueft standardmaessig Transparenz, Groesse und Seitenverhaeltnis (`LOGO_PREFLIGHT=true`).
- Mit `PREFLIGHT_STRICT=true` stoppt das Skript bei Warnungen statt trotzdem weiterzurendern.
- Audio wird aus der Quelle uebernommen (`-map 0:a? -c:a copy`).
- Fuer produktive Uploads am besten SSH-Key-Authentifizierung verwenden.
