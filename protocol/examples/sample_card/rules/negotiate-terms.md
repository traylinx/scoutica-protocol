# Negotiate Terms

How to check whether an opportunity's terms comply with the candidate's Rules of Engagement.

## Input

From the job description or role schema, extract:

- **Engagement type** — permanent, fractional, advisory, contract, internship, etc.
- **Remote policy** — 100% remote, hybrid, on-site
- **Location** — where the company or role is based
- **Compensation** — salary, daily rate, or hourly rate (in EUR or convertible)

If any of these are missing from the job description, note them as "unknown" in the output.

## Policy Checks

Load `profile/roe.yaml` and run the following checks **in this order**. Stop at the first hard REJECT.

### Check 1: Engagement Type
- If `engagement_type` is not in `engagement.allowed_types` → **REJECT**
- Reason: "Engagement type `{type}` is not accepted."

### Check 2: Remote Policy
- If `remote_policy` is `on-site` AND `remote.policy` is `remote_only` → **REJECT**
- Reason: "On-site opportunities are auto-rejected by policy."
- If `remote_policy` is `hybrid` AND location is NOT in `remote.hybrid_locations` → **REJECT**
- Reason: "Hybrid roles are only acceptable within the candidate's listed hybrid locations."

### Check 3: Compensation
- Look up the minimum for the engagement type from `engagement.compensation.minimum_base_eur`
- If the offered compensation is below the minimum → **REJECT**
- Reason: "Compensation below minimum threshold: {offered} < {minimum}."
- If compensation is unknown, note it but do not reject.

### Check 4: Stack Overlap
- Count how many of the role's required capabilities appear in `filters.stack_keywords.preferred`
- If the overlap count is below `filters.soft_reject.weak_stack_overlap_below` → **SOFT_REJECT**
- Reason: "Role has weak stack overlap with preferred domains."

### If All Checks Pass → **ACCEPT**
- Reason: "Role satisfies current engagement and compensation policies."

## Output Format

```
Policy Verdict: ACCEPT | SOFT_REJECT | REJECT

Reasons:
  • Role satisfies current engagement and compensation policies.

Next Actions:
  • request_evidence (see rules/verify-evidence.md)
  • request_interview (see rules/request-interview.md)
```

For REJECT:
```
Policy Verdict: REJECT

Reasons:
  • On-site opportunities are auto-rejected by policy.

Recommendation: Do not proceed with this opportunity.
```

For SOFT_REJECT:
```
Policy Verdict: SOFT_REJECT

Reasons:
  • Role has weak stack overlap with preferred domains.

Recommendation: Flag for manual review. The candidate may want to evaluate this personally.
```
