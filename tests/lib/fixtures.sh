#!/bin/sh
# tests/lib/fixtures.sh — reusable isolated-process and boundary fixtures.
#
# Source after tests/lib/assert.sh. Helpers use only mock data and write below the caller-provided
# root (normally $WORK). Nothing automatically starts a process or installs a trap.

if [ -z "${FIXTURES:-}" ]; then
    _FIXTURE_LIB_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
    FIXTURES=$(CDPATH= cd -- "$_FIXTURE_LIB_DIR/../fixtures" && pwd)
fi

FIXTURE_ORIGINAL_PATH=${FIXTURE_ORIGINAL_PATH:-$PATH}
FIXTURE_PIDS=${FIXTURE_PIDS:-}

# fixture_isolated_env <root>
# Export a clean user/runtime envelope while retaining host tools after the fake-command bin dir.
fixture_isolated_env() {
    FIXTURE_SANDBOX=$1
    HOME="$FIXTURE_SANDBOX/home"
    SCOUTICA_HOME="$FIXTURE_SANDBOX/scoutica-home"
    XDG_CONFIG_HOME="$FIXTURE_SANDBOX/xdg-config"
    XDG_CACHE_HOME="$FIXTURE_SANDBOX/xdg-cache"
    TMPDIR="$FIXTURE_SANDBOX/tmp"
    FIXTURE_BIN="$FIXTURE_SANDBOX/bin"
    GIT_CONFIG_GLOBAL="$FIXTURE_SANDBOX/gitconfig"
    GIT_CONFIG_NOSYSTEM=1
    GIT_TERMINAL_PROMPT=0
    PATH="$FIXTURE_BIN:$FIXTURE_ORIGINAL_PATH"

    export FIXTURE_SANDBOX HOME SCOUTICA_HOME XDG_CONFIG_HOME XDG_CACHE_HOME TMPDIR
    export FIXTURE_BIN GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM GIT_TERMINAL_PROMPT PATH

    mkdir -p "$HOME" "$SCOUTICA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$TMPDIR" "$FIXTURE_BIN"
    : > "$GIT_CONFIG_GLOBAL"
    git config --file "$GIT_CONFIG_GLOBAL" user.name "Alice Developer"
    git config --file "$GIT_CONFIG_GLOBAL" user.email "alice@example.test"
    git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main
}

