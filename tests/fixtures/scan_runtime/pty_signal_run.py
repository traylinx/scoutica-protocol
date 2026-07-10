#!/usr/bin/env python3
"""Signal a command PID after a prompt appears on its controlling PTY."""

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


def write_new(path: str, content: bytes) -> None:
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


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--signal", choices=("INT", "TERM"), required=True)
    parser.add_argument("--wait-for", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--timeout", type=float, default=10.0)
    parser.add_argument("--delivery", choices=("pid", "tty"), default="pid")
    parser.add_argument("--nonleader", action="store_true")
    parser.add_argument("--target-pid-file")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command:
        parser.error("command required after --")

    pid, master = pty.fork()
    if pid == 0:
        signal.signal(signal.SIGINT, signal.SIG_DFL)
        signal.signal(signal.SIGTERM, signal.SIG_DFL)
        if args.nonleader:
            process = subprocess.Popen(command, env=os.environ.copy())
            if args.target_pid_file:
                write_new(args.target_pid_file, f"{process.pid}\n".encode())
            return_code = process.wait()
            if os.tcgetpgrp(0) != os.getpgrp():
                return 127
            return return_code
        os.execvpe(command[0], command, os.environ)

    marker = args.wait_for.encode()
    output = bytearray()
    deadline = time.monotonic() + args.timeout
    status = None
    signal_sent = False
    residual_group = False
    try:
        while time.monotonic() < deadline:
            ready, _, _ = select.select([master], [], [], 0.05)
            if ready:
                try:
                    chunk = os.read(master, 65536)
                except OSError:
                    chunk = b""
                output.extend(chunk)
            if not signal_sent and marker in output:
                if args.delivery == "tty":
                    if args.signal != "INT":
                        parser.error("TTY delivery only supports INT")
                    os.write(master, b"\x03")
                else:
                    target_pid = pid
                    if args.nonleader:
                        if not args.target_pid_file or not Path(args.target_pid_file).exists():
                            time.sleep(0.01)
                            continue
                        target_pid = int(Path(args.target_pid_file).read_text().strip())
                    os.kill(target_pid, getattr(signal, f"SIG{args.signal}"))
                signal_sent = True
            waited, candidate = os.waitpid(pid, os.WNOHANG)
            if waited == pid:
                status = candidate
                break
        if status is None:
            signal_session(pid, signal.SIGTERM)
            stop_deadline = time.monotonic() + 1.0
            while time.monotonic() < stop_deadline:
                waited, candidate = os.waitpid(pid, os.WNOHANG)
                if waited == pid:
                    status = candidate
                    break
                time.sleep(0.05)
        if status is None:
            signal_session(pid, signal.SIGKILL)
            _, status = os.waitpid(pid, 0)
        group_deadline = time.monotonic() + 0.5
        while session_members(pid) and time.monotonic() < group_deadline:
            time.sleep(0.05)
        if session_members(pid):
            residual_group = True
            signal_session(pid, signal.SIGTERM)
            time.sleep(0.1)
            if session_members(pid):
                signal_session(pid, signal.SIGKILL)
    finally:
        os.close(master)
        Path(args.output).write_bytes(bytes(output))

    if not signal_sent:
        return 124
    if residual_group:
        return 125
    if os.WIFEXITED(status):
        return os.WEXITSTATUS(status)
    if os.WIFSIGNALED(status):
        return 128 + os.WTERMSIG(status)
    return 1


if __name__ == "__main__":
    sys.exit(main())
