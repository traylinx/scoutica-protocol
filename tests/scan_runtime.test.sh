#!/bin/sh
# Phase 3: private provider execution, bounded resources, cleanup, promotion, and card-owned state.

. "$TESTLIB/assert.sh"
. "$TESTLIB/fixtures.sh"

fixture_isolated_env "$WORK/scan-runtime"
trap 'fixture_cleanup' EXIT INT TERM

SCAN_FIXTURES="$FIXTURES/scan_runtime"
VALID_RESPONSE="$SCAN_FIXTURES/valid_response.json"
INVALID_RESPONSE="$SCAN_FIXTURES/invalid_response.json"
SENSITIVE_MARKER="SCOUTICA_PRIVATE_DOCUMENT_MARKER_7391"

mkdir -p "$SCOUTICA_HOME/templates/rules"
cp "$REPO_ROOT/protocol/templates/rules/"*.md "$SCOUTICA_HOME/templates/rules/"
cp "$REPO_ROOT/protocol/templates/card.gitignore" "$SCOUTICA_HOME/templates/card.gitignore"

make_source() {
    _scan_source=$1
    _scan_size=${2:-0}
    rm -rf "$_scan_source"
    mkdir -p "$_scan_source"
    if [ "$_scan_size" -gt 0 ]; then
        python3 - "$_scan_source/document.txt" "$_scan_size" "$SENSITIVE_MARKER" <<'PY'
import sys
path, size, marker = sys.argv[1], int(sys.argv[2]), sys.argv[3].encode()
assert size >= len(marker)
with open(path, "wb") as handle:
    handle.write(marker)
    handle.write(b"x" * (size - len(marker)))
PY
    else
        printf '%s\n' "$SENSITIVE_MARKER" 'Alice builds reliable backend systems.' \
            > "$_scan_source/document.txt"
    fi
}

make_response_size() {
    _scan_response=$1
    _scan_size=$2
    python3 - "$VALID_RESPONSE" "$_scan_response" "$_scan_size" <<'PY'
import sys
source, target, size = sys.argv[1], sys.argv[2], int(sys.argv[3])
payload = open(source, "rb").read()
assert len(payload) <= size
open(target, "wb").write(payload + b" " * (size - len(payload)))
PY
}

reset_provider_env() {
    unset FAKE_PROVIDER_PID_FILE FAKE_PROVIDER_READY_FILE FAKE_PROVIDER_RELEASE_FILE
    unset FAKE_PROVIDER_SIGNAL_FILE FAKE_PROVIDER_ARGV_LOG FAKE_PROVIDER_STDIN_LOG
    unset FAKE_PROVIDER_RESPONSE_FILE FAKE_PROVIDER_RESPONSE FAKE_PROVIDER_OUTPUT_FILE
    unset FAKE_PROVIDER_EXIT FAKE_PROVIDER_COUNT_FILE FAKE_PROVIDER_FORK_PID_FILE
}

prepare_provider() {
    _scan_provider=$1
    _scan_prefix=$2
    _scan_response=${3:-$VALID_RESPONSE}
    fixture_install_fake_provider "$_scan_provider" >/dev/null
    FAKE_PROVIDER_ARGV_LOG="${_scan_prefix}.argv"
    FAKE_PROVIDER_STDIN_LOG="${_scan_prefix}.stdin"
    FAKE_PROVIDER_COUNT_FILE="${_scan_prefix}.count"
    FAKE_PROVIDER_RESPONSE_FILE="$_scan_response"
    export FAKE_PROVIDER_ARGV_LOG FAKE_PROVIDER_STDIN_LOG FAKE_PROVIDER_COUNT_FILE
    export FAKE_PROVIDER_RESPONSE_FILE
}

provider_count() {
    [ -f "$1" ] && cat "$1" || printf '0\n'
}

assert_no_scan_temps() {
    _scan_left=$(find "$TMPDIR" -maxdepth 1 \( -name 'scoutica-scan*' -o -name 'scoutica_prompt*' \
        -o -name 'scoutica_resp*' -o -name 'scoutica_payload*' \) -print 2>/dev/null)
    assert_eq "" "$_scan_left" "scan-owned temporary paths removed"
}

run_remote_scan() {
    _scan_out=$1
    _scan_source=$2
    _scan_card=$3
    _scan_provider=$4
    shift 4
    "$SCOUTICA" scan "$_scan_source" --output "$_scan_card" --with "$_scan_provider" \
        --force --allow-remote-provider "$@" </dev/null >"$_scan_out" 2>&1
    SCAN_RC=$?
}

# Supported fixed adapters receive document text only on stdin; disabled adapters never run.
t_begin F-03 "fixed provider registry supports safe stdin adapters and disables unsafe adapters"
for provider in gemini claude codex opencode; do
    reset_provider_env
    source_dir="$WORK/provider-$provider-source"
    card_dir="$WORK/provider-$provider-card"
    make_source "$source_dir"
    prepare_provider "$provider" "$WORK/provider-$provider"
    run_remote_scan "$WORK/provider-$provider.out" "$source_dir" "$card_dir" "$provider"
    assert_eq 0 "$SCAN_RC" "$provider safe adapter succeeds"
    assert_grep "$SENSITIVE_MARKER" "$FAKE_PROVIDER_STDIN_LOG" "$provider receives source through stdin"
    assert_no_grep "$SENSITIVE_MARKER" "$FAKE_PROVIDER_ARGV_LOG" "$provider argv contains no source text"
    assert_exists "$card_dir/.scoutica/state.json" "$provider writes card-owned state"
