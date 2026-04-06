from __future__ import annotations

from pathlib import Path


REQUIRED_JOB_FILES = [
    "request.json",
    "metadata.json",
    "content/narration.txt",
    "audio/narration.wav",
]

REQUIRED_PUBLIC_FILES = [
    "index.html",
    "data/catalog.json",
    "data/asset-manifest.json",
    "data/build.json",
]


def audit_job_directory(job_dir: Path) -> dict:
    missing = []
    for relative in REQUIRED_JOB_FILES:
        if not (job_dir / relative).exists():
            missing.append(relative)

    video_files = list((job_dir / "video").glob("*.mp4"))
    if not video_files:
        missing.append("video/<job_id>.mp4")

    poster_files = list((job_dir / "video").glob("poster.*"))
    if not poster_files:
        missing.append("video/poster.*")

    return {
        "ok": not missing,
        "missing": missing,
    }


def audit_public_bundle(public_root: Path, job_id: str | None = None) -> dict:
    missing = []
    for relative in REQUIRED_PUBLIC_FILES:
        if not (public_root / relative).exists():
            missing.append(relative)

    if job_id:
        if not (public_root / "data" / f"{job_id}.json").exists():
            missing.append(f"data/{job_id}.json")
        if not (public_root / "videos" / f"{job_id}.mp4").exists():
            missing.append(f"videos/{job_id}.mp4")

    return {
        "ok": not missing,
        "missing": missing,
    }
