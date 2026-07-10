#!/bin/sh
# tests/scoring.test.sh — Phase 2 regression tests for the deterministic scoring engine.
# Each case would FAIL against the pre-remediation scoring.py and PASS after.
. "$TESTLIB/assert.sh"

_out=$(python3 - "$REPO_ROOT/tools/scoring.py" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("scoring", sys.argv[1])
sc = importlib.util.module_from_spec(spec); spec.loader.exec_module(sc)

# H1: "negotiable" (the init default) or a numeric floor must never raise TypeError.
rules_neg = {"engagement": {"allowed_types": ["permanent"],
             "compensation": {"minimum_base_eur": {"permanent": "negotiable"}}}}
role90 = {"engagement": {"type": "permanent"}, "compensation": {"base_max": 90000}}
try:
    sc.check_hard_filters({}, rules_neg, role90)
    print("H1_EMPLOYER_NOCRASH=1")
    sc.candidate_evaluates_role(rules_neg, role90)
    print("H1_CANDIDATE_NOCRASH=1")
except Exception as e:
    print("H1_CRASH=" + type(e).__name__)
rules120 = {"engagement": {"allowed_types": ["permanent"],
            "compensation": {"minimum_base_eur": {"permanent": 120000}}}}
okb, _ = sc.check_hard_filters({}, rules120, role90)
print("H1_BELOW_FLOOR_REJECTS=" + ("1" if not okb else "0"))

# M5: without explicit EUR context, a contract floor must fail closed rather than compare raw values.
rulesC = {"engagement": {"allowed_types": ["contract"],
          "compensation": {"minimum_base_eur": {"contract": 500}}}}
roleC = {"engagement": {"type": "contract"}, "compensation": {"base_max": 120000}}
dc, _ = sc.check_hard_filters_detailed({}, rulesC, roleC)
print("M5_CONTRACT_NEEDS_CURRENCY=" + ("1" if dc == "needs_context" else "0"))

# H4a: skills_demonstrated is the canonical evidence field; legacy tags/skills do not fire.
prof = {"seniority": "senior"}
role2 = {"requirements": {"hard_skills": ["python", "rust"]}}
bnew, _ = sc.compute_bonuses(prof, role2, {"evidence": [{"skills_demonstrated": ["python", "rust"]}]})
bold, _ = sc.compute_bonuses(prof, role2, {"evidence": [{"tags": ["python", "rust"]}]})
print("H4A_DEMO_BONUS=" + str(bnew))
print("H4A_LEGACY_BONUS=" + str(bold))

# H4b: freshness dead branch removed; engine carries no datetime (determinism).
bf, _ = sc.compute_bonuses({"updated": "2026-07-01"}, role2, None)
print("H4B_FRESHNESS_GONE=" + ("1" if bf == 0 else "0"))
print("H4B_NO_DATETIME=" + ("1" if not hasattr(sc, "datetime") else "0"))

# M4 / SCORE-005: weak-stack overlap is a manual-review signal (not hard auto-reject) and opt-in.
rulesS = {"filters": {"stack_keywords": {"preferred": ["go"]},
          "soft_reject": {"weak_stack_overlap_below": 2}}}
roleS = {"requirements": {"hard_skills": ["python", "rust"]}}
accS, rS = sc.candidate_evaluates_role(rulesS, roleS)
decS, _ = sc.evaluate_candidate_policy(rulesS, roleS)
print("M4_SOFT_STOPS_AUTO=" + ("1" if (not accS and decS == "needs_context") else "0"))
print("M4_MANUAL_REVIEW=" + ("1" if any(x.startswith("manual_review:") for x in rS) else "0"))
accO, rO = sc.candidate_evaluates_role({"filters": {"stack_keywords": {"preferred": ["go"]}}}, roleS)
print("SCORE005_OPT_IN=" + ("1" if not any("manual_review" in x for x in rO) else "0"))
PY
)

t_begin F-HIGH-SCORE-001 "negotiable/null floor never crashes; numeric floor still rejects"
assert_grep "H1_EMPLOYER_NOCRASH=1" "$_out"
assert_grep "H1_CANDIDATE_NOCRASH=1" "$_out"
assert_grep "H1_BELOW_FLOOR_REJECTS=1" "$_out"
assert_no_grep "H1_CRASH=" "$_out"
t_end

t_begin F-HIGH-COMP-001 "contract compensation without currency fails closed"
assert_grep "M5_CONTRACT_NEEDS_CURRENCY=1" "$_out"
t_end

t_begin F-HIGH-SCORE-002 "skills_demonstrated fires evidence bonus; legacy tags do not"
assert_grep "H4A_DEMO_BONUS=10" "$_out"
assert_grep "H4A_LEGACY_BONUS=0" "$_out"
t_end

t_begin F-HIGH-SCORE-003 "freshness dead branch removed; engine deterministic"
assert_grep "H4B_FRESHNESS_GONE=1" "$_out"
assert_grep "H4B_NO_DATETIME=1" "$_out"
t_end

t_begin F-MED-SCORE-004 "soft-reject surfaces manual-review and stops auto-apply"
assert_grep "M4_SOFT_STOPS_AUTO=1" "$_out"
assert_grep "M4_MANUAL_REVIEW=1" "$_out"
t_end

t_begin F-MED-SCORE-005 "weak-overlap soft-reject is opt-in (absent threshold = off)"
assert_grep "SCORE005_OPT_IN=1" "$_out"
t_end
