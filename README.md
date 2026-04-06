# auto-clip

auto-clip ist eine saubere, lokale Video-Pipeline fuer Fahrzeug- oder Produktclips.

## Warum dieses Projekt so aufgebaut ist

Das Projekt trennt vier Dinge hart voneinander:

1. **Eingang**: Jeder Lauf startet mit genau einem Job-Manifest als JSON.
2. **Produktion**: Die Pipeline schreibt alle Artefakte deterministisch nach `dist/jobs/<job_id>/`.
3. **Qualitaet**: Vor dem Oeffnen nach aussen werden lokale und oeffentliche Artefakte geprueft.
4. **Auslieferung**: Das oeffentliche Bundle wird jedes Mal vollstaendig neu aus `dist/jobs/` aufgebaut.

Damit vermeidet das Projekt genau die klassischen Drift-Probleme:
- keine globale `ids.txt`
- kein uneindeutiger Launcher
- keine manuell gepflegte `public/`-Wahrheit
- kein zweiter oder dritter Producer fuer dieselben Daten

## Voraussetzungen

- macOS oder Linux
- Python 3.11+
- `ffmpeg` im Pfad

## Installation

```bash
cd auto-clip
python3 -m venv .venv
source .venv/bin/activate
pip install -e .
```

## Offizielle Befehle

```bash
./scripts/run_once.sh examples/job-beispiel.json
./scripts/watch.sh
./scripts/publish.sh
python3 -m auto_clip.cli doctor --job-id 10001
```

## Was ein Job-Manifest enthaelt

Ein Manifest beschreibt genau einen Lauf:

```json
{
  "job_id": "10001",
  "source": {
    "frame_dir": "examples/frames/10001",
    "voice_wav": null
  },
  "vehicle": {
    "title": "Skoda Karoq Sportline 2.0 TDI DSG",
    "price_eur": 28990,
    "year": 2022,
    "mileage_km": 42350,
    "fuel": "Diesel",
    "power_hp": 150,
    "color": "Schwarz",
    "transmission": "Automatik",
    "listing_url": "https://beispiel.de/fahrzeuge/10001"
  }
}
```

## Ergebnis

Nach einem erfolgreichen Lauf liegen die Dateien hier:

- `dist/jobs/<job_id>/metadata.json`
- `dist/jobs/<job_id>/content/narration.txt`
- `dist/jobs/<job_id>/audio/narration.wav`
- `dist/jobs/<job_id>/video/<job_id>.mp4`
- `dist/public/index.html`
- `dist/public/data/catalog.json`
- `dist/public/data/<job_id>.json`
- `dist/public/videos/<job_id>.mp4`

## Watch-Modus

Der Watcher beobachtet `jobs/inbox/*.json`. Jeder Fund wird atomar nach `jobs/working/` verschoben, verarbeitet und danach nach `jobs/done/` oder `jobs/failed/` archiviert.

## Lokale Vorschau

```bash
python3 -m http.server -d dist/public 8000
```

Danach im Browser aufrufen:

```text
http://localhost:8000/?job=10001
```