done

reset_provider_env
make_source "$WORK/provider-ollama-source"
prepare_provider ollama "$WORK/provider-ollama"
OLLAMA_HOST="http://127.0.0.1:11434"; export OLLAMA_HOST
"$SCOUTICA" scan "$WORK/provider-ollama-source" --output "$WORK/provider-ollama-card" \
    --with ollama --force </dev/null >"$WORK/provider-ollama.out" 2>&1
SCAN_RC=$?
assert_eq 0 "$SCAN_RC" "loopback Ollama safe adapter succeeds without remote consent"
assert_grep "$SENSITIVE_MARKER" "$FAKE_PROVIDER_STDIN_LOG"
assert_no_grep "$SENSITIVE_MARKER" "$FAKE_PROVIDER_ARGV_LOG"
unset OLLAMA_HOST

for provider in vibe openclaw; do
    reset_provider_env
    source_dir="$WORK/provider-$provider-source"
    make_source "$source_dir"
    prepare_provider "$provider" "$WORK/provider-$provider"
    run_remote_scan "$WORK/provider-$provider.out" "$source_dir" "$WORK/provider-$provider-card" "$provider"
    assert_ne 0 "$SCAN_RC" "$provider is explicitly disabled"
    assert_eq 0 "$(provider_count "$FAKE_PROVIDER_COUNT_FILE")" "$provider binary is never invoked"
    assert_grep 'disabled:.*(prompt|argv)' "$WORK/provider-$provider.out"
done
t_end

t_begin F-06 "rollback failure preserves a private recovery set and returns distinct nonzero"
reset_provider_env
make_source "$WORK/recovery-source"
prepare_provider gemini "$WORK/recovery-baseline"
run_remote_scan "$WORK/recovery-baseline.out" "$WORK/recovery-source" "$WORK/recovery-card" gemini
assert_eq 0 "$SCAN_RC" "recovery baseline created"
printf '%s\n' changed >> "$WORK/recovery-source/document.txt"
reset_provider_env
prepare_provider gemini "$WORK/recovery-failure"
SCOUTICA_TEST_PROMOTE_FAIL_AFTER=2; export SCOUTICA_TEST_PROMOTE_FAIL_AFTER
SCOUTICA_TEST_ROLLBACK_FAIL=1; export SCOUTICA_TEST_ROLLBACK_FAIL
run_remote_scan "$WORK/recovery-failure.out" "$WORK/recovery-source" "$WORK/recovery-card" gemini
unset SCOUTICA_TEST_PROMOTE_FAIL_AFTER SCOUTICA_TEST_ROLLBACK_FAIL
assert_eq 2 "$SCAN_RC" "rollback failure uses the distinct recovery exit"
recovery_dir=$(find "$WORK/recovery-card/.scoutica" -maxdepth 1 -type d -name 'recovery-*' -print | head -1)
assert_ne "" "$recovery_dir" "rollback failure preserves a reported recovery directory"
assert_exists "$recovery_dir/manifest.json"
recovery_mode=$(python3 - "$recovery_dir" <<'PY'
import os, stat, sys
print(oct(stat.S_IMODE(os.stat(sys.argv[1]).st_mode)))
PY
)
assert_eq 0o700 "$recovery_mode" "recovery directory is private"
assert_grep 'Recovery data preserved at' "$WORK/recovery-failure.out"
assert_no_scan_temps
t_end

t_begin F-03 "switchAILocal adapter uses a bounded request body and never prompt argv"
reset_provider_env
make_source "$WORK/provider-ail-source"
"$FIXTURE_SERVER_PYTHON" "$SCAN_FIXTURES/ail_server.py" --ready-file "$WORK/provider-ail.ready" \
    --response-file "$VALID_RESPONSE" --payload-log "$WORK/provider-ail.payload" \
    >"$WORK/provider-ail.server.out" 2>&1 &
ail_pid=$!
fixture_register_pid "$ail_pid"
if ! fixture_wait_for_file "$WORK/provider-ail.ready" 200; then
    t_fail "ail fixture did not become ready"
    if [ -s "$WORK/provider-ail.server.out" ]; then
        sed 's/^/    /' "$WORK/provider-ail.server.out" >&2
    else
        printf '%s\n' "    ail fixture stderr: <empty>" >&2
    fi
fi
http_proxy="http://proxy.example.test:9999"; export http_proxy
HTTP_PROXY="$http_proxy"; export HTTP_PROXY
unset no_proxy NO_PROXY
run_remote_scan "$WORK/provider-ail.out" "$WORK/provider-ail-source" "$WORK/provider-ail-card" ail
unset http_proxy HTTP_PROXY
assert_eq 0 "$SCAN_RC" "ail payload adapter succeeds"
assert_grep "$SENSITIVE_MARKER" "$WORK/provider-ail.payload" "ail payload contains source text"
assert_no_grep "$SENSITIVE_MARKER" "$(ps -o command= -p "$ail_pid" 2>/dev/null)" \
    "ail server argv contains no source text"
