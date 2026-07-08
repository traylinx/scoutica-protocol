#!/bin/sh
# tests/security_gate.sh — Scoutica security-invariant gate (STATIC + RUNTIME probes).
#
# Enforces the five AGENTS.md invariants (+ publish consent) as a repo-scanning check.
# Every invariant emits one machine-readable line consumed by tests/run.sh:
#
#     RESULT <PASS|FAIL> <finding-id> <INV-ID [type] :: detail>
#
# and a human-readable summary on stderr. It is invoked by run.sh AND is callable
# standalone (`sh tests/security_gate.sh`), in which case it exits non-zero iff any
# invariant FAILs. run.sh does NOT rely on that exit code — it reconciles each RESULT
# line's finding-id against tests/EXPECTED_FAIL.txt (open findings ⇒ XFAIL).
#
# STATIC gates are authoritative for the interpolation/injection classes (a runtime test
# cannot prove absence of injection). RUNTIME-PROBE gates are fix-marker heuristics: they
# FAIL until the remediation marker (a named helper / trap coverage / corrected copy) lands,
# then flip to PASS — at which point the finding-id is removed from EXPECTED_FAIL. Later
# phases add behavioral tests/*.test.sh that supplement (never replace) these probes.
#
# POSIX sh; no bashisms; no external deps beyond grep/awk/sed (python/jq not required here).

set -u

GATE_HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=${REPO_ROOT:-$(CDPATH= cd -- "$GATE_HERE/.." && pwd)}
CLI="$REPO_ROOT/tools/scoutica"
PS1FILE="$REPO_ROOT/tools/scoutica.ps1"

_gate_fail=0

# emit <status> <finding-id> <inv-id> <type> <detail...>
emit() {
    _e_status="$1"; _e_finding="$2"; _e_inv="$3"; _e_type="$4"
    shift 4
    printf 'RESULT %s %s %s [%s] :: %s\n' "$_e_status" "$_e_finding" "$_e_inv" "$_e_type" "$*"
    if [ "$_e_status" = "FAIL" ]; then
        _gate_fail=$((_gate_fail + 1))
        printf '  ✗ %-26s %-16s %s\n' "$_e_inv" "$_e_finding" "$*" >&2
    else
        printf '  ✓ %-26s %-16s %s\n' "$_e_inv" "$_e_finding" "$*" >&2
    fi
}

