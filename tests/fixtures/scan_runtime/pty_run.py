#!/usr/bin/env python3
"""Run one command in a PTY and feed a consent answer. POSIX test fixture only."""

from __future__ import annotations

import argparse
import os
import pty
import select
import signal
import subprocess
import sys
import time
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--answer", choices=("yes", "no", "eof"), required=True)
    parser.add_argument("--nonleader", action="store_true")
    parser.add_argument("--output", required=True)
    parser.add_argument("--timeout", type=float, default=30.0)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command:
        parser.error("command required after --")

    pid, master = pty.fork()
    if pid == 0:
        if args.nonleader:
            completed = subprocess.run(command, check=False, env=os.environ.copy())
            if os.tcgetpgrp(0) != os.getpgrp():
                os._exit(125)
            os._exit(completed.returncode)
        os.execvpe(command[0], command, os.environ)

    answer = {"yes": b"y\n", "no": b"n\n", "eof": b"\x04"}[args.answer]
    os.write(master, answer)
    output = bytearray()
    deadline = time.monotonic() + args.timeout
    status = None
    try:
        while time.monotonic() < deadline:
            ready, _, _ = select.select([master], [], [], 0.1)
            if ready:
                try:
                    chunk = os.read(master, 65536)
                except OSError:
                    chunk = b""
                if chunk:
                    output.extend(chunk)
            waited, candidate = os.waitpid(pid, os.WNOHANG)
            if waited == pid:
                status = candidate
                break
        if status is None:
            os.kill(pid, signal.SIGTERM)
            _, status = os.waitpid(pid, 0)
    finally:
        os.close(master)
        Path(args.output).write_bytes(bytes(output))

    if os.WIFEXITED(status):
        return os.WEXITSTATUS(status)
    if os.WIFSIGNALED(status):
        return 128 + os.WTERMSIG(status)
    return 1


if __name__ == "__main__":
    sys.exit(main())
