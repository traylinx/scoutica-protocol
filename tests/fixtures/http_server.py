#!/usr/bin/env python3
"""Deterministic loopback HTTP fixture for bounded-fetch tests. Mock data only."""

from __future__ import annotations

import argparse
import json
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit


class FixtureHandler(BaseHTTPRequestHandler):
    server_version = "ScouticaFixture/1"

    def log_message(self, fmt: str, *args: object) -> None:
        log_file = Path(self.server.log_file)  # type: ignore[attr-defined]
        with log_file.open("a", encoding="utf-8") as handle:
            handle.write(f"{self.command} {self.path} " + (fmt % args) + "\n")

    def _send(self, status: int, body: bytes, content_type: str = "application/json") -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802 - stdlib handler API
        parsed = urlsplit(self.path)
        if parsed.path == "/ok.json":
            body = json.dumps({"fixture": "scoutica", "status": "ok"}).encode()
            self._send(200, body)
        elif parsed.path == "/invalid.json":
            self._send(200, b'{"fixture":')
        elif parsed.path == "/wrong-type":
            self._send(200, b"fixture text", "text/html")
        elif parsed.path == "/oversize":
            self._send(200, b"x" * (2 * 1024 * 1024 + 1), "application/octet-stream")
        elif parsed.path == "/redirect":
            self.send_response(302)
            self.send_header("Location", "/ok.json")
            self.end_headers()
        elif parsed.path == "/redirect-private":
            self.send_response(302)
            self.send_header("Location", "http://169.254.169.254/latest/meta-data/")
            self.end_headers()
        elif parsed.path == "/slow":
            delay = min(float(parse_qs(parsed.query).get("seconds", ["1"])[0]), 5.0)
            time.sleep(max(delay, 0.0))
            self._send(200, b'{"status":"slow"}')
        else:
            self._send(404, b'{"error":"not found"}')


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--ready-file", required=True)
    parser.add_argument("--port-file", required=True)
    parser.add_argument("--log-file", required=True)
    args = parser.parse_args()

    server = ThreadingHTTPServer(("127.0.0.1", 0), FixtureHandler)
    server.log_file = args.log_file  # type: ignore[attr-defined]
    Path(args.log_file).write_text("", encoding="utf-8")
    Path(args.port_file).write_text(str(server.server_port), encoding="ascii")
    Path(args.ready_file).touch()
    server.serve_forever(poll_interval=0.05)


if __name__ == "__main__":
    main()
