#!/usr/bin/env python3
"""Pause a wc invocation after safely reporting readiness to a test harness."""

from __future__ import annotations

import os
import signal
import sys
import time


def write_new(path: str, content: bytes) -> None:
    """Create one private, non-symlink diagnostic file."""
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    descriptor = os.open(path, flags, 0o600)
    try:
        os.write(descriptor, content)
    finally:
        os.close(descriptor)


def main() -> None:
    if os.environ.get("FAKE_WC_IGNORE_SIGNALS") == "1":
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
    ready_file = os.environ["FAKE_WC_READY_FILE"]
    pid_file = os.environ["FAKE_WC_PID_FILE"]
    write_new(pid_file, f"{os.getpid()}\n".encode())
    write_new(ready_file, b"")
    delay = float(os.environ.get("FAKE_WC_DELAY_SECONDS", "10"))
    time.sleep(max(0.0, min(delay, 10.0)))
    os.execv("/usr/bin/wc", ["wc", *sys.argv[1:]])


if __name__ == "__main__":
    main()
