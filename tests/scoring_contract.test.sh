#!/bin/sh
# Phase 5 authoritative scoring contract: dependency, currency, unit, and context handling.

. "$TESTLIB/assert.sh"

out=$(python3 - "$REPO_ROOT/tools/scoring.py" "$WORK" <<'PY'
import builtins
import importlib.util
import json
import pathlib
import sys

spec = importlib.util.spec_from_file_location("scoring_contract", sys.argv[1])
sc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sc)
work = pathlib.Path(sys.argv[2])


def flag(name, value):
    print(f"{name}={1 if value else 0}")


yaml_path = work / "nested-rules.yaml"
yaml_path.write_text(
    "engagement:\n  allowed_types:\n    - permanent\n  compensation:\n"
    "    minimum_base_eur:\n      permanent: 100000\n",
    encoding="utf-8",
)
json_path = work / "rules.json"
json_path.write_text(json.dumps({"engagement": {"allowed_types": ["permanent"]}}), encoding="utf-8")

original_import = builtins.__import__


def without_yaml(name, *args, **kwargs):
    if name == "yaml":
        raise ImportError("fixture blocks PyYAML")
    return original_import(name, *args, **kwargs)


builtins.__import__ = without_yaml
try:
    flag("YAML_FAILS_CLOSED", False)
    try:
        sc.load_yaml(str(yaml_path))
    except RuntimeError as exc:
        flag("YAML_FAILS_CLOSED", "PyYAML is required" in str(exc))
    flag("JSON_WITHOUT_YAML", sc.load_yaml(str(json_path))["engagement"]["allowed_types"] == ["permanent"])
finally:
    builtins.__import__ = original_import

for name, payload in [
    ("BLANK_RULES_FAIL", "\n"),
    ("EMPTY_RULES_FAIL", "{}\n"),
    ("UNKNOWN_POLICY_FAIL", '{"remote":{"policy":"moon_only"}}\n'),
]:
    path = work / (name.lower() + ".yaml")
    path.write_text(payload, encoding="utf-8")
    try:
        sc.load_yaml(str(path))
        flag(name, False)
    except RuntimeError:
        flag(name, True)


def rules_for(kind, floor):
    return {"engagement": {"allowed_types": [kind], "compensation": {"minimum_base_eur": {kind: floor}}}}


def role_for(kind, value=None, currency="EUR"):
    compensation = {}
    if value is not None:
        compensation["base_max"] = value
    if currency is not None:
        compensation["currency"] = currency
    return {"engagement": {"type": kind}, "compensation": compensation, "requirements": {}}


matrix = [
    ("EUR_BELOW", "reject", rules_for("permanent", 100000), role_for("permanent", 99999)),
    ("EUR_EQUAL", "pass", rules_for("permanent", 100000), role_for("permanent", 100000)),
    ("EUR_ABOVE", "pass", rules_for("permanent", 100000), role_for("permanent", 120000)),
    ("USD_CONTEXT", "needs_context", rules_for("permanent", 100000), role_for("permanent", 120000, "USD")),
    ("JPY_CONTEXT", "needs_context", rules_for("permanent", 100000), role_for("permanent", 12000000, "JPY")),
    ("MISSING_CURRENCY", "needs_context", rules_for("permanent", 100000), role_for("permanent", 120000, None)),
    ("MISSING_VALUE", "needs_context", rules_for("permanent", 100000), role_for("permanent", None)),
    ("NEGOTIABLE", "pass", rules_for("permanent", "negotiable"), role_for("permanent", None, None)),
    ("CONTRACT_BELOW", "reject", rules_for("contract", 600), role_for("contract", 599)),
    ("CONTRACT_EQUAL", "pass", rules_for("contract", 600), role_for("contract", 600)),
    ("ADVISORY_BELOW", "reject", rules_for("advisory", 150), role_for("advisory", 149)),
    ("ADVISORY_EQUAL", "pass", rules_for("advisory", 150), role_for("advisory", 150)),
]
for name, expected, rules, role in matrix:
    decision, _ = sc.check_compensation_policy(rules, role)
    flag(name, decision == expected)
    employer_decision, _ = sc.check_hard_filters_detailed({}, rules, role)
    candidate_decision, _ = sc.evaluate_candidate_policy(rules, role)
    flag(name + "_PARITY", employer_decision == candidate_decision == expected)

