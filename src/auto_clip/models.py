from __future__ import annotations

import re
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


JOB_ID_RE = re.compile(r"^[A-Za-z0-9_-]+$")


@dataclass(frozen=True)
class SourceData:
    frame_dir: str
    voice_wav: str | None = None


@dataclass(frozen=True)
class VehicleData:
    title: str
    price_eur: int
    year: int
    mileage_km: int
    fuel: str
    power_hp: int
    color: str
    transmission: str
    listing_url: str


@dataclass(frozen=True)
class JobRequest:
    job_id: str
    source: SourceData
    vehicle: VehicleData

    @classmethod
    def from_dict(cls, payload: dict[str, Any]) -> "JobRequest":
        job_id = str(payload.get("job_id", "")).strip()
        if not job_id or not JOB_ID_RE.match(job_id):
            raise ValueError("job_id fehlt oder ist ungueltig")

        source_payload = payload.get("source") or {}
        vehicle_payload = payload.get("vehicle") or {}

        frame_dir = str(source_payload.get("frame_dir", "")).strip()
        if not frame_dir:
            raise ValueError("source.frame_dir fehlt")

        voice_wav = source_payload.get("voice_wav")
        if voice_wav is not None:
            voice_wav = str(voice_wav).strip() or None

        required_vehicle_fields = [
            "title",
            "price_eur",
            "year",
            "mileage_km",
            "fuel",
            "power_hp",
            "color",
            "transmission",
            "listing_url",
        ]
        missing = [field for field in required_vehicle_fields if field not in vehicle_payload]
        if missing:
            raise ValueError(f"vehicle-Felder fehlen: {', '.join(missing)}")

        return cls(
            job_id=job_id,
            source=SourceData(
                frame_dir=frame_dir,
                voice_wav=voice_wav,
            ),
            vehicle=VehicleData(
                title=str(vehicle_payload["title"]).strip(),
                price_eur=int(vehicle_payload["price_eur"]),
                year=int(vehicle_payload["year"]),
                mileage_km=int(vehicle_payload["mileage_km"]),
                fuel=str(vehicle_payload["fuel"]).strip(),
                power_hp=int(vehicle_payload["power_hp"]),
                color=str(vehicle_payload["color"]).strip(),
                transmission=str(vehicle_payload["transmission"]).strip(),
                listing_url=str(vehicle_payload["listing_url"]).strip(),
            ),
        )

    def resolved_frame_dir(self, project_root: Path) -> Path:
        return (project_root / self.source.frame_dir).resolve()

    def resolved_voice_wav(self, project_root: Path) -> Path | None:
        if not self.source.voice_wav:
            return None
        return (project_root / self.source.voice_wav).resolve()

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()
