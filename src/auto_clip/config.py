from __future__ import annotations

import json
import os
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class PathConfig:
    jobs_inbox: Path
    jobs_working: Path
    jobs_done: Path
    jobs_failed: Path
    build_root: Path
    site_root: Path


@dataclass(frozen=True)
class RenderConfig:
    frame_rate: float
    width: int
    height: int
    codec: str
    crf: int
    audio_bitrate: str


@dataclass(frozen=True)
class WatchConfig:
    poll_seconds: int


@dataclass(frozen=True)
class VoiceConfig:
    fallback_duration_seconds: int


@dataclass(frozen=True)
class AppConfig:
    project_root: Path
    config_path: Path
    paths: PathConfig
    render: RenderConfig
    watch: WatchConfig
    voice: VoiceConfig
    base_url: str
    ffmpeg_bin: str
    ffprobe_bin: str


def _resolve(base: Path, value: str) -> Path:
    return (base / value).resolve()


def load_config(config_path: str | None = None) -> AppConfig:
    raw_path = config_path or os.getenv("AUTO_CLIP_CONFIG", "auto-clip.config.json")
    path = Path(raw_path).expanduser().resolve()
    data = json.loads(path.read_text(encoding="utf-8"))
    base = path.parent

    paths = data["paths"]
    render = data["render"]
    watch = data["watch"]
    voice = data["voice"]

    return AppConfig(
        project_root=base,
        config_path=path,
        paths=PathConfig(
            jobs_inbox=_resolve(base, paths["jobs_inbox"]),
            jobs_working=_resolve(base, paths["jobs_working"]),
            jobs_done=_resolve(base, paths["jobs_done"]),
            jobs_failed=_resolve(base, paths["jobs_failed"]),
            build_root=_resolve(base, paths["build_root"]),
            site_root=_resolve(base, paths["site_root"]),
        ),
        render=RenderConfig(
            frame_rate=float(render["frame_rate"]),
            width=int(render["width"]),
            height=int(render["height"]),
            codec=str(render["codec"]),
            crf=int(render["crf"]),
            audio_bitrate=str(render["audio_bitrate"]),
        ),
        watch=WatchConfig(
            poll_seconds=int(watch["poll_seconds"]),
        ),
        voice=VoiceConfig(
            fallback_duration_seconds=int(voice["fallback_duration_seconds"]),
        ),
        base_url=os.getenv("AUTO_CLIP_BASE_URL", "http://localhost:8000").rstrip("/"),
        ffmpeg_bin=os.getenv("AUTO_CLIP_FFMPEG_BIN", "ffmpeg"),
        ffprobe_bin=os.getenv("AUTO_CLIP_FFPROBE_BIN", "ffprobe"),
    )