scalar_rules = {"engagement": {"allowed_types": ["contract"], "compensation": {"minimum_base_eur": 60000}}}
flag("SCALAR_FLOOR_CONTEXT", sc.check_compensation_policy(scalar_rules, role_for("contract", 800))[0] == "needs_context")
flag("UNKNOWN_ENGAGEMENT_CONTEXT", sc.check_compensation_policy(rules_for("contract", 600), role_for("gig", 800))[0] == "needs_context")
missing_engagement = {"requirements": {}, "compensation": {"currency": "EUR", "base_max": 100000}}
flag("EMPLOYER_ENGAGEMENT_CONTEXT", sc.check_hard_filters_detailed({}, rules_for("permanent", "negotiable"), missing_engagement)[0] == "needs_context")
remote_rules = {"remote": {"policy": "remote_only"}}
flag("EMPLOYER_LOCATION_CONTEXT", sc.check_hard_filters_detailed({}, remote_rules, {"requirements": {}})[0] == "needs_context")
for name, expected, location_type in [
    ("REMOTE_LOCATION_UNKNOWN", "needs_context", "moon"),
    ("REMOTE_LOCATION_HYBRID", "reject", "hybrid"),
    ("REMOTE_LOCATION_ONSITE", "reject", "onsite"),
    ("REMOTE_LOCATION_REMOTE", "pass", "remote"),
]:
    location_role = {"location": {"type": location_type}, "requirements": {}}
    flag(
        name,
        sc.check_hard_filters_detailed({}, remote_rules, location_role)[0] == expected
        and sc.evaluate_candidate_policy(remote_rules, location_role)[0] == expected,
    )
hybrid_cases = [
    ("HYBRID_ALLOWED", "pass", ["Berlin"], {"type": "hybrid", "office_location": "Berlin"}),
    ("HYBRID_CASEFOLD_ALLOWED", "pass", ["Berlin"], {"type": "hybrid", "office_location": "berlin"}),
    ("HYBRID_BLOCKED", "reject", ["Berlin"], {"type": "hybrid", "office_location": "Paris"}),
    ("HYBRID_OFFICE_MISSING", "needs_context", ["Berlin"], {"type": "hybrid"}),
    ("HYBRID_ALLOWLIST_EMPTY", "needs_context", [], {"type": "hybrid", "office_location": "Berlin"}),
    ("HYBRID_ONSITE_REJECT", "reject", ["Berlin"], {"type": "onsite", "office_location": "Berlin"}),
    ("HYBRID_REMOTE_ALLOWED", "pass", ["Berlin"], {"type": "remote"}),
]
for name, expected, allowed_locations, location in hybrid_cases:
    hybrid_rules = {"remote": {"policy": "hybrid", "hybrid_locations": allowed_locations}}
    hybrid_role = {"location": location, "requirements": {}}
    flag(
        name,
        sc.check_hard_filters_detailed({}, hybrid_rules, hybrid_role)[0] == expected
        and sc.evaluate_candidate_policy(hybrid_rules, hybrid_role)[0] == expected,
    )
flag("MALFORMED_POLICY_CONTEXT", sc.check_hard_filters_detailed({}, {"engagement": "broken"}, {"requirements": {}})[0] == "needs_context")
for name, bad_rules in [
    ("ABSENT_RULES_CONTEXT", None),
    ("EMPTY_RULES_CONTEXT", {}),
    ("UNKNOWN_REMOTE_CONTEXT", {"remote": {"policy": "moon_only"}}),
    ("EMPTY_ENGAGEMENT_CONTEXT", {"engagement": {"allowed_types": []}}),
]:
    employer_decision, employer_reasons = sc.check_hard_filters_detailed({}, bad_rules, {"requirements": {}})
    candidate_decision, candidate_reasons = sc.evaluate_candidate_policy(bad_rules, {"requirements": {}})
    flag(
        name,
        employer_decision == candidate_decision == "needs_context"
        and "all_rules_passed" not in employer_reasons + candidate_reasons,
    )

nested_bad_rules = [
    ("ENGAGEMENT_FIELD_TYPO", {"engagement": {"allowed_type": ["permanent"]}}),
    ("COMPENSATION_FIELD_TYPO", {"engagement": {"allowed_types": ["permanent"], "compensation": {"minimum_base_euro": {"permanent": 100000}}}}),
    ("REMOTE_FIELD_TYPO", {"remote": {"policies": "remote_only"}}),
    ("FILTER_FIELD_TYPO", {"filters": {"blocked_industry": ["gambling"]}}),
    ("STACK_FIELD_TYPO", {"filters": {"stack_keywords": {"prefered": ["Python"]}}}),
    ("SOFT_FIELD_TYPO", {"filters": {"soft_reject": {"weak_stack_overlap_under": 2}}}),
    ("PRIVACY_FIELD_TYPO", {"privacy": {"zone_1_public": [], "zone_2_paid": [], "zone_3_privte": []}}),
]
for name, bad_rules in nested_bad_rules:
    policy_path = work / (name.lower() + ".json")
    policy_path.write_text(json.dumps(bad_rules), encoding="utf-8")
    try:
        sc.load_yaml(str(policy_path))
        loader_closed = False
    except RuntimeError:
        loader_closed = True
    employer_decision, _ = sc.check_hard_filters_detailed({}, bad_rules, {"requirements": {}})
    candidate_decision, candidate_reasons = sc.evaluate_candidate_policy(bad_rules, {"requirements": {}})
    flag(
        name,
        loader_closed
        and employer_decision == candidate_decision == "needs_context"
        and "all_rules_passed" not in candidate_reasons,
    )

