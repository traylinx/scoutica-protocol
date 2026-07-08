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

# ---- F-HIGH-PS-001: allowlist staging, never git add -A; stages the real .gitignore ----
t_begin F-HIGH-PS-001 "PowerShell publish stages an allowlist (incl. real .gitignore), never git add -A"
assert_no_grep "git add -A" "$PS1"
assert_no_grep "git add \." "$PS1"
assert_grep "git add -- " "$PS1"
# stages a file git actually honors; the git-inert 'card.gitignore' must NOT be in the allowlist
assert_grep "'\.gitignore'\)\)" "$PS1"
assert_no_grep "'card\.gitignore'" "$PS1"
t_end

# ---- F-HIGH-PS-002: init writes a REAL .gitignore (git ignores a file named card.gitignore) ----
t_begin F-HIGH-PS-002 "PowerShell init copies the template to .gitignore so secrets are never staged"
assert_grep 'giDest = Join-Path \$targetDir "\.gitignore"' "$PS1"
assert_grep 'Copy-Item -Path \$giSrc -Destination \$giDest' "$PS1"
# the old broken behavior (writing a literal card.gitignore into the card dir) must be gone
assert_no_grep 'Destination \(Join-Path \$targetDir "card\.gitignore"\)' "$PS1"
t_end

# ---- F-MED-PS-001: every generated scalar routed through an escaping converter ----
# No pwsh on the dev box, so these are STATIC regressions that lock the fix in place; the
# authoritative behavioral enforcement is security_gate.sh:inv_ps_interp (shapes A + B).
t_begin F-MED-PS-001 "PowerShell routes every generated JSON/YAML scalar through an escaper"
assert_grep "ConvertTo-JsonScalar" "$PS1"
assert_grep "ConvertTo-YamlScalar" "$PS1"
# the converters themselves escape their elements (ConvertTo-JsonArray pipes each item to ConvertTo-Json)
assert_grep 'ConvertTo-Json -Compress' "$PS1"
# the exact review bug — an interpolation opening right after an escaped JSON quote — must be gone
assert_no_grep '`"\$' "$PS1"
# and evidence.json fields specifically go through the scalar escaper
assert_grep 'type`": \$\(ConvertTo-JsonScalar \$_\.type\)' "$PS1"
# SKILL.md Markdown body strips control chars so a name/title cannot inject a new block/line
assert_grep 'nameLine = \(\$name -replace' "$PS1"
assert_no_grep 'profile for \*\*\$name\*\*' "$PS1"
# ConvertTo-YamlScalar encodes every C0 control char (else a control in a name -> invalid YAML)
assert_grep 'code -lt 0x20' "$PS1"
t_end
