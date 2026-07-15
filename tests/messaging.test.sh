#!/bin/sh
# Phase 6 messaging contract: identity, validation, idempotency, ordered writes,
# collision-safe processing, and pure machine output.

. "$TESTLIB/assert.sh"

PYTHON=${SCOUTICA_TEST_PYTHON:-python3}
case "$PYTHON" in */*) PATH="$(dirname "$PYTHON"):$PATH"; export PATH ;; esac

CASE_ROOT="$WORK/messaging"
mkdir -p "$CASE_ROOT"

make_card() {
    _mc_dir=$1
    _mc_url=$2
    mkdir -p "$_mc_dir"
    "$PYTHON" - "$_mc_dir/scoutica.json" "$_mc_url" <<'PY'
import json, sys
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump({"scoutica": "0.4.0", "card_url": sys.argv[2], "name": "Alice Developer"}, handle)
    handle.write("\n")
PY
}

make_message() {
    _mm_path=$1
    _mm_id=$2
    _mm_sender=$3
    _mm_recipient=$4
    _mm_conversation=${5:-conv_12345678}
    mkdir -p "$(dirname "$_mm_path")"
    "$PYTHON" - "$_mm_path" "$_mm_id" "$_mm_sender" "$_mm_recipient" "$_mm_conversation" <<'PY'
import json, sys
message = {
    "message_id": sys.argv[2],
    "type": "opportunity.pitch",
    "sender": {"card_url": sys.argv[3]},
    "recipient": sys.argv[4],
    "conversation_id": sys.argv[5],
    "timestamp": "2026-07-10T12:00:00Z",
    "ttl_hours": 168,
    "transport_used": "git",
    "payload": {"message": "Would you like to discuss this role?"},
}
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(message, handle, indent=2)
    handle.write("\n")
PY
}

reply_id() {
    "$PYTHON" - "$1" "$2" "$3" <<'PY'
import hashlib, json, sys
raw = json.dumps([sys.argv[1], sys.argv[2], sys.argv[3]], separators=(",", ":"), ensure_ascii=False)
print("msg_" + hashlib.sha256(raw.encode()).hexdigest()[:16])
PY
}

A_URL=https://cards.example.test/alice
B_URL=https://cards.example.test/blair

# A -> B -> A identity, relative processed route, inbox purity, and idempotent retry.
t_begin F-09 "reply uses local identity, preserves thread, prunes processed, and retries idempotently"
ROOT="$CASE_ROOT/identity"
make_card "$ROOT/card-a" "$A_URL"
make_card "$ROOT/card-b" "$B_URL"
make_message "$ROOT/runtime/inbox/account/threads/incoming.json" msg_a1b2c3d4 "$A_URL" "$B_URL" conv_a1b2c3d4
SCOUTICA_HOME="$ROOT/runtime" "$SCOUTICA" reply msg_a1b2c3d4 --accept \
    --message "Yes, let us talk." --card "$ROOT/card-b" >"$ROOT/reply.out" 2>"$ROOT/reply.err"
_rc=$?
assert_eq 0 "$_rc" "valid reply must succeed"
RID=$(reply_id msg_a1b2c3d4 accept "$B_URL")
REPLY="$ROOT/runtime/outbox/$RID.json"
assert_exists "$REPLY"
assert_exists "$ROOT/runtime/inbox/processed/account/threads/incoming.json"
assert_not_exists "$ROOT/runtime/inbox/account/threads/incoming.json"
"$PYTHON" - "$REPLY" "$REPO_ROOT/schemas/recruiter/message.schema.json" "$A_URL" "$B_URL" <<'PY' || t_fail "reply envelope failed identity/schema assertions"
import json, jsonschema, sys
message = json.load(open(sys.argv[1], encoding="utf-8"))
schema = json.load(open(sys.argv[2], encoding="utf-8"))
jsonschema.validate(message, schema, format_checker=jsonschema.FormatChecker())
assert message["sender"]["card_url"] == sys.argv[4]
assert message["recipient"] == sys.argv[3]
assert message["conversation_id"] == "conv_a1b2c3d4"
assert message["in_reply_to"] == "msg_a1b2c3d4"
PY
SCOUTICA_HOME="$ROOT/runtime" "$SCOUTICA" inbox --json >"$ROOT/inbox.json" 2>"$ROOT/inbox.err"
_rc=$?
assert_eq 0 "$_rc" "JSON inbox must succeed"
"$PYTHON" -m json.tool "$ROOT/inbox.json" >/dev/null 2>&1 || t_fail "inbox stdout is not pure JSON"
assert_no_grep '\033|Scoutica Inbox|processed' "$ROOT/inbox.json" "JSON output must contain no header, ANSI, or processed messages"
assert_grep '"count": 0' "$ROOT/inbox.json"
SCOUTICA_HOME="$ROOT/runtime" "$SCOUTICA" reply msg_a1b2c3d4 --accept \
    --message "Yes, let us talk." --card "$ROOT/card-b" >"$ROOT/retry.out" 2>"$ROOT/retry.err"
_rc=$?
assert_eq 0 "$_rc" "same deterministic reply must be idempotent"
_outbox_count=$(find "$ROOT/runtime/outbox" -type f -name '*.json' | wc -l | tr -d ' ')
_log_count=$(grep -c "\"message_id\":\"$RID\"" "$ROOT/runtime/privacy/access_log.jsonl" || true)
assert_eq 1 "$_outbox_count" "retry must not duplicate outbox envelope"
assert_eq 1 "$_log_count" "retry must not duplicate transparency event"
SCOUTICA_HOME="$ROOT/runtime" "$SCOUTICA" reply msg_a1b2c3d4 --reject \
    --card "$ROOT/card-b" >"$ROOT/conflicting-action.out" 2>"$ROOT/conflicting-action.err"
_rc=$?
assert_ne 0 "$_rc" "different action after processing must fail closed"
t_end

# A retry recognizes one matching ordered send prefix, but a completed send is
# not a permanent deduplication key for future deliberate messages.
t_begin F-09 "send resumes an incomplete prefix and permits a later identical send"
ROOT="$CASE_ROOT/send-resume"
make_card "$ROOT/card-a" "$A_URL"
HASH=$("$PYTHON" -c 'import hashlib,sys; print(hashlib.sha256(sys.argv[1].encode()).hexdigest()[:12])' "$B_URL")
mkdir -p "$ROOT/runtime/pending_delivery"
ln -s "$ROOT/missing-route" "$ROOT/runtime/pending_delivery/$HASH"
SCOUTICA_HOME="$ROOT/runtime" "$SCOUTICA" send "$B_URL" --card "$ROOT/card-a" \
    --type opportunity.pitch --message "Stable retry composition." \
    >"$ROOT/first.out" 2>"$ROOT/first.err"
_first_rc=$?
assert_ne 0 "$_first_rc" "pending-route failure must surface"
_first_count=$(find "$ROOT/runtime/outbox" -type f -name '*.json' | wc -l | tr -d ' ')
assert_eq 1 "$_first_count" "failed send must leave one ordered outbox prefix"
FIRST_FILE=$(find "$ROOT/runtime/outbox" -type f -name '*.json' | head -n 1)
FIRST_ID=$(basename "$FIRST_FILE" .json)
assert_not_exists "$ROOT/runtime/privacy/access_log.jsonl"
rm "$ROOT/runtime/pending_delivery/$HASH"

SCOUTICA_HOME="$ROOT/runtime" "$SCOUTICA" send "$B_URL" --card "$ROOT/card-a" \
    --type opportunity.pitch --message "Stable retry composition." \
    >"$ROOT/retry.out" 2>"$ROOT/retry.err"
_retry_rc=$?
assert_eq 0 "$_retry_rc" "identical retry must fill the incomplete prefix"
_retry_count=$(find "$ROOT/runtime/outbox" -type f -name '*.json' | wc -l | tr -d ' ')
assert_eq 1 "$_retry_count" "retry must reuse rather than orphan the first outbox ID"
assert_exists "$ROOT/runtime/pending_delivery/$HASH/$FIRST_ID.json"
assert_grep "Message resumed: $FIRST_ID" "$ROOT/retry.out"
_log_count=$(grep -c "\"message_id\":\"$FIRST_ID\"" "$ROOT/runtime/privacy/access_log.jsonl" || true)
assert_eq 1 "$_log_count" "resumed send must write one transparency record"

SCOUTICA_HOME="$ROOT/runtime" "$SCOUTICA" send "$B_URL" --card "$ROOT/card-a" \
    --type opportunity.pitch --message "Stable retry composition." \
    >"$ROOT/new.out" 2>"$ROOT/new.err"
_new_rc=$?
assert_eq 0 "$_new_rc" "completed identical send must not block a deliberate new send"
_new_count=$(find "$ROOT/runtime/outbox" -type f -name '*.json' | wc -l | tr -d ' ')
assert_eq 2 "$_new_count" "new send after completion must receive a fresh ID"

rm -rf "$ROOT/runtime/pending_delivery"
SCOUTICA_HOME="$ROOT/runtime" "$SCOUTICA" send "$B_URL" --card "$ROOT/card-a" \
    --type opportunity.pitch --message "Stable retry composition." \
    >"$ROOT/post-delivery.out" 2>"$ROOT/post-delivery.err"
_delivered_rc=$?
assert_eq 0 "$_delivered_rc" "delivered history without pending files must permit a new send"
_delivered_count=$(find "$ROOT/runtime/outbox" -type f -name '*.json' | wc -l | tr -d ' ')
assert_eq 3 "$_delivered_count" "post-delivery send must mint a fresh ID rather than resume history"
t_end

# The persistent private flock serializes the full state transition, preventing
# lost JSONL updates and divergent deterministic reply timestamps.
t_begin F-09 "parallel sends and replies preserve every successful transition exactly once"
ROOT="$CASE_ROOT/concurrency"
make_card "$ROOT/card-a" "$A_URL"
mkdir -p "$ROOT/send-results"
_pids=""
_i=1
while [ "$_i" -le 16 ]; do
    (
        SCOUTICA_HOME="$ROOT/send-runtime" "$SCOUTICA" send "$B_URL" --card "$ROOT/card-a" \
            --message "Parallel composition $_i" \
            >"$ROOT/send-results/$_i.out" 2>"$ROOT/send-results/$_i.err"
        printf '%s\n' "$?" > "$ROOT/send-results/$_i.rc"
    ) &
    _pids="$_pids $!"
    _i=$((_i + 1))
done
for _pid in $_pids; do wait "$_pid"; done

_i=1
while [ "$_i" -le 16 ]; do
    assert_eq 0 "$(cat "$ROOT/send-results/$_i.rc")" "parallel send $_i must succeed"
    _i=$((_i + 1))
done
"$PYTHON" - "$ROOT/send-runtime" "$REPO_ROOT/schemas/recruiter/message.schema.json" "$ROOT/send-results" 16 <<'PY' || t_fail "parallel send artifacts/log are incomplete, duplicated, or corrupt"
import collections, json, pathlib, re, sys
import jsonschema

root = pathlib.Path(sys.argv[1])
schema = json.load(open(sys.argv[2], encoding="utf-8"))
results = pathlib.Path(sys.argv[3])
expected = int(sys.argv[4])
validator = jsonschema.Draft7Validator(schema, format_checker=jsonschema.FormatChecker())
outbox = sorted((root / "outbox").glob("*.json"))
pending = sorted((root / "pending_delivery").glob("*/*.json"))
records = [json.loads(line) for line in (root / "privacy" / "access_log.jsonl").read_text().splitlines() if line]
successful_ids = []
for output in sorted(results.glob("*.out")):
    match = re.search(r"Message (?:created|resumed): (msg_[a-f0-9]+)", output.read_text())
    assert match, output
    successful_ids.append(match.group(1))