for label, value in [("NAN", float("nan")), ("POS_INF", float("inf")), ("NEG_INF", float("-inf"))]:
    bad_floor_rules = rules_for("permanent", value)
    good_role = role_for("permanent", 120000)
    bad_role = role_for("permanent", value)
    good_rules = rules_for("permanent", 100000)
    flag(label + "_FLOOR_CONTEXT", sc.check_compensation_policy(bad_floor_rules, good_role)[0] == "needs_context")
    flag(label + "_ROLE_CONTEXT", sc.check_compensation_policy(good_rules, bad_role)[0] == "needs_context")
    flag(
        label + "_PARITY",
        sc.check_hard_filters_detailed({}, bad_floor_rules, good_role)[0] == "needs_context"
        and sc.evaluate_candidate_policy(bad_floor_rules, good_role)[0] == "needs_context"
        and sc.check_hard_filters_detailed({}, good_rules, bad_role)[0] == "needs_context"
        and sc.evaluate_candidate_policy(good_rules, bad_role)[0] == "needs_context",
    )


language_role = {"requirements": {"languages_required": ["English", "German"]}}
language_cases = [
    ("LANG_MISSING", "needs_context", {}),
    ("LANG_EMPTY", "needs_context", {"spoken_languages": []}),
    ("LANG_MALFORMED", "needs_context", {"spoken_languages": [{"level": "fluent"}]}),
    ("LANG_MATCH", "pass", {"spoken_languages": [{"language": "English"}, {"language": "German"}]}),
    ("LANG_MISMATCH", "reject", {"spoken_languages": [{"language": "English"}]}),
]
for name, expected, profile in language_cases:
    decision, _ = sc._check_required_languages(profile, language_role)
    flag(name, decision == expected)


blocked_rules = {"filters": {"blocked_industries": ["gambling"]}}
recruiter_cases = [
    ("RECRUITER_ABSENT", "needs_context", None),
    ("RECRUITER_MALFORMED", "needs_context", {"industries": "software"}),
    ("RECRUITER_EMPTY", "needs_context", {"industries": []}),
    ("RECRUITER_BLANK", "needs_context", {"industries": ["  "]}),
    ("RECRUITER_BLOCKED", "reject", {"industries": ["Gambling"]}),
    ("RECRUITER_CLEAN", "pass", {"industries": ["software"]}),
]
for name, expected, recruiter in recruiter_cases:
    decision, _ = sc._check_blocked_industries(blocked_rules, recruiter)
    flag(name, decision == expected)

context_decision, context_reasons = sc.evaluate_candidate_policy(
    blocked_rules, {"requirements": {}}, recruiter=None, profile={}
)
flag("NO_FALSE_ALL_RULES", context_decision == "needs_context" and "all_rules_passed" not in context_reasons)
PY
)

t_begin F-07 "nested YAML requires PyYAML while JSON-form rules remain supported"
assert_grep '^YAML_FAILS_CLOSED=1$' "$out"
assert_grep '^JSON_WITHOUT_YAML=1$' "$out"
for key in BLANK_RULES_FAIL EMPTY_RULES_FAIL UNKNOWN_POLICY_FAIL; do
    assert_grep "^${key}=1$" "$out"
done
t_end

t_begin F-07 "CLI emits no JSON on missing PyYAML and accepts explicit JSON rules"
no_yaml="$WORK/no-yaml"
mkdir -p "$no_yaml"
printf '%s\n' 'raise ImportError("fixture blocks PyYAML")' > "$no_yaml/yaml.py"
cat > "$WORK/profile.json" <<'JSON'
{"name":"Alice Developer","title":"Engineer","spoken_languages":[{"language":"English"}]}
JSON
cat > "$WORK/role.json" <<'JSON'
{"engagement":{"type":"permanent"},"compensation":{"currency":"EUR","base_max":100000},"requirements":{}}
JSON
cat > "$WORK/rules.yaml" <<'YAML'
engagement:
  allowed_types:
    - permanent
