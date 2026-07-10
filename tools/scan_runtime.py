#!/usr/bin/env python3
"""Private runtime boundary for ``scoutica scan``.

This helper intentionally owns only the seams Bash cannot implement safely:
provider process lifecycle, card-owned state, and rollback-capable atomic
promotion.  Prompt and response contents are always read from files or stdin;
they are never accepted as command-line values.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import selectors
import shutil
import signal
import stat
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


MAX_RESPONSE_BYTES = 8 * 1024 * 1024
MAX_PROVIDER_SECONDS = 300
SUPPORTED_SOURCE_SUFFIXES = {
    ".md",
    ".txt",
    ".json",
    ".yaml",
    ".yml",
    ".csv",
    ".html",
    ".htm",
    ".pdf",
    ".docx",
}
GENERATED_SOURCE_NAMES = {
    "profile.json",
    "rules.yaml",
    "evidence.json",
    "SKILL.md",
    "README.md",
    "scoutica.json",
    "scoutica_prompt.txt",
}
CARD_PATHS = (
    "profile.json",
    "rules.yaml",
    "evidence.json",
    "SKILL.md",
    "README.md",
    ".gitignore",
    "rules/evaluate-fit.md",
    "rules/negotiate-terms.md",
    "rules/verify-evidence.md",
    "rules/request-interview.md",
)


def _utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _canonical_directory(value: str, *, must_exist: bool = True) -> Path:
    path = Path(value).expanduser()
    if must_exist:
        return path.resolve(strict=True)
    return Path(os.path.abspath(os.path.expanduser(value)))


def _provider_timeout() -> int:
    raw = os.environ.get("SCOUTICA_SCAN_TIMEOUT_SECONDS", "")
    if not raw:
        return MAX_PROVIDER_SECONDS
    try:
        requested = int(raw)
    except ValueError:
        return MAX_PROVIDER_SECONDS
    return min(MAX_PROVIDER_SECONDS, max(1, requested))


def _ollama_is_loopback() -> tuple[bool, str]:
    raw = os.environ.get("OLLAMA_HOST", "").strip()
    if not raw:
        return True, "local Ollama endpoint http://127.0.0.1:11434"
    candidate = raw if "://" in raw else f"http://{raw}"
    try:
        from urllib.parse import urlsplit

        parsed = urlsplit(candidate)
        host = (parsed.hostname or "").lower().rstrip(".")
    except Exception:
        host = ""
    loopback = host == "localhost" or host == "::1" or host.startswith("127.")
    return loopback, f"Ollama endpoint {raw}"


def provider_info(provider: str) -> tuple[bool, str, str, str]:
    """Return enabled, class, destination, disabled reason."""

    if provider == "clipboard":
        return True, "clipboard", "the operating-system clipboard", ""
    if provider == "ollama":
        local, destination = _ollama_is_loopback()
        return True, "local" if local else "remote", destination, ""
    if provider == "gemini":
        return True, "remote", "Google Gemini CLI configured account/provider", ""
    if provider == "claude":
        return True, "remote", "Anthropic Claude CLI configured account/provider", ""
    if provider == "codex":
        return True, "remote", "OpenAI Codex CLI configured account/provider", ""
    if provider == "opencode":
        return True, "remote", "OpenCode configured account/provider", ""
    if provider == "ail":
        return (
            True,
            "remote",
            "switchAILocal gateway at http://127.0.0.1:18080 (may route to a remote model)",
            "",
        )
    disabled = {
        "vibe": "no characterized stdin or prompt-file interface",
        "openclaw": "current interface requires the full message in argv",
    }
    if provider in disabled:
        return False, "remote", provider, disabled[provider]
    return False, "remote", provider, "unknown provider"


def cmd_provider_info(args: argparse.Namespace) -> int:
    enabled, scope, destination, reason = provider_info(args.provider)
    print("\t".join(("enabled" if enabled else "disabled", scope, destination, reason)))
    return 0


def _kill_process_group(process: subprocess.Popen[bytes], sig: int) -> None:
    try:
        os.killpg(process.pid, sig)
    except (ProcessLookupError, PermissionError):
        try:
            process.send_signal(sig)
        except ProcessLookupError:
            pass


def _process_group_exists(process: subprocess.Popen[bytes]) -> bool:
    try:
        os.killpg(process.pid, 0)
        return True
    except (ProcessLookupError, PermissionError):
        return False


def _finish_process_group(process: subprocess.Popen[bytes]) -> None:
    """Terminate descendants left behind after the adapter's direct child exits."""
    _kill_process_group(process, signal.SIGTERM)
    deadline = time.monotonic() + 1.0
    while _process_group_exists(process) and time.monotonic() < deadline:
        time.sleep(0.02)
    if _process_group_exists(process):
        _kill_process_group(process, signal.SIGKILL)


