from __future__ import annotations

import json
import shutil
from pathlib import Path

from auto_clip.config import AppConfig
from auto_clip.fs_utils import atomic_write_json, copy_file, ensure_dir


def _load_job_metadata(job_root: Path) -> dict | None:
    path = job_root / "metadata.json"
    if not path.exists():
        return None
    return json.loads(path.read_text(encoding="utf-8"))


def _iter_jobs(build_jobs_root: Path) -> list[dict]:
    jobs: list[dict] = []
    if not build_jobs_root.exists():
        return jobs
    for job_root in sorted(build_jobs_root.iterdir()):
        if not job_root.is_dir():
            continue
        metadata = _load_job_metadata(job_root)
        if metadata:
            jobs.append(metadata)
    jobs.sort(key=lambda item: item["created_at"], reverse=True)
    return jobs


def build_public_bundle(config: AppConfig) -> dict:
    jobs_root = config.paths.build_root / "jobs"
    public_root = config.paths.build_root / "public"

    if public_root.exists():
        shutil.rmtree(public_root)
    shutil.copytree(config.paths.site_root, public_root)

    data_root = public_root / "data"
    video_root = public_root / "videos"
    poster_root = public_root / "posters"
    ensure_dir(data_root)
    ensure_dir(video_root)
    ensure_dir(poster_root)

    asset_manifest = {"videos": {}, "posters": {}, "data": {}}
    catalog_items: list[dict] = []

    for metadata in _iter_jobs(jobs_root):
        job_id = metadata["job_id"]
        source_video = config.project_root / metadata["artifacts"]["video_path"]
        source_poster = config.project_root / metadata["artifacts"]["poster_path"]

        target_video = video_root / f"{job_id}.mp4"
        target_poster = poster_root / source_poster.name
        copy_file(source_video, target_video)
        copy_file(source_poster, target_poster)

        public_payload = dict(metadata)
        public_payload["public"] = {
            "page_url": f"{config.base_url}/?job={job_id}",
            "video_url": f"./videos/{job_id}.mp4",
            "poster_url": f"./posters/{target_poster.name}",
            "metadata_url": f"./data/{job_id}.json",
        }

        atomic_write_json(data_root / f"{job_id}.json", public_payload)

        asset_manifest["videos"][job_id] = f"./videos/{job_id}.mp4"
        asset_manifest["posters"][job_id] = f"./posters/{target_poster.name}"
        asset_manifest["data"][job_id] = f"./data/{job_id}.json"

        catalog_items.append({
            "job_id": job_id,
            "vehicle": public_payload["vehicle"],
            "public": public_payload["public"],
            "created_at": public_payload["created_at"],
        })

    atomic_write_json(data_root / "catalog.json", {"items": catalog_items})
    atomic_write_json(data_root / "asset-manifest.json", asset_manifest)
    atomic_write_json(data_root / "build.json", {
        "job_count": len(catalog_items),
        "base_url": config.base_url,
    })

    return {
        "public_root": public_root,
        "job_count": len(catalog_items),
    }
