#!/bin/sh
# tests/run.sh — Scoutica test runner (plain POSIX; no bats/shellcheck required).
#
# What it does:
#   1. Runs the security-invariant gate (tests/security_gate.sh).
#   2. Discovers and runs every tests/**/*.test.sh (sourcing tests/lib/assert.sh).
#   3. Collects each RESULT line — "RESULT <PASS|FAIL> <finding-id> <name...>" — and
#      reconciles it against the expected-fail allowlist tests/EXPECTED_FAIL.txt:
#
#        FAIL, finding in allowlist          -> XFAIL  (known-open finding; tolerated)
#        FAIL, finding NOT in allowlist       -> FAIL   (unexpected regression; run goes red)
#        FAIL, finding "-" (harness self-test) -> FAIL   ("-" is never allowlistable)
#        PASS, finding in allowlist            -> XPASS  (fixed! remove it from EXPECTED_FAIL)
#        PASS, finding NOT in allowlist        -> PASS
#
#   The suite is GREEN (exit 0) iff there are zero unexpected FAILs. On an empty suite the
#   gate's failures are all known-open ⇒ all XFAIL ⇒ green. The allowlist must shrink to
#   empty by sprint end; set STRICT_XPASS=1 to make lingering XPASS entries fatal.
#
# Env knobs: STRICT_XPASS=1 (XPASS ⇒ red), VERBOSE=1 (echo every gate/test line).
# Exit: 0 = green, 1 = red, 2 = harness misconfiguration.

set -u

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$HERE/.." && pwd)
GATE="$HERE/security_gate.sh"
ALLOW="$HERE/EXPECTED_FAIL.txt"

export REPO_ROOT
export TESTLIB="$HERE/lib"
export FIXTURES="$HERE/fixtures"
export SCOUTICA="$REPO_ROOT/tools/scoutica"

# Per-run scratch dir, exported to tests as $WORK, cleaned on exit (invariant #5 discipline).
WORK=$(mktemp -d 2>/dev/null || mktemp -d -t scoutica-tests) || {
    echo "run.sh: cannot create temp dir" >&2; exit 2; }
export WORK
trap 'rm -rf "$WORK" 2>/dev/null' EXIT INT TERM

# --- load the allowlist into a space-padded lookup string ---------------------
allow=" "
if [ -f "$ALLOW" ]; then
    while IFS= read -r _line || [ -n "$_line" ]; do
        _line=${_line%%#*}                         # strip inline/full-line comments
        _line=$(printf '%s' "$_line" | tr -d '[:space:]')
        [ -n "$_line" ] && allow="$allow$_line "
    done < "$ALLOW"
fi
is_allowed() { case "$allow" in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

pass=0; xfail=0; xpass=0; fail=0

results="$WORK/all.results"
: > "$results"

# --- 1. security gate ---------------------------------------------------------
printf '── security gate ──\n' >&2
if [ -f "$GATE" ]; then
    sh "$GATE" >> "$results" 2>&1 || true          # gate exit code is advisory; we reconcile below
else
    printf 'RESULT FAIL - GATE-MISSING security_gate.sh not found\n' >> "$results"
fi

# --- 2. discover + run *.test.sh ---------------------------------------------
files="$WORK/files.list"
find "$HERE" -type f -name '*.test.sh' 2>/dev/null | sort > "$files"
_count=$(grep -c . "$files" 2>/dev/null || echo 0)
printf '── test files: %s ──\n' "$_count" >&2

while IFS= read -r f; do
    [ -n "$f" ] || continue
    printf '  » %s\n' "${f#"$REPO_ROOT"/}" >&2
    # Each test file runs in its own shell with the assert lib + env available.
    if ! sh "$f" >> "$results" 2>>"$WORK/test.err"; then
        # A nonzero exit with no RESULT lines means the file errored before reporting.
        if ! grep -q "^RESULT " "$results"; then :; fi
        printf 'RESULT FAIL - TESTFILE-ERROR %s exited nonzero without a clean RESULT\n' "${f#"$REPO_ROOT"/}" >> "$results"
    fi
done < "$files"
[ -s "$WORK/test.err" ] && { printf '── test stderr ──\n' >&2; cat "$WORK/test.err" >&2; }

# --- 3. reconcile every RESULT line ------------------------------------------
printf '── results ──\n' >&2
while IFS= read -r ln; do
    case "$ln" in
        "RESULT "*) : ;;
        *) [ "${VERBOSE:-0}" = "1" ] && [ -n "$ln" ] && printf '    %s\n' "$ln" >&2; continue ;;
    esac
    # shellcheck disable=SC2086  # deliberate word-splitting of the RESULT record
    set -- $ln
    shift                                   # drop the literal "RESULT"
    status=$1; finding=$2; shift 2; name=$*
    case "$status" in
        PASS)
            if [ "$finding" != "-" ] && is_allowed "$finding"; then
                xpass=$((xpass + 1))
                printf '  XPASS %-16s %s  → remove from EXPECTED_FAIL.txt\n' "$finding" "$name" >&2
            else
                pass=$((pass + 1))
                [ "${VERBOSE:-0}" = "1" ] && printf '  PASS  %-16s %s\n' "$finding" "$name" >&2
            fi
            ;;
        FAIL)
            if [ "$finding" != "-" ] && is_allowed "$finding"; then
                xfail=$((xfail + 1))
                printf '  XFAIL %-16s %s  (known-open)\n' "$finding" "$name" >&2
            else
                fail=$((fail + 1))
                printf '  FAIL  %-16s %s\n' "$finding" "$name" >&2
            fi
            ;;
        *)
            fail=$((fail + 1))
            printf '  FAIL  %-16s malformed RESULT status [%s]\n' "$finding" "$status" >&2
            ;;
    esac
done < "$results"

# --- 4. summary + exit --------------------------------------------------------
printf '──────────────────────────────────────────────\n' >&2
printf 'pass=%d  xfail=%d  xpass=%d  fail=%d\n' "$pass" "$xfail" "$xpass" "$fail" >&2

rc=0
[ "$fail" -eq 0 ] || rc=1
if [ "${STRICT_XPASS:-0}" = "1" ] && [ "$xpass" -gt 0 ]; then
    printf 'STRICT_XPASS: %d unexpected pass(es) — update EXPECTED_FAIL.txt\n' "$xpass" >&2
    rc=1
fi

if [ "$rc" -eq 0 ]; then
    printf 'RESULT: GREEN\n' >&2
else
    printf 'RESULT: RED\n' >&2
fi
exit "$rc"