# fixture_install_fake_provider <command-name>
# Installs the environment-driven provider double at the front of the isolated PATH.
fixture_install_fake_provider() {
    _fp_name=$1
    [ -n "${FIXTURE_BIN:-}" ] || return 2
    case "$_fp_name" in
        */*|""|.|..) return 2 ;;
    esac
    cp "$FIXTURES/bin/fake-provider" "$FIXTURE_BIN/$_fp_name"
    chmod +x "$FIXTURE_BIN/$_fp_name"
    printf '%s\n' "$FIXTURE_BIN/$_fp_name"
}

# fixture_make_git_remote <path> [accept|reject]
# Creates a local bare remote. reject installs a deterministic rejecting pre-receive hook.
fixture_make_git_remote() {
    _fgr_path=$1
    _fgr_mode=${2:-accept}
    rm -rf "$_fgr_path"
    git init --bare -q "$_fgr_path" || return 1
    if [ "$_fgr_mode" = "reject" ]; then
        printf '%s\n' '#!/bin/sh' 'echo "fixture: push rejected" >&2' 'exit 1' \
            > "$_fgr_path/hooks/pre-receive"
        chmod +x "$_fgr_path/hooks/pre-receive"
    fi
    printf '%s\n' "$_fgr_path"
}

# fixture_copy_hostile_cwd <path>
# Copies deliberately permissive schemas used to prove cwd must never be a trust root.
fixture_copy_hostile_cwd() {
    _fhc_path=$1
    rm -rf "$_fhc_path"
    mkdir -p "$_fhc_path"
    cp -R "$FIXTURES/hostile_cwd/." "$_fhc_path/"
    printf '%s\n' "$_fhc_path"
}

# fixture_make_symlink_victim <root> [link-name]
# Exports victim/link paths and a sentinel; callers can verify that a command did not overwrite it.
fixture_make_symlink_victim() {
    _fsv_root=$1
    _fsv_name=${2:-predicted-output.json}
    mkdir -p "$_fsv_root"
    FIXTURE_SYMLINK_SENTINEL='fixture-victim-must-remain-unchanged'
    FIXTURE_SYMLINK_VICTIM="$_fsv_root/victim.txt"
    FIXTURE_SYMLINK_PATH="$_fsv_root/$_fsv_name"
    printf '%s\n' "$FIXTURE_SYMLINK_SENTINEL" > "$FIXTURE_SYMLINK_VICTIM"
    rm -f "$FIXTURE_SYMLINK_PATH"
    ln -s "$FIXTURE_SYMLINK_VICTIM" "$FIXTURE_SYMLINK_PATH"
    export FIXTURE_SYMLINK_SENTINEL FIXTURE_SYMLINK_VICTIM FIXTURE_SYMLINK_PATH
}

# fixture_wait_for_file <path> [attempts]
fixture_wait_for_file() {
    _fwf_path=$1
    _fwf_left=${2:-200}
    while [ "$_fwf_left" -gt 0 ]; do
        [ -e "$_fwf_path" ] && return 0
        sleep 0.05
        _fwf_left=$((_fwf_left - 1))
    done
    return 1
}

fixture_register_pid() {
    case "$1" in ''|*[!0-9]*) return 2 ;; esac
    FIXTURE_PIDS="$1 ${FIXTURE_PIDS:-}"
    export FIXTURE_PIDS
}

fixture_unregister_pid() {
    _fup_drop=$1
    _fup_keep=""
    for _fup_pid in ${FIXTURE_PIDS:-}; do
        [ "$_fup_pid" = "$_fup_drop" ] || _fup_keep="$_fup_keep$_fup_pid "
    done
    FIXTURE_PIDS="$_fup_keep"
    export FIXTURE_PIDS
}

# fixture_stop_pid <pid> [signal]
fixture_stop_pid() {
    _fsp_pid=$1
    _fsp_signal=${2:-TERM}
    if kill -0 "$_fsp_pid" 2>/dev/null; then
        kill -s "$_fsp_signal" "$_fsp_pid" 2>/dev/null || true
        _fsp_left=100
        while kill -0 "$_fsp_pid" 2>/dev/null && [ "$_fsp_left" -gt 0 ]; do
            _fsp_state=$(ps -o stat= -p "$_fsp_pid" 2>/dev/null | tr -d '[:space:]')
            case "$_fsp_state" in Z*|"") break ;; esac
            sleep 0.05
            _fsp_left=$((_fsp_left - 1))
        done
        if kill -0 "$_fsp_pid" 2>/dev/null; then
            kill -KILL "$_fsp_pid" 2>/dev/null || true
        fi
    fi
    wait "$_fsp_pid" 2>/dev/null || true
    fixture_unregister_pid "$_fsp_pid"
}

# fixture_cleanup : stop every process registered through fixture_register_pid.
fixture_cleanup() {
    for _fc_pid in ${FIXTURE_PIDS:-}; do
        fixture_stop_pid "$_fc_pid" TERM
    done
    FIXTURE_PIDS=""
    export FIXTURE_PIDS
}

# fixture_start_http <root>
# Starts the local deterministic HTTP boundary fixture and exports URL/PID/log paths.
fixture_start_http() {
    _fhs_root=$1
    mkdir -p "$_fhs_root"
    FIXTURE_HTTP_READY="$_fhs_root/ready"
    FIXTURE_HTTP_PORT_FILE="$_fhs_root/port"
    FIXTURE_HTTP_LOG="$_fhs_root/requests.log"
    rm -f "$FIXTURE_HTTP_READY" "$FIXTURE_HTTP_PORT_FILE" "$FIXTURE_HTTP_LOG"
    python3 "$FIXTURES/http_server.py" \
        --ready-file "$FIXTURE_HTTP_READY" \
        --port-file "$FIXTURE_HTTP_PORT_FILE" \
        --log-file "$FIXTURE_HTTP_LOG" \
        >"$_fhs_root/stdout" 2>"$_fhs_root/stderr" &
    FIXTURE_HTTP_PID=$!
    fixture_register_pid "$FIXTURE_HTTP_PID"
    if ! fixture_wait_for_file "$FIXTURE_HTTP_READY" 200; then
        fixture_stop_pid "$FIXTURE_HTTP_PID" TERM
        return 1
    fi
    FIXTURE_HTTP_PORT=$(cat "$FIXTURE_HTTP_PORT_FILE")
    FIXTURE_HTTP_URL="http://127.0.0.1:$FIXTURE_HTTP_PORT"
    export FIXTURE_HTTP_PID FIXTURE_HTTP_PORT FIXTURE_HTTP_URL
    export FIXTURE_HTTP_READY FIXTURE_HTTP_PORT_FILE FIXTURE_HTTP_LOG
}
