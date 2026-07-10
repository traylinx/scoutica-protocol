#!/bin/sh
# Phase 1 regressions for generated artifact contracts and prerequisite behavior.

. "$TESTLIB/assert.sh"
. "$TESTLIB/fixtures.sh"

fixture_isolated_env "$WORK/generator-contracts"
trap 'fixture_cleanup' EXIT INT TERM

TEST_PYTHON=""
for python_candidate in python3.13 python3.12 python3.11 python3 python; do
    if command -v "$python_candidate" >/dev/null 2>&1 \
        && "$python_candidate" -c 'import jsonschema, yaml' >/dev/null 2>&1; then
        TEST_PYTHON="$python_candidate"
        break
    fi
done
[ -n "$TEST_PYTHON" ] || { printf '%s\n' 'No strict test Python available' >&2; exit 1; }

role_create_input() {
    printf '%s\n' \
        'Senior Engineer' 'Build systems' '4' '5' 'Python' '' '' '' \
        '' '' '' 'n' '1' '' '' '4' '' '' ''
}

t_begin F-17 "candidate init serializes SKILL frontmatter structurally"
candidate="$WORK/candidate"
mkdir -p "$candidate"
if ! printf '%s\n' \
    'Alice: metadata: injected' 'Engineer *lead*' '4' '5' '1' \
    'Backend' 'Python, YAML' '' '' '' '' '' '' \
    'y' 'n' 'n' 'n' 'n' '' '1' '' '' '' 'n' \
    | "$SCOUTICA" init "$candidate" >/dev/null 2>&1; then
    t_fail "candidate init failed"
fi
assert_exists "$candidate/SKILL.md"
assert_exit 0 "$TEST_PYTHON" - "$candidate/SKILL.md" <<'PY'
import sys, yaml

content = open(sys.argv[1], encoding="utf-8").read()
frontmatter = yaml.safe_load(content.split("---", 2)[1])
assert set(frontmatter) == {"name", "description", "metadata"}
assert frontmatter["name"] == "scoutica"
assert frontmatter["metadata"]["author"] == "Alice: metadata: injected"
assert set(frontmatter["metadata"]) == {"tags", "author", "version"}
assert isinstance(frontmatter["description"], str) and "\n" not in frontmatter["description"]
PY
t_end

t_begin F-18 "candidate init refuses an empty engagement policy"
candidate_empty="$WORK/candidate-empty"
mkdir -p "$candidate_empty"
if printf '%s\n' \
    'Alice Developer' '' '4' '' '1' 'Backend' 'Python' '' '' '' '' '' '' \
    'n' 'n' 'n' 'n' 'n' \
    | "$SCOUTICA" init "$candidate_empty" >/dev/null 2>&1; then
    t_fail "candidate init accepted zero engagement types"
fi
assert_not_exists "$candidate_empty/profile.json"
t_end

t_begin F-17 "candidate init validates in staging and preserves a prior card on failure"
candidate_prior="$WORK/candidate-prior"
cp -R "$REPO_ROOT/protocol/examples/sample_card" "$candidate_prior"
cp "$candidate_prior/profile.json" "$WORK/candidate-prior-profile.before"
cp "$candidate_prior/evidence.json" "$WORK/candidate-prior-evidence.before"
if printf '%s\n' \
    'Alice Developer' 'Engineer' '4' '5' '1' \
    'Backend' 'Python' '' '' '' '' '' '' \
    'y' 'n' 'n' 'n' 'n' '' '1' '' '' '' \
    'y' '1' 'Example evidence' 'not a URI' 'Example proof' 'Python' 'n' \
    | "$SCOUTICA" init "$candidate_prior" >/dev/null 2>&1; then
    t_fail "candidate init accepted an invalid evidence URI"
fi
assert_file_eq "$WORK/candidate-prior-profile.before" "$candidate_prior/profile.json" \
    "invalid init must preserve prior profile"
assert_file_eq "$WORK/candidate-prior-evidence.before" "$candidate_prior/evidence.json" \
    "invalid init must preserve prior evidence"
t_end

