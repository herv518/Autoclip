# Autoclip

**Quick test: run `./autoclip.sh --demo` - it always uses the repo examples (`nexora-22222-ohne-logo.mp4` + `fahrzeugdaten.txt`). No setup required.**

## About

Autoclip is a Bash workflow for automatic car sales videos with FFmpeg, text overlays, logo placement, and optional secure SFTP upload.

## SEO Copy (English)

AutoClip is an automatic car sales video generation workflow for dealerships and automotive marketing teams. It uses FFmpeg to turn vehicle photos into professional auto sales videos with branded overlays, logo placement, dynamic text generation, AI-powered copywriting, and voiceover output. The pipeline supports structured processing by vehicle ID, repeatable batch rendering, and upload automation for finished assets, including FTPS/SFTP-style delivery workflows. It is built to create consistent, high-converting car sales videos for websites, marketplaces, and social media channels.

### SEO Keywords

- automatic car sales video generation
- auto dealership video automation
- FFmpeg car video creator
- professional auto sales videos
- automotive video overlays and logos
- AI vehicle description generation
- car ad text generation
- branded vehicle reel production
- WebM and MP4 car video rendering
- SFTP and FTPS video upload automation
- batch car inventory video creator
- dealership social media video tool

### Search-Friendly Feature Line

Create professional auto sales videos with overlays, logos, AI text generation, voiceover, FFmpeg rendering, and automated FTPS/SFTP uploads.

## Contents

- `index.html` landing page
- `autoclip.sh` Bash script for video creation
- `fetch_data.sh` web fetcher for ID -> headline/bullets
- `generate_sales_text.sh` AI text generator (local via Ollama, optional OpenAI)
- `setup.sh` setup helper (checks tools + pulls model)
- `.env.example` sample configuration
- `fahrzeugdaten.txt` sample file for PS/model year/price
- `assets/videos/` demo videos (Nexora 22222)
- `assets/audio/` voice files
- `screenshots/` before/after screenshots
- `Nexora/` source material, structured:
  - `Nexora/inputframes/22222/` vehicle photos
  - `Nexora/metadata/22222_metadata.json` metadata
  - `Nexora/logos/` branding logos

## Requirements

- `bash` (macOS/Linux)
- `ffmpeg`
- `sftp` (OpenSSH)
- `curl` (for web fetch)
- optional: `pup` (better HTML parsing, otherwise awk fallback)
- optional: `ollama` (for local AI text)

## Installation

1. Create config:
   ```bash
   cp .env.example .env
   ```
2. Adjust `.env` with your values.
3. Make scripts executable:
   ```bash
   chmod +x autoclip.sh fetch_data.sh setup.sh generate_sales_text.sh
   ```

## Local AI Text (Ollama)

Quick start:

```bash
./setup.sh
./generate_sales_text.sh "Mileage: 45,000 km\nFirst registration: 2023\nAccident-free"
```

The setup run checks `ollama` and pulls `gemma3:2b` by default (no automatic pull during render).

Recommended models for local vehicle copy:

- Fast/light: `gemma3:2b`
- Better style: `qwen2.5:7b`
- High quality, but much heavier: `gpt-oss:20b` (if available in your Ollama setup and you have enough RAM/VRAM)

Optional custom default model:

```bash
AI_TEXT_MODEL=qwen2.5:7b ./setup.sh
AI_TEXT_MODEL=qwen2.5:7b ./generate_sales_text.sh "Navigation, LED, first owner"
```

## Usage

Fixed demo command (always uses repo examples):

```bash
./autoclip.sh --demo
```

By default, this creates `output/demo-repo.mp4` from `assets/videos/nexora-22222-ohne-logo.mp4`, `fahrzeugdaten.txt`, and logos from `Nexora/logos/`.

Example with data file and two logos:

```bash
./autoclip.sh \
  --input assets/videos/nexora-22222-ohne-logo.mp4 \
  --data-file fahrzeugdaten.txt \
  --output output/final.mp4 \
  --logo Nexora/logos/auto-forge.png \
  --logo Nexora/logos/finanz-forge.png
```

Example content for `fahrzeugdaten.txt`:

```txt
PS=150
Baujahr=2021
Preis=18.990 EUR
```

Fetch web data first (ID -> URL -> `fahrzeugdaten.txt`):

```bash
./fetch_data.sh \
  --id 22222 \
  --url "https://your-company-site.tld/vehicle/{ID}" \
  --output fahrzeugdaten.txt
```

Then render as usual:

```bash
./autoclip.sh \
  --input assets/videos/nexora-22222-ohne-logo.mp4 \
  --data-file fahrzeugdaten.txt \
  --output output/final.mp4 \
  --logo Nexora/logos/auto-forge.png \
  --logo Nexora/logos/finanz-forge.png
```

Or in one step (fetch + render):

```bash
./autoclip.sh \
  --input assets/videos/nexora-22222-ohne-logo.mp4 \
  --data-file fahrzeugdaten.txt \
  --fetch-id 22222 \
  --fetch-url "https://your-company-site.tld/vehicle/{ID}" \
  --output output/final.mp4 \
  --logo Nexora/logos/auto-forge.png \
  --logo Nexora/logos/finanz-forge.png
```

Data-file format example (recommended keys):

```txt
headline=Your H1 title
bullet1=Strong value statement
bullet2=Financing available
```

Optional manual text (overrides `--data-file` / `DATA_FILE`):

```bash
./autoclip.sh \
  --input assets/videos/nexora-22222-ohne-logo.mp4 \
  --output output/final.mp4 \
  --text "Top offer this week" \
  --logo Nexora/logos/auto-forge.png \
  --logo Nexora/logos/finanz-forge.png
```

Enable upload:

```bash
./autoclip.sh --input /path/to/input.mp4 --upload
```

Or permanently in `.env`:

```env
UPLOAD_AFTER_RENDER=true
```

## Notes

- Logos are stacked at the top-right by default.
- Logo preflight checks transparency, size, and aspect ratio (`LOGO_PREFLIGHT=true`).
- With `PREFLIGHT_STRICT=true`, the script stops on warnings instead of continuing.
- Audio is copied from source (`-map 0:a? -c:a copy`).
- For production uploads, use SSH key authentication.

## Auto-Clip Tips (local page + video bridge)

For the internal recommendation page `auto-clip-tips.html`, use the local bridge server:

```bash
python3 auto_clip_tips_server.py
```

Then open in browser:

```txt
http://127.0.0.1:8787/auto-clip-tips.html
```

Or start directly:

```bash
./start_auto_clip_tips.sh
```

Used scripts:

- `build_auto_clip_tips_from_page.sh` collects page context and starts the video build.
- `build_auto_clip_tips_video.sh` generates the main video in `assets/videos/`.

Dependencies for tips build:

- Required: `python3`, `ffmpeg`, `ffprobe`, `curl`
- Optional: `ollama` (if AI rewrite is enabled), `say` (macOS TTS)
