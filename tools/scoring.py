#!/usr/bin/env python3
"""
Scoutica Fit Scoring Engine — Deterministic Candidate ↔ Role Matching

This is the core machine of the Scoutica Protocol. Given a candidate's
profile.json + rules.yaml and an employer's role.json, it produces a
deterministic, reproducible integer score with a structured breakdown.

The same engine runs in BOTH directions:
  - Employer evaluating candidate: role.json vs profile.json
  - Candidate evaluating role: rules.yaml vs role.json + recruiter_profile.json

Usage:
  python3 scoring.py <profile.json> <rules.yaml> <role.json> [recruiter_profile.json]
  python3 scoring.py --batch <role.json> <registry_index.json>

Zero external dependencies. Ships with the CLI.
"""

import json
import sys
import os
from datetime import datetime, timezone


# ─── Hard Filter Engine ──────────────────────────────────────────────────────

def check_hard_filters(profile, rules, role, recruiter=None):
    """
    Boolean pass/fail checks. If ANY fail → HARD_REJECT.
    Returns (passed: bool, reasons: list[str])
    """
    reasons = []

    # 1. Engagement type match
    if rules and "engagement" in rules:
        allowed = rules["engagement"].get("allowed_types", [])
        role_type = role.get("engagement", {}).get("type", "")
        if allowed and role_type and role_type not in allowed:
            reasons.append(f"engagement_type_mismatch: role requires '{role_type}', candidate allows {allowed}")

    # 2. Compensation range
    if rules and "engagement" in rules:
        compensation = rules["engagement"].get("compensation", {})
        min_base = compensation.get("minimum_base_eur", {})
        role_type = role.get("engagement", {}).get("type", "permanent")
        role_comp = role.get("compensation", {})
        role_max = role_comp.get("base_max", 0)

        if isinstance(min_base, dict):
            candidate_min = min_base.get(role_type, 0)
        else:
            candidate_min = min_base

        if candidate_min and role_max and role_max < candidate_min:
            reasons.append(
                f"salary_below_minimum: role max {role_max} < candidate min {candidate_min} ({role_type})"
            )

    # 3. Location / remote policy
    if rules and "remote" in rules:
        candidate_policy = rules["remote"].get("policy", "")
        role_location_type = role.get("location", {}).get("type", "")

        if candidate_policy == "remote_only" and role_location_type == "onsite":
            reasons.append(
                f"location_mismatch: candidate is remote_only, role is onsite"
            )

    # 4. Blocked industries
    if rules and "filters" in rules and recruiter:
        blocked = rules["filters"].get("blocked_industries", [])
        recruiter_industries = recruiter.get("industries", [])
        blocked_lower = [b.lower() for b in blocked]
        overlap = [ind for ind in recruiter_industries if ind.lower() in blocked_lower]
        if overlap:
            reasons.append(f"blocked_industry: {overlap}")

    # 5. Language overlap
    role_languages = role.get("requirements", {}).get("languages_required", [])
    if role_languages and profile:
        spoken = profile.get("spoken_languages", [])
        if isinstance(spoken, list) and spoken:
            if isinstance(spoken[0], dict):
                candidate_langs = [l.get("language", "").lower() for l in spoken]
            else:
                candidate_langs = [l.lower() for l in spoken]
            role_langs_lower = [l.lower() for l in role_languages]
            overlap = [l for l in role_langs_lower if l in candidate_langs]
            if not overlap:
                reasons.append(
                    f"language_mismatch: role requires {role_languages}, candidate speaks {[l.get('language', l) if isinstance(l, dict) else l for l in spoken]}"
                )

    return (len(reasons) == 0, reasons)


# ─── Skill Scoring (0-100) ───────────────────────────────────────────────────