t_begin F-18 "org init persists freelance as contract and validates before success"
org="$WORK/org"
mkdir -p "$org"
if ! printf '%s\n' \
    'Acme Test' 'example.com' 'Test organization' '1' '' '' '1' '1' 'AI' 'Python' \
    'n' 'n' 'n' 'n' 'y' 'n' \
    '' '' '' '' 'n' 'n' 'n' '' '' '' '' '' '' \
    | "$SCOUTICA" org init "$org" >/dev/null 2>&1; then
    t_fail "org init failed"
fi
assert_exit 0 "$TEST_PYTHON" - "$org/recruiter_profile.json" "$org/hiring_rules.yaml" <<'PY'
import json, sys, yaml

profile = json.load(open(sys.argv[1], encoding="utf-8"))
rules = yaml.safe_load(open(sys.argv[2], encoding="utf-8"))
assert profile["engagement_types"] == ["contract"]
assert rules["preferences"]["preferred_engagement"] == ["contract"]
assert "freelance" not in json.dumps(profile)
PY
t_end

t_begin F-18 "org init refuses zero engagement types before persistence"
org_empty="$WORK/org-empty"
mkdir -p "$org_empty"
if printf '%s\n' \
    'Acme Test' 'example.com' 'Test organization' '1' '' '' '1' '1' 'AI' 'Python' \
    'n' 'n' 'n' 'n' 'n' 'n' \
    | "$SCOUTICA" org init "$org_empty" >/dev/null 2>&1; then
    t_fail "org init accepted zero engagement types"
fi
assert_not_exists "$org_empty/recruiter_profile.json"
t_end

t_begin F-18 "role create persists freelance as schema-valid contract"
role_root="$WORK/role"
mkdir -p "$role_root"
if ! role_create_input | "$SCOUTICA" role create "$role_root" >/dev/null 2>&1; then
    t_fail "role create failed"
fi
role_file="$role_root/roles/senior-engineer.json"
assert_exists "$role_file"
assert_exit 0 "$TEST_PYTHON" - "$role_file" "$REPO_ROOT/schemas/recruiter/role.schema.json" <<'PY'
import json, os, stat, sys
import jsonschema

role = json.load(open(sys.argv[1], encoding="utf-8"))
schema = json.load(open(sys.argv[2], encoding="utf-8"))
assert role["engagement"]["type"] == "contract"
assert "freelance" not in json.dumps(role)
jsonschema.validate(role, schema, format_checker=jsonschema.FormatChecker())
assert stat.S_IMODE(os.stat(sys.argv[1]).st_mode) == 0o600
PY
role_regular_files=$(find "$role_root/roles" -type f -print | wc -l | tr -d '[:space:]')
role_symlinks=$(find "$role_root/roles" -type l -print | wc -l | tr -d '[:space:]')
assert_eq 1 "$role_regular_files" "normal role creation leaves only the final role file"
assert_eq 0 "$role_symlinks" "normal role creation leaves no temporary symlink"
t_end

t_begin F-02 "role create refuses a symlinked roles parent without changing victim"
role_parent_root="$WORK/role-parent-symlink"
role_parent_victim_dir="$WORK/role-parent-victim"
mkdir -p "$role_parent_root" "$role_parent_victim_dir"
role_parent_victim="$role_parent_victim_dir/senior-engineer.json"
printf '%s\n' 'role-parent-victim-must-remain-unchanged' > "$role_parent_victim"
cp "$role_parent_victim" "$WORK/role-parent-victim.before"
ln -s "$role_parent_victim_dir" "$role_parent_root/roles"
if role_create_input | "$SCOUTICA" role create "$role_parent_root" >/dev/null 2>&1; then
    t_fail "role create accepted a symlinked roles parent"
fi
assert_file_eq "$WORK/role-parent-victim.before" "$role_parent_victim" \
    "symlinked roles parent must not permit victim overwrite"
assert_exists "$role_parent_root/roles" "roles symlink remains present for inspection"
t_end

t_begin F-02 "role create refuses a multiply-slashed symlink target without changing victim"
slash_victim="$WORK/role-target-slash-victim"
slash_link="$WORK/role-target-slash-link"
mkdir -p "$slash_victim/roles"
printf '%s\n' '{"victim":true}' > "$slash_victim/roles/senior-software-engineer.json"
cp "$slash_victim/roles/senior-software-engineer.json" "$WORK/role-target-slash-victim.before"
ln -s "$slash_victim" "$slash_link"
if printf '%s\n' \
    '' '' '8' '' '' '' '' '' '' '' '' '' '' '' '' '' '' '' '' '' \
    | "$SCOUTICA" role create "$slash_link//" >"$WORK/role-target-slash.out" 2>&1; then
    t_fail "role create accepted a multiply-slashed symlink target"