fixture_stop_pid "$ail_pid" TERM
t_end

t_begin F-06 "normal provider completion terminates forked descendants"
reset_provider_env
make_source "$WORK/fork-source"
prepare_provider gemini "$WORK/fork-provider"
FAKE_PROVIDER_FORK_PID_FILE="$WORK/fork-child.pid"; export FAKE_PROVIDER_FORK_PID_FILE
run_remote_scan "$WORK/fork.out" "$WORK/fork-source" "$WORK/fork-card" gemini
assert_eq 0 "$SCAN_RC" "provider parent completion succeeds"
assert_exists "$FAKE_PROVIDER_FORK_PID_FILE"
assert_pid_stopped "$(cat "$FAKE_PROVIDER_FORK_PID_FILE")"
assert_no_scan_temps
t_end

t_begin F-03 "noninteractive remote selection refuses without explicit consent and accepts flag"
reset_provider_env
make_source "$WORK/consent-source"
prepare_provider gemini "$WORK/consent"
"$SCOUTICA" scan "$WORK/consent-source" --output "$WORK/consent-refused" --with gemini \
    --force </dev/null >"$WORK/consent-refused.out" 2>&1
SCAN_RC=$?
assert_ne 0 "$SCAN_RC" "noninteractive remote provider refuses without flag"
assert_eq 0 "$(provider_count "$FAKE_PROVIDER_COUNT_FILE")" "refusal happens before provider invocation"
assert_grep '[Rr]emote-capable' "$WORK/consent-refused.out"
assert_grep 'full.*document|document.*full' "$WORK/consent-refused.out"
run_remote_scan "$WORK/consent-allowed.out" "$WORK/consent-source" "$WORK/consent-allowed" gemini
assert_eq 0 "$SCAN_RC" "explicit remote flag succeeds"
assert_eq 1 "$(provider_count "$FAKE_PROVIDER_COUNT_FILE")"
t_end

t_begin F-03 "auto-selected remote provider follows the same noninteractive consent gate"
reset_provider_env
make_source "$WORK/auto-source"
prepare_provider gemini "$WORK/auto"
"$SCOUTICA" scan "$WORK/auto-source" --output "$WORK/auto-refused" --force \
    </dev/null >"$WORK/auto-refused.out" 2>&1
SCAN_RC=$?
assert_ne 0 "$SCAN_RC" "auto-selected Gemini refuses without flag"
assert_eq 0 "$(provider_count "$FAKE_PROVIDER_COUNT_FILE")"
"$SCOUTICA" scan "$WORK/auto-source" --output "$WORK/auto-allowed" --force \
    --allow-remote-provider </dev/null >"$WORK/auto-allowed.out" 2>&1
SCAN_RC=$?
assert_eq 0 "$SCAN_RC" "auto-selected Gemini accepts explicit flag"
assert_eq 1 "$(provider_count "$FAKE_PROVIDER_COUNT_FILE")"
t_end

t_begin F-03 "interactive remote disclosure handles yes, no, and EOF"
for answer in yes no eof; do
    reset_provider_env
    make_source "$WORK/interactive-$answer-source"
    prepare_provider gemini "$WORK/interactive-$answer"
    python3 "$SCAN_FIXTURES/pty_run.py" --answer "$answer" --output "$WORK/interactive-$answer.out" -- \
        "$SCOUTICA" scan "$WORK/interactive-$answer-source" --output "$WORK/interactive-$answer-card" \
        --with gemini --force
    SCAN_RC=$?
    assert_grep '[Rr]emote-capable' "$WORK/interactive-$answer.out"
    assert_grep 'full.*document|document.*full' "$WORK/interactive-$answer.out"
    if [ "$answer" = yes ]; then
        assert_eq 0 "$SCAN_RC" "interactive yes proceeds"
        assert_eq 1 "$(provider_count "$FAKE_PROVIDER_COUNT_FILE")"
    else
        assert_ne 0 "$SCAN_RC" "interactive $answer refuses"
        assert_eq 0 "$(provider_count "$FAKE_PROVIDER_COUNT_FILE")"
    fi
done
t_end

t_begin F-03 "remote Ollama endpoint requires consent while clipboard is user-controlled local transfer"
reset_provider_env
make_source "$WORK/remote-ollama-source"
prepare_provider ollama "$WORK/remote-ollama"
OLLAMA_HOST="https://ollama.example.test"; export OLLAMA_HOST
"$SCOUTICA" scan "$WORK/remote-ollama-source" --output "$WORK/remote-ollama-card" \
    --with ollama --force </dev/null >"$WORK/remote-ollama.out" 2>&1
SCAN_RC=$?
assert_ne 0 "$SCAN_RC" "remote Ollama refuses without explicit consent"
assert_eq 0 "$(provider_count "$FAKE_PROVIDER_COUNT_FILE")"
unset OLLAMA_HOST

reset_provider_env
make_source "$WORK/clipboard-source"
prepare_provider pbcopy "$WORK/clipboard" "$VALID_RESPONSE"
unset FAKE_PROVIDER_RESPONSE_FILE
"$SCOUTICA" scan "$WORK/clipboard-source" --output "$WORK/clipboard-card" --clipboard --force \
    </dev/null >"$WORK/clipboard.out" 2>&1
