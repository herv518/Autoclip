from __future__ import annotations

import json
import logging
from pathlib import Path

from auto_clip.config import AppConfig
from auto_clip.fs_utils import atomic_write_json, atomic_write_text, ensure_dir, list_frame_files, relative_to
from auto_clip.models import JobRequest, utc_now_iso
from auto_clip.publish import build_public_bundle
from auto_clip.qa import audit_job_directory, audit_public_bundle
from auto_clip.steps.ingest import load_job_request
from auto_clip.steps.render import render_video
from auto_clip.steps.script_text import build_content
from auto_clip.steps.voice import prepare_audio

logger = logging.getLogger(__name__)


def _job_dir(config: AppConfig, job_id: str) -> Path:
    return config.paths.build_root / "jobs" / job_id


def process_manifest(manifest_path: Path, config: AppConfig) -> dict:
    logger.info("Starte Lauf fuer Manifest %s", manifest_path)
    request = load_job_request(manifest_path)
    return process_request(request, manifest_path, config)


def process_request(request: JobRequest, manifest_path: Path, config: AppConfig) -> dict:
    job_dir = _job_dir(config, request.job_id)
    ensure_dir(job_dir)
    atomic_write_json(job_dir / "request.json", request.to_dict())

    frame_dir = request.resolved_frame_dir(config.project_root)
    if not frame_dir.exists():
        raise FileNotFoundError(f"Frame-Ordner nicht gefunden: {frame_dir}")

    frame_files = list_frame_files(frame_dir)
    if not frame_files:
        raise FileNotFoundError(f"Keine Bilddateien im Frame-Ordner gefunden: {frame_dir}")

    content = build_content(request)
    content_dir = job_dir / "content"
    audio_dir = job_dir / "audio"
    video_dir = job_dir / "video"
    ensure_dir(content_dir)
    ensure_dir(audio_dir)
    ensure_dir(video_dir)

    narration_file = content_dir / "narration.txt"
    atomic_write_text(narration_file, content["narration"] + "\n")

    source_wav = request.resolved_voice_wav(config.project_root)
    audio_file = audio_dir / "narration.wav"
    voice_report = prepare_audio(
        config=config,
        source_wav=source_wav,
        target_wav=audio_file,
        narration_text=content["narration"],
    )
    atomic_write_json(audio_dir / "voice.json", voice_report)

    render_result = render_video(
        config=config,
        frame_files=frame_files,
        audio_file=audio_file,
        job_video_dir=video_dir,
        job_id=request.job_id,
    )

    metadata = {
        "schema_version": "v2",
        "created_at": utc_now_iso(),
        "job_id": request.job_id,
        "manifest_path": relative_to(manifest_path, config.project_root),
        "vehicle": request.to_dict()["vehicle"],
        "content": content,
        "artifacts": {
            "narration_path": relative_to(narration_file, config.project_root),
            "audio_path": relative_to(audio_file, config.project_root),
            "video_path": relative_to(render_result["video_file"], config.project_root),
            "poster_path": relative_to(render_result["poster_file"], config.project_root),
        },
        "render": {
            "frame_count": len(frame_files),
            "staged_frame_count": render_result["staged_frame_count"],
            "frame_rate": config.render.frame_rate,
            "width": config.render.width,
            "height": config.render.height,
        },
        "provenance": {
            "generator": "auto-clip",
            "base_url": config.base_url,
            "source_frame_dir": relative_to(frame_dir, config.project_root),
        },
        "qa": {},
    }

    atomic_write_json(job_dir / "metadata.json", metadata)

    local_audit = audit_job_directory(job_dir)
    metadata["qa"]["local"] = local_audit
    atomic_write_json(job_dir / "metadata.json", metadata)
    if not local_audit["ok"]:
        raise RuntimeError(f"Lokale QA fehlgeschlagen: {json.dumps(local_audit, ensure_ascii=False)}")

    publish_report = build_public_bundle(config)
    public_root = Path(publish_report["public_root"])
    public_audit = audit_public_bundle(public_root, request.job_id)
    metadata["qa"]["public"] = public_audit
    atomic_write_json(job_dir / "metadata.json", metadata)

    if not public_audit["ok"]:
        raise RuntimeError(f"Public-QA fehlgeschlagen: {json.dumps(public_audit, ensure_ascii=False)}")

    logger.info("Lauf fuer %s erfolgreich abgeschlossen", request.job_id)
    return metadata
