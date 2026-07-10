#!/usr/bin/env python3
"""Trusted local persistence boundary for Scoutica messages.

The CLI deliberately keeps transport separate from composition.  This helper
validates complete envelopes before it performs the ordered local writes used
by ``send`` and ``reply``.
"""

from __future__ import annotations

import argparse
import errno
import fcntl
import hashlib
import json
import os
import stat
import sys
import tempfile
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, NoReturn

import jsonschema


MAX_JSON_BYTES = 2 * 1024 * 1024
MAX_LOG_BYTES = 8 * 1024 * 1024


class MessageError(Exception):
    """Expected policy or persistence failure."""


def fail(message: str) -> NoReturn:
    raise MessageError(message)


def _reject_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def read_json(path: Path, *, label: str) -> Any:
    try:
        if path.is_symlink():
            fail(f"Refusing to read symlinked {label}: {path}")
        with path.open("rb") as handle:
            raw = handle.read(MAX_JSON_BYTES + 1)
        if len(raw) > MAX_JSON_BYTES:
            fail(f"{label} exceeds the 2 MiB limit: {path}")
        return json.loads(
            raw.decode("utf-8", errors="strict"),
            object_pairs_hook=_reject_duplicate_keys,
        )
    except MessageError:
        raise
    except (OSError, UnicodeError, ValueError) as exc:
        fail(f"Invalid {label} at {path}: {exc}")


def load_validator(schema_path: Path) -> jsonschema.Draft7Validator:
    schema = read_json(schema_path, label="trusted message schema")
    try:
        jsonschema.Draft7Validator.check_schema(schema)
    except jsonschema.SchemaError as exc:
        fail(f"Trusted message schema is invalid: {exc.message}")
    return jsonschema.Draft7Validator(
        schema, format_checker=jsonschema.FormatChecker()
    )


def validate_message(
    validator: jsonschema.Draft7Validator, message: Any, *, label: str
) -> dict[str, Any]:
    errors = sorted(validator.iter_errors(message), key=lambda item: list(item.path))
    if errors:
        first = errors[0]
        location = ".".join(str(part) for part in first.absolute_path) or "<root>"
        fail(f"{label} is not a valid message envelope at {location}: {first.message}")
    if not isinstance(message, dict):  # Kept explicit for type checkers.
        fail(f"{label} must be a JSON object")
    return message


def utc_timestamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def canonical_bytes(document: Any) -> bytes:
    return (json.dumps(document, indent=2, ensure_ascii=False) + "\n").encode("utf-8")


def canonical_line(document: Any) -> bytes:
    return (json.dumps(document, sort_keys=True, separators=(",", ":")) + "\n").encode(
        "utf-8"
    )


def _assert_no_user_symlink(path: Path) -> None:
    """Reject symlinks in a caller-selected path while allowing macOS /tmp aliases."""
    absolute = path.expanduser().absolute()
    current = Path(absolute.anchor)
    for part in absolute.parts[1:]:
        current = current / part
        try:
            mode = os.lstat(current).st_mode
        except FileNotFoundError:
            continue
        except OSError as exc:
            fail(f"Cannot inspect message path {current}: {exc}")
        if stat.S_ISLNK(mode):
            # /tmp and /var are root-owned aliases on macOS.  User-controlled
            # descendants are never accepted as symlinks.
            if str(current) in {"/tmp", "/var"}:
                continue
            fail(f"Refusing symlinked message path: {current}")