def compute_skill_score(profile, role):
    """
    Compute skill overlap score.
    hard_match * 70 + preferred_match * 30
    """
    requirements = role.get("requirements", {})
    hard_skills = requirements.get("hard_skills", [])
    preferred_skills = requirements.get("preferred_skills", [])

    # Candidate's full skill set (skills + tools_and_platforms + specializations)
    candidate_skills = set()
    for field in ["skills", "tools_and_platforms", "specializations", "primary_domains"]:
        items = profile.get(field, [])
        if isinstance(items, list):
            candidate_skills.update(s.lower().strip() for s in items)

    # Hard skill match
    hard_skills_lower = [s.lower().strip() for s in hard_skills]
    hard_matches = sum(1 for s in hard_skills_lower if s in candidate_skills)
    hard_ratio = hard_matches / len(hard_skills_lower) if hard_skills_lower else 1.0

    # Preferred skill match
    if preferred_skills:
        preferred_lower = [s.lower().strip() for s in preferred_skills]
        preferred_matches = sum(1 for s in preferred_lower if s in candidate_skills)
        preferred_ratio = preferred_matches / len(preferred_lower)
    else:
        preferred_ratio = 0.5  # neutral if no preferred skills specified

    # Weighted combination
    score = (hard_ratio * 70) + (preferred_ratio * 30)
    return round(score, 1), {
        "hard_match": round(hard_ratio, 2),
        "hard_matched": hard_matches,
        "hard_total": len(hard_skills_lower),
        "preferred_match": round(preferred_ratio, 2),
        "preferred_matched": sum(1 for s in [s.lower().strip() for s in preferred_skills] if s in candidate_skills) if preferred_skills else 0,
        "preferred_total": len(preferred_skills) if preferred_skills else 0,
    }


# ─── Bonus Adjustments ──────────────────────────────────────────────────────

def compute_bonuses(profile, role, evidence=None):
    """
    Compute bonus adjustments:
    +10 evidence, +5 seniority match, +5 freshness, +5 recruiter trust
    """
    bonuses = []
    bonus_total = 0

    # Evidence bonus: +10 if candidate has evidence for ≥50% of hard skills
    if evidence and isinstance(evidence, dict):
        evidence_items = evidence.get("evidence", evidence.get("items", []))
        if isinstance(evidence_items, list) and evidence_items:
            hard_skills = role.get("requirements", {}).get("hard_skills", [])
            if hard_skills:
                evidenced_skills = set()
                for item in evidence_items:
                    tags = item.get("tags", []) + item.get("skills", [])
                    evidenced_skills.update(t.lower() for t in tags)
                covered = sum(1 for s in hard_skills if s.lower() in evidenced_skills)
                if covered >= len(hard_skills) * 0.5:
                    bonuses.append("evidence")
                    bonus_total += 10

    # Seniority match: +5 if exact match
    role_seniority = role.get("requirements", {}).get("seniority", "")
    candidate_seniority = profile.get("seniority", "")
    if role_seniority and candidate_seniority and role_seniority == candidate_seniority:
        bonuses.append("seniority_match")
        bonus_total += 5

    # Freshness bonus: +5 if profile updated within 30 days
    updated = profile.get("updated", profile.get("last_updated", ""))
    if updated:
        try:
            if isinstance(updated, str) and len(updated) >= 10:
                update_date = datetime.strptime(updated[:10], "%Y-%m-%d")
                days_old = (datetime.now() - update_date).days
                if days_old <= 30:
                    bonuses.append("freshness")
                    bonus_total += 5
        except (ValueError, TypeError):
            pass

    return bonus_total, bonuses


# ─── Verdict ─────────────────────────────────────────────────────────────────

def compute_verdict(score):
    """Map score to verdict."""
    if score >= 80:
        return "STRONG_MATCH"
    elif score >= 60:
        return "MODERATE_MATCH"
    elif score >= 40:
        return "WEAK_MATCH"
    else:
        return "NO_MATCH"


# ─── Main Scoring Pipeline ──────────────────────────────────────────────────

