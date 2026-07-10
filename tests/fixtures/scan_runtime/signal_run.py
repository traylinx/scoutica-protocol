#!/usr/bin/env python3
"""Start a scan, wait for its provider-ready file, then signal the scan parent."""

from __future__ import annotations

import argparse
import os
import signal
import subprocess
import sys
import time
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--signal", choices=("INT", "TERM"), required=True)
    parser.add_argument("--ready-file", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--timeout", type=float, default=20.0)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command:
        parser.error("command required after --")

    with open(args.output, "wb") as output:
        process = subprocess.Popen(
            command,
            stdin=subprocess.DEVNULL,
            stdout=output,
            stderr=subprocess.STDOUT,
            env=os.environ.copy(),
        )
        deadline = time.monotonic() + args.timeout
        while time.monotonic() < deadline and not Path(args.ready_file).exists():
            if process.poll() is not None:
                return process.returncode
            time.sleep(0.05)
        if not Path(args.ready_file).exists():
            process.terminate()
            process.wait(timeout=5)
            return 124
        process.send_signal(getattr(signal, f"SIG{args.signal}"))
        try:
            return process.wait(timeout=args.timeout)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
            return 125


if __name__ == "__main__":
    sys.exit(main())
