#!/bin/sh
# Trusted schema resolution, strict JSON Schema formats, and SKILL frontmatter.

. "$TESTLIB/assert.sh"

VALIDATOR="$REPO_ROOT/tools/validate_card.py"
SAMPLE_CARD="$REPO_ROOT/protocol/examples/sample_card"
SCHEMA_FIXTURES="$FIXTURES/schema_trust"
HOSTILE_SCHEMAS="$FIXTURES/hostile_cwd/schemas"

run_validator() {
    _sv_output=$1
    shift
    python3 "$VALIDATOR" "$@" >"$_sv_output" 2>&1
    _sv_rc=$?
}

copy_sample_card() {
    _sv_target=$1
    rm -rf "$_sv_target"
    cp -R "$SAMPLE_CARD" "$_sv_target"
}

t_begin F-04 "validator uses trusted script-relative schemas, never cwd or SCOUTICA_HOME"
copy_sample_card "$WORK/schema-hostile-card"
python3 - "$WORK/schema-hostile-card/profile.json" <<'PY'
import json, sys
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump({}, handle)
PY
(
    cd "$FIXTURES/hostile_cwd" || exit 1
    SCOUTICA_HOME="$FIXTURES/hostile_cwd" python3 "$VALIDATOR" "$WORK/schema-hostile-card"
) >"$WORK/schema-hostile.out" 2>&1
_sv_rc=$?
assert_eq 1 "$_sv_rc" "hostile cwd and SCOUTICA_HOME cannot shadow schemas"
assert_grep '\[VALIDATION_ERROR\].*path=\$.*rule=required' "$WORK/schema-hostile.out"
assert_no_grep "$HOSTILE_SCHEMAS" "$WORK/schema-hostile.out"
t_end

t_begin F-04 "explicit schema override is absolute, authoritative, and surfaced"
run_validator "$WORK/schema-relative.out" "$WORK/schema-hostile-card" --schema-dir schemas
assert_eq 1 "$_sv_rc" "relative schema override rejected"
assert_grep '\[SCHEMA_DIR_NOT_ABSOLUTE\]' "$WORK/schema-relative.out"
run_validator "$WORK/schema-missing.out" "$WORK/schema-hostile-card" --schema-dir "$WORK/no-such-schema-dir"
assert_eq 1 "$_sv_rc" "missing schema override rejected"
assert_grep '\[SCHEMA_DIR_NOT_FOUND\]' "$WORK/schema-missing.out"
run_validator "$WORK/schema-explicit.out" "$WORK/schema-hostile-card" --schema-dir "$HOSTILE_SCHEMAS"
assert_eq 0 "$_sv_rc" "explicit permissive fixture is intentionally authoritative"
assert_grep "Schema override: $HOSTILE_SCHEMAS" "$WORK/schema-explicit.out"
t_end

t_begin F-04 "checkout CLI cannot be downgraded by a stale installed validator"
copy_sample_card "$WORK/stale-validator-card"
python3 - "$WORK/stale-validator-card/evidence.json" <<'PY'
import json, sys
path = sys.argv[1]
document = json.load(open(path, encoding="utf-8"))
document["items"][0]["url"] = "not a URI"
with open(path, "w", encoding="utf-8") as handle:
    json.dump(document, handle)
PY
mkdir -p "$WORK/stale-home/bin"
cat > "$WORK/stale-home/bin/validate_card.py" <<'PY'
raise SystemExit(0)
PY
SCOUTICA_HOME="$WORK/stale-home" "$SCOUTICA" validate "$WORK/stale-validator-card" \
    >"$WORK/stale-validator.out" 2>&1
_sv_rc=$?
assert_eq 1 "$_sv_rc" "active checkout validator must win over stale installed helper"
assert_grep '\[VALIDATION_ERROR\].*rule=format' "$WORK/stale-validator.out"
t_end

t_begin F-17 "declared schema draft is checked before instance validation"
rm -rf "$WORK/schema-invalid"
cp -R "$REPO_ROOT/protocol/platform/01_schemas" "$WORK/schema-invalid"
python3 - "$WORK/schema-invalid/candidate_profile.schema.json" <<'PY'
import json, sys
path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    schema = json.load(handle)
schema["type"] = "not-a-json-schema-type"
with open(path, "w", encoding="utf-8") as handle:
    json.dump(schema, handle)
PY
copy_sample_card "$WORK/schema-valid-card"
run_validator "$WORK/schema-invalid.out" "$WORK/schema-valid-card" --schema-dir "$WORK/schema-invalid"
assert_eq 1 "$_sv_rc" "invalid schema rejected"
assert_grep '\[SCHEMA_INVALID\].*path=.*type' "$WORK/schema-invalid.out"
t_end

t_begin F-17 "FormatChecker rejects invalid candidate evidence URI"
copy_sample_card "$WORK/schema-format-card"
python3 - "$WORK/schema-format-card/evidence.json" <<'PY'
import json, sys
path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    document = json.load(handle)
document["items"][0]["url"] = "not a URI"
with open(path, "w", encoding="utf-8") as handle:
    json.dump(document, handle)
PY
run_validator "$WORK/schema-format.out" "$WORK/schema-format-card"
assert_eq 1 "$_sv_rc" "invalid evidence URI rejected"
assert_grep '\[VALIDATION_ERROR\].*path=\$.items\[0\].url.*rule=format' "$WORK/schema-format.out"
t_end

