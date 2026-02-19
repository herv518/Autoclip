# Autoclip

## About

Autoclip: Bash-Skript für Auto-Videos mit FFmpeg – Text, Logos, SFTP.

Automatische Autoverkaufs-Videos mit FFmpeg - Text, Logos und optionaler SFTP-Upload.

## Inhalt

- `index.html` Landingpage
- `autoclip.sh` Bash-Skript fuer Video-Erstellung
- `.env.example` Beispiel-Konfiguration
- `logos/` Beispiel-Logos
- `screenshots/` Platzhalter fuer Video-Screenshots

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

Beispiel mit Text und zwei Logos:

```bash
./autoclip.sh \
  --input /pfad/zum/input.mp4 \
  --output output/final.mp4 \
  --text "Top Angebot diese Woche" \
  --logo logos/placeholder.png \
  --logo logos/finance-sample.png
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
- Audio wird aus der Quelle uebernommen (`-map 0:a? -c:a copy`).
- Fuer produktive Uploads am besten SSH-Key-Authentifizierung verwenden.