YAML
cat > "$WORK/rules.json" <<'JSON'
{"engagement":{"allowed_types":["permanent"]}}
JSON
: > "$WORK/missing-yaml.stdout"
if PYTHONPATH="$no_yaml" python3 "$REPO_ROOT/tools/scoring.py" --json \
    "$WORK/profile.json" "$WORK/rules.yaml" "$WORK/role.json" \
    >"$WORK/missing-yaml.stdout" 2>"$WORK/missing-yaml.stderr"; then
    t_fail "nested YAML unexpectedly evaluated without PyYAML"
fi
assert_eq 0 "$(wc -c < "$WORK/missing-yaml.stdout" | tr -d ' ')" \
    "failed JSON-mode scoring keeps stdout empty"
assert_grep 'PyYAML is required' "$WORK/missing-yaml.stderr"
PYTHONPATH="$no_yaml" python3 "$REPO_ROOT/tools/scoring.py" --json \
    "$WORK/profile.json" "$WORK/rules.json" "$WORK/role.json" > "$WORK/json-rules.out"
assert_exit 0 python3 -m json.tool "$WORK/json-rules.out"
assert_grep '"decision": "pass"' "$WORK/json-rules.out"

: > "$WORK/missing-rules.stdout"
if python3 "$REPO_ROOT/tools/scoring.py" --json "$WORK/profile.json" "$WORK/no-rules.yaml" \
    "$WORK/role.json" >"$WORK/missing-rules.stdout" 2>"$WORK/missing-rules.stderr"; then
    t_fail "missing rules path unexpectedly passed"
fi
assert_eq 0 "$(wc -c < "$WORK/missing-rules.stdout" | tr -d ' ')"
assert_grep 'Rules file not found' "$WORK/missing-rules.stderr"

mkdir -p "$WORK/card-without-rules"
cp "$WORK/profile.json" "$WORK/card-without-rules/profile.json"
: > "$WORK/card-without-rules.stdout"
if "$SCOUTICA" evaluate --json "$WORK/card-without-rules" "$WORK/role.json" \
    >"$WORK/card-without-rules.stdout" 2>"$WORK/card-without-rules.stderr"; then
    t_fail "card without rules.yaml unexpectedly passed"
fi
assert_eq 0 "$(wc -c < "$WORK/card-without-rules.stdout" | tr -d ' ')"
assert_grep 'Rules file not found' "$WORK/card-without-rules.stderr"

: > "$WORK/usage.stdout"
if python3 "$REPO_ROOT/tools/scoring.py" --json >"$WORK/usage.stdout" 2>"$WORK/usage.stderr"; then
    t_fail "insufficient JSON-mode arguments unexpectedly passed"
fi
assert_eq 0 "$(wc -c < "$WORK/usage.stdout" | tr -d ' ')"
assert_grep '^Usage:' "$WORK/usage.stderr"

cat > "$WORK/nonfinite-role.json" <<'JSON'
{"engagement":{"type":"permanent"},"compensation":{"currency":"EUR","base_max":NaN},"requirements":{}}
JSON
: > "$WORK/nonfinite.stdout"
if python3 "$REPO_ROOT/tools/scoring.py" --json "$WORK/profile.json" "$WORK/rules.json" \
    "$WORK/nonfinite-role.json" >"$WORK/nonfinite.stdout" 2>"$WORK/nonfinite.stderr"; then
    t_fail "non-finite JSON compensation unexpectedly passed"
fi
assert_eq 0 "$(wc -c < "$WORK/nonfinite.stdout" | tr -d ' ')"
assert_grep 'non-finite JSON number' "$WORK/nonfinite.stderr"

for case_name in compensation filter; do
    case "$case_name" in
        compensation)
            cat > "$WORK/nested-typo-rules.json" <<'JSON'
{"engagement":{"allowed_types":["permanent"],"compensation":{"minimum_base_euro":{"permanent":100000}}}}
JSON
            extra_args=""
            ;;
        filter)
            cat > "$WORK/nested-typo-rules.json" <<'JSON'
{"filters":{"blocked_industry":["gambling"]}}
JSON
            cat > "$WORK/recruiter.json" <<'JSON'
{"industries":["gambling"]}
JSON
            extra_args="$WORK/recruiter.json"
            ;;
    esac
    : > "$WORK/nested-${case_name}.stdout"
    if python3 "$REPO_ROOT/tools/scoring.py" --json "$WORK/profile.json" \
        "$WORK/nested-typo-rules.json" "$WORK/role.json" $extra_args \
        >"$WORK/nested-${case_name}.stdout" 2>"$WORK/nested-${case_name}.stderr"; then
        t_fail "nested $case_name policy typo unexpectedly passed"
    fi
    assert_eq 0 "$(wc -c < "$WORK/nested-${case_name}.stdout" | tr -d ' ')"
    assert_grep 'Invalid rules policy' "$WORK/nested-${case_name}.stderr"