class Store:
    def __init__(self, home: str):
        requested = Path(home).expanduser().absolute()
        _assert_no_user_symlink(requested)
        self.root = requested.resolve(strict=False)

    def path(self, *parts: str) -> Path:
        candidate = self.root.joinpath(*parts)
        try:
            candidate.relative_to(self.root)
        except ValueError:
            fail(f"Message path escapes runtime root: {candidate}")
        return candidate

    def ensure_dir(self, directory: Path) -> None:
        try:
            relative = directory.relative_to(self.root)
        except ValueError:
            fail(f"Message directory escapes runtime root: {directory}")

        if not self.root.exists():
            self.root.mkdir(parents=True, mode=0o700, exist_ok=True)
        if self.root.is_symlink() or not self.root.is_dir():
            fail(f"Unsafe message runtime root: {self.root}")
        try:
            os.chmod(self.root, 0o700)
        except OSError:
            pass

        current = self.root
        for part in relative.parts:
            current = current / part
            try:
                mode = os.lstat(current).st_mode
            except FileNotFoundError:
                try:
                    os.mkdir(current, 0o700)
                except FileExistsError:
                    pass
                except OSError as exc:
                    fail(f"Cannot create message directory {current}: {exc}")
                mode = os.lstat(current).st_mode
            except OSError as exc:
                fail(f"Cannot inspect message directory {current}: {exc}")
            if stat.S_ISLNK(mode) or not stat.S_ISDIR(mode):
                fail(f"Unsafe message directory: {current}")

    def assert_regular(self, path: Path, *, allow_missing: bool = False) -> bool:
        try:
            mode = os.lstat(path).st_mode
        except FileNotFoundError:
            if allow_missing:
                return False
            fail(f"Message file does not exist: {path}")
        except OSError as exc:
            fail(f"Cannot inspect message file {path}: {exc}")
        if stat.S_ISLNK(mode) or not stat.S_ISREG(mode):
            fail(f"Unsafe message file: {path}")
        return True

    @contextmanager
    def transition_lock(self):
        """Serialize one complete send/reply state transition across processes."""
        self.ensure_dir(self.root)
        lock_path = self.path(".message-runtime.lock")
        nofollow = getattr(os, "O_NOFOLLOW", 0)
        if not nofollow:
            fail("This platform cannot safely open the message runtime lock")
        flags = os.O_RDWR | nofollow
        fd = -1
        try:
            try:
                fd = os.open(lock_path, flags | os.O_CREAT | os.O_EXCL, 0o600)
            except OSError as exc:
                if exc.errno != errno.EEXIST:
                    fail(f"Cannot create message runtime lock {lock_path}: {exc}")
                fd = os.open(lock_path, flags)
            metadata = os.fstat(fd)
            if (
                not stat.S_ISREG(metadata.st_mode)
                or metadata.st_nlink != 1
                or metadata.st_uid != os.geteuid()
            ):
                fail(f"Unsafe message runtime lock: {lock_path}")
            os.fchmod(fd, 0o600)
            fcntl.flock(fd, fcntl.LOCK_EX)
            # Re-check after waiting: a same-user process must not swap or
            # hard-link the inode while contenders are queued.
            metadata = os.fstat(fd)
            path_metadata = os.lstat(lock_path)
            if (
                not stat.S_ISREG(path_metadata.st_mode)
                or metadata.st_ino != path_metadata.st_ino
                or metadata.st_dev != path_metadata.st_dev
                or metadata.st_nlink != 1
            ):
                fail(f"Message runtime lock changed while waiting: {lock_path}")
            yield
        except MessageError:
            raise
        except OSError as exc:
            fail(f"Cannot lock message runtime {lock_path}: {exc}")
        finally:
            if fd >= 0:
                try:
                    fcntl.flock(fd, fcntl.LOCK_UN)
                except OSError:
                    pass
                os.close(fd)

    def read_bytes(self, path: Path, *, limit: int) -> bytes:
        self.assert_regular(path)
        try:
            with path.open("rb") as handle:
                data = handle.read(limit + 1)
        except OSError as exc:
            fail(f"Cannot read message artifact {path}: {exc}")
        if len(data) > limit:
            fail(f"Message artifact exceeds size limit: {path}")
        return data

    def ensure_bytes(self, path: Path, content: bytes) -> None:
        """Create one artifact atomically or accept an identical existing file."""
        self.ensure_dir(path.parent)
        if self.assert_regular(path, allow_missing=True):
            if self.read_bytes(path, limit=max(MAX_JSON_BYTES, len(content))) != content:
                fail(f"Conflicting message artifact already exists: {path}")
            return

        fd = -1
        temp_name = ""
        try:
            fd, temp_name = tempfile.mkstemp(prefix=".message-", dir=path.parent)
            os.fchmod(fd, 0o600)
            with os.fdopen(fd, "wb") as handle:
                fd = -1
                handle.write(content)
                handle.flush()
                os.fsync(handle.fileno())
            # os.replace replaces rather than follows a final symlink.  Recheck
            # anyway so a pre-existing conflicting artifact is never hidden.
            if self.assert_regular(path, allow_missing=True):
                if self.read_bytes(path, limit=max(MAX_JSON_BYTES, len(content))) != content:
                    fail(f"Conflicting message artifact already exists: {path}")
                os.unlink(temp_name)
                temp_name = ""
                return
            os.replace(temp_name, path)
            temp_name = ""
            os.chmod(path, 0o600)
        except MessageError:
            raise
        except OSError as exc:
            fail(f"Cannot persist message artifact {path}: {exc}")
        finally:
            if fd >= 0:
                os.close(fd)
            if temp_name:
                try:
                    os.unlink(temp_name)
                except OSError:
                    pass

    def replace_bytes(self, path: Path, previous: bytes, content: bytes) -> None:
        """Atomically replace a regular file only if its bytes still match."""
        self.ensure_dir(path.parent)
        if self.read_bytes(path, limit=max(MAX_LOG_BYTES, len(previous))) != previous:
            fail(f"Message artifact changed during update: {path}")
        fd = -1
        temp_name = ""
        try:
            fd, temp_name = tempfile.mkstemp(prefix=".message-", dir=path.parent)
            os.fchmod(fd, 0o600)
            with os.fdopen(fd, "wb") as handle:
                fd = -1
                handle.write(content)
                handle.flush()
                os.fsync(handle.fileno())
            if self.read_bytes(path, limit=max(MAX_LOG_BYTES, len(previous))) != previous:
                fail(f"Message artifact changed during update: {path}")
            os.replace(temp_name, path)
            temp_name = ""
            os.chmod(path, 0o600)
        except MessageError:
            raise
        except OSError as exc:
            fail(f"Cannot update message artifact {path}: {exc}")
        finally:
            if fd >= 0:
                os.close(fd)
            if temp_name:
                try:
                    os.unlink(temp_name)
                except OSError:
                    pass


