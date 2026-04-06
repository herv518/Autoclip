from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from auto_clip.config import AppConfig, PathConfig, RenderConfig, VoiceConfig, WatchConfig
from auto_clip.fs_utils import atomic_write_json, ensure_dir
from auto_clip.publish import build_public_bundle


class PublishBundleTest(unittest.TestCase):
    def test_bundle_is_rebuilt_from_jobs(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            site = root / "site"
            (site / "assets").mkdir(parents=True)
            (site / "index.html").write_text("ok", encoding="utf-8")
            (site / "assets" / "app.js").write_text("ok", encoding="utf-8")
            (site / "assets" / "styles.css").write_text("ok", encoding="utf-8")

            jobs_root = root / "dist" / "jobs" / "10001" / "video"
            ensure_dir(jobs_root)
            (jobs_root / "10001.mp4").write_text("video", encoding="utf-8")
            (jobs_root / "poster.ppm").write_text("poster", encoding="utf-8")

            atomic_write_json(root / "dist" / "jobs" / "10001" / "metadata.json", {
                "job_id": "10001",
                "created_at": "2026-01-01T10:00:00+00:00",
                "vehicle": {
                    "title": "Beispielauto",
                    "price_eur": 10000,
                    "year": 2022,
                    "mileage_km": 1000,
                    "fuel": "Benzin",
                    "power_hp": 150,
                    "color": "Schwarz",
                    "transmission": "Automatik",
                    "listing_url": "https://beispiel.de/10001",
                },
                "content": {"summary": "Kurztext"},
                "artifacts": {
                    "video_path": "dist/jobs/10001/video/10001.mp4",
                    "poster_path": "dist/jobs/10001/video/poster.ppm",
                },
            })

            config = AppConfig(
                project_root=root,
                config_path=root / "auto-clip.config.json",
                paths=PathConfig(
                    jobs_inbox=root / "jobs" / "inbox",
                    jobs_working=root / "jobs" / "working",
                    jobs_done=root / "jobs" / "done",
                    jobs_failed=root / "jobs" / "failed",
                    build_root=root / "dist",
                    site_root=site,
                ),
                render=RenderConfig(frame_rate=1.0, width=1280, height=720, codec="libx264", crf=20, audio_bitrate="192k"),
                watch=WatchConfig(poll_seconds=5),
                voice=VoiceConfig(fallback_duration_seconds=8),
                base_url="http://localhost:8000",
                ffmpeg_bin="ffmpeg",
                ffprobe_bin="ffprobe",
            )

            report = build_public_bundle(config)
            self.assertEqual(report["job_count"], 1)

            catalog = json.loads((root / "dist" / "public" / "data" / "catalog.json").read_text(encoding="utf-8"))
            self.assertEqual(catalog["items"][0]["job_id"], "10001")


if __name__ == "__main__":
    unittest.main()