def _run_subprocess_provider(
    provider: str, prompt_path: Path, response_path: Path, log_path: Path
) -> int:
    instruction = (
        "Read stdin and generate a Scoutica Protocol Skill Card. Return ONLY raw JSON "
        "with keys: profile, rules, evidence, skill_md. No markdown fences or explanation."
    )
    commands = {
        "gemini": ["gemini", "-p", instruction],
        "claude": ["claude", "-p", instruction],
        "codex": ["codex", "exec", "-"],
        "opencode": ["opencode", "run"],
        "ollama": ["ollama", "run", os.environ.get("SCOUTICA_OLLAMA_MODEL", "llama3.2")],
    }
    command = commands[provider]
    timeout = _provider_timeout()
    start = time.monotonic()
    process: subprocess.Popen[bytes] | None = None

    def forward(signum: int, _frame: Any) -> None:
        if process is not None:
            _kill_process_group(process, signum)
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                _kill_process_group(process, signal.SIGKILL)
                process.wait()
            _finish_process_group(process)
        raise SystemExit(128 + signum)

    previous_int = signal.signal(signal.SIGINT, forward)
    previous_term = signal.signal(signal.SIGTERM, forward)
    try:
        with prompt_path.open("rb") as prompt, response_path.open("wb") as response, log_path.open("ab") as log:
            process = subprocess.Popen(
                command,
                stdin=prompt,
                stdout=subprocess.PIPE,
                stderr=log,
                start_new_session=True,
            )
            assert process.stdout is not None
            selector = selectors.DefaultSelector()
            selector.register(process.stdout, selectors.EVENT_READ)
            response_size = 0
            stdout_open = True
            while process.poll() is None or stdout_open:
                elapsed = time.monotonic() - start
                if elapsed >= timeout:
                    log.write(f"Scoutica: provider exceeded {timeout} seconds\n".encode())
                    log.flush()
                    _kill_process_group(process, signal.SIGTERM)
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        _kill_process_group(process, signal.SIGKILL)
                        process.wait()
                    _finish_process_group(process)
                    return 124
                for key, _ in selector.select(timeout=0.05):
                    chunk = os.read(key.fd, 64 * 1024)
                    if not chunk:
                        selector.unregister(process.stdout)
                        stdout_open = False
                        break
                    remaining = MAX_RESPONSE_BYTES - response_size
                    if len(chunk) > remaining:
                        if remaining > 0:
                            response.write(chunk[:remaining])
                            response_size += remaining
                        response.flush()
                        os.fsync(response.fileno())
                        log.write(b"Scoutica: provider response exceeded 8 MiB\n")
                        log.flush()
                        _kill_process_group(process, signal.SIGTERM)
                        try:
                            process.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            _kill_process_group(process, signal.SIGKILL)
                            process.wait()
                        _finish_process_group(process)
                        return 125
                    response.write(chunk)
                    response_size += len(chunk)
                if process.poll() is not None and stdout_open:
                    _finish_process_group(process)
            response.flush()
            os.fsync(response.fileno())
            _finish_process_group(process)
            return int(process.returncode or 0)
    except FileNotFoundError:
        with log_path.open("ab") as log:
            log.write(f"Scoutica: provider executable not found: {command[0]}\n".encode())
        return 127
    finally:
        signal.signal(signal.SIGINT, previous_int)
        signal.signal(signal.SIGTERM, previous_term)


