#!/bin/sh
# tests/phase5.test.sh — Phase 5 regression tests (PowerShell + identity).
. "$TESTLIB/assert.sh"
PS1="$REPO_ROOT/tools/scoutica.ps1"

# ---- F-HIGH-ID-001: no placeholder keys; refuse when no real secp256k1 lib ----
t_begin F-HIGH-ID-001 "identity emits no placeholder keys; refuses (exit 3) without a secp256k1 lib"
assert_no_grep "Placeholder keys" "$SCOUTICA"
assert_no_grep "npub_placeholder" "$SCOUTICA"
assert_no_grep "sha256\(private_key" "$SCOUTICA"
# Extract the embedded identity script and run it; with no coincurve it must refuse (exit 3)
# and write no key file. (If coincurve IS installed, the refuse path can't be forced — skip it.)
awk "/<<'IDENTITY_SCRIPT'/{f=1;next} /^IDENTITY_SCRIPT\$/{f=0} f" "$SCOUTICA" > "$WORK/idscript.py"
if ! python3 -c "import coincurve" 2>/dev/null; then
    python3 "$WORK/idscript.py" "$WORK/id" >/dev/null 2>&1
    assert_eq 3 "$?" "no-lib path exits 3 (refuse)"
    assert_exit 1 test -f "$WORK/id/keypair.json"
fi
t_end

# ---- F-HIGH-ID-002: atomic 0600 key file + 0700 dir ----
t_begin F-HIGH-ID-002 "identity key file written race-free (mkstemp 0600 + fchmod + atomic replace); dir 0700"
assert_grep "tempfile.mkstemp" "$SCOUTICA"
assert_grep "os.fchmod\(_fd, 0o600\)" "$SCOUTICA"
assert_grep "os.replace\(_tmp, keypair_file\)" "$SCOUTICA"
assert_grep "makedirs\(identity_dir, mode=0o700" "$SCOUTICA"
t_end

# ---- F-HIGH-PS-001: allowlist staging, never git add -A ----
t_begin F-HIGH-PS-001 "PowerShell publish stages an allowlist, never git add -A / git add ."
assert_no_grep "git add -A" "$PS1"
assert_no_grep "git add \." "$PS1"
assert_grep "git add -- " "$PS1"
t_end

# ---- F-HIGH-PS-002: card.gitignore copied at init ----
t_begin F-HIGH-PS-002 "PowerShell init copies card.gitignore so secrets are never staged"
assert_grep 'Destination \(Join-Path \$targetDir "card.gitignore"\)' "$PS1"
t_end

# ---- F-MED-PS-001: structured writers, no raw scalar interpolation into JSON/YAML ----
t_begin F-MED-PS-001 "PowerShell uses structured JSON/YAML escapers for generated files"
assert_grep "ConvertTo-JsonScalar" "$PS1"
assert_grep "ConvertTo-YamlScalar" "$PS1"
t_end