def score_fit(profile, rules, role, recruiter=None, evidence=None):
    """
    Full scoring pipeline:
    1. Hard filters (boolean pass/fail)
    2. Skill scoring (0-100)
    3. Bonus adjustments
    4. Verdict

    Returns a structured result dict.
    """
    # Step 1: Hard filters
    filters_passed, filter_reasons = check_hard_filters(profile, rules, role, recruiter)
    if not filters_passed:
        return {
            "score": 0,
            "verdict": "HARD_REJECT",
            "hard_filters_passed": False,
            "rejection_reasons": filter_reasons,
            "skill_breakdown": None,
            "bonuses": [],
        }

    # Step 2: Skill scoring
    skill_score, skill_breakdown = compute_skill_score(profile, role)

    # Step 3: Bonuses
    bonus_total, bonus_list = compute_bonuses(profile, role, evidence)

    # Step 4: Final score + verdict
    final_score = min(100, round(skill_score + bonus_total))
    verdict = compute_verdict(final_score)

    return {
        "score": final_score,
        "verdict": verdict,
        "hard_filters_passed": True,
        "rejection_reasons": [],
        "skill_breakdown": skill_breakdown,
        "bonuses": bonus_list,
    }


# ─── Reverse Scoring: Candidate Evaluates Role ──────────────────────────────

def candidate_evaluates_role(rules, role, recruiter=None):
    """
    Candidate-side evaluation: does this role meet my rules?
    Returns (accept: bool, reasons: list[str])
    """
    reasons = []
    accepted = True

    if not rules:
        return True, ["no_rules_defined"]

    # Check engagement type
    if "engagement" in rules:
        allowed = rules["engagement"].get("allowed_types", [])
        role_type = role.get("engagement", {}).get("type", "")
        if allowed and role_type and role_type not in allowed:
            reasons.append(f"engagement_type_not_allowed: {role_type}")
            accepted = False

    # Check minimum compensation
    if "engagement" in rules:
        compensation = rules["engagement"].get("compensation", {})
        min_base = compensation.get("minimum_base_eur", {})
        role_type = role.get("engagement", {}).get("type", "permanent")
        role_comp = role.get("compensation", {})
        role_max = role_comp.get("base_max", 0)

        if isinstance(min_base, dict):
            candidate_min = min_base.get(role_type, 0)
        else:
            candidate_min = min_base

        if candidate_min and role_max and role_max < candidate_min:
            reasons.append(f"salary_too_low: max {role_max} < min {candidate_min}")
            accepted = False

    # Check remote policy
    if "remote" in rules:
        candidate_policy = rules["remote"].get("policy", "")
        role_location_type = role.get("location", {}).get("type", "")
        if candidate_policy == "remote_only" and role_location_type == "onsite":
            reasons.append("requires_remote_but_role_is_onsite")
            accepted = False

    # Check blocked industries
    if "filters" in rules and recruiter:
        blocked = rules["filters"].get("blocked_industries", [])
        recruiter_industries = recruiter.get("industries", [])
        blocked_lower = [b.lower() for b in blocked]
        overlap = [ind for ind in recruiter_industries if ind.lower() in blocked_lower]
        if overlap:
            reasons.append(f"blocked_industry: {overlap}")
            accepted = False

    # Check stack overlap
    if "filters" in rules:
        stack_pref = rules["filters"].get("stack_keywords", {}).get("preferred", [])
        role_skills = role.get("requirements", {}).get("hard_skills", [])
        if stack_pref and role_skills:
            soft_reject_threshold = rules["filters"].get("soft_reject", {}).get("weak_stack_overlap_below", 0)
            overlap = sum(1 for s in role_skills if s.lower() in [p.lower() for p in stack_pref])
            if overlap < soft_reject_threshold:
                reasons.append(f"weak_stack_overlap: {overlap} matching skills (threshold: {soft_reject_threshold})")
                accepted = False

    if accepted:
        reasons.append("all_rules_passed")

    return accepted, reasons


# ─── CLI Interface ───────────────────────────────────────────────────────────