SCAN_RC=$?
assert_eq 0 "$SCAN_RC" "clipboard mode needs no remote-consent flag"
assert_grep 'system clipboard|clipboard.*user' "$WORK/clipboard.out"
assert_grep "$SENSITIVE_MARKER" "$FAKE_PROVIDER_STDIN_LOG" "full prompt reaches clipboard command stdin"
t_end

# Provider failure, timeout, and parent signals must reap the provider and remove the owned run dir.
t_begin F-06 "provider failure and parse failure preserve card and clean all scan temporaries"
reset_provider_env
make_source "$WORK/failure-source"
prepare_provider gemini "$WORK/provider-failure"
FAKE_PROVIDER_EXIT=23; FAKE_PROVIDER_RESPONSE_FILE=""; export FAKE_PROVIDER_EXIT FAKE_PROVIDER_RESPONSE_FILE
run_remote_scan "$WORK/provider-failure.out" "$WORK/failure-source" "$WORK/provider-failure-card" gemini
assert_ne 0 "$SCAN_RC" "provider failure propagates"
assert_not_exists "$WORK/provider-failure-card/profile.json"
assert_no_scan_temps

reset_provider_env
prepare_provider gemini "$WORK/parse-failure" "$INVALID_RESPONSE"
run_remote_scan "$WORK/parse-failure.out" "$WORK/failure-source" "$WORK/parse-failure-card" gemini
assert_ne 0 "$SCAN_RC" "invalid provider response propagates"
assert_not_exists "$WORK/parse-failure-card/profile.json"
assert_no_scan_temps
t_end

t_begin F-06 "timeout forwards TERM, reaps provider, and cleans owned run directory"
reset_provider_env
make_source "$WORK/timeout-source"
prepare_provider gemini "$WORK/timeout"
clamped_timeout=$(SCOUTICA_SCAN_TIMEOUT_SECONDS=999 python3 - "$REPO_ROOT/tools/scan_runtime.py" <<'PY'
import runpy, sys

runtime = runpy.run_path(sys.argv[1])
print(runtime["_provider_timeout"]())
PY
)
assert_eq 300 "$clamped_timeout" "timeout override is clamped to the 300-second hard maximum"
FAKE_PROVIDER_READY_FILE="$WORK/timeout.ready"
FAKE_PROVIDER_RELEASE_FILE="$WORK/timeout.release"
FAKE_PROVIDER_SIGNAL_FILE="$WORK/timeout.signal"
FAKE_PROVIDER_PID_FILE="$WORK/timeout.pid"
export FAKE_PROVIDER_READY_FILE FAKE_PROVIDER_RELEASE_FILE FAKE_PROVIDER_SIGNAL_FILE FAKE_PROVIDER_PID_FILE
start=$(date +%s)
SCOUTICA_SCAN_TIMEOUT_SECONDS=1 "$SCOUTICA" scan "$WORK/timeout-source" --output "$WORK/timeout-card" \
    --with gemini --force --allow-remote-provider </dev/null >"$WORK/timeout.out" 2>&1
SCAN_RC=$?
elapsed=$(( $(date +%s) - start ))
assert_ne 0 "$SCAN_RC" "provider timeout returns nonzero"
assert_grep '^TERM$' "$FAKE_PROVIDER_SIGNAL_FILE"
assert_pid_stopped "$(cat "$FAKE_PROVIDER_PID_FILE")"
# The one-second budget begins inside the provider helper. Allow loaded CI hosts
# enough startup/teardown headroom while still proving the 300-second cap was
# not used accidentally.
if [ "$elapsed" -gt 30 ]; then t_fail "one-second timeout took ${elapsed}s"; fi
assert_no_scan_temps
t_end

t_begin F-06 "INT and TERM forward to provider, reap child, and preserve nonzero status"
for signal_name in INT TERM; do
    reset_provider_env
    make_source "$WORK/signal-$signal_name-source"
    prepare_provider gemini "$WORK/signal-$signal_name"
    FAKE_PROVIDER_READY_FILE="$WORK/signal-$signal_name.ready"
    FAKE_PROVIDER_RELEASE_FILE="$WORK/signal-$signal_name.release"
    FAKE_PROVIDER_SIGNAL_FILE="$WORK/signal-$signal_name.seen"
    FAKE_PROVIDER_PID_FILE="$WORK/signal-$signal_name.pid"
    export FAKE_PROVIDER_READY_FILE FAKE_PROVIDER_RELEASE_FILE FAKE_PROVIDER_SIGNAL_FILE FAKE_PROVIDER_PID_FILE
    python3 "$SCAN_FIXTURES/signal_run.py" --signal "$signal_name" \
        --ready-file "$FAKE_PROVIDER_READY_FILE" --output "$WORK/signal-$signal_name.out" -- \
        "$SCOUTICA" scan "$WORK/signal-$signal_name-source" --output "$WORK/signal-$signal_name-card" \
        --with gemini --force --allow-remote-provider
    SCAN_RC=$?
    assert_ne 0 "$SCAN_RC" "$signal_name returns nonzero"
    assert_grep "^$signal_name$" "$FAKE_PROVIDER_SIGNAL_FILE"
    assert_pid_stopped "$(cat "$FAKE_PROVIDER_PID_FILE")"
    assert_not_exists "$WORK/signal-$signal_name-card/profile.json"
    assert_no_scan_temps
