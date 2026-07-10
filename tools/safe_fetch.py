#!/usr/bin/env python3
"""Bounded, redirect-free HTTPS fetch boundary for Scoutica registries/cards."""

from __future__ import annotations

import argparse
import ipaddress
import json
import os
import queue
import resource
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Iterable
from urllib.parse import SplitResult, urlsplit


CONNECT_TIMEOUT = 10
TOTAL_TIMEOUT = 30
MAX_BODY_BYTES = 2 * 1024 * 1024

EXIT_POLICY = 2
EXIT_TRANSPORT = 3
EXIT_NOT_FOUND = 4
EXIT_RESPONSE = 5

JSON_MEDIA_TYPES = {"application/json", "text/json", "text/plain"}
TEXT_MEDIA_TYPES = {
    "text/plain",
    "text/markdown",
    "text/yaml",
    "application/yaml",
    "application/x-yaml",
}
PROXY_KEYS = {
    "http_proxy",
    "https_proxy",
    "all_proxy",
    "no_proxy",
    "HTTP_PROXY",
    "HTTPS_PROXY",
    "ALL_PROXY",
    "NO_PROXY",
}


class FetchError(RuntimeError):
    def __init__(self, category: str, message: str, exit_code: int):
        super().__init__(message)
        self.category = category
        self.exit_code = exit_code


@dataclass(frozen=True)
class Target:
    url: str
    parsed: SplitResult
    host: str
    port: int
    addresses: tuple[str, ...]
    literal: bool


def _public_address(value: str) -> bool:
    try:
        address = ipaddress.ip_address(value.split("%", 1)[0])
    except ValueError:
        return False
    mapped = getattr(address, "ipv4_mapped", None)
    if mapped is not None:
        address = mapped
    return bool(
        address.is_global
        and not address.is_private
        and not address.is_loopback
        and not address.is_link_local
        and not address.is_reserved
        and not address.is_multicast
        and not address.is_unspecified
    )


def _resolve_with_timeout(host: str, port: int, timeout: float) -> list[str]:
    result: queue.Queue[object] = queue.Queue(maxsize=1)

    def run() -> None:
        try:
            answers = socket.getaddrinfo(host, port, type=socket.SOCK_STREAM)
            result.put([answer[4][0] for answer in answers])
        except BaseException as exc:  # surfaced on the caller thread
            result.put(exc)

    thread = threading.Thread(target=run, daemon=True)
    thread.start()
    try:
        value = result.get(timeout=timeout)
    except queue.Empty as exc:
        raise FetchError("dns_policy", "DNS resolution exceeded 10 seconds", EXIT_POLICY) from exc
    if isinstance(value, BaseException):
        raise FetchError("dns_policy", "DNS resolution failed", EXIT_POLICY) from value
    return list(value)


def validate_target(
    url: str,
    resolver: Callable[[str, int, float], Iterable[str]] = _resolve_with_timeout,
) -> Target:
    if any(ord(character) < 0x21 or ord(character) == 0x7F for character in url):
        raise FetchError("url_policy", "URL contains whitespace or control characters", EXIT_POLICY)
    try:
        parsed = urlsplit(url)
        parsed_port = parsed.port
    except ValueError as exc:
        raise FetchError("url_policy", "malformed URL or port", EXIT_POLICY) from exc
    if parsed.scheme.lower() != "https":
        raise FetchError("url_policy", "only HTTPS URLs are allowed", EXIT_POLICY)
    if parsed_port is not None and parsed_port < 1:
        raise FetchError("url_policy", "URL port must be between 1 and 65535", EXIT_POLICY)
    port = parsed_port or 443
    if parsed.username is not None or parsed.password is not None:
        raise FetchError("url_policy", "credentials in URLs are forbidden", EXIT_POLICY)
    if not parsed.hostname:
        raise FetchError("url_policy", "URL host is missing", EXIT_POLICY)
    if parsed.fragment:
        raise FetchError("url_policy", "URL fragments are not fetch targets", EXIT_POLICY)

    raw_host = parsed.hostname.lower()
    if raw_host.endswith("."):
        raise FetchError("url_policy", "trailing-dot hostnames are forbidden", EXIT_POLICY)
    try:
        raw_host.encode("ascii")
    except UnicodeEncodeError as exc:
        raise FetchError("url_policy", "non-ASCII hostnames are forbidden", EXIT_POLICY) from exc
    host = raw_host
    if host in {"localhost", "ip6-localhost", "ip6-loopback"}:
        raise FetchError("url_policy", "localhost is forbidden", EXIT_POLICY)

    try:
        literal = ipaddress.ip_address(host.split("%", 1)[0])
    except ValueError:
        literal = None
    if literal is not None:
        addresses = [host]
    else:
        addresses = list(resolver(host, port, CONNECT_TIMEOUT))
    if not addresses:
        raise FetchError("dns_policy", "host resolved to no addresses", EXIT_POLICY)
    if any(not _public_address(address) for address in addresses):
        raise FetchError(
            "dns_policy",
            "host resolution includes a non-public address",
            EXIT_POLICY,
        )
    unique = tuple(dict.fromkeys(address.split("%", 1)[0] for address in addresses))
    return Target(
        url=url,
        parsed=parsed,
        host=host,
        port=port,
        addresses=unique,
        literal=literal is not None,
    )


