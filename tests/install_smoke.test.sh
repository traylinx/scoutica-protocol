#!/bin/sh
# tests/install_smoke.test.sh — capability contract ↔ installer ↔ CLI parity.
#
# The shared capability/resource contract is the source of expected install
# contents for both POSIX (this test) and Windows (tests/windows.ps1). A fake
# curl records the production install.sh request/destination pairs so loops and
# future helpers cannot hide drift behind source-text grep heuristics.

. "$TESTLIB/assert.sh"

CLI="$REPO_ROOT/tools/scoutica"
INSTALLER="$REPO_ROOT/install.sh"
CONTRACT="$REPO_ROOT/protocol/platform/cli_support_contract.json"
PYTHON=${SCOUTICA_TEST_PYTHON:-python3}
CASE_ROOT="$WORK/install-smoke"
BIN="$CASE_ROOT/bin"
HOME_DIR="$CASE_ROOT/home"
INSTALL_DIR="$CASE_ROOT/installed"
RECORD="$CASE_ROOT/requests.tsv"
EXPECTED="$CASE_ROOT/expected.tsv"
ACTUAL="$CASE_ROOT/actual.tsv"
mkdir -p "$BIN" "$HOME_DIR"
: > "$RECORD"

cat > "$BIN/curl" <<'SH'
#!/bin/sh
url=""
out=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        -o) shift; out=${1:-} ;;
        https://*) url=$1 ;;
    esac
    shift
done
[ -n "$url" ] && [ -n "$out" ] || exit 2
case "$url" in
    https://raw.githubusercontent.com/traylinx/scoutica-protocol/main/*)
        source=${url#https://raw.githubusercontent.com/traylinx/scoutica-protocol/main/}
        ;;
    *) exit 3 ;;
esac
case "$out" in
    "$SCOUTICA_HOME"/*) destination=${out#"$SCOUTICA_HOME"/} ;;
    *) exit 4 ;;
esac
printf '%s\t%s\n' "$source" "$destination" >> "$INSTALL_RECORD"
mkdir -p "$(dirname "$out")"
: > "$out"
SH
chmod +x "$BIN/curl"

cat > "$BIN/python-stub" <<'SH'
#!/bin/sh
exit 0
SH
chmod +x "$BIN/python-stub"
for python_name in python3.13 python3.12 python3.11 python3 python; do
    ln -s python-stub "$BIN/$python_name"
done

"$PYTHON" - "$CONTRACT" > "$EXPECTED" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    contract = json.load(handle)

pairs = {
    (resource["source"], resource["destination"])
    for resource in contract["installation"]["resources"]
    if "posix" in resource["platforms"]
}
for source, destination in sorted(pairs):
    print(f"{source}\t{destination}")
PY

# ── T-INSTALL-SMOKE-001 — production install requests exactly the POSIX manifest ──
t_begin T-INSTALL-SMOKE-001 "install.sh request/destination pairs match the shared POSIX resource manifest"
HOME="$HOME_DIR" SCOUTICA_HOME="$INSTALL_DIR" INSTALL_RECORD="$RECORD" PATH="$BIN:$PATH" \
    bash "$INSTALLER" >"$CASE_ROOT/install.out" 2>"$CASE_ROOT/install.err"
install_rc=$?
assert_eq 0 "$install_rc" "mocked POSIX install must succeed"
LC_ALL=C sort "$RECORD" > "$ACTUAL"
assert_file_eq "$EXPECTED" "$ACTUAL" "install.sh downloads must exactly match contract POSIX resources"
t_end

# ── T-INSTALL-SMOKE-002 — CLI helper and fallback lookups are contract resources ──
t_begin T-INSTALL-SMOKE-002 "CLI runtime lookups are declared in the shared POSIX resource manifest"
helpers=$(grep -oE '\$script_dir/[A-Za-z0-9_]+\.py' "$CLI" | sed 's#.*/##' | sort -u)
assert_ne "" "$helpers" "CLI helper discovery returned nothing"
assert_grep '^scoring\.py$' "$helpers" "scoring.py must be a resolved CLI helper"
assert_grep '^import_aijs\.py$' "$helpers" "import_aijs.py must be a resolved CLI helper"
for helper in $helpers; do
    pair=$(printf 'tools/%s\tbin/%s' "$helper" "$helper")
    if ! grep -Fqx "$pair" "$EXPECTED"; then
        t_fail "POSIX resource manifest missing CLI helper pair: $pair"
    fi
done
for pair in \
    "protocol/examples/sample_card/profile.json$(printf '\t')protocol/examples/sample_card/profile.json" \
    "protocol/examples/employer_card/roles/senior-ai-architect.json$(printf '\t')protocol/examples/employer_card/roles/senior-ai-architect.json"
do
    if ! grep -Fqx "$pair" "$EXPECTED"; then
        t_fail "POSIX resource manifest missing fallback pair: $pair"
    fi
done
t_end