done
t_end

# Exact source/response budgets. Boundaries succeed; one byte above fails before promotion.
t_begin F-15 "source per-file and aggregate limits accept exact boundary and reject one byte above"
reset_provider_env
prepare_provider gemini "$WORK/source-limits"
make_source "$WORK/per-file-exact" $((2 * 1024 * 1024))
run_remote_scan "$WORK/per-file-exact.out" "$WORK/per-file-exact" "$WORK/per-file-exact-card" gemini
assert_eq 0 "$SCAN_RC" "exact 2 MiB source file accepted"

make_source "$WORK/per-file-over" $((2 * 1024 * 1024 + 1))
run_remote_scan "$WORK/per-file-over.out" "$WORK/per-file-over" "$WORK/per-file-over-card" gemini
assert_ne 0 "$SCAN_RC" "source file one byte above 2 MiB rejected"
assert_not_exists "$WORK/per-file-over-card/profile.json"

rm -rf "$WORK/aggregate-exact"; mkdir -p "$WORK/aggregate-exact"
python3 - "$WORK/aggregate-exact" "$SENSITIVE_MARKER" <<'PY'
import pathlib, sys
root, marker = pathlib.Path(sys.argv[1]), sys.argv[2].encode()
for name in ("one.txt", "two.txt"):
    (root / name).write_bytes(marker + b"x" * (2 * 1024 * 1024 - len(marker)))
PY
run_remote_scan "$WORK/aggregate-exact.out" "$WORK/aggregate-exact" "$WORK/aggregate-exact-card" gemini
assert_eq 0 "$SCAN_RC" "exact 4 MiB aggregate accepted"
printf 'x' > "$WORK/aggregate-exact/three.txt"
run_remote_scan "$WORK/aggregate-over.out" "$WORK/aggregate-exact" "$WORK/aggregate-over-card" gemini
assert_ne 0 "$SCAN_RC" "aggregate one byte above 4 MiB rejected"
assert_not_exists "$WORK/aggregate-over-card/profile.json"
t_end

t_begin F-15 "provider response limit accepts exact 8 MiB and rejects one byte above without argv leakage"
make_source "$WORK/response-limit-source"
make_response_size "$WORK/response-exact.json" $((8 * 1024 * 1024))
reset_provider_env
prepare_provider gemini "$WORK/response-exact" "$WORK/response-exact.json"
run_remote_scan "$WORK/response-exact.out" "$WORK/response-limit-source" "$WORK/response-exact-card" gemini
assert_eq 0 "$SCAN_RC" "exact 8 MiB response accepted"
assert_no_grep "$SENSITIVE_MARKER" "$FAKE_PROVIDER_ARGV_LOG"

make_response_size "$WORK/response-over.json" $((8 * 1024 * 1024 + 1))
reset_provider_env
prepare_provider gemini "$WORK/response-over" "$WORK/response-over.json"
run_remote_scan "$WORK/response-over.out" "$WORK/response-limit-source" "$WORK/response-over-card" gemini
assert_ne 0 "$SCAN_RC" "response one byte above 8 MiB rejected"
assert_not_exists "$WORK/response-over-card/profile.json"
assert_no_scan_temps

reset_provider_env
prepare_provider gemini "$WORK/response-burst"
cat > "$(command -v gemini)" <<'SH'
#!/bin/sh
cat >/dev/null
python3 - <<'PY'
import os
os.write(1, b"x" * (16 * 1024 * 1024))
PY
SH
chmod +x "$(command -v gemini)"
printf '%s\n' prompt > "$WORK/burst-prompt"
python3 "$REPO_ROOT/tools/scan_runtime.py" run-provider gemini \
    --prompt-file "$WORK/burst-prompt" --response-file "$WORK/burst-response" \
    --log-file "$WORK/burst-log"
burst_rc=$?
assert_eq 125 "$burst_rc" "fast response burst is rejected"
assert_eq $((8 * 1024 * 1024)) "$(wc -c < "$WORK/burst-response" | tr -d ' ')" \
    "response file never exceeds the locked cap"
t_end

# Card and state promotion are one reported unit: ordinary injected failure and invalid data roll back.
t_begin F-06 "injected promotion failure rolls back prior card and state byte-for-byte"
reset_provider_env
make_source "$WORK/rollback-source"
prepare_provider gemini "$WORK/rollback-baseline"
run_remote_scan "$WORK/rollback-baseline.out" "$WORK/rollback-source" "$WORK/rollback-card" gemini
assert_eq 0 "$SCAN_RC" "rollback baseline created"
cp "$WORK/rollback-card/profile.json" "$WORK/rollback-profile.before"
cp "$WORK/rollback-card/rules.yaml" "$WORK/rollback-rules.before"
cp "$WORK/rollback-card/evidence.json" "$WORK/rollback-evidence.before"
cp "$WORK/rollback-card/SKILL.md" "$WORK/rollback-skill.before"
cp "$WORK/rollback-card/.scoutica/state.json" "$WORK/rollback-state.before"
printf '%s\n' changed >> "$WORK/rollback-source/document.txt"
reset_provider_env
prepare_provider gemini "$WORK/rollback-injected"
SCOUTICA_TEST_PROMOTE_FAIL_AFTER=2; export SCOUTICA_TEST_PROMOTE_FAIL_AFTER
run_remote_scan "$WORK/rollback-injected.out" \
    "$WORK/rollback-source" "$WORK/rollback-card" gemini
