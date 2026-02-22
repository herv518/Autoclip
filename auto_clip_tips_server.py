#!/usr/bin/env python3
"""Local bridge server for one-click Auto-Clip Tips video generation.

Run:
  python3 auto_clip_tips_server.py

Then open:
  http://127.0.0.1:8787/auto-clip-tips.html
"""

from __future__ import annotations

import json
import os
import subprocess
import time
from http import HTTPStatus
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse


ROOT_DIR = Path(__file__).resolve().parent
BUILD_SCRIPT = ROOT_DIR / "build_auto_clip_tips_from_page.sh"
HOST = os.environ.get("TIPS_HOST", "127.0.0.1")
PORT = int(os.environ.get("TIPS_PORT", "8787"))


def _tail(text: str, limit: int = 3500) -> str:
    text = (text or "").strip()
    if len(text) <= limit:
        return text
    return text[-limit:]


class TipsHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT_DIR), **kwargs)

    def end_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        super().end_headers()

    def log_message(self, fmt: str, *args):
        # Keep terminal logs concise.
        print(f"[tips-server] {self.address_string()} - " + (fmt % args))

    def _send_json(self, status: int, payload: dict):
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_response(HTTPStatus.NO_CONTENT)
        self.end_headers()

    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path in {"/api/health", "/health"}:
            return self._send_json(
                HTTPStatus.OK,
                {
                    "ok": True,
                    "service": "auto-clip-tips-bridge",
                    "root": str(ROOT_DIR),
                    "build_script_exists": BUILD_SCRIPT.exists(),
                },
            )
        return super().do_GET()

    def do_POST(self):
        parsed = urlparse(self.path)
        if parsed.path != "/api/generate":
            return self._send_json(
                HTTPStatus.NOT_FOUND,
                {"ok": False, "error": "Unknown endpoint."},
            )

        if not BUILD_SCRIPT.exists():
            return self._send_json(
                HTTPStatus.INTERNAL_SERVER_ERROR,
                {
                    "ok": False,
                    "error": "Build script not found: build_auto_clip_tips_from_page.sh",
                },
            )

        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            length = 0

        raw = self.rfile.read(length) if length > 0 else b"{}"
        try:
            data = json.loads(raw.decode("utf-8"))
        except json.JSONDecodeError:
            return self._send_json(
                HTTPStatus.BAD_REQUEST,
                {"ok": False, "error": "Invalid JSON body."},
            )

        page_url = str(data.get("page_url", "")).strip()
        section_target = str(data.get("section_target", "")).strip()
        marker_text = str(data.get("marker_text", "")).strip()
        recommendation = str(data.get("recommendation", "")).strip()
        voice = str(data.get("voice", "Anna")).strip() or "Anna"
        use_ai = bool(data.get("use_ai", True))
        no_webm = bool(data.get("no_webm", False))

        missing = []
        if not page_url:
            missing.append("page_url")
        if not section_target:
            missing.append("section_target")
        if not marker_text:
            missing.append("marker_text")
        if not recommendation:
            missing.append("recommendation")

        if missing:
            return self._send_json(
                HTTPStatus.BAD_REQUEST,
                {"ok": False, "error": f"Missing required field(s): {', '.join(missing)}"},
            )

        cmd = [
            str(BUILD_SCRIPT),
            "--url",
            page_url,
            "--section-target",
            section_target,
            "--marker-text",
            marker_text,
            "--recommendation",
            recommendation,
            "--voice",
            voice,
        ]
        if not use_ai:
            cmd.append("--no-ai")
        if no_webm:
            cmd.append("--no-webm")

        start = time.time()
        proc = subprocess.run(
            cmd,
            cwd=str(ROOT_DIR),
            capture_output=True,
            text=True,
            env=os.environ.copy(),
            check=False,
        )
        duration = round(time.time() - start, 3)

        if proc.returncode != 0:
            return self._send_json(
                HTTPStatus.INTERNAL_SERVER_ERROR,
                {
                    "ok": False,
                    "error": "Video generation failed.",
                    "returncode": proc.returncode,
                    "duration_sec": duration,
                    "stdout_tail": _tail(proc.stdout),
                    "stderr_tail": _tail(proc.stderr),
                },
            )

        return self._send_json(
            HTTPStatus.OK,
            {
                "ok": True,
                "duration_sec": duration,
                "output_mp4": "assets/videos/auto-clip-tips-main.mp4",
                "output_webm": "assets/videos/auto-clip-tips-main.webm",
                "context_json": "assets/videos/auto-clip-tips-page-context.json",
                "used_recommendation": recommendation,
                "used_section_target": section_target,
                "stdout_tail": _tail(proc.stdout),
            },
        )


def main():
    server = ThreadingHTTPServer((HOST, PORT), TipsHandler)
    print(f"[tips-server] running on http://{HOST}:{PORT}")
    print("[tips-server] open /auto-clip-tips.html and use 'Video generieren'")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[tips-server] stopped.")


if __name__ == "__main__":
    main()
