#!/bin/sh
# tests/lib/assert.sh — POSIX assertion + test-case helpers for the Scoutica test harness.
#
# Sourced by tests/**/*.test.sh. Each test case is bracketed by t_begin/t_end and emits a
# single machine-readable line on stdout:
#
#     RESULT <PASS|FAIL> <finding-id> <name...>
#
# tests/run.sh collects these lines and reconciles FAILs against tests/EXPECTED_FAIL.txt
# (known-open findings become XFAIL; anything else is a hard failure). Use finding-id "-"
# for pure harness self-tests — "-" is never allowlistable, so a broken harness always fails.
#
# No bashisms, no `local` (some /bin/sh lack it): all helper state is underscore-prefixed
# globals, mutated sequentially within a single test case.

# --- test-case state -------------------------------------------------------
_A_FINDING=""
_A_NAME=""
_A_FAILED=0

# t_begin <finding-id> <name...> : open a test case.
t_begin() {
    _A_FINDING="$1"
    shift
    _A_NAME="$*"
    _A_FAILED=0
}

# t_fail <reason...> : record a failure + diagnostic for the current case (stderr).
t_fail() {
    _A_FAILED=1
    printf '    FAIL: %s\n' "$*" >&2
}

# t_end : emit the RESULT line for the current case.
t_end() {
    if [ "$_A_FAILED" -eq 0 ]; then
        printf 'RESULT PASS %s %s\n' "$_A_FINDING" "$_A_NAME"
    else
        printf 'RESULT FAIL %s %s\n' "$_A_FINDING" "$_A_NAME"
    fi
}

# --- assertions ------------------------------------------------------------
# Each returns 0 on success, 1 on failure, and records the failure via t_fail so the
# common `assert_x ...` form is enough. They can also be chained: `assert_x ... || t_fail "extra"`.

# assert_eq <expected> <actual> [msg]
assert_eq() {
    if [ "$1" = "$2" ]; then
        return 0
    fi
    t_fail "${3:-assert_eq}: expected [$1] got [$2]"
    return 1
}

# assert_ne <unexpected> <actual> [msg]
assert_ne() {
    if [ "$1" != "$2" ]; then
        return 0
    fi
    t_fail "${3:-assert_ne}: value unexpectedly equal to [$1]"
    return 1
}

# assert_exit <expected-code> <cmd> [args...] : run cmd, assert its exit status.
assert_exit() {
    _av_want="$1"
    shift
    "$@" >/dev/null 2>&1
    _av_got=$?
    if [ "$_av_got" -eq "$_av_want" ]; then
        return 0
    fi
    t_fail "assert_exit: expected exit $_av_want got $_av_got for: $*"
    return 1
}

# assert_grep <ere-pattern> <file-or-string> [msg] : pattern must be present.
# If arg 2 is an existing regular file it is grepped; otherwise it is treated as a literal string.
assert_grep() {
    _av_pat="$1"
    _av_hay="$2"
    if [ -f "$_av_hay" ]; then
        if grep -Eq -- "$_av_pat" "$_av_hay"; then return 0; fi
    else
        if printf '%s\n' "$_av_hay" | grep -Eq -- "$_av_pat"; then return 0; fi
    fi
    t_fail "${3:-assert_grep}: pattern /$_av_pat/ not found in [$_av_hay]"
    return 1
}

# assert_no_grep <ere-pattern> <file-or-string> [msg] : pattern must be absent.
assert_no_grep() {
    _av_pat="$1"
    _av_hay="$2"
    if [ -f "$_av_hay" ]; then
        if grep -Eq -- "$_av_pat" "$_av_hay"; then
            t_fail "${3:-assert_no_grep}: pattern /$_av_pat/ unexpectedly present in file [$_av_hay]"
            return 1
        fi
    else
        if printf '%s\n' "$_av_hay" | grep -Eq -- "$_av_pat"; then
            t_fail "${3:-assert_no_grep}: pattern /$_av_pat/ unexpectedly present in string"
            return 1
        fi
    fi
    return 0
}

# assert_no_exec <canary-path> <cmd> [args...] : run cmd (which processes untrusted input);
# assert that no injected payload executed, evidenced by <canary-path> NOT being created.
# This is the anti-injection primitive for the RCE regression tests: a malicious AI response
# containing e.g. `; touch <canary>` must route through a data-safe path and leave no canary.
assert_no_exec() {
    _av_canary="$1"
    shift
    rm -f -- "$_av_canary" 2>/dev/null
    "$@" >/dev/null 2>&1
    if [ -e "$_av_canary" ]; then
        t_fail "assert_no_exec: INJECTION EXECUTED — canary [$_av_canary] created by: $*"
        rm -f -- "$_av_canary" 2>/dev/null
        return 1
    fi
    return 0
}

# assert_exists <path> [msg] : path of any type (including a symlink) must exist.
assert_exists() {
    if [ -e "$1" ] || [ -L "$1" ]; then
        return 0
    fi
    t_fail "${2:-assert_exists}: path does not exist [$1]"
    return 1
}

# assert_not_exists <path> [msg] : path must not exist, including as a dangling symlink.
assert_not_exists() {
    if [ ! -e "$1" ] && [ ! -L "$1" ]; then
        return 0
    fi
    t_fail "${2:-assert_not_exists}: path unexpectedly exists [$1]"
    return 1
}

# assert_file_eq <expected-file> <actual-file> [msg] : files must be byte-equivalent.
assert_file_eq() {
    if [ -f "$1" ] && [ -f "$2" ] && cmp -s -- "$1" "$2"; then
        return 0
    fi
    t_fail "${3:-assert_file_eq}: files differ or are missing [$1] [$2]"
    return 1
}

# assert_pid_running <pid> [msg] : process must currently exist.
assert_pid_running() {
    if kill -0 "$1" 2>/dev/null; then
        return 0
    fi
    t_fail "${2:-assert_pid_running}: pid is not running [$1]"
    return 1
}

# assert_pid_stopped <pid> [msg] : process must no longer exist.
assert_pid_stopped() {
    if ! kill -0 "$1" 2>/dev/null; then
        return 0
    fi
    t_fail "${2:-assert_pid_stopped}: pid is still running [$1]"
    return 1
}