unset SCOUTICA_TEST_PROMOTE_FAIL_AFTER
assert_ne 0 "$SCAN_RC" "injected promotion failure propagates"
assert_file_eq "$WORK/rollback-profile.before" "$WORK/rollback-card/profile.json"
assert_file_eq "$WORK/rollback-rules.before" "$WORK/rollback-card/rules.yaml"
assert_file_eq "$WORK/rollback-evidence.before" "$WORK/rollback-card/evidence.json"
assert_file_eq "$WORK/rollback-skill.before" "$WORK/rollback-card/SKILL.md"
assert_file_eq "$WORK/rollback-state.before" "$WORK/rollback-card/.scoutica/state.json"
assert_no_scan_temps
t_end

t_begin F-06 "registry failure rolls back card, state, and registry together"
reset_provider_env
make_source "$WORK/registry-rollback-source"
prepare_provider gemini "$WORK/registry-rollback-baseline"
run_remote_scan "$WORK/registry-rollback-baseline.out" "$WORK/registry-rollback-source" \
    "$WORK/registry-rollback-card" gemini
assert_eq 0 "$SCAN_RC" "registry rollback baseline created"
cp "$WORK/registry-rollback-card/profile.json" "$WORK/registry-rollback-profile.before"
cp "$WORK/registry-rollback-card/.scoutica/state.json" "$WORK/registry-rollback-state.before"
cp "$SCOUTICA_HOME/registry.json" "$WORK/registry.before"
printf '%s\n' changed >> "$WORK/registry-rollback-source/document.txt"
reset_provider_env
prepare_provider gemini "$WORK/registry-rollback-failure"
SCOUTICA_TEST_REGISTRY_FAIL=1; export SCOUTICA_TEST_REGISTRY_FAIL
run_remote_scan "$WORK/registry-rollback-failure.out" "$WORK/registry-rollback-source" \
    "$WORK/registry-rollback-card" gemini
unset SCOUTICA_TEST_REGISTRY_FAIL
assert_ne 0 "$SCAN_RC" "registry write failure propagates"
assert_file_eq "$WORK/registry-rollback-profile.before" "$WORK/registry-rollback-card/profile.json"
assert_file_eq "$WORK/registry-rollback-state.before" "$WORK/registry-rollback-card/.scoutica/state.json"
assert_file_eq "$WORK/registry.before" "$SCOUTICA_HOME/registry.json"
assert_no_scan_temps
t_end

t_begin F-16 "unchanged source is zero-call; changed source invalidates card-owned state"
reset_provider_env
make_source "$WORK/state-source"
prepare_provider gemini "$WORK/state-provider"
run_remote_scan "$WORK/state-first.out" "$WORK/state-source" "$WORK/state-card" gemini
assert_eq 0 "$SCAN_RC" "first stateful scan succeeds"
assert_eq 1 "$(provider_count "$FAKE_PROVIDER_COUNT_FILE")"
"$SCOUTICA" scan "$WORK/state-source" --output "$WORK/state-card" --with gemini \
    --allow-remote-provider </dev/null >"$WORK/state-unchanged.out" 2>&1
SCAN_RC=$?
assert_eq 0 "$SCAN_RC" "unchanged scan succeeds without regeneration"
assert_eq 1 "$(provider_count "$FAKE_PROVIDER_COUNT_FILE")" "unchanged scan invokes provider zero times"
printf '%s\n' changed >> "$WORK/state-source/document.txt"
"$SCOUTICA" scan "$WORK/state-source" --output "$WORK/state-card" --with gemini \
    --allow-remote-provider </dev/null >"$WORK/state-changed.out" 2>&1
SCAN_RC=$?
assert_eq 0 "$SCAN_RC" "changed source regenerates"
assert_eq 2 "$(provider_count "$FAKE_PROVIDER_COUNT_FILE")"
assert_exists "$WORK/state-card/.scoutica/state.json"
assert_grep "$(cd "$WORK/state-source" && pwd)" "$WORK/state-card/.scoutica/state.json"
t_end

t_begin F-16 "two cards in one cwd keep isolated state and legacy cwd state is ignored"
reset_provider_env
common="$WORK/state-common"; mkdir -p "$common"
make_source "$common/source-a"; make_source "$common/source-b"
prepare_provider gemini "$WORK/state-isolation"
run_remote_scan "$WORK/state-a.out" "$common/source-a" "$common/card-a" gemini
assert_eq 0 "$SCAN_RC" "card A created"
run_remote_scan "$WORK/state-b.out" "$common/source-b" "$common/card-b" gemini
assert_eq 0 "$SCAN_RC" "card B created"
assert_exists "$common/card-a/.scoutica/state.json"
assert_exists "$common/card-b/.scoutica/state.json"
assert_grep "$(cd "$common/source-a" && pwd)" "$common/card-a/.scoutica/state.json"
assert_grep "$(cd "$common/source-b" && pwd)" "$common/card-b/.scoutica/state.json"

