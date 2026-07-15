#!/usr/bin/env python3
"""Signal a non-process-group-leader CLI and verify its session drains."""

from __future__ import annotations

import argparse
import os
import signal
import subprocess
import sys
import time
from pathlib import Path


SUPERVISE = "--supervise"


def write_new(path: str, content: bytes) -> None:
    """Create one private, non-symlink coordination file."""
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    descriptor = os.open(path, flags, 0o600)
    try:
        os.write(descriptor, content)
    finally:
        os.close(descriptor)


def session_members(session_id: int) -> list[int]:
    result = subprocess.run(
        ["ps", "-eo", "pid=,sess="],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    members: list[int] = []
    for line in result.stdout.splitlines():
        fields = line.split()
        if len(fields) == 2 and fields[1] == str(session_id):
            members.append(int(fields[0]))
    return members


def signal_session(session_id: int, signum: int) -> None:
    for pid in session_members(session_id):
        try:
            os.kill(pid, signum)
        except ProcessLookupError:
            pass


def cleanup_residual_session(session_id: int) -> bool:
    deadline = time.monotonic() + 0.5
    while session_members(session_id) and time.monotonic() < deadline:
        time.sleep(0.05)
    if not session_members(session_id):
        return True
    signal_session(session_id, signal.SIGTERM)
    time.sleep(0.1)
    if session_members(session_id):
        signal_session(session_id, signal.SIGKILL)
    return False


def supervise(command: list[str], output_path: str, target_pid_file: str) -> int:
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    signal.signal(signal.SIGTERM, signal.SIG_DFL)
    with open(output_path, "wb") as output:
        process = subprocess.Popen(
            command,
            stdin=subprocess.DEVNULL,
            stdout=output,
            stderr=subprocess.STDOUT,
            env=os.environ.copy(),
        )
        write_new(target_pid_file, f"{process.pid}\n".encode())
        return process.wait()


def main() -> int:
    if sys.argv[1:2] == [SUPERVISE]:
        parser = argparse.ArgumentParser()
        parser.add_argument("--output", required=True)
        parser.add_argument("--target-pid-file", required=True)
        parser.add_argument("command", nargs=argparse.REMAINDER)
        args = parser.parse_args(sys.argv[2:])
        command = args.command[1:] if args.command[:1] == ["--"] else args.command
        if not command:
            parser.error("command required after --")
        return supervise(command, args.output, args.target_pid_file)

    parser = argparse.ArgumentParser()
    parser.add_argument("--signal", choices=("INT", "TERM"), required=True)
    parser.add_argument("--ready-file", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--target-pid-file", required=True)
    parser.add_argument("--timeout", type=float, default=5.0)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command:
        parser.error("command required after --")

    supervisor = subprocess.Popen(
        [
            sys.executable,
            str(Path(__file__).resolve()),
            SUPERVISE,
            "--output",
            args.output,
            "--target-pid-file",
            args.target_pid_file,
            "--",
            *command,
        ],
        env=os.environ.copy(),
        start_new_session=True,
    )
    deadline = time.monotonic() + args.timeout
    ready_path = Path(args.ready_file)
    pid_path = Path(args.target_pid_file)
    while time.monotonic() < deadline and not (ready_path.exists() and pid_path.exists()):
        if supervisor.poll() is not None:
            return supervisor.returncode
        time.sleep(0.02)
    if not (ready_path.exists() and pid_path.exists()):
        signal_session(supervisor.pid, signal.SIGKILL)
        supervisor.wait()
        return 124

    target_pid = int(pid_path.read_text(encoding="utf-8").strip())
    os.kill(target_pid, getattr(signal, f"SIG{args.signal}"))
    try:
        return_code = supervisor.wait(timeout=args.timeout)
    except subprocess.TimeoutExpired:
        signal_session(supervisor.pid, signal.SIGKILL)
        supervisor.wait()
        return 125
    if not cleanup_residual_session(supervisor.pid):
        return 126
    return return_code


if __name__ == "__main__":
    sys.exit(main())