assert len(outbox) == len(pending) == len(records) == expected
counts = collections.Counter(record["message_id"] for record in records)
assert set(counts.values()) == {1}
outbox_docs = {}
pending_docs = {}
for path in outbox:
    document = json.load(open(path, encoding="utf-8"))
    outbox_docs[document["message_id"]] = document
for path in pending:
    document = json.load(open(path, encoding="utf-8"))
    pending_docs[document["message_id"]] = document
assert len(successful_ids) == len(set(successful_ids)) == expected
assert set(successful_ids) == set(outbox_docs) == set(pending_docs) == set(counts)
for message_id, document in outbox_docs.items():
    validator.validate(document)
    assert pending_docs[message_id] == document
PY

make_card "$ROOT/card-b" "$B_URL"
make_message "$ROOT/reply-runtime/inbox/thread/incoming.json" msg_cc11dd22 "$A_URL" "$B_URL"
mkdir -p "$ROOT/reply-results"
_pids=""
_i=1
while [ "$_i" -le 8 ]; do
    (
        SCOUTICA_HOME="$ROOT/reply-runtime" "$SCOUTICA" reply msg_cc11dd22 --accept \
            --message "One deterministic response." --card "$ROOT/card-b" \
            >"$ROOT/reply-results/$_i.out" 2>"$ROOT/reply-results/$_i.err"
        printf '%s\n' "$?" > "$ROOT/reply-results/$_i.rc"
    ) &
    _pids="$_pids $!"
    _i=$((_i + 1))
