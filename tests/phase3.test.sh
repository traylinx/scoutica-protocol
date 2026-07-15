#!/bin/sh
# tests/phase3.test.sh — Phase 3 regression tests (fetch/publish/FS/preview hardening).
. "$TESTLIB/assert.sh"
error() { :; }   # stubs for the extracted helpers
warn() { :; }

# Load the filesystem helper straight from the CLI (definition ends at a column-0 '}').
eval "$(awk '/^_refuse_if_symlink\(\) \{/{f=1} f{print} f&&/^\}/{exit}' "$SCOUTICA")"

# ---- F-HIGH-SSRF-001: authoritative behavior lives in jobs_security.test.sh ----
t_begin F-HIGH-SSRF-001 "jobs and resolve share the installed safe-fetch boundary"
assert_grep '^_safe_fetch()' "$SCOUTICA"
assert_grep '\$script_dir/safe_fetch.py' "$SCOUTICA"
assert_no_grep 'from urllib.request import urlopen' "$SCOUTICA"
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
assert_grep "--expect json --allow-not-found" "$SCOUTICA"
assert_grep "_json_ok" "$SCOUTICA"
t_end

# ---- F-HIGH-PUBLISH-001: supplemental copy markers (not provider-consent closure) ----
t_begin F-HIGH-PUBLISH-001 "supplemental copy probe: no auto-publish or categorical locality marker"
assert_no_grep "your data stays on your machine" "$SCOUTICA"
assert_no_grep "Auto-deploying live preview" "$SCOUTICA"
t_end

# ---- F-HIGH-TEMP-001: supplemental owned-runtime marker (behavior is authoritative) ----
t_begin F-HIGH-TEMP-001 "supplemental marker probe: scan trap cleans its owned runtime directory"
_trapline=$(grep -E "^[[:space:]]*trap " "$SCOUTICA" | grep _scan_runtime_cleanup)
assert_grep "_scan_runtime_cleanup" "$_trapline"
assert_grep 'rm -rf "\$_SCAN_RUN_DIR"' "$SCOUTICA"
t_end

# ---- F-MED-PARSE-001: parse-failure branch reachable under set -e ----
t_begin F-MED-PARSE-001 "parse-failure branch is reachable through the strict response parser"
assert_grep 'if ! "\$VALIDATION_PYTHON" "\$runtime_helper" parse-response' "$SCOUTICA"
t_end
