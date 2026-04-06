from __future__ import annotations

import shutil
import wave
from pathlib import Path

from auto_clip.config import AppConfig
from auto_clip.fs_utils import ensure_dir


def _create_silence_wav(target: Path, duration_seconds: int, sample_rate: int = 44100) -> None:
    ensure_dir(target.parent)
    frame_count = duration_seconds * sample_rate
    with wave.open(str(target), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(sample_rate)
        handle.writeframes(b"\x00\x00" * frame_count)


def prepare_audio(
    *,
    config: AppConfig,
    source_wav: Path | None,
    target_wav: Path,
    narration_text: str,
) -> dict:
    ensure_dir(target_wav.parent)
    if source_wav and source_wav.exists():
        shutil.copy2(source_wav, target_wav)
        return {
            "provider": "extern",
            "duration_seconds": None,
            "note": "Vorhandene WAV-Datei uebernommen.",
        }

    wortzahl = max(len(narration_text.split()), 1)
    fallback_duration = max(config.voice.fallback_duration_seconds, round(wortzahl / 2))
    _create_silence_wav(target_wav, fallback_duration)
    return {
        "provider": "stille_fallback",
        "duration_seconds": fallback_duration,
        "note": "Kein TTS-Provider konfiguriert; stille WAV als Render-Basis erzeugt.",
    }