def identity_candidates(card_dir: Path) -> list[str]:
    if not card_dir.exists() or not card_dir.is_dir() or card_dir.is_symlink():
        fail(f"Card directory is missing or unsafe: {card_dir}")
    candidates: list[str] = []
    for name in ("scoutica.json", "recruiter_profile.json"):
        identity_file = card_dir / name
        if not identity_file.exists():
            continue
        document = read_json(identity_file, label="card identity")
        if not isinstance(document, dict):
            fail(f"Card identity must be an object: {identity_file}")
        value = document.get("card_url")
        if value is not None:
            if not isinstance(value, str) or not value.strip():
                fail(f"Card identity has an empty card_url: {identity_file}")
            candidates.append(value)
    return sorted(set(candidates))


def resolve_identity(card: str | None, cwd: str) -> str:
    card_dir = Path(card).expanduser() if card else Path(cwd)
    candidates = identity_candidates(card_dir.absolute())
    if len(candidates) != 1:
        qualifier = "explicit card" if card else "current directory fallback"
        fail(
            f"Cannot resolve one local sender from {qualifier}: found {len(candidates)} "
            "distinct card_url values; use --card <dir>."
        )
    return candidates[0]


def route_hash(url: str) -> str:
    return hashlib.sha256(url.encode("utf-8")).hexdigest()[:12]