def _run_ail(prompt_path: Path, response_path: Path, log_path: Path) -> int:
    timeout = _provider_timeout()
    payload = json.dumps(
        {
            "messages": [{"role": "user", "content": prompt_path.read_text(encoding="utf-8")}],
            "temperature": 0.1,
            "stream": False,
        }
    ).encode("utf-8")
    request = urllib.request.Request(
        "http://127.0.0.1:18080/v1/chat/completions",
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    def timed_out(_signum: int, _frame: Any) -> None:
        raise TimeoutError(f"provider exceeded {timeout} seconds")

    previous_alarm = signal.signal(signal.SIGALRM, timed_out)
    signal.setitimer(signal.ITIMER_REAL, timeout)
    try:
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        with opener.open(request, timeout=timeout) as result:  # noqa: S310 - fixed loopback, proxies disabled
            body = bytearray()
            while True:
                chunk = result.read(64 * 1024)
                if not chunk:
                    break
                body.extend(chunk)
                if len(body) > MAX_RESPONSE_BYTES:
                    log_path.write_text("Scoutica: provider response exceeded 8 MiB\n")
                    return 125
        document = json.loads(body.decode("utf-8"))
        content = document["choices"][0]["message"]["content"]
        encoded = str(content).encode("utf-8")
        if len(encoded) > MAX_RESPONSE_BYTES:
            log_path.write_text("Scoutica: provider response exceeded 8 MiB\n")
            return 125
        response_path.write_bytes(encoded)
        return 0
    except TimeoutError as exc:
        log_path.write_text(f"Scoutica: {exc}\n", encoding="utf-8")
        return 124
    except (OSError, ValueError, KeyError, IndexError, urllib.error.URLError) as exc:
        log_path.write_text(f"Scoutica: switchAILocal request failed: {exc}\n", encoding="utf-8")
        return 1
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, previous_alarm)


def cmd_run_provider(args: argparse.Namespace) -> int:
    prompt = Path(args.prompt_file)
    response = Path(args.response_file)
    log = Path(args.log_file)
    response.parent.mkdir(parents=True, exist_ok=True)
    response.write_bytes(b"")
    log.write_bytes(b"")
    enabled, _, _, reason = provider_info(args.provider)
    if not enabled or args.provider == "clipboard":
        print(f"Provider {args.provider} is unavailable: {reason or 'not executable'}", file=sys.stderr)
        return 2
    if args.provider == "ail":
        return _run_ail(prompt, response, log)
    return _run_subprocess_provider(args.provider, prompt, response, log)


def _source_files(source: Path) -> list[Path]:
    entries: list[Path] = []
    for entry in source.iterdir():
        if entry.name in GENERATED_SOURCE_NAMES or entry.suffix.lower() not in SUPPORTED_SOURCE_SUFFIXES:
            continue
        if entry.is_symlink():
            raise RuntimeError(f"refusing symlinked source document: {entry}")
        if entry.is_file():
            entries.append(entry)
    return sorted(entries, key=lambda entry: entry.name)


def cmd_source_hash(args: argparse.Namespace) -> int:
    try:
        source = _canonical_directory(args.source)
        digest = hashlib.sha256()
        for entry in _source_files(source):
            digest.update(entry.name.encode("utf-8", "surrogateescape"))
            digest.update(b"\0")
            total = 0
            with entry.open("rb") as handle:
                for chunk in iter(lambda: handle.read(128 * 1024), b""):
                    total += len(chunk)
                    if total > 2 * 1024 * 1024:
                        raise RuntimeError(f"source file exceeds the 2 MiB limit: {entry.name}")
                    digest.update(chunk)
            digest.update(b"\0")
        print(digest.hexdigest())
        return 0
    except (OSError, RuntimeError) as exc:
        print(f"Could not hash source safely: {exc}", file=sys.stderr)
        return 1


def _assert_no_symlink_components(path: Path) -> None:
    absolute = Path(os.path.abspath(path))
    current = Path(absolute.anchor)
    for part in absolute.parts[1:]:
        current /= part
        if not os.path.lexists(current) or not current.is_symlink():
            continue
        # macOS exposes system paths such as /var and /tmp through root-owned
        # aliases.  Those immutable-to-the-caller aliases are safe to follow;
        # user-owned aliases are not.
        if getattr(os.lstat(current), "st_uid", None) == 0:
            continue
        raise RuntimeError(f"refusing symlinked path component: {current}")


