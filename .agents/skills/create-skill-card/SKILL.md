---
name: create-skill-card
description: Create a Scoutica Skill Card from candidate documents. Use when asked to generate a professional profile, build a skill card, or convert a CV/resume into a machine-readable format. Reads documents from a folder and outputs 4 structured files (profile.json, rules.yaml, evidence.json, SKILL.md).
---

# create-skill-card

Generate a complete Scoutica Skill Card from candidate documents (CVs, portfolios, certifications).

## When to Use

- User asks you to "create my card" or "generate my profile"
- User wants to convert a CV/resume into Scoutica format
- User drops documents and asks for a professional profile
- User says "scoutica scan" or references card generation

## Quick Method: Use the CLI

```bash
# Auto-detect local AI CLI and generate
scoutica scan <docs-folder> --output <card-folder>

# Or with a specific provider
scoutica scan <docs-folder> --with gemini
scoutica scan <docs-folder> --with claude
scoutica scan <docs-folder> --with ollama
scoutica scan <docs-folder> --with ail
```

## Manual Method: Read Docs and Generate Directly

If you are the AI agent being asked to generate the card, follow these steps:

### Step 1: Read All Documents

Read every supported file in the user's folder:
- Text: `.md`, `.txt`, `.json`, `.yaml`, `.csv`, `.html`
- PDFs: extract text via `pdftotext` or `python3 -c "import PyPDF2; ..."`
- DOCX: extract via `textutil` (macOS) or `python-docx`

### Step 2: Generate profile.json

```json
{
  "schema_version": "0.1.0",
  "name": "Full Name",
  "title": "Professional Title",
  "seniority": "senior",
  "years_experience": 10,
  "availability": "in_2_weeks",
  "domains": ["Backend Engineering", "DevOps"],
  "skills": {
    "languages": ["Python", "Go", "TypeScript"],
    "frameworks": ["Django", "FastAPI", "React"],
    "tools_and_platforms": ["Kubernetes", "AWS", "Docker", "PostgreSQL"],
    "certifications": ["AWS Solutions Architect"],
    "soft_skills": ["Technical Leadership", "System Design"]
  },
  "languages": [
    {"language": "English", "proficiency": "native"},
    {"language": "German", "proficiency": "fluent"}
  ],
  "experience": [
    {
      "company": "Company Name",
      "role": "Senior Engineer",
      "duration": "2020-2024",
      "highlights": ["Built X", "Led Y team"]
    }
  ]
}
```

**Rules:**
- NEVER invent skills not found in the documents
- Use standardized names (e.g., "Kubernetes" not "K8s")
- Map seniority from context: "Lead" → "lead", "Manager" → "manager"

### Step 3: Generate rules.yaml

```yaml
engagement:
  allowed_types:
    - full_time
    - contract
  notice_period: "30 days"

compensation:
  minimum_base_eur: negotiable
  equity_required: false

remote:
  policy: remote_first
  timezone_range: "UTC-1 to UTC+3"

auto_reject:
  blocked_industries:
    - gambling
    - weapons
  no_relocation: true

soft_reject:
  weak_stack_overlap_below: 40
```

**Rules:**
- Use "negotiable" if salary info is not in the documents
- Default `remote.policy` to "flexible" if not stated
- Only add `blocked_industries` if explicitly mentioned

### Step 4: Generate evidence.json

```json
{
  "items": [
    {
      "type": "github_repo",
      "title": "Project Name",
      "url": "https://github.com/user/repo",
      "skills": ["Python", "FastAPI"],
      "description": "Brief description"
    },
    {
      "type": "certification",
      "title": "AWS Solutions Architect",
      "url": "https://verify.link",
      "skills": ["AWS"],
      "issued": "2024"
    }
  ]
}
```

**Rules:**
- Only include URLs found in the documents
- NEVER fabricate links
- Types: `github_repo`, `website`, `certification`, `article`, `talk`, `portfolio`

### Step 5: Generate SKILL.md

Use the template in `templates/card/SKILL.md` or generate:

```markdown
---
name: scoutica
description: <Name> — AI-readable professional profile
metadata:
  author: <Name>
  version: 0.1.0
---

# Scoutica

Professional profile for **<Name>** — <Title>.
[... standard structure ...]
```

### Step 6: Copy Rule Templates

Copy evaluation rules from `templates/rules/`:
- `evaluate-fit.md`
- `negotiate-terms.md`
- `verify-evidence.md`
- `request-interview.md`

### Step 7: Validate

```bash
scoutica validate <card-folder>
```

## Output Structure

```
<card-folder>/
├── profile.json
├── rules.yaml
├── evidence.json
├── SKILL.md
└── rules/
    ├── evaluate-fit.md
    ├── negotiate-terms.md
    ├── verify-evidence.md
    └── request-interview.md
```

## Schema Reference

See `schemas/candidate_profile.schema.json` for the full JSON Schema validation spec.
