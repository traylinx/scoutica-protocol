# 📄 Structured Job Posting Format

## 1. `role.json` Schema
A machine-readable job definition that allows candidate agents to algorithmically score fit.

```json
{
  "$schema": "https://schema.scoutica.com/v1/role.json",
  "job_id": "req_88f9a2",
  "title": "Senior AI Architect",
  "status": "active",
  "posted_at": "2026-03-25T10:00:00Z",
  "requirements": {
    "hard_skills": ["Python", "Agentic AI", "PostgreSQL"],
    "soft_skills": ["System Design", "Mentorship"],
    "minimum_years_experience": 8
  },
  "compensation": {
    "currency": "EUR",
    "base_min": 100000,
    "base_max": 140000,
    "equity_offered": true
  },
  "location": {
    "type": "remote",
    "regions_allowed": ["EU", "UK", "US-East"]
  }
}
```

## 2. Deterministic Matching Algorithm
When an Employer agent evaluates a Candidate card (or vice-versa), the scoring is deterministic:

1. **Hard Filter (Pass/Fail):**
   - Does Candidate `location` match Role `regions_allowed`?
   - Does Candidate `salary_min` fit inside Role `compensation`?
   - Does Candidate `languages` overlap required languages?
   - *If any fail → Drop.*

2. **Skill Score (0-100):**
   - Ratio of Role `hard_skills` present in Candidate `skills` array.
   - Example: 2/3 required skills matched = 66 points.

3. **Bonus Variables (+X pts):**
   - Verified Evidence matching key role technologies (+10).
   - Past titles semantically matching Role title (+15).

4. **Verdict Trigger:**
   - Score >= 80: **Auto-Ping (Strong Match)**
   - Score 60-79: **Human Review Queue**
   - Score < 60: **Reject/Ignore**

## 3. Ghost Job Prevention
- Jobs mathematically "decay" after 30 days unless cryptographic proof of active interviewing is published to the chain/registry.
- `status` must be actively refreshed by the Recruiter agent via the API.