def log_records(store: Store, log_path: Path) -> tuple[bytes, list[dict[str, Any]]]:
    if not store.assert_regular(log_path, allow_missing=True):
        return b"", []
    raw = store.read_bytes(log_path, limit=MAX_LOG_BYTES)
    records: list[dict[str, Any]] = []
    for number, line in enumerate(raw.splitlines(), 1):
        if not line.strip():
            continue
        try:
            value = json.loads(
                line.decode("utf-8", errors="strict"),
                object_pairs_hook=_reject_duplicate_keys,
            )
        except (UnicodeError, ValueError) as exc:
            fail(f"Invalid transparency log line {number}: {exc}")
        if not isinstance(value, dict):
            fail(f"Invalid transparency log line {number}: expected object")
        records.append(value)
    return raw, records


def ensure_log_entry(store: Store, path: Path, entry: dict[str, Any]) -> None:
    existed = store.assert_regular(path, allow_missing=True)
    raw, records = log_records(store, path)
    matches = [record for record in records if record.get("message_id") == entry["message_id"]]
    if matches:
        if len(matches) != 1 or matches[0] != entry:
            fail(f"Conflicting transparency log entry for {entry['message_id']}")
        return
    separator = b"" if not raw or raw.endswith(b"\n") else b"\n"
    updated = raw + separator + canonical_line(entry)
    if existed:
        store.replace_bytes(path, raw, updated)
    else:
        store.ensure_bytes(path, updated)


def message_paths(store: Store, message_id: str, recipient: str) -> tuple[Path, Path, Path]:
    return (
        store.path("outbox", f"{message_id}.json"),
        store.path("pending_delivery", route_hash(recipient), f"{message_id}.json"),
        store.path("privacy", "access_log.jsonl"),
    )


def existing_envelope(
    store: Store,
    validator: jsonschema.Draft7Validator,
    paths: list[Path],
) -> dict[str, Any] | None:
    found: list[dict[str, Any]] = []
    for path in paths:
        if store.assert_regular(path, allow_missing=True):
            document = read_json(path, label="existing message artifact")
            found.append(validate_message(validator, document, label=str(path)))
    if not found:
        return None
    if any(document != found[0] for document in found[1:]):
        fail("Existing outbox and pending message artifacts conflict")
    return found[0]


def persist_outbound(
    store: Store,
    message: dict[str, Any],
    log_entry: dict[str, Any],
) -> tuple[Path, Path, Path]:
    outbox, pending, log_path = message_paths(
        store, message["message_id"], message["recipient"]
    )
    # This order is the resumable contract.  Each step is atomic per file.
    store.ensure_bytes(outbox, canonical_bytes(message))
    store.ensure_bytes(pending, canonical_bytes(message))
    ensure_log_entry(store, log_path, log_entry)
    return outbox, pending, log_path


def build_payload(action: str, message_text: str) -> dict[str, Any]:
    if action == "reject":
        return {
            "reasons": [message_text] if message_text else ["auto_rejected_by_rules"],
            "auto_rejected": not bool(message_text),
        }
    if action == "accept" and message_text:
        return {"message": message_text}
    if action == "withdraw" and message_text:
        return {"reason": message_text}
    return {}


def _send_log_entry(message: dict[str, Any]) -> dict[str, Any]:
    return {
        "event": "message_sent",
        "message_id": message["message_id"],
        "recipient": message["recipient"],
        "sender": message["sender"]["card_url"],
        "type": message["type"],
        "timestamp": message["timestamp"],
        "transport": "git",
    }


def _same_send_composition(message: dict[str, Any], composition: dict[str, Any]) -> bool:
    return {
        key: value
        for key, value in message.items()
        if key not in {"message_id", "timestamp"}
    } == composition


