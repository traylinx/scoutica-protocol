#!/bin/sh
# tests/phase4.test.sh — Phase 4 regression tests (schema/enum/docs/housekeeping).
. "$TESTLIB/assert.sh"

_enum=$(python3 - "$REPO_ROOT/tools/scoring.py" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("scoring", sys.argv[1])
sc = importlib.util.module_from_spec(spec); spec.loader.exec_module(sc)
ok1, _ = sc.check_hard_filters({}, {"engagement": {"allowed_types": ["contract"]}},
                               {"engagement": {"type": "freelance"}})
ok2, _ = sc.check_hard_filters({}, {"engagement": {"allowed_types": ["freelance"]}},
                               {"engagement": {"type": "contract"}})
print("FL_ROLE_MATCHES_CONTRACT=" + ("1" if ok1 else "0"))
print("LEGACY_FL_CANDIDATE_MATCHES=" + ("1" if ok2 else "0"))
print("NORM=" + str(sc._norm_engagement("Freelance")))
PY
)

t_begin F-HIGH-ENUM-001 "freelance normalizes to contract in both scoring directions; no schema lists it"
assert_grep "FL_ROLE_MATCHES_CONTRACT=1" "$_enum"
assert_grep "LEGACY_FL_CANDIDATE_MATCHES=1" "$_enum"
assert_grep "NORM=contract" "$_enum"
# drift: no *.schema.json enum still contains freelance
assert_exit 1 grep -rq --include=*.schema.json "freelance" "$REPO_ROOT/schemas" "$REPO_ROOT/protocol/platform/01_schemas"
t_end

t_begin F-MED-SCHEMA-001 "schema index exists; recruiter/registry schemas carry an \$id"
assert_grep "Scoutica Schema Index" "$REPO_ROOT/schemas/SCHEMA_INDEX.md"
assert_grep '"\$id"' "$REPO_ROOT/schemas/recruiter/role.schema.json"
assert_grep '"\$id"' "$REPO_ROOT/schemas/registry/roles_index.schema.json"
t_end

t_begin F-MED-DOCS-001 "network transport described as local simulation, not live"
assert_no_grep "Git-native inbox.*Live" "$REPO_ROOT/README.md"
assert_no_grep "Identity ready" "$REPO_ROOT/README.md"
t_end

t_begin F-MED-EXAMPLES-001 "examples use mock names, not real-looking ones"
assert_exit 1 grep -rq "Alex Chen" "$REPO_ROOT/protocol"
t_end

t_begin F-MED-AGENTS-001 "AGENTS.md line count corrected; docs path fixed; CLAUDE.md symlink kept"
assert_no_grep "3,900 lines" "$REPO_ROOT/AGENTS.md"
assert_grep "docs-site/" "$REPO_ROOT/AGENTS.md"
t_end

t_begin F-LOW-DOCS-002 "README tree references protocol/templates, not a nonexistent root templates/"
assert_grep "protocol/templates/" "$REPO_ROOT/README.md"
t_end

t_begin F-MED-HOUSE-001 "build manual no longer links to the unshipped (gitignored) _archive tree"
assert_no_grep "\]\(\.\./_archive/" "$REPO_ROOT/protocol/platform/THE_BUILD_MANUAL.md"
t_end
