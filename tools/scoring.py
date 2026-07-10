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

PyYAML is required for YAML rules; JSON-form rules remain supported without it.
"""

import json
import math
import re
import sys
import os


def _as_number(x):
    """Return x as a float if it is a real numeric value, else None.

    Compensation floors may be the literal "negotiable" (or absent); treat any
    non-numeric value as "no floor" so comparisons never raise TypeError.
    """
    if isinstance(x, bool):
        return None
    if isinstance(x, (int, float)):
        value = float(x)
        return value if math.isfinite(value) else None
    return None


# Canonical engagement types: permanent, contract, fractional, advisory, internship.
# `freelance` is an accepted alias of `contract` (F-HIGH-ENUM-001), never a first-class type.
_ENGAGEMENT_ALIASES = {"freelance": "contract"}


def _norm_engagement(t):
    """Normalize an engagement type to its canonical form (freelance -> contract)."""
    if not t:
        return t
    key = str(t).strip().lower()
    return _ENGAGEMENT_ALIASES.get(key, key)


_DECISION_ORDER = {"pass": 0, "needs_context": 1, "reject": 2}
_COMPENSATION_UNITS = {
    "permanent": "annual",
    "contract": "daily",
    "fractional": "monthly",
    "advisory": "hourly",
    "internship": "annual",
}
_CANONICAL_ENGAGEMENTS = set(_COMPENSATION_UNITS)
_REMOTE_POLICIES = {"remote_only", "hybrid", "flexible", "on_site"}
_RULE_KEYS = {"schema_version", "engagement", "remote", "filters", "privacy"}
_ROLE_LOCATION_TYPES = {"remote", "hybrid", "onsite"}


def _unknown_fields(document, allowed, reason):
    unknown = sorted(set(document) - set(allowed))
    return [f"{reason}:{','.join(unknown)}"] if unknown else []


def _rules_policy_errors(rules):
    """Return structural policy errors that must prevent an automatic pass.

    The scorer deliberately supports focused rule documents in addition to a
    complete RoE, but every configured policy still has to use the protocol's
    shapes and enums. This prevents a typo or partially parsed policy from being
    treated as an absent restriction.
    """
    if not isinstance(rules, dict):
        return ["rules_document_malformed"]
    if not rules:
        return ["rules_document_empty"]

    errors = []
    unknown = sorted(set(rules) - _RULE_KEYS)
    if unknown:
        errors.append(f"rules_unknown_fields:{','.join(unknown)}")
    version = rules.get("schema_version")
    if "schema_version" in rules and (
        not isinstance(version, str) or re.fullmatch(r"\d+\.\d+\.\d+", version) is None
    ):
        errors.append("rules_schema_version_malformed")

    engagement = rules.get("engagement")
    if "engagement" in rules:
        if not isinstance(engagement, dict):
            errors.append("engagement_policy_malformed")
        else:
            errors.extend(
                _unknown_fields(
                    engagement,
                    {"allowed_types", "compensation"},
                    "engagement_unknown_fields",
                )
            )
            allowed = engagement.get("allowed_types")
            if (
                not isinstance(allowed, list)
                or not allowed
                or not all(
                    isinstance(item, str)
                    and _norm_engagement(item) in _CANONICAL_ENGAGEMENTS
                    for item in allowed
                )
            ):
                errors.append("engagement_allowed_types_malformed")
            compensation = engagement.get("compensation")
            if compensation is not None:
                if not isinstance(compensation, dict):
                    errors.append("compensation_policy_malformed")
                else:
                    errors.extend(
                        _unknown_fields(
                            compensation,
                            {"minimum_base_eur"},
                            "compensation_unknown_fields",
                        )
                    )
                    floors = compensation.get("minimum_base_eur")
                    if floors is not None:
                        if not isinstance(floors, dict):
                            errors.append("compensation_floors_malformed")
                        else:
                            compensable = {"permanent", "contract", "fractional", "advisory"}
                            if set(floors) - compensable:
                                errors.append("compensation_floor_units_unknown")
                            for value in floors.values():
                                negotiable = (
                                    isinstance(value, str)
                                    and value.strip().lower() == "negotiable"
                                )
                                number = _as_number(value)
                                if not negotiable and (number is None or number < 0):
                                    errors.append("compensation_floor_value_malformed")
                                    break

    remote = rules.get("remote")
    if "remote" in rules:
        if not isinstance(remote, dict):
            errors.append("remote_policy_malformed")
        else:
            errors.extend(
                _unknown_fields(
                    remote,
                    {"policy", "hybrid_locations"},
                    "remote_unknown_fields",
                )
            )
            if remote.get("policy") not in _REMOTE_POLICIES:
                errors.append("remote_policy_value_unknown")
            hybrid_locations = remote.get("hybrid_locations")
            if hybrid_locations is not None and (
                not isinstance(hybrid_locations, list)
                or not all(isinstance(item, str) and item.strip() for item in hybrid_locations)
            ):
                errors.append("remote_hybrid_locations_malformed")

    filters = rules.get("filters")
    if "filters" in rules:
        if not isinstance(filters, dict):
            errors.append("filters_policy_malformed")
        else:
            errors.extend(
                _unknown_fields(
                    filters,
                    {"blocked_industries", "stack_keywords", "soft_reject"},
                    "filters_unknown_fields",
                )
            )
            blocked = filters.get("blocked_industries")
            if blocked is not None and (
                not isinstance(blocked, list)
                or not all(isinstance(item, str) and item.strip() for item in blocked)
            ):
                errors.append("blocked_industries_policy_malformed")
            stack = filters.get("stack_keywords")
            if stack is not None:
                preferred = stack.get("preferred") if isinstance(stack, dict) else None
                if not isinstance(stack, dict):
                    errors.append("stack_keywords_policy_malformed")
                else:
                    errors.extend(
                        _unknown_fields(
                            stack,
                            {"preferred"},
                            "stack_keywords_unknown_fields",
                        )
                    )
                    if preferred is not None and (
                        not isinstance(preferred, list)
                        or not all(isinstance(item, str) and item.strip() for item in preferred)
                    ):
                        errors.append("stack_keywords_policy_malformed")
            soft = filters.get("soft_reject")
            if soft is not None:
                threshold = soft.get("weak_stack_overlap_below") if isinstance(soft, dict) else None
                if not isinstance(soft, dict):
                    errors.append("soft_reject_policy_malformed")
                else:
                    errors.extend(
                        _unknown_fields(
                            soft,
                            {"weak_stack_overlap_below"},
                            "soft_reject_unknown_fields",
                        )
                    )
                    if threshold is not None and (
                        isinstance(threshold, bool)
                        or not isinstance(threshold, int)
                        or threshold < 0
                    ):
                        errors.append("soft_reject_policy_malformed")

    if "privacy" in rules:
        privacy = rules.get("privacy")
        zones = {"zone_1_public", "zone_2_paid", "zone_3_private"}
        if not isinstance(privacy, dict):
            errors.append("privacy_policy_malformed")
        else:
            errors.extend(_unknown_fields(privacy, zones, "privacy_unknown_fields"))
            if set(privacy) != zones or not all(
                isinstance(privacy.get(zone), list)
                and all(isinstance(item, str) and item.strip() for item in privacy[zone])
                for zone in zones
            ):
                errors.append("privacy_policy_malformed")
    return errors


def _merge_decisions(*decisions):
    """Return the most conservative decision: reject > needs_context > pass."""
    return max(decisions or ("pass",), key=lambda value: _DECISION_ORDER[value])


def check_compensation_policy(rules, role):
    """Evaluate the candidate's EUR floor against the role's matching-unit maximum.

    The engagement type defines the unit for both values because the current role
    schema exposes one generic base range. Numeric values are compared only when
    the role explicitly declares EUR; any missing or foreign-currency context is
    returned as needs_context rather than guessed or converted.
    """
    engagement = rules.get("engagement", {}) if isinstance(rules, dict) else {}
    compensation = engagement.get("compensation", {}) if isinstance(engagement, dict) else {}
    floors = compensation.get("minimum_base_eur", {}) if isinstance(compensation, dict) else {}
    role_engagement = role.get("engagement", {}) if isinstance(role, dict) else {}
    role_type = _norm_engagement(role_engagement.get("type")) if isinstance(role_engagement, dict) else ""

    if not role_type:
        if floors:
            return "needs_context", ["compensation_engagement_missing"]
        return "pass", []

    if role_type not in _COMPENSATION_UNITS:
        return "needs_context", [f"compensation_engagement_unknown:{role_type}"]

    if floors and not isinstance(floors, dict):
        return "needs_context", ["compensation_floors_malformed"]

    floor = floors.get(role_type) if isinstance(floors, dict) else None
    if floor is None or (isinstance(floor, str) and floor.strip().lower() == "negotiable"):
        return "pass", []

    floor_number = _as_number(floor)
    if floor_number is None:
        return "needs_context", [f"compensation_floor_malformed:{role_type}"]

    role_comp = role.get("compensation") if isinstance(role, dict) else None
    if not isinstance(role_comp, dict):
        return "needs_context", [f"compensation_missing:{role_type}:{_COMPENSATION_UNITS.get(role_type, 'unknown')}"]

    currency = role_comp.get("currency")
    if not isinstance(currency, str) or not currency.strip():
        return "needs_context", ["compensation_currency_missing"]
    currency = currency.strip().upper()
    if currency != "EUR":
        return "needs_context", [f"compensation_currency_requires_conversion:{currency}:EUR"]

    role_max = _as_number(role_comp.get("base_max"))
    if role_max is None:
        return "needs_context", [f"compensation_max_missing:{role_type}:{_COMPENSATION_UNITS.get(role_type, 'unknown')}"]
    if role_max < floor_number:
        return "reject", [
            f"compensation_below_floor:{role_type}:{_COMPENSATION_UNITS.get(role_type, 'unknown')}:{role_max:g}<{floor_number:g}:EUR"
        ]
    return "pass", []


def check_remote_policy(rules, role):
    """Evaluate one remote-work policy identically in both scoring directions."""
    remote = rules.get("remote") if isinstance(rules, dict) else None
    if remote is None:
        return "pass", []
    if not isinstance(remote, dict) or remote.get("policy") not in _REMOTE_POLICIES:
        return "needs_context", ["remote_policy_malformed"]

    location = role.get("location") if isinstance(role, dict) else None
    if not isinstance(location, dict):
        return "needs_context", ["role_location_context_missing"]
    location_type = location.get("type")
    if not isinstance(location_type, str) or not location_type:
        return "needs_context", ["role_location_context_missing"]
    if location_type not in _ROLE_LOCATION_TYPES:
        return "needs_context", ["role_location_type_unknown"]

    policy = remote["policy"]
    if policy == "remote_only":
        if location_type != "remote":
            return "reject", [f"location_mismatch:remote_only:{location_type}"]
        return "pass", []

    if policy == "hybrid":
        if location_type == "onsite":
            return "reject", ["location_mismatch:hybrid:onsite"]
        if location_type == "hybrid":
            allowed = remote.get("hybrid_locations")
            if not isinstance(allowed, list) or not allowed:
                return "needs_context", ["hybrid_locations_missing_or_empty"]
            office = location.get("office_location")
            if not isinstance(office, str) or not office.strip():
                return "needs_context", ["hybrid_office_location_missing"]
            allowed_names = {item.strip().casefold() for item in allowed}
            if office.strip().casefold() not in allowed_names:
                return "reject", [f"hybrid_location_not_allowed:{office.strip()}"]
        return "pass", []

    # flexible and on_site do not impose a narrower location gate.
    return "pass", []


def _check_required_languages(profile, role):
    requirements = role.get("requirements", {}) if isinstance(role, dict) else {}
    required = requirements.get("languages_required", []) if isinstance(requirements, dict) else []
    if not required:
        return "pass", []
    if not isinstance(required, list) or not all(isinstance(item, str) and item.strip() for item in required):
        return "needs_context", ["required_languages_malformed"]
    if not isinstance(profile, dict) or "spoken_languages" not in profile:
        return "needs_context", ["candidate_languages_missing"]
    spoken = profile.get("spoken_languages")
    if not isinstance(spoken, list) or not spoken:
        return "needs_context", ["candidate_languages_empty"]

    candidate_languages = []
    for item in spoken:
        if isinstance(item, dict) and isinstance(item.get("language"), str) and item["language"].strip():
            candidate_languages.append(item["language"].strip().lower())
        elif isinstance(item, str) and item.strip():
            candidate_languages.append(item.strip().lower())
        else:
            return "needs_context", ["candidate_languages_malformed"]

    missing = [item for item in required if item.strip().lower() not in candidate_languages]
    if missing:
        return "reject", [f"language_mismatch:{','.join(missing)}"]
    return "pass", []


def _check_blocked_industries(rules, recruiter):
    filters = rules.get("filters", {}) if isinstance(rules, dict) else {}
    if filters is not None and not isinstance(filters, dict):
        return "needs_context", ["filters_policy_malformed"]
    blocked = filters.get("blocked_industries", []) if isinstance(filters, dict) else []
    if not blocked:
        return "pass", []
    if not isinstance(blocked, list) or not all(isinstance(item, str) and item.strip() for item in blocked):
        return "needs_context", ["blocked_industries_policy_malformed"]
    if recruiter is None:
        return "needs_context", ["recruiter_context_missing_for_blocked_industries"]
    if not isinstance(recruiter, dict):
        return "needs_context", ["recruiter_context_malformed"]
    industries = recruiter.get("industries")
    if (
        not isinstance(industries, list)
        or not industries
        or not all(isinstance(item, str) and item.strip() for item in industries)
    ):
        return "needs_context", ["recruiter_industries_missing_or_malformed"]
    blocked_lower = {item.strip().lower() for item in blocked}
    overlap = [item for item in industries if item.strip().lower() in blocked_lower]
    if overlap:
        return "reject", [f"blocked_industry:{','.join(overlap)}"]
    return "pass", []


# ─── Hard Filter Engine ──────────────────────────────────────────────────────

def check_hard_filters_detailed(profile, rules, role, recruiter=None):
    """
    Fail-closed hard-filter evaluation with tri-state context.
    Returns (decision: pass|reject|needs_context, reasons: list[str]).
    """
    reasons = []

    if not isinstance(profile, dict) or not isinstance(role, dict):
        return "needs_context", ["scoring_document_malformed"]

    policy_errors = _rules_policy_errors(rules)
    if policy_errors:
        return "needs_context", policy_errors

    context_reasons = []

    # 1. Engagement type match
    if rules and "engagement" in rules:
        engagement = rules.get("engagement")
        if not isinstance(engagement, dict):
            context_reasons.append("engagement_policy_malformed")
        else:
            allowed_raw = engagement.get("allowed_types", [])
            if not isinstance(allowed_raw, list):
                context_reasons.append("engagement_allowed_types_malformed")
                allowed = []
            else:
                allowed = [_norm_engagement(a) for a in allowed_raw]
            role_engagement = role.get("engagement")
            role_type = (
                _norm_engagement(role_engagement.get("type"))
                if isinstance(role_engagement, dict)
                else ""
            )
            if allowed and not role_type:
                context_reasons.append("engagement_type_missing")
            elif allowed and role_type not in allowed:
                reasons.append(
                    f"engagement_type_mismatch: role requires '{role_type}', candidate allows {allowed}"
                )

    # 2. Compensation range (same predicate used by candidate-side evaluation)
    compensation_decision, compensation_reasons = check_compensation_policy(rules or {}, role)
    if compensation_decision == "reject":
        reasons.extend(compensation_reasons)
    elif compensation_decision == "needs_context":
        context_reasons.extend(compensation_reasons)

    # 3. Location / remote policy (same predicate used by candidate-side evaluation)
    remote_decision, remote_reasons = check_remote_policy(rules, role)
    if remote_decision == "reject":
        reasons.extend(remote_reasons)
    elif remote_decision == "needs_context":
        context_reasons.extend(remote_reasons)

    # 4. Blocked industries
    blocked_decision, blocked_reasons = _check_blocked_industries(rules or {}, recruiter)
    if blocked_decision == "reject":
        reasons.extend(blocked_reasons)
    elif blocked_decision == "needs_context":
        context_reasons.extend(blocked_reasons)

    # 5. Required languages
    language_decision, language_reasons = _check_required_languages(profile, role)
    if language_decision == "reject":
        reasons.extend(language_reasons)
    elif language_decision == "needs_context":
        context_reasons.extend(language_reasons)

    if reasons:
        return "reject", reasons
    if context_reasons:
        return "needs_context", context_reasons
    return "pass", []


def check_hard_filters(profile, rules, role, recruiter=None):
    """Backward-compatible boolean wrapper; unknown context never passes."""
    decision, reasons = check_hard_filters_detailed(profile, rules, role, recruiter)
    return decision == "pass", reasons


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
    +10 evidence (≥50% hard-skill coverage), +5 exact seniority match.
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
                    # Canonical evidence field per evidence.schema.json is skills_demonstrated
                    # (required); legacy tags/skills are not schema fields and never populated.
                    demonstrated = item.get("skills_demonstrated", [])
                    evidenced_skills.update(t.lower() for t in demonstrated)
                covered = sum(1 for s in hard_skills if s.lower() in evidenced_skills)
                if covered >= len(hard_skills) * 0.5:
                    bonuses.append("evidence")
                    bonus_total += 10

    # Seniority match: +5 if exact match
    role_seniority = role.get("requirements", {}).get("seniority", "")
    candidate_seniority = profile.get("seniority", "")
    if (
        role_seniority
        and candidate_seniority
        and str(role_seniority).strip().lower() == str(candidate_seniority).strip().lower()
    ):
        bonuses.append("seniority_match")
        bonus_total += 5

    # Freshness bonus removed: the candidate schema sets additionalProperties:false and defines
    # no `updated`/`last_updated` field, so a schema-valid card could never carry it — the branch
    # was unreachable dead code that also used datetime.now() (non-deterministic, contradicting the
    # engine's determinism contract). See F-HIGH-SCORE-003.

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
    filter_decision, filter_reasons = check_hard_filters_detailed(profile, rules, role, recruiter)
    if filter_decision != "pass":
        return {
            "score": 0,
            "verdict": "HARD_REJECT" if filter_decision == "reject" else "NEEDS_CONTEXT",
            "decision": filter_decision,
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
        "decision": "pass",
        "hard_filters_passed": True,
        "rejection_reasons": [],
        "skill_breakdown": skill_breakdown,
        "bonuses": bonus_list,
    }


# ─── Reverse Scoring: Candidate Evaluates Role ──────────────────────────────

def evaluate_candidate_policy(rules, role, recruiter=None, profile=None):
    """
    Candidate-side policy evaluation with explicit context handling.
    Returns (decision: pass|reject|needs_context, reasons: list[str]).
    """
    reasons = []
    if not isinstance(role, dict):
        return "needs_context", ["scoring_document_malformed"]

    policy_errors = _rules_policy_errors(rules)
    if policy_errors:
        return "needs_context", policy_errors

    decision = "pass"

    # Check engagement type
    if "engagement" in rules:
        engagement = rules.get("engagement")
        if not isinstance(engagement, dict):
            reasons.append("engagement_policy_malformed")
            decision = _merge_decisions(decision, "needs_context")
        else:
            allowed_raw = engagement.get("allowed_types", [])
            if not isinstance(allowed_raw, list):
                reasons.append("engagement_allowed_types_malformed")
                allowed = []
                decision = _merge_decisions(decision, "needs_context")
            else:
                allowed = [_norm_engagement(a) for a in allowed_raw]
            role_engagement = role.get("engagement")
            role_type = (
                _norm_engagement(role_engagement.get("type"))
                if isinstance(role_engagement, dict)
                else ""
            )
            if allowed and role_type and role_type not in allowed:
                reasons.append(f"engagement_type_not_allowed: {role_type}")
                decision = "reject"
            elif allowed and not role_type:
                reasons.append("engagement_type_missing")
                decision = _merge_decisions(decision, "needs_context")

    compensation_decision, compensation_reasons = check_compensation_policy(rules, role)
    decision = _merge_decisions(decision, compensation_decision)
    reasons.extend(compensation_reasons)

    remote_decision, remote_reasons = check_remote_policy(rules, role)
    decision = _merge_decisions(decision, remote_decision)
    reasons.extend(remote_reasons)

    blocked_decision, blocked_reasons = _check_blocked_industries(rules, recruiter)
    decision = _merge_decisions(decision, blocked_decision)
    reasons.extend(blocked_reasons)

    language_decision, language_reasons = _check_required_languages(profile, role)
    decision = _merge_decisions(decision, language_decision)
    reasons.extend(language_reasons)

    # Check stack overlap → SOFT reject (manual review), NOT a hard auto-reject.
    # roe.schema.json models soft_reject as a manual-review signal; collapsing it into
    # accepted=False (F-MED-SCORE-004) silently auto-rejected borderline roles. We surface a
    # distinct manual_review reason and leave accepted unchanged. The check is opt-in: it only
    # runs when weak_stack_overlap_below is explicitly configured (F-MED-SCORE-005) — absent = off.
    if "filters" in rules:
        filters = rules.get("filters")
        if not isinstance(filters, dict):
            return _merge_decisions(decision, "needs_context"), reasons + ["filters_policy_malformed"]
        stack_keywords = filters.get("stack_keywords", {})
        soft_cfg = filters.get("soft_reject", {})
        if not isinstance(stack_keywords, dict) or not isinstance(soft_cfg, dict):
            return _merge_decisions(decision, "needs_context"), reasons + ["soft_filter_policy_malformed"]
        stack_pref = stack_keywords.get("preferred", [])
        requirements = role.get("requirements", {})
        role_skills = requirements.get("hard_skills", []) if isinstance(requirements, dict) else []
        if stack_pref and role_skills and "weak_stack_overlap_below" in soft_cfg:
            soft_reject_threshold = soft_cfg.get("weak_stack_overlap_below", 0)
            overlap = sum(1 for s in role_skills if s.lower() in [p.lower() for p in stack_pref])
            if overlap < soft_reject_threshold:
                reasons.append(
                    f"manual_review:weak_stack_overlap: {overlap} matching skills (threshold: {soft_reject_threshold})"
                )
                decision = _merge_decisions(decision, "needs_context")

    if decision == "pass":
        reasons.append("all_rules_passed")

    return decision, reasons


def candidate_evaluates_role(rules, role, recruiter=None, profile=None):
    """Backward-compatible boolean wrapper; only an explicit pass is accepted."""
    decision, reasons = evaluate_candidate_policy(rules, role, recruiter, profile)
    return decision == "pass", reasons


# ─── CLI Interface ───────────────────────────────────────────────────────────

def load_yaml(filepath):
    """Load rules authoritatively; JSON remains usable when PyYAML is absent."""
    with open(filepath) as f:
        content = f.read()
    if not content.strip():
        raise RuntimeError("Rules document is empty")
    try:
        import yaml
        try:
            rules = yaml.safe_load(content)
        except yaml.YAMLError as exc:
            raise RuntimeError(f"Invalid YAML rules: {exc}") from exc
    except ImportError:
        try:
            rules = json.loads(content, parse_constant=_reject_json_constant)
        except json.JSONDecodeError as exc:
            raise RuntimeError(
                "PyYAML is required to evaluate YAML rules. Install it with: python3 -m pip install PyYAML"
            ) from exc
    errors = _rules_policy_errors(rules)
    if errors:
        raise RuntimeError(f"Invalid rules policy: {', '.join(errors)}")
    return rules


def _reject_json_constant(value):
    raise ValueError(f"non-finite JSON number is not allowed: {value}")


def main():
    # Parse args
    output_json = False
    args = sys.argv[1:]
    if args and args[0] == "--json":
        output_json = True
        args = args[1:]
    if len(args) < 3:
        print(
            "Usage: python3 scoring.py <profile.json> <rules.yaml> <role.json> [recruiter_profile.json]",
            file=sys.stderr,
        )
        print(
            "       python3 scoring.py --json <profile.json> <rules.yaml> <role.json> [recruiter_profile.json]",
            file=sys.stderr,
        )
        return 1

    profile_path = args[0]
    rules_path = args[1]
    role_path = args[2]
    recruiter_path = args[3] if len(args) > 3 else None

    try:
        with open(profile_path) as f:
            profile = json.load(f, parse_constant=_reject_json_constant)

        if not os.path.exists(rules_path):
            raise RuntimeError(f"Rules file not found: {rules_path}")
        rules = load_yaml(rules_path)

        with open(role_path) as f:
            role = json.load(f, parse_constant=_reject_json_constant)

        recruiter = None
        if recruiter_path and os.path.exists(recruiter_path):
            with open(recruiter_path) as f:
                recruiter = json.load(f, parse_constant=_reject_json_constant)

        evidence = None
        evidence_path = os.path.join(os.path.dirname(profile_path), "evidence.json")
        if os.path.exists(evidence_path):
            with open(evidence_path) as f:
                evidence = json.load(f, parse_constant=_reject_json_constant)
    except (OSError, ValueError, RuntimeError) as exc:
        print(f"scoring error: {exc}", file=sys.stderr)
        return 1

    try:
        result = score_fit(profile, rules, role, recruiter, evidence)
        candidate_decision, candidate_reasons = evaluate_candidate_policy(
            rules, role, recruiter, profile
        )
        result["candidate_decision"] = candidate_decision
        result["candidate_accepts"] = candidate_decision == "pass"
        result["candidate_reasons"] = candidate_reasons
        result["decision"] = _merge_decisions(result.get("decision", "pass"), candidate_decision)
    except (AttributeError, KeyError, TypeError, ValueError) as exc:
        print(f"scoring error: malformed scoring input: {exc}", file=sys.stderr)
        return 1

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

        if result["decision"] == "needs_context":
            print(f"  ⚠️  NEEDS CONTEXT — cannot make an autonomous decision:")
            for r in result["rejection_reasons"] + result["candidate_reasons"]:
                print(f"     • {r}")
        elif not result["hard_filters_passed"]:
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
            if result["candidate_decision"] == "pass":
                print(f"     ✅ Rules PASSED — agent would auto-accept")
            elif result["candidate_decision"] == "needs_context":
                print(f"     ⚠️  NEEDS CONTEXT — agent must not auto-apply:")
                for r in result["candidate_reasons"]:
                    print(f"        • {r}")
            else:
                print(f"     ❌ Rules FAILED — agent would auto-reject:")
                for r in result["candidate_reasons"]:
                    if r != "all_rules_passed":
                        print(f"        • {r}")

        print()

    return 0


if __name__ == "__main__":
    sys.exit(main())