def load_yaml(filepath):
    """Load YAML file, falling back to JSON parser if pyyaml unavailable."""
    with open(filepath) as f:
        content = f.read()
    try:
        import yaml
        return yaml.safe_load(content)
    except ImportError:
        # Fallback: try as JSON (hiring_rules can be JSON)
        try:
            return json.loads(content)
        except json.JSONDecodeError:
            # Ultra-basic YAML parser for simple structures
            result = {}
            current_section = result
            indent_stack = [(0, result)]
            for line in content.split("\n"):
                stripped = line.strip()
                if not stripped or stripped.startswith("#"):
                    continue
                indent = len(line) - len(line.lstrip())
                if ":" in stripped:
                    key, _, val = stripped.partition(":")
                    key = key.strip().strip('"').strip("'")
                    val = val.strip().strip('"').strip("'")
                    # Find parent
                    while indent_stack and indent_stack[-1][0] >= indent:
                        indent_stack.pop()
                    if not indent_stack:
                        indent_stack = [(0, result)]
                    parent = indent_stack[-1][1]
                    if val:
                        if val.lower() == "true":
                            parent[key] = True
                        elif val.lower() == "false":
                            parent[key] = False
                        else:
                            try:
                                parent[key] = int(val)
                            except ValueError:
                                parent[key] = val
                    else:
                        parent[key] = {}
                        indent_stack.append((indent, parent[key]))
                elif stripped.startswith("- "):
                    item = stripped[2:].strip().strip('"').strip("'")
                    parent = indent_stack[-1][1]
                    if isinstance(parent, dict):
                        last_key = list(parent.keys())[-1] if parent else None
                        if last_key and parent[last_key] == {}:
                            parent[last_key] = [item]
                        elif last_key and isinstance(parent[last_key], list):
                            parent[last_key].append(item)
                    elif isinstance(parent, list):
                        parent.append(item)
            return result


def main():
    if len(sys.argv) < 4:
        print("Usage: python3 scoring.py <profile.json> <rules.yaml> <role.json> [recruiter_profile.json]")
        print("       python3 scoring.py --json <profile.json> <rules.yaml> <role.json> [recruiter_profile.json]")
        sys.exit(1)

    # Parse args
    output_json = False
    args = sys.argv[1:]
    if args[0] == "--json":
        output_json = True
        args = args[1:]

    profile_path = args[0]
    rules_path = args[1]
    role_path = args[2]
    recruiter_path = args[3] if len(args) > 3 else None

    # Load files
    with open(profile_path) as f:
        profile = json.load(f)

    rules = load_yaml(rules_path) if os.path.exists(rules_path) else None

    with open(role_path) as f:
        role = json.load(f)

    recruiter = None
    if recruiter_path and os.path.exists(recruiter_path):
        with open(recruiter_path) as f:
            recruiter = json.load(f)

    # Load evidence if available
    evidence = None
    evidence_path = os.path.join(os.path.dirname(profile_path), "evidence.json")
    if os.path.exists(evidence_path):
        with open(evidence_path) as f:
            evidence = json.load(f)

    # Run scoring
    result = score_fit(profile, rules, role, recruiter, evidence)

    # Run candidate-side evaluation
    candidate_result = candidate_evaluates_role(rules, role, recruiter)
    result["candidate_accepts"] = candidate_result[0]
    result["candidate_reasons"] = candidate_result[1]

    if output_json:
        print(json.dumps(result, indent=2))
    else:
        # Pretty print
        print()
        print(f"  ╔═══════════════════════════════════════════╗")
        print(f"  ║  Scoutica Fit Score: {result['score']:>3}/100               ║")
        print(f"  ║  Verdict: {result['verdict']:<33}║")
        print(f"  ╚═══════════════════════════════════════════╝")
        print()

        if not result["hard_filters_passed"]:
            print(f"  ❌ HARD REJECT — Failed mandatory filters:")
            for r in result["rejection_reasons"]:
                print(f"     • {r}")
        else:
            sb = result["skill_breakdown"]
            print(f"  📊 Skill Match:")
            print(f"     Hard skills:      {sb['hard_matched']}/{sb['hard_total']} ({sb['hard_match']:.0%})")
            print(f"     Preferred skills: {sb['preferred_matched']}/{sb['preferred_total']} ({sb['preferred_match']:.0%})")
            if result["bonuses"]:
                print(f"  🎁 Bonuses: {', '.join(result['bonuses'])}")
            print()
            print(f"  🤖 Candidate-side evaluation:")
            if result["candidate_accepts"]:
                print(f"     ✅ Rules PASSED — agent would auto-accept")
            else:
                print(f"     ❌ Rules FAILED — agent would auto-reject:")
                for r in result["candidate_reasons"]:
                    if r != "all_rules_passed":
                        print(f"        • {r}")

        print()


if __name__ == "__main__":
    main()
