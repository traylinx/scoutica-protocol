#!/bin/sh
# tests/phase3.test.sh — Phase 3 regression tests (fetch/publish/FS/preview hardening).
. "$TESTLIB/assert.sh"
error() { :; }   # stubs for the extracted helpers
warn() { :; }

# Load the two bash helpers straight from the CLI (defs end at a column-0 '}').
eval "$(awk '/^_validate_url\(\) \{/{f=1} f{print} f&&/^\}/{exit}' "$SCOUTICA")"
eval "$(awk '/^_refuse_if_symlink\(\) \{/{f=1} f{print} f&&/^\}/{exit}' "$SCOUTICA")"

# ---- F-HIGH-SSRF-001: URL validator (fail-closed) ----
_vu() { _validate_url "$1" >/dev/null 2>&1 && echo OK || echo BLOCKED; }
t_begin F-HIGH-SSRF-001 "URL validator: HTTPS-only; block localhost/private/link-local/metadata"
assert_eq BLOCKED "$(_vu http://example.com/x)" "plain http rejected"
assert_eq BLOCKED "$(_vu https://localhost/x)" "localhost blocked"
assert_eq BLOCKED "$(_vu https://127.0.0.1/x)" "loopback blocked"
assert_eq BLOCKED "$(_vu https://10.1.2.3/x)" "rfc1918/8 blocked"
assert_eq BLOCKED "$(_vu https://192.168.0.1/x)" "rfc1918/16 blocked"
assert_eq BLOCKED "$(_vu https://169.254.169.254/latest/meta-data/)" "cloud metadata blocked"
assert_eq OK "$(_vu https://8.8.8.8/x)" "public literal IP allowed"
# DNS-rebinding defense: validator emits "host port ip"; fetches pin via curl --resolve.
assert_eq "8.8.8.8 443 8.8.8.8" "$(_validate_url https://8.8.8.8/x 2>/dev/null)" "validator emits host port ip"
assert_eq "8.8.8.8 8443 8.8.8.8" "$(_validate_url https://8.8.8.8:8443/x 2>/dev/null)" "pins the URL's actual port"
assert_grep 'resolve_args "\$base_url' "$SCOUTICA" "fetches pinned to validated IP via --resolve"
t_end

# ---- F-HIGH-FS-001: supplemental helper probe (not command-level closure) ----
t_begin F-HIGH-FS-001 "supplemental helper probe: refuse_if_symlink rejects a target symlink"
ln -sf /etc/passwd "$WORK/evil.json" 2>/dev/null
assert_exit 1 _refuse_if_symlink "$WORK/evil.json"
assert_exit 0 _refuse_if_symlink "$WORK/normal.json"
t_end

# ---- F-MED-PREVIEW-001: evidence href scheme filter ----
_href=$(python3 - "$SCOUTICA" <<'PY'
import sys, re
src = open(sys.argv[1]).read()
m = re.search(r'def safe_href\(u\):.*?return "#"', src, re.S)
ns = {'html_mod': __import__('html')}
exec(m.group(0), ns)
for u in ("javascript:alert(1)", "https://ok.com/a", "data:text/html,x", "mailto:a@b"):
    print(u + " => " + ns['safe_href'](u))
PY
)
t_begin F-MED-PREVIEW-001 "preview href allows only http(s)/mailto; drops javascript:/data:"
assert_grep "javascript:alert\(1\) => #" "$_href"
assert_grep "https://ok.com/a => https://ok.com/a" "$_href"
assert_grep "data:text/html,x => #" "$_href"
assert_grep "mailto:a@b => mailto:a@b" "$_href"
t_end

# ---- F-MED-FETCH-002: fetches size-capped + JSON-validated before save ----
t_begin F-MED-FETCH-002 "resolve fetches are size-capped and JSON-validated before disk write"
assert_grep "--max-filesize 2097152" "$SCOUTICA"
assert_grep "_json_ok" "$SCOUTICA"
t_end

# ---- F-HIGH-PUBLISH-001: supplemental copy markers (not provider-consent closure) ----
t_begin F-HIGH-PUBLISH-001 "supplemental copy probe: no auto-publish or categorical locality marker"
assert_no_grep "your data stays on your machine" "$SCOUTICA"
assert_no_grep "Auto-deploying live preview" "$SCOUTICA"
t_end

# ---- F-HIGH-TEMP-001: supplemental trap marker (not lifecycle closure) ----
t_begin F-HIGH-TEMP-001 "supplemental marker probe: scan trap names payload and raw response"
_trapline=$(grep -E "^[[:space:]]*trap " "$SCOUTICA" | grep payload_file)
assert_grep "payload_file" "$_trapline"
assert_grep "scan_raw_file" "$_trapline"
t_end

# ---- F-MED-PARSE-001: parse-failure branch reachable under set -e ----
t_begin F-MED-PARSE-001 "parse-failure branch is reachable (if ! strict Python, not post-hoc \$?)"
assert_grep "if ! \"\\\$VALIDATION_PYTHON\" << 'PARSE_SCRIPT'" "$SCOUTICA"
t_end