done
for _pid in $_pids; do wait "$_pid"; done
_i=1
while [ "$_i" -le 8 ]; do
    assert_eq 0 "$(cat "$ROOT/reply-results/$_i.rc")" "parallel reply $_i must be idempotent"
    _i=$((_i + 1))
done
_reply_outbox=$(find "$ROOT/reply-runtime/outbox" -type f -name '*.json' | wc -l | tr -d ' ')
_reply_pending=$(find "$ROOT/reply-runtime/pending_delivery" -type f -name '*.json' | wc -l | tr -d ' ')
_reply_logs=$(grep -c '"event":"reply_sent"' "$ROOT/reply-runtime/privacy/access_log.jsonl" || true)
assert_eq 1 "$_reply_outbox" "parallel deterministic replies must share one outbox envelope"
assert_eq 1 "$_reply_pending" "parallel deterministic replies must share one pending envelope"
assert_eq 1 "$_reply_logs" "parallel deterministic replies must log once"
assert_exists "$ROOT/reply-runtime/inbox/processed/thread/incoming.json"
t_end

# The serialization primitive itself must not become a symlink write gadget.
t_begin F-09 "message transition lock refuses symlinks without touching the victim"
ROOT="$CASE_ROOT/lock-symlink"
make_card "$ROOT/card-a" "$A_URL"
mkdir -p "$ROOT/runtime"
printf '%s\n' 'lock-victim-must-remain-unchanged' > "$ROOT/victim"
ln -s "$ROOT/victim" "$ROOT/runtime/.message-runtime.lock"
_before=$(shasum -a 256 "$ROOT/victim" | awk '{print $1}')
SCOUTICA_HOME="$ROOT/runtime" "$SCOUTICA" send "$B_URL" --card "$ROOT/card-a" \
    >"$ROOT/send.out" 2>"$ROOT/send.err"