fi
assert_file_eq "$WORK/role-target-slash-victim.before" \
    "$slash_victim/roles/senior-software-engineer.json" \
    "multiply-slashed symlink target must leave victim unchanged"
t_end

t_begin F-02 "role create refuses a symlinked final role without changing victim"
role_final_root="$WORK/role-final-symlink"
mkdir -p "$role_final_root/roles"
fixture_make_symlink_victim "$role_final_root/roles" "senior-engineer.json"
cp "$FIXTURE_SYMLINK_VICTIM" "$WORK/role-final-victim.before"
if role_create_input | "$SCOUTICA" role create "$role_final_root" >/dev/null 2>&1; then
    t_fail "role create accepted a symlinked final role file"
fi
assert_file_eq "$WORK/role-final-victim.before" "$FIXTURE_SYMLINK_VICTIM" \
    "symlinked final role must not permit victim overwrite"
assert_exists "$FIXTURE_SYMLINK_PATH" "final role symlink remains present for inspection"
t_end

t_begin F-17 "scan serializes frontmatter and canonicalizes engagement before writes"
scan_source="$WORK/scan-source"
scan_output="$WORK/scan-output"
mkdir -p "$scan_source" "$scan_output"
printf '%s\n' 'Alice builds reliable backend systems.' > "$scan_source/cv.txt"
provider=$(fixture_install_fake_provider gemini)
scan_response="$WORK/scan-response.json"
cat > "$scan_response" <<'JSON'
{"profile":{"schema_version":"0.1.0","name":"Alice: metadata: injected","title":"Engineer *lead*","seniority":"senior","years_experience":5,"availability":"immediately","primary_domains":["Backend"],"skills":["Python"]},"rules":{"schema_version":"0.1.0","engagement":{"allowed_types":["freelance"]},"remote":{"policy":"remote_only","hybrid_locations":[]},"filters":{"blocked_industries":[],"stack_keywords":{"preferred":["Python"]},"soft_reject":{"weak_stack_overlap_below":1}},"privacy":{"zone_1_public":[],"zone_2_paid":[],"zone_3_private":[]}},"evidence":{"schema_version":"0.1.0","items":[]},"skill_md":{"name":"Alice: metadata: injected","title":"Engineer *lead*","tags":["Python","YAML: injected"]}}
JSON
FAKE_PROVIDER_RESPONSE_FILE="$scan_response"
export FAKE_PROVIDER_RESPONSE_FILE
if ! "$SCOUTICA" scan "$scan_source" --output "$scan_output" --with gemini --force \
    >/dev/null 2>&1; then
    t_fail "scan generation failed"
fi
assert_exit 0 "$TEST_PYTHON" - "$scan_output/SKILL.md" "$scan_output/rules.yaml" <<'PY'
import sys, yaml

content = open(sys.argv[1], encoding="utf-8").read()
frontmatter = yaml.safe_load(content.split("---", 2)[1])
rules = yaml.safe_load(open(sys.argv[2], encoding="utf-8"))
assert set(frontmatter) == {"name", "description", "metadata"}
assert frontmatter["metadata"]["author"] == "Alice: metadata: injected"
assert frontmatter["metadata"]["tags"] == "Python, YAML: injected"
assert rules["engagement"]["allowed_types"] == ["contract"]
PY
t_end

t_begin F-17 "scan rejects an empty engagement policy before card writes"
bad_response="$WORK/scan-response-empty-engagement.json"
"$TEST_PYTHON" - "$scan_response" "$bad_response" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
data["rules"]["engagement"]["allowed_types"] = []
json.dump(data, open(sys.argv[2], "w", encoding="utf-8"))
PY
FAKE_PROVIDER_RESPONSE_FILE="$bad_response"
export FAKE_PROVIDER_RESPONSE_FILE
bad_output="$WORK/scan-output-empty"
mkdir -p "$bad_output"
if "$SCOUTICA" scan "$scan_source" --output "$bad_output" --with gemini --force \
    >/dev/null 2>&1; then
    t_fail "scan accepted an empty engagement policy"