make_employer_card() {
    _sv_employer_dir=$1
    _sv_case=${2:-valid}
    rm -rf "$_sv_employer_dir"
    python3 - "$_sv_employer_dir" "$_sv_case" <<'PY'
import json, os, sys, yaml

root, case = sys.argv[1:]
os.makedirs(os.path.join(root, "roles"), exist_ok=True)
profile = {
    "scoutica_version": "0.4.0",
    "entity_type": "in-house",
    "organization": {
        "name": "Example Organization",
        "domain": "example.test",
        "verified_at": "2026-07-10T12:00:00Z",
    },
    "engagement_types": ["contract"],
    "contact": {
        "agent_endpoint": "https://example.test/agent",
        "human_fallback": "alice@example.test",
    },
}
role = {
    "scoutica_version": "0.4.0",
    "job_id": "req_abcdef",
    "title": "Backend Engineer",
    "status": "active",
    "requirements": {"hard_skills": ["Python"]},
    "location": {"type": "remote"},
    "engagement": {"type": "contract", "start_date": "2026-08-01"},
}
if case == "hostname":
    profile["organization"]["domain"] = "not a hostname"
elif case == "date-time":
    profile["organization"]["verified_at"] = "2026-99-99"
elif case == "email":
    profile["contact"]["human_fallback"] = "not-an-email"
elif case == "uri":
    profile["contact"]["agent_endpoint"] = "not a URI"
elif case == "date":
    role["engagement"]["start_date"] = "2026-02-30"
with open(os.path.join(root, "recruiter_profile.json"), "w", encoding="utf-8") as handle:
    json.dump(profile, handle)
with open(os.path.join(root, "hiring_rules.yaml"), "w", encoding="utf-8") as handle:
    yaml.safe_dump({"commitments": {}}, handle)
with open(os.path.join(root, "roles", "role.json"), "w", encoding="utf-8") as handle:
    json.dump(role, handle)
PY
}

t_begin F-17 "FormatChecker enforces hostname, date-time, email, URI, and date"
for _sv_case in hostname date-time email uri date; do
    make_employer_card "$WORK/employer-$_sv_case" "$_sv_case"
    run_validator "$WORK/employer-$_sv_case.out" "$WORK/employer-$_sv_case" --type employer
    assert_eq 1 "$_sv_rc" "invalid $_sv_case rejected"
    assert_grep 'rule=format' "$WORK/employer-$_sv_case.out" "$_sv_case reports format failure"
done
t_end

t_begin F-17 "valid candidate and employer examples pass strict validation"
copy_sample_card "$WORK/schema-valid-candidate"
run_validator "$WORK/schema-valid-candidate.out" "$WORK/schema-valid-candidate"
assert_eq 0 "$_sv_rc" "sample candidate remains valid"
make_employer_card "$WORK/schema-valid-employer" valid
run_validator "$WORK/schema-valid-employer.out" "$WORK/schema-valid-employer" --type employer
assert_eq 0 "$_sv_rc" "valid employer remains valid"
t_end

t_begin F-17 "candidate SKILL frontmatter accepts exact full and minimal contracts"
copy_sample_card "$WORK/frontmatter-valid"
run_validator "$WORK/frontmatter-valid.out" "$WORK/frontmatter-valid"
assert_eq 0 "$_sv_rc" "full sample frontmatter valid"
cp "$SCHEMA_FIXTURES/skill_valid_minimal.md" "$WORK/frontmatter-valid/SKILL.md"
run_validator "$WORK/frontmatter-minimal.out" "$WORK/frontmatter-valid"
assert_eq 0 "$_sv_rc" "metadata is optional"
cp "$SCHEMA_FIXTURES/skill_extra_fence.md" "$WORK/frontmatter-valid/SKILL.md"
run_validator "$WORK/frontmatter-body-fence.out" "$WORK/frontmatter-valid"
assert_eq 0 "$_sv_rc" "Markdown thematic break after frontmatter is valid body content"
t_end

t_begin F-17 "candidate SKILL frontmatter rejects duplicate keys, aliases, documents, keys, and types"
for _sv_spec in \
    skill_duplicate_root.md:FRONTMATTER_DUPLICATE_KEY \
    skill_duplicate_nested.md:FRONTMATTER_DUPLICATE_KEY \
    skill_alias.md:FRONTMATTER_ALIAS \
    skill_multiple_documents.md:FRONTMATTER_YAML \
    skill_unknown_root.md:FRONTMATTER_ROOT_KEYS \
    skill_bad_metadata.md:FRONTMATTER_METADATA_KEYS \
    skill_multiline_description.md:FRONTMATTER_DESCRIPTION \
    skill_root_list.md:FRONTMATTER_ROOT_TYPE \
    skill_bad_name.md:FRONTMATTER_NAME \
    skill_bad_tags.md:FRONTMATTER_TAGS \
    skill_missing_author.md:FRONTMATTER_METADATA_KEYS \
    skill_bad_contact.md:FRONTMATTER_CONTACT \
    skill_bad_version.md:FRONTMATTER_VERSION
do
    _sv_file=${_sv_spec%%:*}
    _sv_code=${_sv_spec#*:}
    cp "$SCHEMA_FIXTURES/$_sv_file" "$WORK/frontmatter-valid/SKILL.md"
    run_validator "$WORK/$_sv_file.out" "$WORK/frontmatter-valid"
    assert_eq 1 "$_sv_rc" "$_sv_file rejected"
    assert_grep "\\[$_sv_code\\]" "$WORK/$_sv_file.out" "$_sv_file has stable reason code"
done
t_end

[ "$_A_FAILED" -eq 0 ]