_rc=$?
_after=$(shasum -a 256 "$ROOT/victim" | awk '{print $1}')
assert_ne 0 "$_rc" "symlinked transition lock must fail closed"
assert_eq "$_before" "$_after" "lock victim must remain unchanged"
assert_not_exists "$ROOT/runtime/outbox"
assert_not_exists "$ROOT/runtime/pending_delivery"
assert_not_exists "$ROOT/runtime/privacy"
t_end

# Machine-mode success, empty, and failure are all stdout-pure contracts.
t_begin F-13 "inbox JSON mode emits one document or empty stdout on failure"
ROOT="$CASE_ROOT/json-purity"
make_message "$ROOT/message-runtime/inbox/incoming.json" msg_aa11bb22 "$A_URL" "$B_URL"
SCOUTICA_HOME="$ROOT/message-runtime" "$SCOUTICA" inbox --json >"$ROOT/message.json" 2>"$ROOT/message.err"
_message_rc=$?
SCOUTICA_HOME="$ROOT/empty-runtime" "$SCOUTICA" inbox --json >"$ROOT/empty.json" 2>"$ROOT/empty.err"
_empty_rc=$?
mkdir -p "$ROOT/failure-runtime/inbox"
printf '%s\n' '{malformed' > "$ROOT/failure-runtime/inbox/broken.json"
SCOUTICA_HOME="$ROOT/failure-runtime" "$SCOUTICA" inbox --json >"$ROOT/failure.out" 2>"$ROOT/failure.err"
_failure_rc=$?
assert_eq 0 "$_message_rc" "nonempty inbox JSON must succeed"
assert_eq 0 "$_empty_rc" "empty inbox JSON must succeed"
assert_ne 0 "$_failure_rc" "invalid inbox must fail"
"$PYTHON" - "$ROOT/message.json" "$ROOT/empty.json" "$ROOT/failure.out" <<'PY' || t_fail "inbox JSON purity contract failed"
import json, pathlib, sys
message_raw = pathlib.Path(sys.argv[1]).read_bytes()
empty_raw = pathlib.Path(sys.argv[2]).read_bytes()
failure_raw = pathlib.Path(sys.argv[3]).read_bytes()
assert b"\x1b" not in message_raw and b"\x1b" not in empty_raw
message = json.loads(message_raw)
empty = json.loads(empty_raw)
assert message["count"] == 1 and len(message["messages"]) == 1
assert empty == {"messages": [], "count": 0, "pending_delivery": 0}
assert failure_raw == b""
PY
assert_no_grep 'Scoutica Inbox' "$ROOT/message.json"
assert_no_grep 'Scoutica Inbox' "$ROOT/empty.json"
assert_grep 'Message error:' "$ROOT/failure.err"
t_end