fi
assert_not_exists "$bad_output/profile.json"
assert_not_exists "$bad_output/SKILL.md"
t_end

t_begin F-17 "scan validates in staging and preserves a prior card on failure"
prior_scan="$WORK/scan-prior"
cp -R "$REPO_ROOT/protocol/examples/sample_card" "$prior_scan"
cp "$prior_scan/profile.json" "$WORK/scan-prior-profile.before"
invalid_profile_response="$WORK/scan-response-invalid-profile.json"
"$TEST_PYTHON" - "$scan_response" "$invalid_profile_response" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
del data["profile"]["title"]
json.dump(data, open(sys.argv[2], "w", encoding="utf-8"))
PY
FAKE_PROVIDER_RESPONSE_FILE="$invalid_profile_response"
export FAKE_PROVIDER_RESPONSE_FILE
if "$SCOUTICA" scan "$scan_source" --output "$prior_scan" --with gemini --force \
    >/dev/null 2>&1; then
    t_fail "scan accepted a profile missing required title"
fi
assert_file_eq "$WORK/scan-prior-profile.before" "$prior_scan/profile.json" \
    "invalid scan must preserve prior profile"
t_end

t_begin F-04 "validate accepts only an explicit existing absolute schema override"
override_card="$WORK/override-card"
override_schemas="$WORK/override-schemas"
cp -R "$REPO_ROOT/protocol/examples/sample_card" "$override_card"
mkdir -p "$override_schemas"
cp "$REPO_ROOT/protocol/platform/01_schemas/"*.json "$override_schemas/"
if ! "$SCOUTICA" validate "$override_card" --schema-dir "$override_schemas" >/dev/null 2>&1; then
    t_fail "validate rejected an explicit absolute schema directory"
fi
if "$SCOUTICA" validate "$override_card" --schema-dir relative/schemas >/dev/null 2>&1; then
    t_fail "validate accepted a relative schema directory"
fi
if "$SCOUTICA" validate "$override_card" --schema-dir "$WORK/missing-schemas" >/dev/null 2>&1; then
    t_fail "validate accepted a missing schema directory"
fi
t_end

t_begin F-17 "validate fails with exact prerequisites and never invokes pip"
fake_python_bin="$WORK/fake-python-bin"
mkdir -p "$fake_python_bin" "$WORK/validate-card"
python_log="$WORK/python-argv.log"
cat > "$fake_python_bin/python-stub" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$FAKE_PYTHON_LOG"
case "$*" in
    *sys.version_info*jsonschema*) exit 1 ;;
    *sys.version_info*) exit 0 ;;
    --version) printf '%s\n' 'Python 3.11.0'; exit 0 ;;
esac
exit 1
SH
chmod +x "$fake_python_bin/python-stub"
for python_name in python3.13 python3.12 python3.11 python3 python; do
    ln -s python-stub "$fake_python_bin/$python_name"
done
printf '%s\n' '{}' > "$WORK/validate-card/profile.json"
printf '%s\n' '---' 'name: scoutica' 'description: test' '---' > "$WORK/validate-card/SKILL.md"
FAKE_PYTHON_LOG="$python_log"
export FAKE_PYTHON_LOG
validate_output="$WORK/validate-prerequisite.out"
if PATH="$fake_python_bin:/usr/bin:/bin" /bin/bash "$SCOUTICA" validate "$WORK/validate-card" \
    >"$validate_output" 2>&1; then
    t_fail "validate succeeded without strict dependencies"
fi
assert_grep "python3 -m pip install 'jsonschema\[format\]' PyYAML" "$validate_output"
assert_no_grep ' -m pip install ' "$python_log"
t_end

t_begin F-17 "doctor rejects weak format support with exact prerequisite guidance"
doctor_output="$WORK/doctor-prerequisite.out"
if PATH="$fake_python_bin:/usr/bin:/bin" /bin/bash "$SCOUTICA" doctor \
    >"$doctor_output" 2>&1; then
    t_fail "doctor succeeded without strict format dependencies"
fi
assert_grep 'Missing required Python dependencies: jsonschema\[format\] and PyYAML' "$doctor_output"
assert_grep "python3 -m pip install 'jsonschema\[format\]' PyYAML" "$doctor_output"
t_end

fixture_cleanup
