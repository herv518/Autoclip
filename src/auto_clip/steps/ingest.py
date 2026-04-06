from __future__ import annotations

import json
from pathlib import Path

from auto_clip.models import JobRequest


def load_job_request(manifest_path: Path) -> JobRequest:
    payload = json.loads(manifest_path.read_text(encoding="utf-8"))
    return JobRequest.from_dict(payload)