# Missing or ambiguous fallback identity must fail before any outbound mutation.
t_begin F-09 "reply sender fallback is allowed only for one unambiguous local card"
ROOT="$CASE_ROOT/identity-failure"
make_message "$ROOT/runtime/inbox/original.json" msg_b1b2c3d4 "$A_URL" "$B_URL"
mkdir -p "$ROOT/empty"
(cd "$ROOT/empty" && SCOUTICA_HOME="$ROOT/runtime" "$SCOUTICA" reply msg_b1b2c3d4 --accept) \
    >"$ROOT/missing.out" 2>"$ROOT/missing.err"
_rc=$?
assert_ne 0 "$_rc" "missing fallback identity must fail"
assert_not_exists "$ROOT/runtime/outbox"
make_card "$ROOT/ambiguous" "$B_URL"
"$PYTHON" - "$ROOT/ambiguous/recruiter_profile.json" <<'PY'
import json, sys
json.dump({"card_url": "https://cards.example.test/other"}, open(sys.argv[1], "w", encoding="utf-8"))
PY
(cd "$ROOT/ambiguous" && SCOUTICA_HOME="$ROOT/runtime" "$SCOUTICA" reply msg_b1b2c3d4 --accept) \
    >"$ROOT/ambiguous.out" 2>"$ROOT/ambiguous.err"
_rc=$?
assert_ne 0 "$_rc" "ambiguous fallback identity must fail"
assert_not_exists "$ROOT/runtime/outbox"
assert_exists "$ROOT/runtime/inbox/original.json" "identity failure must leave original actionable"
rm "$ROOT/ambiguous/recruiter_profile.json"
(cd "$ROOT/ambiguous" && SCOUTICA_HOME="$ROOT/runtime" "$SCOUTICA" reply msg_b1b2c3d4 --accept) \
    >"$ROOT/unambiguous.out" 2>"$ROOT/unambiguous.err"
_rc=$?
assert_eq 0 "$_rc" "one local fallback card must resolve without --card"
t_end