# --- shared detector: single-quote-then-shell-var interpolation inside `python -c` regions ---
# Prints "<line>: <text>" for every offending site whose line number is within [lo,hi].
# lo/hi = 0/0 means "outside a given scan region" is selected by the caller via awk range.
# Discriminator '\$  : a shell interpolation ($word / ${..} / $() ) opening immediately after a
# Python string quote — the exact shape of every injection site (open('$dir'), '''$response''',
# strptime('$x')). Numeric f-string fields ({$total_ms/1000}) and bash "$" trailers are NOT matched.
_interp_hits() {
    _ih_lo="$1"; _ih_hi="$2"
    awk -v lo="$_ih_lo" -v hi="$_ih_hi" '
        inblk == 1 {
            if ($0 ~ /^[[:space:]]*"/) { inblk = 0; next }   # closing quote line of a multi-line -c
            if ($0 ~ /'\''\$[A-Za-z_{(]/ && NR >= lo && NR <= hi) print NR": "$0
            next
        }
        /python3?[[:space:]]+-c[[:space:]]+"[[:space:]]*$/ { inblk = 1; next }   # multi-line opener
        /python3?[[:space:]]+-c[[:space:]]+"/ {                                   # single-line
            if ($0 ~ /'\''\$[A-Za-z_{(]/ && NR >= lo && NR <= hi) print NR": "$0
        }
    ' "$CLI"
}

# =========================================================================
# STATIC invariants (authoritative)
# =========================================================================

inv_interp_scan() {
    # F-CRIT-RCE-001: zero interpolated `python -c` sites inside the scan path (cmd_scan).
    if [ ! -f "$CLI" ]; then
        emit FAIL F-CRIT-RCE-001 INV-STATIC-INTERP-SCAN STATIC "CLI not found at $CLI"; return
    fi
    _lo=$(grep -nE '^cmd_scan\(\)' "$CLI" | head -1 | cut -d: -f1)
    if [ -z "$_lo" ]; then
        emit FAIL F-CRIT-RCE-001 INV-STATIC-INTERP-SCAN STATIC "cmd_scan() not found — cannot bound scan region"; return
    fi
    _hi=$(awk -v s="$_lo" 'NR>s && /^cmd_[a-z_]+\(\)/{print NR-1; exit}' "$CLI")
    [ -n "$_hi" ] || _hi=$(wc -l < "$CLI" | tr -d ' ')
    _hits=$(_interp_hits "$_lo" "$_hi")
    if [ -n "$_hits" ]; then
        _n=$(printf '%s\n' "$_hits" | grep -c ':')
        _lines=$(printf '%s\n' "$_hits" | cut -d: -f1 | tr '\n' ',' | sed 's/,$//')
        emit FAIL F-CRIT-RCE-001 INV-STATIC-INTERP-SCAN STATIC "scan region [$_lo-$_hi]: $_n interpolated -c site(s) at lines $_lines"
    else
        emit PASS F-CRIT-RCE-001 INV-STATIC-INTERP-SCAN STATIC "no interpolated -c sites in scan region [$_lo-$_hi]"
    fi
}

inv_interp_local() {
    # F-MED-LOCAL-001: zero interpolated `python -c` sites OUTSIDE the scan path.
    if [ ! -f "$CLI" ]; then
        emit FAIL F-MED-LOCAL-001 INV-STATIC-INTERP-LOCAL STATIC "CLI not found at $CLI"; return
    fi
    _lo=$(grep -nE '^cmd_scan\(\)' "$CLI" | head -1 | cut -d: -f1)
    _hi=$(awk -v s="${_lo:-0}" 'NR>s && /^cmd_[a-z_]+\(\)/{print NR-1; exit}' "$CLI")
    [ -n "$_lo" ] || _lo=0
    [ -n "$_hi" ] || _hi=0
    _total=$(wc -l < "$CLI" | tr -d ' ')
    # hits before the scan region and after it
    _hits=$(
        _interp_hits 1 "$((_lo - 1))"
        _interp_hits "$((_hi + 1))" "$_total"
    )
    _hits=$(printf '%s\n' "$_hits" | grep ':' || true)
    if [ -n "$_hits" ]; then
        _n=$(printf '%s\n' "$_hits" | grep -c ':')
        _lines=$(printf '%s\n' "$_hits" | cut -d: -f1 | tr '\n' ',' | sed 's/,$//')
        emit FAIL F-MED-LOCAL-001 INV-STATIC-INTERP-LOCAL STATIC "$_n interpolated -c site(s) outside scan at lines $_lines"
    else
        emit PASS F-MED-LOCAL-001 INV-STATIC-INTERP-LOCAL STATIC "no interpolated -c sites outside scan region"
    fi
}

inv_ps_staging() {
    # F-HIGH-PS-001: PowerShell publish must not broad-stage (git add -A / git add . / git commit -a).
    if [ ! -f "$PS1FILE" ]; then
        emit PASS F-HIGH-PS-001 INV-STATIC-PS-STAGING STATIC "scoutica.ps1 absent (nothing to stage)"; return
    fi
    _hits=$(grep -nE 'git[[:space:]]+add[[:space:]]+(-A|--all|\.)|git[[:space:]]+commit[[:space:]]+-a' "$PS1FILE" || true)
    if [ -n "$_hits" ]; then
        _lines=$(printf '%s\n' "$_hits" | cut -d: -f1 | tr '\n' ',' | sed 's/,$//')
        emit FAIL F-HIGH-PS-001 INV-STATIC-PS-STAGING STATIC "broad git staging in scoutica.ps1 at lines $_lines"
    else
        emit PASS F-HIGH-PS-001 INV-STATIC-PS-STAGING STATIC "scoutica.ps1 stages an allowlist only"
    fi
}

inv_ps_interp() {
    # F-MED-PS-001: PowerShell must generate JSON/YAML through escaping converters, never raw
    # interpolation. Two dangerous shapes, both must be zero (PR#1 review: the old gate only caught
    # `key: $var` and explicitly excluded `$(`, so `$($_.title)` inside JSON quotes false-greened):
    #   A. JSON-string-embedded interpolation — a `$` opening right after an escaped JSON quote (`"$…).
    #      This is the exact bug: `"type`": `"$($_.type)`". After the fix no generated quote is
    #      immediately followed by an interpolation.
    #   B. value-position interpolation (after `key:`) that is NOT an approved escaper: not
    #      $(ConvertTo-JsonScalar|JsonArray|YamlScalar|YamlList …), not a $(if …) numeric guard, and
    #      not a pre-serialized fragment named *Json/*Yaml (built BY the converters — check A proves
    #      such a fragment cannot itself contain embedded raw interpolation).
    # Console output (Write-Host/Err/Warn/Success) is not file generation and is excluded.
    if [ ! -f "$PS1FILE" ]; then
        emit PASS F-MED-PS-001 INV-STATIC-PS-INTERP STATIC "scoutica.ps1 absent"; return
    fi
    # A. interpolation opening right after an escaped JSON quote:  `"$…
    _a=$(grep -nE '`"\$' "$PS1FILE" || true)
    # A'. a raw variable/member subexpression `$($var)` / `$($var.member)` ANYWHERE (mid-value too,
    #     closing the boundary-only bypass) — approved escapers start `$(ConvertTo…`/`$(if …`, never
    #     `$($`; a benign `$($x -join …)` has an operator (no trailing `.`/`)`), so it is not matched.
    #     Console output (Write-Host/Err/Warn/Success) is display, not file generation — excluded.
    _ap=$(grep -nE '\$\(\$[A-Za-z_][A-Za-z0-9_]*[.)]' "$PS1FILE" \
            | grep -vE 'Write-(Host|Err|Warn|Success)' || true)
    # B. value-position `key: $…` that is not an approved escaper / numeric guard / *Json|*Yaml fragment.
    _b=$(grep -nE ':[[:space:]]*"?\$' "$PS1FILE" \
            | grep -vE 'Write-(Host|Err|Warn|Success)' \
            | grep -vE '\$\((ConvertTo-(JsonScalar|JsonArray|YamlScalar|YamlList)|if )' \
            | grep -vE ':[[:space:]]*\$[A-Za-z_][A-Za-z0-9_]*(Json|Yaml)\b' \
            || true)
    _hits=$(printf '%s\n%s\n%s\n' "$_a" "$_ap" "$_b" | grep -c '[^[:space:]]' || true)
    if [ "${_hits:-0}" -gt 0 ]; then
        emit FAIL F-MED-PS-001 INV-STATIC-PS-INTERP STATIC "$_hits raw JSON/YAML interpolation site(s) in scoutica.ps1 (A=embedded, A'=subexpr deref, B=non-escaper value)"
    else
        emit PASS F-MED-PS-001 INV-STATIC-PS-INTERP STATIC "scoutica.ps1 routes every generated scalar through an escaping converter"
    fi
}

# =========================================================================
# RUNTIME-PROBE invariants (fix-marker heuristics; behavioral tests supplement these per phase)
# =========================================================================

inv_symlink_helper() {
    # F-HIGH-FS-001: a shared symlink-safe write helper applied to org/role/identity/state writers.
    # Marker: a reusable helper function definition. Ad-hoc inline `[ -L ]` guards do not satisfy this.
    if grep -qE '^[[:space:]]*(_?safe_write|write_file_safe|_?refuse_if_symlink|assert_not_symlink|_write_safe|_?safe_write_file)[[:space:]]*\(\)' "$CLI" 2>/dev/null; then
        emit PASS F-HIGH-FS-001 INV-RUNTIME-SYMLINK-HELPER RUNTIME-PROBE "shared symlink-safe write helper present"
    else
        emit FAIL F-HIGH-FS-001 INV-RUNTIME-SYMLINK-HELPER RUNTIME-PROBE "no shared symlink-safe write helper; org/role/identity/state writes unguarded"
    fi
}

inv_url_validator() {
    # F-HIGH-SSRF-001: ONE reusable URL validator used by all fetches incl. discovered card_url.
    # Marker: a reusable validator function definition.
    if grep -qE '^[[:space:]]*(_?validate_url|_?is_safe_url|_?url_is_safe|_?safe_fetch|check_fetch_url|_?validate_fetch_url)[[:space:]]*\(\)' "$CLI" 2>/dev/null; then
        emit PASS F-HIGH-SSRF-001 INV-RUNTIME-URL-VALIDATOR RUNTIME-PROBE "reusable URL validator present"
    else
        emit FAIL F-HIGH-SSRF-001 INV-RUNTIME-URL-VALIDATOR RUNTIME-PROBE "no reusable URL validator; discovered card_url fetch bypasses validation"
    fi
}

inv_temp_trap() {
    # F-HIGH-TEMP-001: scan raw-response + request payload cleaned via trap on success/fail/interrupt.
    # Marker: a trap whose cleanup references the scan raw response or the request payload file.
    if grep -E '^[[:space:]]*trap ' "$CLI" 2>/dev/null | grep -qE 'scan_response_raw|payload_file|payload_'; then
        emit PASS F-HIGH-TEMP-001 INV-RUNTIME-TEMP-TRAP RUNTIME-PROBE "scan payload/raw-response covered by trap cleanup"
    else
        emit FAIL F-HIGH-TEMP-001 INV-RUNTIME-TEMP-TRAP RUNTIME-PROBE "scan raw-response/payload not covered by any trap cleanup"
    fi
}

inv_consent_copy() {
    # F-HIGH-PUBLISH-001: consent/privacy copy must state only verified facts. The scan send path
    # claims "your data stays on your machine" even when routing to a provider. Marker: absence of
    # the unqualified claim.
    if grep -qE 'your data stays on your machine' "$CLI" 2>/dev/null; then
        emit FAIL F-HIGH-PUBLISH-001 INV-RUNTIME-CONSENT-COPY RUNTIME-PROBE "unverified privacy claim 'your data stays on your machine' present in scan path"
    else
        emit PASS F-HIGH-PUBLISH-001 INV-RUNTIME-CONSENT-COPY RUNTIME-PROBE "no unverified 'data stays on your machine' claim"
    fi
}

# =========================================================================
# Run all invariants
# =========================================================================
printf '== Scoutica security-invariant gate ==\n' >&2
printf '   repo: %s\n' "$REPO_ROOT" >&2

inv_interp_scan
inv_interp_local
inv_ps_staging
inv_ps_interp
inv_symlink_helper
inv_url_validator
inv_temp_trap
inv_consent_copy

printf '== gate: %d invariant(s) failing ==\n' "$_gate_fail" >&2

# Standalone exit code (run.sh ignores this and reconciles per finding).
if [ "$_gate_fail" -gt 0 ]; then
    exit 1
fi
exit 0
