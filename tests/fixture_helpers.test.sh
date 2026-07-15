#!/bin/sh
# tests/fixture_helpers.test.sh — self-test reusable Phase 0 isolation fixtures.

. "$TESTLIB/assert.sh"
. "$TESTLIB/fixtures.sh"

fixture_isolated_env "$WORK/fixture-helpers"
trap 'fixture_cleanup' EXIT INT TERM

t_begin - "fixture isolation: HOME, Scoutica, PATH, and git config"
assert_exists "$HOME"
assert_exists "$SCOUTICA_HOME"
assert_eq "$FIXTURE_BIN" "${PATH%%:*}" "fake-command bin leads PATH"
assert_eq "Alice Developer" "$(git config --global user.name)" "isolated git identity"
assert_eq "alice@example.test" "$(git config --global user.email)" "isolated git email"
t_end

t_begin - "fake provider: stdin, argv, response, and PID readiness"
_provider=$(fixture_install_fake_provider fake-ai)
_response="$WORK/fixture-response.json"
printf '%s\n' '{"profile":{"name":"Alice Developer"}}' > "$_response"
FAKE_PROVIDER_PID_FILE="$WORK/provider.pid"
FAKE_PROVIDER_READY_FILE="$WORK/provider.ready"
FAKE_PROVIDER_ARGV_LOG="$WORK/provider.argv"
FAKE_PROVIDER_STDIN_LOG="$WORK/provider.stdin"
FAKE_PROVIDER_RESPONSE_FILE="$_response"
export FAKE_PROVIDER_PID_FILE FAKE_PROVIDER_READY_FILE FAKE_PROVIDER_ARGV_LOG
export FAKE_PROVIDER_STDIN_LOG FAKE_PROVIDER_RESPONSE_FILE
_provider_out=$(printf '%s\n' 'mock candidate text' | "$_provider" --mode scan)
assert_exists "$FAKE_PROVIDER_READY_FILE"
assert_grep '^--mode$' "$FAKE_PROVIDER_ARGV_LOG"
assert_grep '^scan$' "$FAKE_PROVIDER_ARGV_LOG"
assert_grep '^mock candidate text$' "$FAKE_PROVIDER_STDIN_LOG"
assert_grep 'Alice Developer' "$_provider_out"
t_end

t_begin - "Git and filesystem fixtures: bare remote, hostile cwd, symlink victim"
_remote=$(fixture_make_git_remote "$WORK/fixture-remote.git")
assert_eq true "$(git --git-dir="$_remote" rev-parse --is-bare-repository)" "bare remote"
_hostile=$(fixture_copy_hostile_cwd "$WORK/hostile-cwd")
assert_exists "$_hostile/schemas/candidate_profile.schema.json"
assert_exists "$_hostile/schemas/recruiter/message.schema.json"
fixture_make_symlink_victim "$WORK/symlink"
assert_exists "$FIXTURE_SYMLINK_PATH"
assert_eq "$FIXTURE_SYMLINK_SENTINEL" "$(cat "$FIXTURE_SYMLINK_VICTIM")" "victim sentinel"
t_end

t_begin - "HTTP fixture: readiness, PID control, deterministic endpoint"
fixture_start_http "$WORK/http-fixture"
assert_pid_running "$FIXTURE_HTTP_PID"
_http_status=$(python3 - "$FIXTURE_HTTP_URL/ok.json" <<'PY'
import json, sys, urllib.request
with urllib.request.urlopen(sys.argv[1], timeout=2) as response:
    print(json.load(response)["status"])
PY
)
assert_eq ok "$_http_status" "fixture HTTP response"
fixture_stop_pid "$FIXTURE_HTTP_PID" TERM
assert_pid_stopped "$FIXTURE_HTTP_PID"
t_end

t_begin - "signal coordination: fake provider records TERM and exits"
_signal_ready="$WORK/signal.ready"
_signal_release="$WORK/signal.release"
_signal_seen="$WORK/signal.seen"
FAKE_PROVIDER_PID_FILE="$WORK/signal.pid"
FAKE_PROVIDER_READY_FILE="$_signal_ready"
FAKE_PROVIDER_RELEASE_FILE="$_signal_release"
FAKE_PROVIDER_SIGNAL_FILE="$_signal_seen"
FAKE_PROVIDER_STDIN_LOG="$WORK/signal.stdin"
unset FAKE_PROVIDER_RESPONSE_FILE FAKE_PROVIDER_ARGV_LOG
export FAKE_PROVIDER_PID_FILE FAKE_PROVIDER_READY_FILE FAKE_PROVIDER_RELEASE_FILE
export FAKE_PROVIDER_SIGNAL_FILE FAKE_PROVIDER_STDIN_LOG
"$_provider" </dev/null >/dev/null 2>&1 &
_signal_pid=$!
fixture_register_pid "$_signal_pid"
if ! fixture_wait_for_file "$_signal_ready" 200; then
    t_fail "fake provider did not become ready"
fi
assert_pid_running "$_signal_pid"
fixture_stop_pid "$_signal_pid" TERM
assert_pid_stopped "$_signal_pid"
assert_grep '^TERM$' "$_signal_seen"
t_end

fixture_cleanup