# Nested same-basename messages retain their relative route under processed/.
t_begin F-09 "processed storage preserves routes for same-basename inbox messages"
ROOT="$CASE_ROOT/collisions"
make_card "$ROOT/card-b" "$B_URL"
make_message "$ROOT/runtime/inbox/one/shared.json" msg_c1b2c3d4 "$A_URL" "$B_URL" conv_c1b2c3d4
make_message "$ROOT/runtime/inbox/two/shared.json" msg_d1b2c3d4 "$A_URL" "$B_URL" conv_d1b2c3d4
SCOUTICA_HOME="$ROOT/runtime" "$SCOUTICA" reply msg_c1b2c3d4 --accept --card "$ROOT/card-b" >/dev/null 2>"$ROOT/one.err"
_rc1=$?
SCOUTICA_HOME="$ROOT/runtime" "$SCOUTICA" reply msg_d1b2c3d4 --reject --card "$ROOT/card-b" >/dev/null 2>"$ROOT/two.err"
_rc2=$?
assert_eq 0 "$_rc1" "first same-basename message must process"
assert_eq 0 "$_rc2" "second same-basename message must process"
assert_exists "$ROOT/runtime/inbox/processed/one/shared.json"
assert_exists "$ROOT/runtime/inbox/processed/two/shared.json"
t_end

# Generated and received invalid envelopes fail before outbound artifacts appear.
t_begin F-18 "invalid message type, URI, and sender produce zero outbound artifacts"
ROOT="$CASE_ROOT/invalid"
make_card "$ROOT/card-a" "$A_URL"
SCOUTICA_HOME="$ROOT/valid-runtime" "$SCOUTICA" send "$B_URL" --card "$ROOT/card-a" \
    --message "Valid generated contract." >"$ROOT/valid.out" 2>"$ROOT/valid.err"
_valid_rc=$?
assert_eq 0 "$_valid_rc" "valid send must persist"
VALID_SEND=$(find "$ROOT/valid-runtime/outbox" -type f -name '*.json' | head -n 1)
"$PYTHON" - "$VALID_SEND" "$REPO_ROOT/schemas/recruiter/message.schema.json" <<'PY' || t_fail "valid send does not satisfy trusted schema"
import json, jsonschema, sys
jsonschema.validate(
    json.load(open(sys.argv[1], encoding="utf-8")),
    json.load(open(sys.argv[2], encoding="utf-8")),
    format_checker=jsonschema.FormatChecker(),
)
PY
SCOUTICA_HOME="$ROOT/type-runtime" "$SCOUTICA" send "$B_URL" --type arbitrary.execute --card "$ROOT/card-a" \
    >"$ROOT/type.out" 2>"$ROOT/type.err"
_type_rc=$?
SCOUTICA_HOME="$ROOT/uri-runtime" "$SCOUTICA" send 'not a uri' --card "$ROOT/card-a" \
    >"$ROOT/uri.out" 2>"$ROOT/uri.err"
_uri_rc=$?
mkdir -p "$ROOT/empty-card"
printf '%s\n' '{"scoutica":"0.4.0","card_url":"","name":"Alice Developer"}' > "$ROOT/empty-card/scoutica.json"
SCOUTICA_HOME="$ROOT/sender-runtime" "$SCOUTICA" send "$B_URL" --card "$ROOT/empty-card" \
    >"$ROOT/sender.out" 2>"$ROOT/sender.err"
_sender_rc=$?
assert_ne 0 "$_type_rc" "unknown message type must fail"
assert_ne 0 "$_uri_rc" "invalid recipient URI must fail"
assert_ne 0 "$_sender_rc" "empty sender must fail"
assert_not_exists "$ROOT/type-runtime"
assert_not_exists "$ROOT/uri-runtime"
assert_not_exists "$ROOT/sender-runtime"

make_card "$ROOT/card-b" "$B_URL"
make_message "$ROOT/reply-runtime/inbox/invalid.json" msg_e1b2c3d4 '' "$B_URL"
SCOUTICA_HOME="$ROOT/reply-runtime" "$SCOUTICA" reply msg_e1b2c3d4 --accept --card "$ROOT/card-b" \
    >"$ROOT/reply.out" 2>"$ROOT/reply.err"