legacy="$common/caller/.scoutica/state.json"
mkdir -p "$(dirname "$legacy")"
printf '%s\n' '{"card":{"source_hash":"forged-legacy-match"}}' > "$legacy"
make_source "$common/legacy-source"
reset_provider_env
prepare_provider gemini "$WORK/state-legacy"
( cd "$common/caller" && "$SCOUTICA" scan "$common/legacy-source" --output "$common/legacy-card" \
    --with gemini --allow-remote-provider </dev/null ) >"$WORK/state-legacy.out" 2>&1
SCAN_RC=$?
assert_eq 0 "$SCAN_RC" "legacy cwd state cannot suppress generation"
assert_eq 1 "$(provider_count "$FAKE_PROVIDER_COUNT_FILE")"
assert_grep 'forged-legacy-match' "$legacy" "legacy state left untouched"
assert_exists "$common/legacy-card/.scoutica/state.json"
t_end

t_begin F-16 "registry mapping survives quoted canonical source paths and source symlinks fail before provider"
reset_provider_env
quoted_source="$WORK/source-\"quoted"
make_source "$quoted_source"
prepare_provider gemini "$WORK/quoted-state"
run_remote_scan "$WORK/quoted-first.out" "$quoted_source" "$WORK/quoted-card" gemini
assert_eq 0 "$SCAN_RC" "quoted source path creates card and mapping"
"$SCOUTICA" scan "$quoted_source" --with gemini --allow-remote-provider \
    </dev/null >"$WORK/quoted-unchanged.out" 2>&1
SCAN_RC=$?
assert_eq 0 "$SCAN_RC" "quoted source mapping resolves without explicit output"
assert_eq 1 "$(provider_count "$FAKE_PROVIDER_COUNT_FILE")" \
    "quoted source unchanged scan invokes provider zero times"

reset_provider_env
make_source "$WORK/symlink-source"
printf '%s\n' 'outside private text' > "$WORK/outside-source.txt"
ln -s "$WORK/outside-source.txt" "$WORK/symlink-source/linked.txt"
prepare_provider gemini "$WORK/symlink-source-provider"
run_remote_scan "$WORK/symlink-source.out" "$WORK/symlink-source" "$WORK/symlink-source-card" gemini
assert_ne 0 "$SCAN_RC" "symlinked source document is rejected"
assert_eq 0 "$(provider_count "$FAKE_PROVIDER_COUNT_FILE")" \
    "source symlink refusal happens before provider invocation"
t_end

t_begin F-06 "explicit and registered output symlinks never overwrite victims"
reset_provider_env
make_source "$WORK/output-symlink-source"
prepare_provider gemini "$WORK/output-symlink-provider"
mkdir -p "$WORK/output-victim"
printf '%s\n' '{"victim":true}' > "$WORK/output-victim/profile.json"
cp "$WORK/output-victim/profile.json" "$WORK/output-victim.before"
ln -s "$WORK/output-victim" "$WORK/output-link"
run_remote_scan "$WORK/output-symlink.out" "$WORK/output-symlink-source" "$WORK/output-link//" gemini
assert_ne 0 "$SCAN_RC" "multiply-slashed explicit output symlink is rejected"
assert_file_eq "$WORK/output-victim.before" "$WORK/output-victim/profile.json"

reset_provider_env
registered_source="$WORK/registered-symlink-source"
make_source "$registered_source"
registered_link="$registered_source/alice-developer-card"
ln -s "$WORK/output-victim" "$registered_link"
source_abs=$(cd "$registered_source" && pwd)
cat > "$SCOUTICA_HOME/registry.json" <<JSON
{"schema_version":"0.1.0","cards":{"$registered_link":{"card_dir":"$registered_link","source_dir":"$source_abs"}}}
JSON
prepare_provider gemini "$WORK/registered-symlink-provider"
"$SCOUTICA" scan "$registered_source" --with gemini --force --allow-remote-provider \
    </dev/null >"$WORK/registered-symlink.out" 2>&1
SCAN_RC=$?
assert_ne 0 "$SCAN_RC" "registered card symlink cannot become a writable output"
assert_file_eq "$WORK/output-victim.before" "$WORK/output-victim/profile.json"

reset_provider_env
mkdir -p "$WORK/intermediate-output-victim"
ln -s "$WORK/intermediate-output-victim" "$WORK/intermediate-output-link"
prepare_provider gemini "$WORK/intermediate-output-provider"
run_remote_scan "$WORK/intermediate-output.out" "$WORK/output-symlink-source" \
    "$WORK/intermediate-output-link/new-card" gemini
assert_ne 0 "$SCAN_RC" "explicit output rejects a user-owned intermediate symlink component"
assert_not_exists "$WORK/intermediate-output-victim/new-card"
assert_eq 0 "$(provider_count "$FAKE_PROVIDER_COUNT_FILE")" \
    "intermediate output symlink refusal happens before provider invocation"

