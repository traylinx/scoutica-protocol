# Evaluate Fit

How to score capability match between this candidate and a role.

## Input

Either a structured role description or a raw job posting. If the input is raw text, extract the following before scoring:

- **Role type** (e.g., "Principal Engineer", "Platform Lead", "Architecture Advisor")
- **Required capabilities** — the must-have technical skills
- **Optional capabilities** — nice-to-have skills
- **Domain** — the business or technical domain (e.g., "fintech", "developer tools", "AI infrastructure")

## Scoring Method

1. Load `profile/candidate_profile.json`
2. Collect the candidate's full capability set from: `primary_domains`, `languages`, `frameworks_and_platforms`, and `specializations`
3. Compare against the role's required capabilities:
   - Count how many required capabilities the candidate matches (case-insensitive)
   - Calculate: `required_score = matched / total_required`
4. Compare against optional capabilities:
   - Count how many optional capabilities the candidate matches
   - Calculate: `optional_score = matched / total_optional`
5. Calculate final score: `score = (required_score × 0.8) + (optional_score × 0.2)`
6. Round to two decimal places

## Output Format

Return the evaluation in this structure:

```
Match Score: 0.85

Matched Capabilities:
  ✅ Python
  ✅ Kubernetes
  ✅ Agentic AI

Missing Capabilities:
  ❌ Terraform
  ❌ Java

Optional Hits:
  ✅ AWS
  ✅ MCP

Rationale: Matched 3/5 required capabilities and 2/3 optional capabilities.
```

## After Scoring

After calculating match score, always proceed to [negotiate-terms.md](./negotiate-terms.md) to check whether the opportunity's terms are acceptable.