def cmd_output_path(args: argparse.Namespace) -> int:
    raw_path = Path(os.path.abspath(os.path.expanduser(args.path)))
    try:
        _assert_no_symlink_components(raw_path)
        if raw_path.is_symlink():
            raise RuntimeError(f"refusing symlinked output path: {raw_path}")
        path = raw_path.resolve(strict=False)
        if path.exists() and not path.is_dir():
            raise RuntimeError(f"output path is not a directory: {path}")
    except (OSError, RuntimeError) as exc:
        print(exc, file=sys.stderr)
        return 1
    print(path)
    return 0


def _find_scoutica_json(text: str) -> dict[str, Any] | None:
    import re

    for match in re.findall(r"```(?:json)?\s*(\{[\s\S]*?\})\s*```", text):
        try:
            value = json.loads(match)
        except ValueError:
            continue
        if isinstance(value, dict) and any(key in value for key in ("profile", "rules", "evidence")):
            return value
    decoder = json.JSONDecoder()
    for index, character in enumerate(text):
        if character != "{":
            continue
        try:
            value, _ = decoder.raw_decode(text[index:])
        except ValueError:
            continue
        if isinstance(value, dict) and any(key in value for key in ("profile", "rules", "evidence")):
            return value
    return None


def _one_line(value: Any, fallback: str) -> str:
    import re

    text = re.sub(r"[\r\n\t]+", " ", str(value or ""))
    text = re.sub(r"\s+", " ", text).strip()
    return text or fallback


def _markdown_inline(value: Any, fallback: str) -> str:
    import re

    return re.sub(r"([\\`*_\[\]<>])", r"\\\1", _one_line(value, fallback))


