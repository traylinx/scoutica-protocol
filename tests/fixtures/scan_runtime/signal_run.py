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


RESET_AND_EXEC = "--reset-signals-and-exec"


def process_group_exists(group_id: int) -> bool:
    try:
        os.killpg(group_id, 0)
        return True
    except ProcessLookupError:
        return False


def signal_process_group(group_id: int, signum: int) -> None:
    try:
        os.killpg(group_id, signum)
    except ProcessLookupError:
        pass


def cleanup_residual_group(group_id: int) -> bool:
    """Return true when the target left no process in its original group."""
    deadline = time.monotonic() + 0.5
    while process_group_exists(group_id) and time.monotonic() < deadline:
        time.sleep(0.05)
    if not process_group_exists(group_id):
        return True
    signal_process_group(group_id, signal.SIGTERM)
    time.sleep(0.1)
    if process_group_exists(group_id):
        signal_process_group(group_id, signal.SIGKILL)
    return False


def reset_signals_and_exec(command: list[str]) -> int:
    """Reset inherited dispositions, then replace this process with the target."""
    if not command:
        return 2
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    signal.signal(signal.SIGTERM, signal.SIG_DFL)
    os.execvpe(command[0], command, os.environ.copy())


def main() -> int:
    if sys.argv[1:2] == [RESET_AND_EXEC]:
        return reset_signals_and_exec(sys.argv[2:])

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
    # POSIX shells cannot reset a signal ignored when they started. Use this
    # Python fixture as a trampoline so the target shell sees default signals.
    target = [
        sys.executable,
        str(Path(__file__).resolve()),
        RESET_AND_EXEC,
        *command,
    ]

    with open(args.output, "wb") as output:
        process = subprocess.Popen(
            target,
            stdin=subprocess.DEVNULL,
            stdout=output,
            stderr=subprocess.STDOUT,
            env=os.environ.copy(),
            start_new_session=True,
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
            return_code = process.wait(timeout=args.timeout)
            if not cleanup_residual_group(process.pid):
                return 126
            return return_code
        except subprocess.TimeoutExpired:
            # A timed-out harness must not strand the scan runtime or provider.
            signal_process_group(process.pid, signal.SIGKILL)
            process.wait()
            return 125


if __name__ == "__main__":
    sys.exit(main())