_reply_rc=$?
assert_ne 0 "$_reply_rc" "invalid received sender must fail"
assert_not_exists "$ROOT/reply-runtime/outbox"
assert_not_exists "$ROOT/reply-runtime/pending_delivery"
assert_not_exists "$ROOT/reply-runtime/privacy"
assert_not_exists "$ROOT/reply-runtime/inbox/processed"
assert_exists "$ROOT/reply-runtime/inbox/invalid.json"

mkdir -p "$ROOT/json-runtime/inbox"
printf '%s\n' '{broken json' > "$ROOT/json-runtime/inbox/broken.json"
SCOUTICA_HOME="$ROOT/json-runtime" "$SCOUTICA" inbox --json >"$ROOT/json.out" 2>"$ROOT/json.err"
_json_rc=$?
assert_ne 0 "$_json_rc" "invalid inbox JSON must fail"
assert_eq "" "$(cat "$ROOT/json.out")" "failed JSON mode must keep stdout empty"
assert_grep 'Invalid inbox message' "$ROOT/json.err"
t_end

# Failures at each ordered persistence boundary leave a retryable prefix only.
t_begin F-09 "ordinary write failures are ordered and resumable"
ROOT="$CASE_ROOT/resume"
make_card "$ROOT/card-b" "$B_URL"
make_message "$ROOT/runtime/inbox/route/original.json" msg_f1b2c3d4 "$A_URL" "$B_URL"
RID=$(reply_id msg_f1b2c3d4 accept "$B_URL")
HASH=$("$PYTHON" -c 'import hashlib,sys; print(hashlib.sha256(sys.argv[1].encode()).hexdigest()[:12])' "$A_URL")
mkdir -p "$ROOT/runtime/outbox"
chmod 500 "$ROOT/runtime/outbox"
SCOUTICA_HOME="$ROOT/runtime" "$SCOUTICA" reply msg_f1b2c3d4 --accept --card "$ROOT/card-b" \
    >"$ROOT/outbox.out" 2>"$ROOT/outbox.err"
_rc=$?
chmod 700 "$ROOT/runtime/outbox"
assert_ne 0 "$_rc" "outbox write failure must surface"
assert_not_exists "$ROOT/runtime/pending_delivery"
assert_exists "$ROOT/runtime/inbox/route/original.json"

mkdir -p "$ROOT/runtime/pending_delivery"
ln -s "$ROOT/victim" "$ROOT/runtime/pending_delivery/$HASH"
SCOUTICA_HOME="$ROOT/runtime" "$SCOUTICA" reply msg_f1b2c3d4 --accept --card "$ROOT/card-b" \
    >"$ROOT/pending.out" 2>"$ROOT/pending.err"
_rc=$?
assert_ne 0 "$_rc" "pending write failure must surface"
assert_exists "$ROOT/runtime/outbox/$RID.json" "outbox is the only completed prefix"
assert_not_exists "$ROOT/runtime/privacy"
assert_exists "$ROOT/runtime/inbox/route/original.json"
rm "$ROOT/runtime/pending_delivery/$HASH"

mkdir -p "$ROOT/runtime/privacy"
chmod 500 "$ROOT/runtime/privacy"
SCOUTICA_HOME="$ROOT/runtime" "$SCOUTICA" reply msg_f1b2c3d4 --accept --card "$ROOT/card-b" \
    >"$ROOT/log.out" 2>"$ROOT/log.err"
_rc=$?
chmod 700 "$ROOT/runtime/privacy"
assert_ne 0 "$_rc" "log write failure must surface"
assert_exists "$ROOT/runtime/pending_delivery/$HASH/$RID.json" "pending follows outbox before log"
assert_not_exists "$ROOT/runtime/privacy/access_log.jsonl"
assert_exists "$ROOT/runtime/inbox/route/original.json"