def incomplete_send_prefix(
    store: Store,
    validator: jsonschema.Draft7Validator,
    composition: dict[str, Any],
) -> dict[str, Any] | None:
    """Return one resumable send prefix; ignore completed identical sends."""
    outbox_dir = store.path("outbox")
    if not outbox_dir.exists():
        return None
    if outbox_dir.is_symlink() or not outbox_dir.is_dir():
        fail(f"Unsafe outbox directory: {outbox_dir}")

    log_path = store.path("privacy", "access_log.jsonl")
    _raw_log, records = log_records(store, log_path)
    incomplete: list[dict[str, Any]] = []
    for path in sorted(outbox_dir.glob("*.json")):
        candidate = validate_message(
            validator, read_json(path, label="outbox message"), label=str(path)
        )
        if "in_reply_to" in candidate or not _same_send_composition(candidate, composition):
            continue

        expected_log = _send_log_entry(candidate)
        log_matches = [
            record for record in records if record.get("message_id") == candidate["message_id"]
        ]
        if len(log_matches) > 1:
            fail(f"Duplicate transparency log entries for {candidate['message_id']}")
        log_complete = False
        if log_matches:
            record = log_matches[0]
            # Logs created before the trusted runtime did not include sender.
            legacy_expected = dict(expected_log)
            del legacy_expected["sender"]
            if record not in (expected_log, legacy_expected):
                fail(f"Conflicting transparency log entry for {candidate['message_id']}")
            log_complete = True

        _outbox, pending, _log = message_paths(
            store, candidate["message_id"], candidate["recipient"]
        )
        pending_complete = store.assert_regular(pending, allow_missing=True)
        if pending_complete:
            pending_message = validate_message(
                validator,
                read_json(pending, label="pending message"),
                label=str(pending),
            )
            if pending_message != candidate:
                fail(f"Conflicting pending message artifact for {candidate['message_id']}")

        if log_complete:
            # The log is the final send step.  Pending may subsequently be
            # removed by `deliver`; either state is completed history, not a
            # permanent content deduplication key.
            continue
        incomplete.append(candidate)

    if len(incomplete) > 1:
        fail("Multiple matching incomplete send prefixes exist; refusing ambiguous recovery")
    return incomplete[0] if incomplete else None


def walk_message_files(root: Path, *, include_processed: bool) -> list[Path]:
    if not root.exists():
        return []
    if root.is_symlink() or not root.is_dir():
        fail(f"Unsafe inbox directory: {root}")
    result: list[Path] = []
    for current, dirs, files in os.walk(root):
        dirs.sort()
        files.sort()
        current_path = Path(current)
        if not include_processed:
            dirs[:] = [name for name in dirs if not (current_path == root and name == "processed")]
        for name in files:
            if name.endswith(".json"):
                result.append(current_path / name)
    return result


def find_original(
    store: Store,
    validator: jsonschema.Draft7Validator,
    message_id: str,
) -> tuple[dict[str, Any], Path, bool]:
    inbox = store.path("inbox")
    processed = inbox / "processed"
    active_paths = walk_message_files(inbox, include_processed=False)
    processed_paths = walk_message_files(processed, include_processed=True)
    matches: list[tuple[dict[str, Any], Path, bool]] = []
    for path, is_processed in [
        *((path, False) for path in active_paths),
        *((path, True) for path in processed_paths),
    ]:
        document = read_json(path, label="inbox message")
        if isinstance(document, dict) and document.get("message_id") == message_id:
            matches.append(
                (validate_message(validator, document, label=str(path)), path, is_processed)
            )
    if not matches:
        fail(f"Message not found: {message_id}. Check your inbox with: scoutica inbox")
    if len(matches) != 1:
        fail(f"Message ID is ambiguous across inbox files: {message_id}")
    return matches[0]