def cmd_parse_response(args: argparse.Namespace) -> int:
    import re

    import yaml

    response_path = Path(args.response_file)
    if response_path.stat().st_size > MAX_RESPONSE_BYTES:
        print("Provider response exceeds the 8 MiB limit.", file=sys.stderr)
        return 1
    raw = response_path.read_text(encoding="utf-8")
    data = _find_scoutica_json(raw)
    if not isinstance(data, dict):
        print("Could not parse JSON from provider response.", file=sys.stderr)
        return 1
    profile = data.get("profile")
    rules = data.get("rules")
    evidence = data.get("evidence")
    if not isinstance(profile, dict) or not isinstance(rules, dict) or not isinstance(evidence, dict):
        print("Provider response must contain profile, rules, and evidence objects.", file=sys.stderr)
        return 1
    engagement = rules.get("engagement")
    allowed = engagement.get("allowed_types") if isinstance(engagement, dict) else None
    valid_engagements = {"permanent", "contract", "fractional", "advisory", "internship"}
    canonical: list[str] = []
    if isinstance(allowed, list):
        for item in allowed:
            normalized = "contract" if item == "freelance" else item
            if normalized in valid_engagements and normalized not in canonical:
                canonical.append(normalized)
    if not canonical:
        print(
            "Provider response must contain a supported rules.engagement.allowed_types value.",
            file=sys.stderr,
        )
        return 1
    engagement["allowed_types"] = canonical

    stage = Path(args.stage_dir)
    stage.mkdir(mode=0o700, parents=True, exist_ok=True)
    (stage / "rules").mkdir(mode=0o700, exist_ok=True)
    (stage / "profile.json").write_text(
        json.dumps(profile, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    (stage / "rules.yaml").write_text(
        yaml.safe_dump(rules, allow_unicode=True, sort_keys=False), encoding="utf-8"
    )
    (stage / "evidence.json").write_text(
        json.dumps(evidence, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )

    skill_data = data.get("skill_md") if isinstance(data.get("skill_md"), dict) else {}
    name = _one_line(skill_data.get("name", profile.get("name")), "Unknown")
    title = _one_line(skill_data.get("title", profile.get("title")), "Professional")
    raw_tags = skill_data.get("tags", "")
    if isinstance(raw_tags, list):
        tags = ", ".join(_one_line(item, "") for item in raw_tags if _one_line(item, ""))
    else:
        tags = _one_line(raw_tags, "")
    frontmatter = {
        "name": "scoutica",
        "description": f"{name} - AI-readable professional profile with opportunity filtering",
        "metadata": {"tags": tags, "author": name, "version": "0.1.0"},
    }
    frontmatter_yaml = yaml.safe_dump(
        frontmatter, allow_unicode=True, sort_keys=False, default_flow_style=False
    ).rstrip()
    prose_name = _markdown_inline(name, "Unknown")
    prose_title = _markdown_inline(title, "Professional")
    skill = f"""---
{frontmatter_yaml}
---

# Scoutica

This skill provides an AI-readable professional profile for **{prose_name}** - {prose_title}.

## Data Files

- [profile.json](./profile.json) - Structured capabilities and experience
- [rules.yaml](./rules.yaml) - Rules of Engagement
- [evidence.json](./evidence.json) - Public evidence registry

## Evaluation Rules

- [evaluate-fit.md](./rules/evaluate-fit.md) - Capability matching
- [negotiate-terms.md](./rules/negotiate-terms.md) - Policy compliance
- [verify-evidence.md](./rules/verify-evidence.md) - Evidence verification
- [request-interview.md](./rules/request-interview.md) - Human handoff

Never fabricate capabilities. Respect `rules.yaml`. Candidate sovereignty applies.
"""
    (stage / "SKILL.md").write_text(skill, encoding="utf-8")
    summary = str(profile.get("summary", ""))
    skills = profile.get("skills", [])
    skills_text = ", ".join(str(item) for item in skills) if isinstance(skills, list) else ""
    readme = f"""# {prose_name}

## {prose_title}

{summary}

### Core Skills
{skills_text or "Not specified"}

Generated by the [Scoutica Protocol](https://scoutica.com).
"""
    (stage / "README.md").write_text(readme, encoding="utf-8")
    for path in stage.rglob("*"):
        if path.is_file():
            path.chmod(0o600)
    return 0


def _load_json(path: Path, fallback: Any) -> Any:
    try:
        with path.open(encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return fallback


def _state_path(card_dir: Path) -> Path:
    return card_dir / ".scoutica" / "state.json"


def _state_source_matches(card_dir: Path, source: Path) -> bool:
    state = _load_json(_state_path(card_dir), {})
    stored = state.get("card", {}).get("source_path") if isinstance(state, dict) else None
    if not isinstance(stored, str):
        return False
    try:
        return Path(stored).resolve(strict=True) == source
    except OSError:
        return False


def cmd_registry_card(args: argparse.Namespace) -> int:
    source = _canonical_directory(args.source)
    registry = _load_json(Path(args.registry), {})
    cards = registry.get("cards", {}) if isinstance(registry, dict) else {}
    matches: list[Path] = []
    for key, value in cards.items() if isinstance(cards, dict) else ():
        if not isinstance(value, dict) or value.get("source_dir") != str(source):
            continue
        raw_card = value.get("card_dir") or key
        try:
            raw_path = Path(os.path.abspath(os.path.expanduser(str(raw_card))))
            _assert_no_symlink_components(raw_path)
            if raw_path.is_symlink():
                raise RuntimeError(f"refusing symlinked registered card: {raw_path}")
            card = raw_path.resolve(strict=True)
        except (OSError, TypeError):
            continue
        except RuntimeError:
            continue
        if card.is_dir() and card not in matches:
            matches.append(card)
    if len(matches) != 1:
        return 1
    card = matches[0]
    print(f"{card}\t{'valid' if _state_source_matches(card, source) else 'stale'}")
    return 0


def _lookup_key(document: Any, key: str) -> Any:
    value = document
    for part in key.split("."):
        if not isinstance(value, dict) or part not in value:
            return None
        value = value[part]
    return value


def cmd_state_get(args: argparse.Namespace) -> int:
    card = _canonical_directory(args.card_dir)
    value = _lookup_key(_load_json(_state_path(card), {}), args.key)
    if value is None:
        return 1
    if isinstance(value, bool):
        print("true" if value else "false")
    elif isinstance(value, (dict, list)):
        print(json.dumps(value, separators=(",", ":")))
    else:
        print(value)
    return 0


def _open_directory(path: Path) -> int:
    required = ("O_DIRECTORY", "O_NOFOLLOW")
    if any(not hasattr(os, name) for name in required):
        raise RuntimeError("platform lacks required no-follow directory operations")
    return os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)


def _atomic_write(path: Path, data: bytes, mode: int = 0o600) -> None:
    parent = path.parent
    _assert_no_symlink_components(parent)
    if parent.is_symlink():
        raise RuntimeError(f"refusing symlinked parent: {parent}")
    parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    if path.is_symlink():
        raise RuntimeError(f"refusing symlinked target: {path}")
    parent_fd = _open_directory(parent)
    temp_name = f".scoutica-{os.getpid()}-{os.urandom(8).hex()}.tmp"
    temp_fd: int | None = None
    try:
        temp_fd = os.open(
            temp_name,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
            mode,
            dir_fd=parent_fd,
        )
        os.fchmod(temp_fd, mode)
        with os.fdopen(temp_fd, "wb") as handle:
            temp_fd = None
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        current = os.stat(path.name, dir_fd=parent_fd, follow_symlinks=False) if path.exists() else None
        if current is not None and stat.S_ISLNK(current.st_mode):
            raise RuntimeError(f"refusing symlinked target: {path}")
        os.replace(temp_name, path.name, src_dir_fd=parent_fd, dst_dir_fd=parent_fd)
        temp_name = ""
        os.fsync(parent_fd)
    finally:
        if temp_fd is not None:
            os.close(temp_fd)
        if temp_name:
            try:
                os.unlink(temp_name, dir_fd=parent_fd)
            except FileNotFoundError:
                pass
        os.close(parent_fd)


def _update_state_document(
    card: Path, source: Path, source_hash: str, provider: str
) -> bytes:
    existing = _load_json(_state_path(card), {})
    state = existing if isinstance(existing, dict) else {}
    state["schema_version"] = "0.1.0"
    state["card"] = {
        "source_hash": source_hash,
        "source_path": str(source),
        "generated_at": _utc_now(),
        "source_files": [entry.name for entry in _source_files(source)],
        "provider": provider,
    }
    state.setdefault("preview", {})
    return (json.dumps(state, indent=2, ensure_ascii=False) + "\n").encode("utf-8")


def _updated_scan_registry_document(
    registry_path: Path, card: Path, source: Path, provider: str, stage: Path
) -> bytes:
    registry = _load_json(registry_path, {"schema_version": "0.1.0", "cards": {}})
    if not isinstance(registry, dict):
        registry = {"schema_version": "0.1.0", "cards": {}}
    cards = registry.get("cards")
    if not isinstance(cards, dict):
        cards = {}
        registry["cards"] = cards
    now = _utc_now()
    profile = _load_json(stage / "profile.json", {})
    name = profile.get("name", "") if isinstance(profile, dict) else ""
    title = profile.get("title", "") if isinstance(profile, dict) else ""
    key = str(card)
    entry = cards.get(key)
    if not isinstance(entry, dict):
        entry = {
            "name": name,
            "title": title,
            "card_dir": key,
            "source_dir": None,
            "github_url": None,
            "preview_url": None,
            "created_at": now,
            "last_scanned": None,
            "last_published": None,
            "last_previewed": None,
            "provider": None,
            "scan_count": 0,
            "exists": True,
            "history": [],
        }
    if name:
        entry["name"] = name
    if title:
        entry["title"] = title
    entry["card_dir"] = key
    entry["source_dir"] = str(source)
    entry["last_scanned"] = now
    entry["provider"] = provider
    entry["exists"] = True
    entry["scan_count"] = int(entry.get("scan_count", 0) or 0) + 1
    history = entry.get("history")
    if not isinstance(history, list):
        history = []
    history.append({"event": "scan", "at": now, "provider": provider})
    entry["history"] = history[-50:]
    cards[key] = entry
    registry.setdefault("schema_version", "0.1.0")
    return (json.dumps(registry, indent=2, ensure_ascii=False) + "\n").encode("utf-8")


class PromotionInterrupted(RuntimeError):
    pass


def _write_recovery(card: Path, snapshots: dict[Path, tuple[bytes, int] | None], error: Exception) -> Path:
    state_dir = card / ".scoutica"
    if state_dir.is_symlink():
        raise RuntimeError("cannot preserve recovery data through symlinked .scoutica")
    state_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    recovery = state_dir / f"recovery-{int(time.time())}-{os.getpid()}"
    recovery.mkdir(mode=0o700)
    manifest: dict[str, Any] = {"error": str(error), "paths": {}}
    for target, snapshot in snapshots.items():
        try:
            relative = str(target.relative_to(card))
            original_path = None
        except ValueError:
            relative = f"external/{target.name}"
            original_path = str(target)
        if snapshot is None:
            manifest["paths"][relative] = {
                "previously_absent": True,
                **({"original_path": original_path} if original_path else {}),
            }
            continue
        data, mode = snapshot
        backup = recovery / relative
        backup.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        backup.write_bytes(data)
        backup.chmod(0o600)
        manifest["paths"][relative] = {
            "backup": relative,
            "mode": oct(mode),
            **({"original_path": original_path} if original_path else {}),
        }
    (recovery / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    (recovery / "manifest.json").chmod(0o600)
    return recovery


def cmd_promote(args: argparse.Namespace) -> int:
    stage = _canonical_directory(args.stage_dir)
    source = _canonical_directory(args.source_dir)
    raw_registry_path = Path(os.path.abspath(os.path.expanduser(args.registry)))
    if raw_registry_path.is_symlink():
        print(f"Refusing symlinked registry path: {raw_registry_path}", file=sys.stderr)
        return 1
    registry_path = raw_registry_path.resolve(strict=False)
    card = _canonical_directory(args.card_dir, must_exist=False)
    try:
        _assert_no_symlink_components(card)
    except RuntimeError as exc:
        print(exc, file=sys.stderr)
        return 1
    if card.is_symlink():
        print(f"Refusing symlinked card directory: {card}", file=sys.stderr)
        return 1
    card.mkdir(mode=0o700, parents=True, exist_ok=True)
    try:
        card = card.resolve(strict=True)
    except OSError as exc:
        print(f"Could not resolve card directory: {exc}", file=sys.stderr)
        return 1
    if (card / "rules").is_symlink() or (card / ".scoutica").is_symlink():
        print("Refusing symlinked card rules/state directory", file=sys.stderr)
        return 1
    (card / "rules").mkdir(mode=0o700, exist_ok=True)
    (card / ".scoutica").mkdir(mode=0o700, exist_ok=True)
    os.chmod(card / ".scoutica", 0o700)

    operations: list[tuple[Path, bytes, int]] = []
    for relative in CARD_PATHS:
        staged = stage / relative
        if staged.is_file():
            operations.append((card / relative, staged.read_bytes(), 0o600))
    operations.append(
        (
            _state_path(card),
            _update_state_document(card, source, args.source_hash, args.provider),
            0o600,
        )
    )
    operations.append(
        (
            registry_path,
            _updated_scan_registry_document(registry_path, card, source, args.provider, stage),
            0o600,
        )
    )
    snapshots: dict[Path, tuple[bytes, int] | None] = {}
    changed: list[Path] = []
    fail_after_raw = os.environ.get("SCOUTICA_TEST_PROMOTE_FAIL_AFTER", "")
    try:
        fail_after = int(fail_after_raw) if fail_after_raw else 0
    except ValueError:
        fail_after = 0

    def interrupted(signum: int, _frame: Any) -> None:
        raise PromotionInterrupted(f"received signal {signum}")

    old_int = signal.signal(signal.SIGINT, interrupted)
    old_term = signal.signal(signal.SIGTERM, interrupted)
    try:
        for target, data, mode in operations:
            if target not in snapshots:
                if target.is_symlink():
                    raise RuntimeError(f"refusing symlinked target: {target}")
                if target.exists():
                    snapshots[target] = (target.read_bytes(), stat.S_IMODE(target.stat().st_mode))
                else:
                    snapshots[target] = None
            _atomic_write(target, data, mode)
            changed.append(target)
            if target == registry_path and os.environ.get("SCOUTICA_TEST_REGISTRY_FAIL") == "1":
                raise RuntimeError("injected registry write failure")
            if fail_after and len(changed) >= fail_after:
                raise RuntimeError(f"injected promotion failure after {fail_after} writes")
        return 0
    except (OSError, RuntimeError) as exc:
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        rollback_error: Exception | None = None
        if os.environ.get("SCOUTICA_TEST_ROLLBACK_FAIL") == "1":
            rollback_error = RuntimeError("injected rollback failure")
        for target in reversed(changed):
            if rollback_error is not None:
                break
            snapshot = snapshots[target]
            try:
                if snapshot is None:
                    if target.exists() and not target.is_symlink():
                        target.unlink()
                        parent_fd = _open_directory(target.parent)
                        try:
                            os.fsync(parent_fd)
                        finally:
                            os.close(parent_fd)
                else:
                    _atomic_write(target, snapshot[0], snapshot[1])
            except Exception as rollback_exc:  # recovery path must retain all evidence
                rollback_error = rollback_exc
                break
        if rollback_error is not None:
            try:
                recovery = _write_recovery(card, snapshots, rollback_error)
                print(
                    f"Promotion and rollback failed. Recovery data preserved at: {recovery}",
                    file=sys.stderr,
                )
            except Exception as recovery_exc:
                print(
                    f"Promotion and rollback failed; recovery preservation also failed: {recovery_exc}",
                    file=sys.stderr,
                )
            return 2
        print(f"Promotion failed; prior card restored: {exc}", file=sys.stderr)
        return 1
    finally:
        signal.signal(signal.SIGINT, old_int)
        signal.signal(signal.SIGTERM, old_term)


def _state_update(card: Path, mutate: Any) -> int:
    if card.is_symlink():
        print(f"Refusing symlinked card directory: {card}", file=sys.stderr)
        return 1
    card = card.resolve(strict=True)
    state_path = _state_path(card)
    existing = _load_json(state_path, {})
    state = existing if isinstance(existing, dict) else {}
    state["schema_version"] = "0.1.0"
    mutate(state)
    try:
        _atomic_write(state_path, (json.dumps(state, indent=2) + "\n").encode("utf-8"), 0o600)
        return 0
    except (OSError, RuntimeError) as exc:
        print(f"Could not update card state: {exc}", file=sys.stderr)
        return 1


def cmd_state_preview(args: argparse.Namespace) -> int:
    card = _canonical_directory(args.card_dir)

    def mutate(state: dict[str, Any]) -> None:
        state["preview"] = {
            "url": args.url,
            "published_at": args.published_at,
            "expires_at": args.expires_at,
            "card_hash": args.card_hash,
        }

    return _state_update(card, mutate)


def cmd_state_resolve(args: argparse.Namespace) -> int:
    card = _canonical_directory(args.card_dir)

    def mutate(state: dict[str, Any]) -> None:
        state["resolve"] = {"url": args.url, "saved_at": _utc_now()}

    return _state_update(card, mutate)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    provider = subparsers.add_parser("provider-info")
    provider.add_argument("provider")
    provider.set_defaults(func=cmd_provider_info)

    run = subparsers.add_parser("run-provider")
    run.add_argument("provider")
    run.add_argument("--prompt-file", required=True)
    run.add_argument("--response-file", required=True)
    run.add_argument("--log-file", required=True)
    run.set_defaults(func=cmd_run_provider)

    source_hash = subparsers.add_parser("source-hash")
    source_hash.add_argument("--source", required=True)
    source_hash.set_defaults(func=cmd_source_hash)

    output_path = subparsers.add_parser("output-path")
    output_path.add_argument("--path", required=True)
    output_path.set_defaults(func=cmd_output_path)

    parse_response = subparsers.add_parser("parse-response")
    parse_response.add_argument("--response-file", required=True)
    parse_response.add_argument("--stage-dir", required=True)
    parse_response.set_defaults(func=cmd_parse_response)

    registry = subparsers.add_parser("registry-card")
    registry.add_argument("--registry", required=True)
    registry.add_argument("--source", required=True)
    registry.set_defaults(func=cmd_registry_card)

    state_get = subparsers.add_parser("state-get")
    state_get.add_argument("--card-dir", required=True)
    state_get.add_argument("--key", required=True)
    state_get.set_defaults(func=cmd_state_get)

    promote = subparsers.add_parser("promote")
    promote.add_argument("--stage-dir", required=True)
    promote.add_argument("--card-dir", required=True)
    promote.add_argument("--source-dir", required=True)
    promote.add_argument("--source-hash", required=True)
    promote.add_argument("--provider", required=True)
    promote.add_argument("--registry", required=True)
    promote.set_defaults(func=cmd_promote)

    preview = subparsers.add_parser("state-preview")
    preview.add_argument("--card-dir", required=True)
    preview.add_argument("--url", required=True)
    preview.add_argument("--published-at", required=True)
    preview.add_argument("--expires-at", required=True)
    preview.add_argument("--card-hash", required=True)
    preview.set_defaults(func=cmd_state_preview)

    resolve = subparsers.add_parser("state-resolve")
    resolve.add_argument("--card-dir", required=True)
    resolve.add_argument("--url", required=True)
    resolve.set_defaults(func=cmd_state_resolve)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main())
