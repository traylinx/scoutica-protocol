---
name: evaluate-candidate
description: Evaluate a candidate's Scoutica Skill Card against a job description or role requirements. Use when asked to match a candidate to a role, score a profile, check if an opportunity fits, or pre-screen applicants. Returns a structured fit report with scores and recommendations.
---

# evaluate-candidate

Score a candidate's Skill Card against specific job requirements and produce a structured evaluation.

## When to Use

- Employer asks "does this candidate fit our role?"
- Candidate asks "do I match this job?"
- ATS system needs automated pre-screening
- Agent needs to compare multiple candidates

## Step-by-Step Process

### Step 1: Load the Skill Card

Read all 4 files from the candidate's card folder or URL:

```bash
profile.json  → skills, experience, seniority
rules.yaml    → engagement rules, salary floor, remote policy
evidence.json → proof of work
SKILL.md      → entry point
```

### Step 2: Load Job Requirements

Accept requirements as either:
- A job description (parse it)
- A structured object: `{required_skills, nice_to_have, seniority, salary_budget, remote_policy, industry}`

### Step 3: Score Skills Match

```
required_matches = count(job.required_skills ∩ candidate.skills)
total_required = count(job.required_skills)
skills_score = (required_matches / total_required) × 100

nice_to_have_matches = count(job.nice_to_have ∩ candidate.skills)
bonus_score = nice_to_have_matches × 5
```

### Step 4: Check Rules of Engagement

```yaml
# From rules.yaml — check each rule:
salary_check:     job.salary >= rules.compensation.minimum_base_eur
remote_check:     job.remote_policy ∈ rules.remote.policy
industry_check:   job.industry ∉ rules.auto_reject.blocked_industries
engagement_check: job.engagement_type ∈ rules.engagement.allowed_types
```

If ANY auto_reject rule fails → **REJECT** (do not continue).

### Step 5: Verify Evidence (Optional)

For each claimed skill in `evidence.json`:
- Check if URL is reachable
- Verify GitHub repos match claimed languages
- Check certification validity dates

### Step 6: Generate Fit Report

```json
{
  "candidate": "Name",
  "role": "Senior DevOps Engineer",
  "overall_score": 78,
  "verdict": "STRONG_MATCH",
  "skills_analysis": {
    "matched": ["Kubernetes", "Terraform", "AWS", "Python"],
    "missing": ["Ansible"],
    "bonus": ["Go", "Helm"],
    "skills_score": 80,
    "bonus_score": 10
  },
  "rules_check": {
    "salary": "PASS",
    "remote": "PASS",
    "industry": "PASS",
    "engagement_type": "PASS"
  },
  "evidence_verified": 4,
  "evidence_total": 5,
  "recommendation": "Proceed to interview. Strong stack overlap with 19 years experience. 1 missing skill (Ansible) is learnable."
}
```

### Scoring Thresholds

| Score | Verdict | Action |
|-------|---------|--------|
| 80-100 | `STRONG_MATCH` | Proceed to interview |
| 60-79 | `GOOD_MATCH` | Review and decide |
| 40-59 | `WEAK_MATCH` | Consider if other factors compensate |
| 0-39 | `NO_MATCH` | Do not proceed |
| Any rule fails | `REJECTED` | Auto-reject, do not present |

## Privacy Rules

- Use ONLY Zone 1 (public) data for initial screening
- Zone 2 (verified) data requires authentication
- NEVER access Zone 3 (private) data without explicit candidate approval
- NEVER share evaluation results with the candidate without employer consent
- NEVER share candidate data with third parties

## Anti-Discrimination

- NEVER factor in name, gender, age, ethnicity, nationality, photo
- Evaluate ONLY on: skills, experience, evidence, engagement rules
- Include this disclaimer in every report: "Evaluation based solely on verified skills and stated requirements"
