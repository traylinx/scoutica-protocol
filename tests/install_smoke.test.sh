#!/bin/sh
# tests/install_smoke.test.sh — installer ↔ CLI parity guard.
#
# main IS production: users install by piping install.sh, which curls individual files from raw
# main. `scoutica` shells out to sibling Python helpers, resolving each as "$script_dir/<name>.py"
# (== the installer's $BIN_DIR when installed). If install.sh fails to fetch one of those helpers,
# the command that needs it 404s at runtime for every fresh install — invisibly, because the dev
# checkout always has tools/ populated. This test fails CI the moment the two drift apart.
#
# It discovers the helper set from the CLI itself (not a hardcoded list) so a helper added tomorrow
# is covered automatically; it then asserts install.sh fetches each one into $BIN_DIR.
. "$TESTLIB/assert.sh"

CLI="$REPO_ROOT/tools/scoutica"
INSTALLER="$REPO_ROOT/install.sh"

# ── T-INSTALL-SMOKE-001 — every python helper the CLI resolves is shipped by install.sh ──
t_begin T-INSTALL-SMOKE-001 "install.sh ships every python helper the CLI resolves next to itself"

# helpers the CLI loads relative to itself: matches occurrences of  $script_dir/<name>.py
helpers=$(grep -oE '\$script_dir/[A-Za-z0-9_]+\.py' "$CLI" | sed 's#.*/##' | sort -u)

# guard against a vacuous pass: discovery must find helpers, including the two this work relies on
assert_ne "" "$helpers" "CLI helper discovery returned nothing (grep/pattern regressed?)"
assert_grep '^scoring\.py$'     "$helpers" "scoring.py must be a resolved CLI helper"
assert_grep '^import_aijs\.py$' "$helpers" "import_aijs.py must be a resolved CLI helper"

# every discovered helper must be fetched by the installer INTO the same dir the CLI looks in
for h in $helpers; do
    assert_grep "tools/$h\""   "$INSTALLER" "install.sh must download tools/$h"
    assert_grep "BIN_DIR/$h\"" "$INSTALLER" "install.sh must place $h in \$BIN_DIR"
done
t_end