def validate_payload(data: bytes, expect: str, content_type: str) -> None:
    if not data:
        raise FetchError("response_policy", "response body is empty", EXIT_RESPONSE)
    if len(data) > MAX_BODY_BYTES:
        raise FetchError("response_policy", "response exceeds 2 MiB", EXIT_RESPONSE)
    media_type = content_type.split(";", 1)[0].strip().lower()
    if expect in {"json", "registry"} and media_type not in JSON_MEDIA_TYPES:
        raise FetchError("response_policy", "response content type is not JSON-compatible", EXIT_RESPONSE)
    if expect == "text" and media_type not in TEXT_MEDIA_TYPES:
        raise FetchError("response_policy", "response content type is not supported text", EXIT_RESPONSE)
    try:
        text = data.decode("utf-8", errors="strict")
    except UnicodeDecodeError as exc:
        raise FetchError("response_policy", "response is not valid UTF-8", EXIT_RESPONSE) from exc
    if expect == "text":
        return
    try:
        document = json.loads(text)
    except (TypeError, ValueError) as exc:
        raise FetchError("response_policy", "response is not valid JSON", EXIT_RESPONSE) from exc
    if not isinstance(document, dict):
        raise FetchError("response_policy", "JSON root must be an object", EXIT_RESPONSE)
    if expect == "registry":
        entries = document.get("entries")
        if not isinstance(entries, list) or not all(isinstance(entry, dict) for entry in entries):
            raise FetchError(
                "response_policy",
                'registry must contain an "entries" list of objects',
                EXIT_RESPONSE,
            )


def _last_headers(path: Path) -> dict[str, str]:
    raw = path.read_bytes().decode("iso-8859-1", errors="replace")
    blocks = [block for block in raw.replace("\r\n", "\n").split("\n\n") if block.strip()]
    block = next((item for item in reversed(blocks) if item.startswith("HTTP/")), "")
    headers: dict[str, str] = {}
    for line in block.splitlines()[1:]:
        if ":" not in line:
            continue
        name, value = line.split(":", 1)
        headers[name.strip().lower()] = value.strip()
    return headers


def _curl_environment(temp_home: str) -> dict[str, str]:
    environment = {
        key: value
        for key, value in os.environ.items()
        if key not in PROXY_KEYS and "proxy" not in key.lower()
    }
    environment["HOME"] = temp_home
    environment["CURL_HOME"] = temp_home
    return environment


def _curl_address(address: str) -> str:
    return f"[{address}]" if ":" in address else address


def _limit_child_files() -> None:
    """Keep curl-owned response/header files from ever growing beyond the body cap."""
    resource.setrlimit(resource.RLIMIT_FSIZE, (MAX_BODY_BYTES, MAX_BODY_BYTES))


