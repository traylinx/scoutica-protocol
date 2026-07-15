#!/usr/bin/env python3
"""Loopback switchAILocal response fixture bound to the runtime's fixed port."""

from __future__ import annotations

import argparse
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_args: object) -> None:
        return

    def do_POST(self) -> None:  # noqa: N802
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length)
        Path(self.server.payload_log).write_bytes(body)  # type: ignore[attr-defined]
        content = Path(self.server.response_file).read_text(encoding="utf-8")  # type: ignore[attr-defined]
        encoded = json.dumps({"choices": [{"message": {"content": content}}]}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--ready-file", required=True)
    parser.add_argument("--response-file", required=True)
    parser.add_argument("--payload-log", required=True)
    args = parser.parse_args()
    server = ThreadingHTTPServer(("127.0.0.1", 18080), Handler)
    server.response_file = args.response_file  # type: ignore[attr-defined]
    server.payload_log = args.payload_log  # type: ignore[attr-defined]
    Path(args.ready_file).touch()
    server.serve_forever(poll_interval=0.05)


if __name__ == "__main__":
    main()