def move_to_processed(store: Store, source: Path, original: dict[str, Any]) -> Path:
    inbox = store.path("inbox")
    processed = inbox / "processed"
    try:
        relative = source.relative_to(inbox)
    except ValueError:
        fail(f"Inbox message escapes inbox root: {source}")
    if relative.parts and relative.parts[0] == "processed":
        return source
    destination = processed / relative
    store.ensure_dir(destination.parent)
    if store.assert_regular(destination, allow_missing=True):
        existing = read_json(destination, label="processed message")
        if existing != original:
            fail(f"Conflicting processed message already exists: {destination}")
        fail(f"Both actionable and processed copies exist: {source}")
    store.assert_regular(source)
    try:
        os.replace(source, destination)
        os.chmod(destination, 0o600)
    except OSError as exc:
        fail(f"Cannot move original message to processed storage: {exc}")
    return destination


def command_send(args: argparse.Namespace) -> None:
    validator = load_validator(Path(args.schema))
    sender = resolve_identity(args.card, args.cwd)
    payload: dict[str, Any] = {}
    if args.message:
        payload["message"] = args.message
    if args.role:
        role_path = Path(args.role)
        role = read_json(role_path, label="role attachment")
        if not isinstance(role, dict):
            fail("Role attachment must be a JSON object")
        payload["role_url"] = args.role
        compensation = role.get("compensation")
        if isinstance(compensation, dict):
            payload["compensation_summary"] = {
                "base_min": compensation.get("base_min"),
                "base_max": compensation.get("base_max"),
                "currency": compensation.get("currency"),
            }

    conversation_id = "conv_" + hashlib.sha256(
        f"{args.recipient}:{sender}:{args.type}".encode("utf-8")
    ).hexdigest()[:16]
    composition = {
        "type": args.type,
        "sender": {"card_url": sender},
        "recipient": args.recipient,
        "conversation_id": conversation_id,
        "ttl_hours": 168,
        "transport_used": "git",
        "payload": payload,
    }

    # Validate all caller-controlled fields before inspecting or creating the
    # runtime store.  The probe values satisfy only the envelope-owned fields.
    probe = dict(composition)
    probe["message_id"] = "msg_0000000000000000"
    probe["timestamp"] = utc_timestamp()
    validate_message(validator, probe, label="Generated message")
    store = Store(args.home)
    with store.transition_lock():
        message = incomplete_send_prefix(store, validator, composition)
        resumed = message is not None
        if message is None:
            now_value = datetime.now(timezone.utc)
            message = dict(composition)
            message["message_id"] = "msg_" + hashlib.sha256(
                f"{args.recipient}:{now_value.isoformat(timespec='microseconds')}".encode("utf-8")
            ).hexdigest()[:16]
            message["timestamp"] = now_value.strftime("%Y-%m-%dT%H:%M:%SZ")
            validate_message(validator, message, label="Generated message")

        message_id = message["message_id"]
        log_entry = _send_log_entry(message)
        outbox, pending, log_path = persist_outbound(store, message, log_entry)
        verb = "resumed" if resumed else "created"
        print(f"  ✅ Message {verb}: {message_id}")
        print(f"     Type: {args.type}")
        print(f"     Recipient: {args.recipient}")
        print(f"     Conversation: {conversation_id}")
        print(f"     Saved to: {outbox}")
        print()
        print(f"  📬 Pending delivery at: {pending}")
        print("     Nothing is transmitted until you run: scoutica deliver")
        print()
        print(f"  📋 Logged to: {log_path}")


def _reply_static_fields(
    original: dict[str, Any], action: str, message_text: str, sender: str, reply_id: str
) -> dict[str, Any]:
    response: dict[str, Any] = {
        "message_id": reply_id,
        "type": f"response.{action}",
        "sender": {"card_url": sender},
        "recipient": original["sender"]["card_url"],
        "in_reply_to": original["message_id"],
        "ttl_hours": 168,
        "transport_used": "git",
        "payload": build_payload(action, message_text),
    }
    if "conversation_id" in original:
        response["conversation_id"] = original["conversation_id"]
    return response