def fetch(
    target: Target,
    expect: str,
    output: Path,
    allow_not_found: bool = False,
    runner: Callable[..., subprocess.CompletedProcess[str]] = subprocess.run,
    deadline: float | None = None,
) -> None:
    deadline = deadline or (time.monotonic() + TOTAL_TIMEOUT)
    last_transport = "request failed"
    with tempfile.TemporaryDirectory(prefix="scoutica-fetch-") as private:
        os.chmod(private, 0o700)
        body_path = Path(private) / "body"
        header_path = Path(private) / "headers"
        for address in target.addresses:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                break
            connect_timeout = max(1, min(CONNECT_TIMEOUT, int(remaining)))
            total_timeout = max(1, int(remaining))
            command = [
                "curl",
                "-q",
                "--silent",
                "--show-error",
                "--globoff",
                "--proto",
                "=https",
                "--noproxy",
                "*",
                "--connect-timeout",
                str(connect_timeout),
                "--max-time",
                str(total_timeout),
                "--max-filesize",
                str(MAX_BODY_BYTES),
                "--header",
                "Accept-Encoding: identity",
                "--output",
                str(body_path),
                "--dump-header",
                str(header_path),
                "--write-out",
                "%{http_code}\n%{content_type}\n%{size_download}",
                target.url,
            ]
            if not target.literal:
                insertion = command.index("--header")
                command[insertion:insertion] = [
                    "--resolve",
                    f"{target.host}:{target.port}:{_curl_address(address)}",
                ]
            try:
                result = runner(
                    command,
                    text=True,
                    capture_output=True,
                    timeout=remaining + 1,
                    env=_curl_environment(private),
                    check=False,
                    preexec_fn=_limit_child_files,
                )
            except (OSError, subprocess.TimeoutExpired) as exc:
                last_transport = type(exc).__name__
                continue
            if result.returncode in {63, -signal.SIGXFSZ, 128 + signal.SIGXFSZ} or (
                result.returncode != 0
                and body_path.exists()
                and body_path.stat().st_size >= MAX_BODY_BYTES
            ):
                raise FetchError("response_policy", "response exceeds 2 MiB", EXIT_RESPONSE)
            if result.returncode in {3, 49}:
                raise FetchError("url_policy", "curl rejected the URL syntax", EXIT_POLICY)
            if result.returncode != 0:
                last_transport = f"curl exit {result.returncode}"
                continue
            lines = result.stdout.splitlines()
            try:
                status = int(lines[0])
            except (IndexError, ValueError) as exc:
                raise FetchError("response_policy", "missing HTTP status", EXIT_RESPONSE) from exc
            if 300 <= status < 400:
                raise FetchError("redirect", f"redirect response HTTP {status} refused", EXIT_RESPONSE)
            if status == 404 and allow_not_found:
                raise FetchError("not_found", "optional resource not found", EXIT_NOT_FOUND)
            if status != 200:
                raise FetchError("response_policy", f"unexpected HTTP status {status}", EXIT_RESPONSE)
            headers = _last_headers(header_path)
            encoding = headers.get("content-encoding", "identity").lower()
            if encoding not in {"", "identity"}:
                raise FetchError("response_policy", "compressed responses are forbidden", EXIT_RESPONSE)
            declared = headers.get("content-length")
            if declared:
                try:
                    if int(declared) > MAX_BODY_BYTES:
                        raise FetchError("response_policy", "response exceeds 2 MiB", EXIT_RESPONSE)
                except ValueError as exc:
                    raise FetchError("response_policy", "invalid Content-Length", EXIT_RESPONSE) from exc
            data = body_path.read_bytes()
            content_type = lines[1] if len(lines) > 1 else headers.get("content-type", "")
            validate_payload(data, expect, content_type)
            _write_output(output, data)
            return
    raise FetchError("transport_unavailable", last_transport, EXIT_TRANSPORT)


def _write_output(path: Path, data: bytes) -> None:
    path = Path(os.path.abspath(os.path.expanduser(path)))
    if path.is_symlink():
        raise FetchError("output_policy", "output path is a symlink", EXIT_RESPONSE)
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        descriptor = os.open(path, flags, 0o600)
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(path, 0o600)
    except OSError as exc:
        raise FetchError("output_policy", "could not write validated response", EXIT_RESPONSE) from exc


def cmd_fetch(args: argparse.Namespace) -> int:
    try:
        deadline = time.monotonic() + TOTAL_TIMEOUT
        target = validate_target(args.url)
        fetch(
            target,
            args.expect,
            Path(args.output),
            args.allow_not_found,
            deadline=deadline,
        )
        return 0
    except FetchError as exc:
        if exc.category != "not_found":
            print(f"safe-fetch[{exc.category}]: {exc}", file=sys.stderr)
        return exc.exit_code


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    fetch_parser = subparsers.add_parser("fetch")
    fetch_parser.add_argument("--url", required=True)
    fetch_parser.add_argument("--output", required=True)
    fetch_parser.add_argument("--expect", choices=("registry", "json", "text"), required=True)
    fetch_parser.add_argument("--allow-not-found", action="store_true")
    fetch_parser.set_defaults(func=cmd_fetch)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
