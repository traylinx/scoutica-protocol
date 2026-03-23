# Human Skill Card Template

> Use this template to create a Scoutica Skill Card for a **human professional**. This works for any profession — software engineers, chefs, truck drivers, account managers, designers, and beyond.

## Card Structure

A complete human skill card consists of:

```
my-scoutica-card/
├── SKILL.md           ← Main card (AI agents read this first)
├── profile.json       ← Structured capabilities and experience
├── rules.yaml         ← Rules of Engagement (salary, remote, blocked industries)
├── evidence.json      ← Links to public work as proof
└── rules/             ← Agent evaluation instructions
    ├── evaluate-fit.md
    ├── negotiate-terms.md
    ├── verify-evidence.md
    └── request-interview.md
```

## SKILL.md Template

Copy the template from `protocol/templates/SKILL.template.md` and fill in your data.

## profile.json Template

```json
{
  "schema_version": "0.1.0",
  "name": "Your Name",
  "title": "Your Professional Title",
  "seniority": "senior",
  "years_experience": 10,
  "availability": "immediately",
  "primary_domains": ["Domain 1", "Domain 2"],
  "skills": ["Skill 1", "Skill 2", "Skill 3"],
  "tools_and_platforms": ["Tool 1", "Tool 2"],
  "certifications_and_licenses": ["Cert 1"],
  "specializations": ["Specialization 1"],
  "spoken_languages": [
    {"language": "English", "level": "native"}
  ],
  "education": "Degree, Institution",
  "summary": "A 2-3 sentence professional summary."
}
```

**Validation:** Your `profile.json` must pass validation against `protocol/platform/01_schemas/candidate_profile.schema.json`.

## rules.yaml Template

```yaml
schema_version: "0.1.0"

engagement:
  allowed_types:
    - permanent
    - contract
  compensation:
    minimum_base_eur:
      permanent: 60000
      contract: 500

remote:
  policy: "remote_only"
  hybrid_locations: []

filters:
  blocked_industries:
    - "gambling"
    - "weapons"
  stack_keywords:
    preferred:
      - "Keyword 1"
      - "Keyword 2"
  soft_reject:
    weak_stack_overlap_below: 3

privacy:
  zone_1_public:
    - title
    - seniority
    - primary_domains
    - availability
  zone_2_paid:
    - full_profile
    - evidence
    - experience_details
  zone_3_private:
    - email
    - phone
    - exact_salary
```

## evidence.json Template

```json
{
  "schema_version": "0.1.0",
  "items": [
    {
      "type": "github_repo",
      "title": "Project Name",
      "url": "https://github.com/you/project",
      "description": "What this proves about your skills.",
      "skills_demonstrated": ["Skill 1", "Skill 2"]
    }
  ]
}
```

## Rules Directory

Copy the files from `protocol/templates/rules/` into your card's `rules/` directory. These contain the standard evaluation instructions that AI agents follow.

## Anti-Discrimination

The profile schema deliberately **excludes** all demographic fields. Your card contains:
- ✅ Skills, tools, certifications, domains, experience
- ❌ No gender, age, ethnicity, photo, nationality, disability

This is by design — matching happens on what you can do, not who you are.