def command_reply(args: argparse.Namespace) -> None:
    validator = load_validator(Path(args.schema))
    sender = resolve_identity(args.card, args.cwd)
    store = Store(args.home)
    with store.transition_lock():
        original, original_path, already_processed = find_original(
            store, validator, args.message_id
        )
        if original["recipient"] != sender:
            fail(
                "Selected local card does not match the original message recipient; "
                "refusing to impersonate another responder."
            )

        digest_input = json.dumps(
            [original["message_id"], args.action, sender], separators=(",", ":"), ensure_ascii=False
        )
        reply_id = "msg_" + hashlib.sha256(digest_input.encode("utf-8")).hexdigest()[:16]
        static = _reply_static_fields(original, args.action, args.message, sender, reply_id)
        outbox, pending, log_path = message_paths(store, reply_id, static["recipient"])
        existing = existing_envelope(store, validator, [outbox, pending])

        # Reject a second or different action for the same original.  The exact
        # deterministic action remains retryable even after the original was filed.
        outbox_dir = store.path("outbox")
        pending_dir = store.path("pending_delivery")
        prior_reply_paths: list[Path] = []
        if outbox_dir.exists():
            prior_reply_paths.extend(sorted(outbox_dir.glob("*.json")))
        if pending_dir.exists():
            prior_reply_paths.extend(walk_message_files(pending_dir, include_processed=True))
        for path in prior_reply_paths:
            document = read_json(path, label="outbound message")
            if isinstance(document, dict) and document.get("in_reply_to") == args.message_id:
                validated = validate_message(validator, document, label=str(path))
                if validated.get("message_id") != reply_id:
                    fail(f"Message {args.message_id} was already answered with a different action")

        timestamp: str | None = existing.get("timestamp") if existing else None
        raw_log, records = log_records(store, log_path)
        del raw_log
        matching_log = [record for record in records if record.get("message_id") == reply_id]
        other_reply_logs = [
            record
            for record in records
            if record.get("event") == "reply_sent"
            and record.get("in_reply_to") == args.message_id
            and record.get("message_id") != reply_id
        ]
        if other_reply_logs:
            fail(f"Message {args.message_id} was already logged with a different action")
        if matching_log:
            if len(matching_log) != 1:
                fail(f"Duplicate transparency log entries for {reply_id}")
            logged_timestamp = matching_log[0].get("timestamp")
            if timestamp is not None and logged_timestamp != timestamp:
                fail(f"Existing reply artifacts disagree on timestamp for {reply_id}")
            if isinstance(logged_timestamp, str):
                timestamp = logged_timestamp
        if timestamp is None:
            timestamp = utc_timestamp()

        response = dict(static)
        response["timestamp"] = timestamp
        validate_message(validator, response, label="Generated reply")
        if existing is not None and existing != response:
            fail(f"Conflicting existing reply content for {reply_id}")
        log_entry = {
            "event": "reply_sent",
            "message_id": reply_id,
            "in_reply_to": args.message_id,
            "type": response["type"],
            "recipient": response["recipient"],
            "sender": sender,
            "timestamp": timestamp,
            "transport": "git",
        }
        if already_processed and (existing is None or matching_log != [log_entry]):
            fail(
                f"Message {args.message_id} is already processed and has no complete matching "
                "staged reply; it is not actionable."
            )
        persist_outbound(store, response, log_entry)
        processed_path = original_path if already_processed else move_to_processed(
            store, original_path, original
        )

        icons = {"accept": "✅", "reject": "❌", "withdraw": "🚪"}
        suffix = " (already staged)" if already_processed else ""
        print(f"  {icons[args.action]} Reply staged: {reply_id}{suffix}")
        print(f"     Action: {args.action}")
        print(f"     From: {sender}")
        print(f"     To: {response['recipient']}")
        print(f"     In reply to: {args.message_id}")
        print()
        print(f"  📬 Pending delivery at: {pending}")
        print(f"  📋 Original filed at: {processed_path}")


