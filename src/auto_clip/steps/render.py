from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

from auto_clip.config import AppConfig
from auto_clip.fs_utils import copy_file, ensure_dir


def _build_concat_file(staged_frames: list[Path], concat_file: Path, frame_rate: float) -> None:
    duration = 1.0 / frame_rate
    lines: list[str] = []
    base_dir = concat_file.parent.resolve()
    for frame in staged_frames:
        relative_frame = frame.resolve().relative_to(base_dir).as_posix()
        lines.append(f"file {relative_frame}")
        lines.append(f"duration {duration:.6f}")
    final_frame = staged_frames[-1].resolve().relative_to(base_dir).as_posix()
    lines.append(f"file {final_frame}")
    concat_file.write_text("\n".join(lines) + "\n", encoding="utf-8")


def render_video(
    *,
    config: AppConfig,
    frame_files: list[Path],
    audio_file: Path,
    job_video_dir: Path,
    job_id: str,
) -> dict:
    if not frame_files:
        raise ValueError("Keine Bilddateien fuer den Render gefunden")

    ensure_dir(job_video_dir)
    staging_dir = job_video_dir / "staged_frames"
    if staging_dir.exists():
        shutil.rmtree(staging_dir)
    staging_dir.mkdir(parents=True)

    staged_frames: list[Path] = []
    for index, frame in enumerate(frame_files, start=1):
        target = staging_dir / f"frame_{index:04d}{frame.suffix.lower()}"
        copy_file(frame, target)
        staged_frames.append(target)

    poster_path = job_video_dir / f"poster{staged_frames[0].suffix.lower()}"
    copy_file(staged_frames[0], poster_path)

    concat_file = job_video_dir / "frames.txt"
    _build_concat_file(staged_frames, concat_file, config.render.frame_rate)

    output_video = job_video_dir / f"{job_id}.mp4"
    scale_filter = (
        f"scale={config.render.width}:{config.render.height}:force_original_aspect_ratio=decrease,"
        f"pad={config.render.width}:{config.render.height}:(ow-iw)/2:(oh-ih)/2"
    )

    command = [
        config.ffmpeg_bin,
        "-y",
        "-f",
        "concat",
        "-safe",
        "0",
        "-i",
        str(concat_file),
        "-i",
        str(audio_file),
        "-vf",
        scale_filter,
        "-c:v",
        config.render.codec,
        "-crf",
        str(config.render.crf),
        "-pix_fmt",
        "yuv420p",
        "-c:a",
        "aac",
        "-b:a",
        config.render.audio_bitrate,
        "-movflags",
        "+faststart",
        "-shortest",
        str(output_video),
    ]

    try:
        subprocess.run(command, check=True, capture_output=True, text=True)
    except FileNotFoundError as exc:
        raise RuntimeError(f"ffmpeg nicht gefunden: {config.ffmpeg_bin}") from exc
    except subprocess.CalledProcessError as exc:
        stderr = (exc.stderr or "").strip()
        raise RuntimeError(f"Render fehlgeschlagen: {stderr}") from exc

    return {
        "video_file": output_video,
        "poster_file": poster_path,
        "staged_frame_count": len(staged_frames),
    }