reset_provider_env
intermediate_registered_source="$WORK/intermediate-registered-source"
make_source "$intermediate_registered_source"
mkdir -p "$WORK/intermediate-registered-victim/card"
printf '%s\n' '{"victim":true}' > "$WORK/intermediate-registered-victim/card/profile.json"
cp "$WORK/intermediate-registered-victim/card/profile.json" \
    "$WORK/intermediate-registered-victim/card/profile.before"
ln -s "$WORK/intermediate-registered-victim" "$WORK/intermediate-registered-link"
intermediate_registered_card="$WORK/intermediate-registered-link/card"
intermediate_source_abs=$(cd "$intermediate_registered_source" && pwd)
cat > "$SCOUTICA_HOME/registry.json" <<JSON
{"schema_version":"0.1.0","cards":{"$intermediate_registered_card":{"card_dir":"$intermediate_registered_card","source_dir":"$intermediate_source_abs"}}}
JSON
prepare_provider gemini "$WORK/intermediate-registered-provider"
"$SCOUTICA" scan "$intermediate_registered_source" --with gemini --force \
    --allow-remote-provider </dev/null >"$WORK/intermediate-registered.out" 2>&1
SCAN_RC=$?
assert_eq 0 "$SCAN_RC" "unsafe registered mapping is ignored and regenerated at a safe default"
assert_file_eq "$WORK/intermediate-registered-victim/card/profile.before" \
    "$WORK/intermediate-registered-victim/card/profile.json"
assert_exists "$intermediate_registered_source/alice-developer-card/profile.json"
assert_eq 1 "$(provider_count "$FAKE_PROVIDER_COUNT_FILE")" \
    "unsafe registered mapping cannot suppress safe regeneration"
t_end

t_begin F-16 "source changes during provider execution preserve prior card and state"
reset_provider_env
make_source "$WORK/source-race"
prepare_provider gemini "$WORK/source-race-baseline"
run_remote_scan "$WORK/source-race-baseline.out" "$WORK/source-race" "$WORK/source-race-card" gemini
assert_eq 0 "$SCAN_RC" "source race baseline created"
cp "$WORK/source-race-card/profile.json" "$WORK/source-race-profile.before"
cp "$WORK/source-race-card/.scoutica/state.json" "$WORK/source-race-state.before"
reset_provider_env
prepare_provider gemini "$WORK/source-race-provider"
FAKE_PROVIDER_READY_FILE="$WORK/source-race.ready"
FAKE_PROVIDER_RELEASE_FILE="$WORK/source-race.release"
export FAKE_PROVIDER_READY_FILE FAKE_PROVIDER_RELEASE_FILE
"$SCOUTICA" scan "$WORK/source-race" --output "$WORK/source-race-card" --with gemini \
    --force --allow-remote-provider </dev/null >"$WORK/source-race.out" 2>&1 &
source_race_pid=$!
fixture_register_pid "$source_race_pid"
fixture_wait_for_file "$FAKE_PROVIDER_READY_FILE" 400 || t_fail "source race provider did not become ready"
printf '%s\n' changed-during-provider >> "$WORK/source-race/document.txt"
: > "$FAKE_PROVIDER_RELEASE_FILE"
wait "$source_race_pid"
SCAN_RC=$?
assert_ne 0 "$SCAN_RC" "source mutation invalidates the in-flight result"
assert_file_eq "$WORK/source-race-profile.before" "$WORK/source-race-card/profile.json"
assert_file_eq "$WORK/source-race-state.before" "$WORK/source-race-card/.scoutica/state.json"
assert_no_scan_temps
t_end

t_begin F-16 "invalid regeneration preserves prior card and card-owned state"
reset_provider_env
make_source "$WORK/prior-source"
prepare_provider gemini "$WORK/prior-baseline"
run_remote_scan "$WORK/prior-baseline.out" "$WORK/prior-source" "$WORK/prior-card" gemini
assert_eq 0 "$SCAN_RC" "prior baseline created"
cp "$WORK/prior-card/profile.json" "$WORK/prior-profile.before"
cp "$WORK/prior-card/rules.yaml" "$WORK/prior-rules.before"
cp "$WORK/prior-card/evidence.json" "$WORK/prior-evidence.before"
cp "$WORK/prior-card/SKILL.md" "$WORK/prior-skill.before"
cp "$WORK/prior-card/.scoutica/state.json" "$WORK/prior-state.before"
printf '%s\n' changed >> "$WORK/prior-source/document.txt"
reset_provider_env
prepare_provider gemini "$WORK/prior-invalid" "$INVALID_RESPONSE"
run_remote_scan "$WORK/prior-invalid.out" "$WORK/prior-source" "$WORK/prior-card" gemini
assert_ne 0 "$SCAN_RC" "invalid regeneration fails"
assert_file_eq "$WORK/prior-profile.before" "$WORK/prior-card/profile.json"
assert_file_eq "$WORK/prior-rules.before" "$WORK/prior-card/rules.yaml"
assert_file_eq "$WORK/prior-evidence.before" "$WORK/prior-card/evidence.json"
assert_file_eq "$WORK/prior-skill.before" "$WORK/prior-card/SKILL.md"
assert_file_eq "$WORK/prior-state.before" "$WORK/prior-card/.scoutica/state.json"
assert_no_scan_temps
t_end

reset_provider_env
fixture_cleanup