def command_inbox(args: argparse.Namespace) -> None:
    validator = load_validator(Path(args.schema))
    store = Store(args.home)
    inbox = store.path("inbox")
    messages: list[dict[str, Any]] = []
    for path in walk_message_files(inbox, include_processed=False):
        message = validate_message(
            validator, read_json(path, label="inbox message"), label=str(path)
        )
        annotated = dict(message)
        annotated["_source"] = "inbox"
        annotated["_file"] = str(path)
        messages.append(annotated)

    pending = store.path("pending_delivery")
    pending_count = len(walk_message_files(pending, include_processed=True))
    if args.json:
        print(
            json.dumps(
                {
                    "messages": messages,
                    "count": len(messages),
                    "pending_delivery": pending_count,
                },
                indent=2,
                ensure_ascii=False,
            )
        )
        return

    if not messages and pending_count == 0:
        print("  📭 No messages in your inbox.")
        print()
        print("  Messages arrive when another card delivers an offer through the registry.")
        return
    if messages:
        print(f"  📬 {len(messages)} message(s) in inbox:\n")
        icons = {
            "opportunity.pitch": "💡",
            "opportunity.offer": "💰",
            "response.accept": "✅",
            "response.reject": "❌",
            "status.check": "❓",
            "rules.check": "📋",
            "response.withdraw": "🚪",
            "event.ghosting": "👻",
        }
        for message in messages:
            kind = message["type"]
            print(f"  {icons.get(kind, '📩')} {message['message_id']} — {kind}")
            print(f"     From: {message['sender']['card_url']}")
            print(f"     Date: {message['timestamp'][:16]}")
            if message.get("conversation_id"):
                print(f"     Thread: {message['conversation_id']}")
            payload = message.get("payload", {})
            if "message" in payload:
                print(f"     Message: {str(payload['message'])[:80]}")
            if "role_url" in payload:
                print(f"     Role: {payload['role_url']}")
            if "compensation_summary" in payload:
                comp = payload["compensation_summary"]
                if isinstance(comp, dict):
                    print(
                        f"     Compensation: {comp.get('base_min', '?')}-"
                        f"{comp.get('base_max', '?')} {comp.get('currency', '')}"
                    )
            if "reasons" in payload and isinstance(payload["reasons"], list):
                print(f"     Reasons: {', '.join(str(x) for x in payload['reasons'][:3])}")
            print()
    if pending_count:
        print(f"  📤 {pending_count} message(s) pending delivery (outbox)")
        print("     Run 'scoutica deliver' to push to registry")


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    subparsers = result.add_subparsers(dest="command", required=True)
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--schema", required=True)
    common.add_argument("--home", required=True)

    send = subparsers.add_parser("send", parents=[common])
    send.add_argument("--recipient", required=True)
    send.add_argument("--type", default="opportunity.pitch")
    send.add_argument("--role", default="")
    send.add_argument("--message", default="")
    send.add_argument("--card")
    send.add_argument("--cwd", required=True)
    send.set_defaults(func=command_send)

    reply = subparsers.add_parser("reply", parents=[common])
    reply.add_argument("--message-id", required=True)
    reply.add_argument("--action", required=True, choices=("accept", "reject", "withdraw"))
    reply.add_argument("--message", default="")
    reply.add_argument("--card")
    reply.add_argument("--cwd", required=True)
    reply.set_defaults(func=command_reply)

    inbox = subparsers.add_parser("inbox", parents=[common])
    inbox.add_argument("--json", action="store_true")
    inbox.set_defaults(func=command_inbox)
    return result


def main() -> int:
    args = parser().parse_args()
    try:
        args.func(args)
    except MessageError as exc:
        print(f"Message error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