mkdir -p "$ROOT/runtime/inbox/processed/route"
make_message "$ROOT/runtime/inbox/processed/route/original.json" msg_abcdef12 "$A_URL" "$B_URL"
SCOUTICA_HOME="$ROOT/runtime" "$SCOUTICA" reply msg_f1b2c3d4 --accept --card "$ROOT/card-b" \
    >"$ROOT/processed.out" 2>"$ROOT/processed.err"
_rc=$?
assert_ne 0 "$_rc" "processed collision must surface after log"
assert_exists "$ROOT/runtime/privacy/access_log.jsonl"
assert_exists "$ROOT/runtime/inbox/route/original.json"
rm "$ROOT/runtime/inbox/processed/route/original.json"
SCOUTICA_HOME="$ROOT/runtime" "$SCOUTICA" reply msg_f1b2c3d4 --accept --card "$ROOT/card-b" \
    >"$ROOT/retry.out" 2>"$ROOT/retry.err"
_rc=$?
assert_eq 0 "$_rc" "retry must fill the missing final step"
assert_exists "$ROOT/runtime/inbox/processed/route/original.json"
_log_count=$(grep -c "\"message_id\":\"$RID\"" "$ROOT/runtime/privacy/access_log.jsonl" || true)
assert_eq 1 "$_log_count" "resumed write must not duplicate log"
t_end

# A valid but conflicting deterministic artifact is never overwritten.
t_begin F-09 "conflicting deterministic reply artifact fails closed"
ROOT="$CASE_ROOT/conflict"
make_card "$ROOT/card-b" "$B_URL"
make_message "$ROOT/runtime/inbox/original.json" msg_1234abcd "$A_URL" "$B_URL"
RID=$(reply_id msg_1234abcd accept "$B_URL")
mkdir -p "$ROOT/runtime/outbox"
make_message "$ROOT/runtime/outbox/$RID.json" "$RID" "$B_URL" "$A_URL"
"$PYTHON" - "$ROOT/runtime/outbox/$RID.json" <<'PY'
import json, sys
path = sys.argv[1]
doc = json.load(open(path, encoding="utf-8"))
doc["type"] = "response.accept"
doc["in_reply_to"] = "msg_1234abcd"
doc["payload"] = {"message": "conflicting text"}
json.dump(doc, open(path, "w", encoding="utf-8"), indent=2)
open(path, "a", encoding="utf-8").write("\n")
PY
_before=$(shasum -a 256 "$ROOT/runtime/outbox/$RID.json" | awk '{print $1}')
SCOUTICA_HOME="$ROOT/runtime" "$SCOUTICA" reply msg_1234abcd --accept --message expected --card "$ROOT/card-b" \
    >"$ROOT/reply.out" 2>"$ROOT/reply.err"
_rc=$?
_after=$(shasum -a 256 "$ROOT/runtime/outbox/$RID.json" | awk '{print $1}')
assert_ne 0 "$_rc" "conflicting artifact must fail"
assert_eq "$_before" "$_after" "conflicting artifact must remain untouched"
assert_not_exists "$ROOT/runtime/pending_delivery"
assert_not_exists "$ROOT/runtime/privacy"
assert_not_exists "$ROOT/runtime/inbox/processed"
assert_exists "$ROOT/runtime/inbox/original.json"
t_end

# A processed-only file without the matching completed staged reply is not actionable.
t_begin F-09 "processed-only messages cannot create a new reply"
ROOT="$CASE_ROOT/processed-only"
make_card "$ROOT/card-b" "$B_URL"
make_message "$ROOT/runtime/inbox/processed/route/original.json" msg_deadbeef "$A_URL" "$B_URL"
SCOUTICA_HOME="$ROOT/runtime" "$SCOUTICA" reply msg_deadbeef --accept --card "$ROOT/card-b" \
    >"$ROOT/reply.out" 2>"$ROOT/reply.err"
_rc=$?
assert_ne 0 "$_rc" "processed-only message must remain non-actionable"
assert_not_exists "$ROOT/runtime/outbox"
assert_not_exists "$ROOT/runtime/pending_delivery"
assert_not_exists "$ROOT/runtime/privacy"
assert_exists "$ROOT/runtime/inbox/processed/route/original.json"
t_end
