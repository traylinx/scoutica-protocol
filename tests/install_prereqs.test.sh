#!/bin/sh
# Installer prerequisite contract: fail before mutation, never run pip, and
# finish from a clean mocked download when declared dependencies are present.

. "$TESTLIB/assert.sh"

INSTALLER="$REPO_ROOT/install.sh"
PS_INSTALLER="$REPO_ROOT/install.ps1"
CASE_ROOT="$WORK/install-prereqs"
BIN="$CASE_ROOT/bin"
mkdir -p "$BIN"

cat > "$BIN/curl" <<'SH'
#!/bin/sh
out=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        -o) shift; out=$1 ;;
    esac
    shift
done
[ -n "$out" ] || exit 2
mkdir -p "$(dirname "$out")"
: > "$out"
SH
chmod +x "$BIN/curl"

write_fake_python() {
    _mode=$1
    rm -f "$BIN/python3.13" "$BIN/python3.12" "$BIN/python3.11" "$BIN/python3" "$BIN/python"
    cat > "$BIN/python-stub" <<SH
#!/bin/sh
case "$_mode" in
  old) exit 1 ;;
  missing)
    case "\${2:-}" in *jsonschema*) exit 1 ;; *) exit 0 ;; esac
    ;;
  present) exit 0 ;;
esac
exit 1
SH
    chmod +x "$BIN/python-stub"
    for _python_name in python3.13 python3.12 python3.11 python3 python; do
        ln -s python-stub "$BIN/$_python_name"
    done
}

t_begin - "POSIX installer rejects unsupported Python before filesystem mutation"
write_fake_python old
_home="$CASE_ROOT/old-home"
_install="$CASE_ROOT/old-install"
mkdir -p "$_home"
HOME="$_home" SCOUTICA_HOME="$_install" PATH="$BIN:$PATH" \
    bash "$INSTALLER" >"$CASE_ROOT/old.out" 2>"$CASE_ROOT/old.err"
_rc=$?
assert_eq 1 "$_rc" "old Python must fail"
assert_not_exists "$_install" "preflight failure must not create install root"
assert_grep 'Python 3\.11 or newer' "$CASE_ROOT/old.err"
assert_grep "python3 -m pip install 'jsonschema\[format\]' PyYAML" "$CASE_ROOT/old.err"
t_end

t_begin - "POSIX installer finds a supported versioned Python after an old python3"
rm -f "$BIN/python3.13" "$BIN/python3.12" "$BIN/python3.11" "$BIN/python3" "$BIN/python"
cat > "$BIN/python3" <<'SH'
#!/bin/sh
exit 1
SH
cat > "$BIN/python3.11" <<'SH'
#!/bin/sh
exit 0
SH
chmod +x "$BIN/python3" "$BIN/python3.11"
_home="$CASE_ROOT/versioned-home"
_install="$CASE_ROOT/versioned-install"
mkdir -p "$_home"
HOME="$_home" SCOUTICA_HOME="$_install" PATH="$BIN:$PATH" \
    bash "$INSTALLER" >"$CASE_ROOT/versioned.out" 2>"$CASE_ROOT/versioned.err"
_rc=$?
assert_eq 0 "$_rc" "supported versioned Python should be selected"
assert_exists "$_install/bin/scoutica"
t_end

t_begin - "POSIX installer rejects missing strict dependencies without invoking pip"
write_fake_python missing
_home="$CASE_ROOT/missing-home"
_install="$CASE_ROOT/missing-install"
mkdir -p "$_home"
HOME="$_home" SCOUTICA_HOME="$_install" PATH="$BIN:$PATH" \
    bash "$INSTALLER" >"$CASE_ROOT/missing.out" 2>"$CASE_ROOT/missing.err"
_rc=$?
assert_eq 1 "$_rc" "missing dependencies must fail"
assert_not_exists "$_install" "dependency failure must not create install root"
assert_grep 'requires jsonschema format support and PyYAML' "$CASE_ROOT/missing.err"
assert_no_grep 'pip install.*--quiet' "$CASE_ROOT/missing.out"
t_end

t_begin - "POSIX installer succeeds with prerequisites and mocked downloads"
write_fake_python present
_home="$CASE_ROOT/present-home"
_install="$CASE_ROOT/present-install"
mkdir -p "$_home"
HOME="$_home" SCOUTICA_HOME="$_install" PATH="$BIN:$PATH" \
    bash "$INSTALLER" >"$CASE_ROOT/present.out" 2>"$CASE_ROOT/present.err"
_rc=$?
assert_eq 0 "$_rc" "declared prerequisites should pass preflight"
assert_exists "$_install/bin/scoutica"
assert_exists "$_install/bin/validate_card.py"
assert_exists "$_install/bin/scoring.py"
assert_exists "$_install/bin/import_aijs.py"
t_end

t_begin - "PowerShell installer declares the same fail-fast prerequisite contract"
assert_grep 'Python 3\.11 or newer' "$PS_INSTALLER"
assert_grep "python3 -m pip install 'jsonschema\[format\]' PyYAML" "$PS_INSTALLER"
assert_no_grep 'pip install.+--quiet' "$PS_INSTALLER"
t_end