done

cat > "$WORK/hybrid-rules.json" <<'JSON'
{"remote":{"policy":"hybrid","hybrid_locations":["Berlin"]}}
JSON
cat > "$WORK/hybrid-role.json" <<'JSON'
{"location":{"type":"hybrid","office_location":"Paris"},"requirements":{}}
JSON
python3 "$REPO_ROOT/tools/scoring.py" --json "$WORK/profile.json" "$WORK/hybrid-rules.json" \
    "$WORK/hybrid-role.json" > "$WORK/hybrid-result.json"
assert_exit 0 python3 -m json.tool "$WORK/hybrid-result.json"
assert_grep '"decision": "reject"' "$WORK/hybrid-result.json"
assert_grep '"candidate_accepts": false' "$WORK/hybrid-result.json"
t_end

t_begin F-08 "compensation uses explicit EUR and engagement-derived units"
for key in EUR_BELOW EUR_EQUAL EUR_ABOVE USD_CONTEXT JPY_CONTEXT MISSING_CURRENCY \
    MISSING_VALUE NEGOTIABLE CONTRACT_BELOW CONTRACT_EQUAL ADVISORY_BELOW ADVISORY_EQUAL; do
    assert_grep "^${key}=1$" "$out"
    assert_grep "^${key}_PARITY=1$" "$out"
done
for key in SCALAR_FLOOR_CONTEXT UNKNOWN_ENGAGEMENT_CONTEXT EMPLOYER_ENGAGEMENT_CONTEXT \
    EMPLOYER_LOCATION_CONTEXT MALFORMED_POLICY_CONTEXT ABSENT_RULES_CONTEXT EMPTY_RULES_CONTEXT \
    UNKNOWN_REMOTE_CONTEXT EMPTY_ENGAGEMENT_CONTEXT; do
    assert_grep "^${key}=1$" "$out"
done
for prefix in NAN POS_INF NEG_INF; do
    for suffix in FLOOR_CONTEXT ROLE_CONTEXT PARITY; do
        assert_grep "^${prefix}_${suffix}=1$" "$out"
    done
done
for key in ENGAGEMENT_FIELD_TYPO COMPENSATION_FIELD_TYPO REMOTE_FIELD_TYPO \
    FILTER_FIELD_TYPO STACK_FIELD_TYPO SOFT_FIELD_TYPO PRIVACY_FIELD_TYPO \
    REMOTE_LOCATION_UNKNOWN REMOTE_LOCATION_HYBRID REMOTE_LOCATION_ONSITE REMOTE_LOCATION_REMOTE; do
    assert_grep "^${key}=1$" "$out"
done
for key in HYBRID_ALLOWED HYBRID_CASEFOLD_ALLOWED HYBRID_BLOCKED HYBRID_OFFICE_MISSING \
    HYBRID_ALLOWLIST_EMPTY HYBRID_ONSITE_REJECT HYBRID_REMOTE_ALLOWED; do
    assert_grep "^${key}=1$" "$out"
done
t_end

t_begin F-10 "required-language context distinguishes missing, malformed, match, and mismatch"
for key in LANG_MISSING LANG_EMPTY LANG_MALFORMED LANG_MATCH LANG_MISMATCH; do
    assert_grep "^${key}=1$" "$out"
done
t_end


t_begin F-10 "human rendering labels missing context without calling it a hard reject"
cat > "$WORK/context-rules.json" <<'JSON'
{"filters":{"blocked_industries":["gambling"]}}
JSON
python3 "$REPO_ROOT/tools/scoring.py" "$WORK/profile.json" "$WORK/context-rules.json" \
    "$WORK/role.json" >"$WORK/context-human.out"
assert_grep 'NEEDS CONTEXT' "$WORK/context-human.out"
assert_no_grep 'HARD REJECT' "$WORK/context-human.out"
t_end

t_begin F-10 "blocked-industry policy fails closed without valid recruiter context"
for key in RECRUITER_ABSENT RECRUITER_MALFORMED RECRUITER_EMPTY RECRUITER_BLANK \
    RECRUITER_BLOCKED RECRUITER_CLEAN NO_FALSE_ALL_RULES; do
    assert_grep "^${key}=1$" "$out"
done
t_end
