#!/bin/sh
# tests/cli_phase2.test.sh — Phase 2 regression tests for CLI-side fixes
# (confirm() capture, resolve-summary schema paths, template syntax).
. "$TESTLIB/assert.sh"

TEMPLATE="$REPO_ROOT/reference/agent-templates/registry_client.py.template"

t_begin F-MED-TEMPLATE-001 "registry_client template is importable Python (ast.parse clean)"
assert_exit 0 python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$TEMPLATE"
t_end

t_begin F-MED-CONFIRM-001 "confirm() prompt is written to stderr so \$(confirm) captures only y/N"
# Static guard: the prompt echo in confirm() must redirect to stderr (>&2). Without it the
# prompt text leaks into command-substitution capture and corrupts the boolean.
_confirm_echo=$(awk '/^confirm\(\)/{f=1} f&&/echo -ne/{print; exit}' "$SCOUTICA")
assert_grep '>&2' "$_confirm_echo"
t_end

t_begin F-MED-SUMMARY-001 "rules summary reads engagement.compensation + filters.blocked_industries"
assert_grep "get\('engagement', \{\}\)\.get\('compensation'" "$SCOUTICA"
assert_grep "get\('filters', \{\}\)\.get\('blocked_industries'" "$SCOUTICA"
assert_no_grep "get\('auto_reject', ?\{\}\)\.get\('blocked_industries'" "$SCOUTICA"
t_end

t_begin F-MED-SUMMARY-002 "resolve skills summary reads array fields, not a skills dict"
assert_grep "_line\('Skills', 'skills'\)" "$SCOUTICA"
assert_no_grep "s\.get\('languages'\)" "$SCOUTICA"
t_end
