from __future__ import annotations

import argparse
import logging
import shutil
import time
from pathlib import Path

from auto_clip.config import load_config
from auto_clip.logging_utils import configure_logging
from auto_clip.pipeline import process_manifest
from auto_clip.publish import build_public_bundle
from auto_clip.qa import audit_job_directory, audit_public_bundle

logger = logging.getLogger(__name__)


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="auto-clip Kommandozeile")
    sub = parser.add_subparsers(dest="command", required=True)

    run_job = sub.add_parser("run-job", help="Genau ein Manifest verarbeiten")
    run_job.add_argument("manifest", help="Pfad zur Manifest-Datei")

    sub.add_parser("publish", help="Public-Bundle aus allen erfolgreichen Jobs neu bauen")

    watch = sub.add_parser("watch", help="Eingangsordner pollen und neue Jobs verarbeiten")
    watch.add_argument("--once", action="store_true", help="Nur einen Poll-Durchlauf ausfuehren")

    doctor = sub.add_parser("doctor", help="Lokalen Job und Public-Bundle pruefen")
    doctor.add_argument("--job-id", help="Optionaler Job fuer Detailpruefung")

    return parser


def _claim_manifest(source: Path, working_dir: Path) -> Path:
    target = working_dir / source.name
    source.replace(target)
    return target


def _archive_manifest(source: Path, target_dir: Path) -> Path:
    target = target_dir / source.name
    if target.exists():
        target.unlink()
    source.replace(target)
    return target


def _write_failure_note(target: Path, message: str) -> None:
    target.write_text(message + "\n", encoding="utf-8")


def _run_one_manifest(manifest_path: Path, config) -> None:
    process_manifest(manifest_path, config)


def command_run_job(args: argparse.Namespace) -> int:
    config = load_config()
    manifest_path = Path(args.manifest).expanduser().resolve()
    _run_one_manifest(manifest_path, config)
    return 0


def command_publish(_: argparse.Namespace) -> int:
    config = load_config()
    report = build_public_bundle(config)
    logger.info("Public-Bundle neu gebaut: %s Jobs", report["job_count"])
    return 0


def command_watch(args: argparse.Namespace) -> int:
    config = load_config()

    for path in [
        config.paths.jobs_inbox,
        config.paths.jobs_working,
        config.paths.jobs_done,
        config.paths.jobs_failed,
    ]:
        path.mkdir(parents=True, exist_ok=True)

    while True:
        found = False
        for manifest in sorted(config.paths.jobs_inbox.glob("*.json")):
            found = True
            claimed = _claim_manifest(manifest, config.paths.jobs_working)
            logger.info("Manifest uebernommen: %s", claimed.name)

            try:
                _run_one_manifest(claimed, config)
                archived = _archive_manifest(claimed, config.paths.jobs_done)
                logger.info("Manifest erfolgreich archiviert: %s", archived)
            except Exception as exc:
                failed_manifest = config.paths.jobs_failed / claimed.name
                shutil.copy2(claimed, failed_manifest)
                _write_failure_note(
                    config.paths.jobs_failed / f"{claimed.stem}.error.txt",
                    str(exc),
                )
                claimed.unlink(missing_ok=True)
                logger.exception("Job fehlgeschlagen: %s", exc)

        if args.once:
            return 0

        if not found:
            logger.debug("Keine neuen Manifeste gefunden.")
        time.sleep(config.watch.poll_seconds)

    return 0


def command_doctor(args: argparse.Namespace) -> int:
    config = load_config()
    public_root = config.paths.build_root / "public"
    public_report = audit_public_bundle(public_root, args.job_id)
    print("Public:", public_report)

    if args.job_id:
        job_dir = config.paths.build_root / "jobs" / args.job_id
        local_report = audit_job_directory(job_dir)
        print("Lokal:", local_report)

    return 0 if public_report["ok"] else 1


def main() -> int:
    configure_logging()
    parser = _build_parser()
    args = parser.parse_args()

    if args.command == "run-job":
        return command_run_job(args)
    if args.command == "publish":
        return command_publish(args)
    if args.command == "watch":
        return command_watch(args)
    if args.command == "doctor":
        return command_doctor(args)

    parser.error("Unbekanntes Kommando")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
