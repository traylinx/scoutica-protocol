---
name: scoutica-protocol
description: Open protocol for AI-readable, candidate-owned professional profiles. This skill tells any visiting AI agent how to consume, evaluate, and interact with Scoutica Skill Cards.
---

# Scoutica Protocol — Agent Instructions

You are visiting the **Scoutica Protocol** repository. This is an open protocol that standardizes how AI agents discover, evaluate, and interact with professional profiles.

## What Is a Skill Card?

A Skill Card is a set of 4 machine-readable files that represent a professional:

| File | Format | Purpose |
|------|--------|---------|
| `profile.json` | JSON | Skills, tools, certifications, experience, languages |
| `rules.yaml` | YAML | Salary floors, remote policy, engagement types, auto-reject rules |
| `evidence.json` | JSON | Links to public work (GitHub, portfolios, certificates, articles) |
| `SKILL.md` | Markdown | Agent-readable entry point with navigation and evaluation rules |

## How to Consume a Skill Card

### Step 1: Read the Profile

```json
GET profile.json → {name, title, seniority, skills, tools_and_platforms, years_experience}
```

### Step 2: Check the Rules of Engagement

```yaml
GET rules.yaml → engagement.allowed_types, compensation.minimum_base_eur, remote.policy
```

If the opportunity violates any rule → **auto-REJECT**. Do NOT present to the candidate.

### Step 3: Verify Evidence

```json
GET evidence.json → items[].url → verify each URL is reachable and matches claimed skills
```

### Step 4: Evaluate Fit

Read `rules/evaluate-fit.md` for the scoring algorithm:
- Match skills against job requirements
- Score = (matched_skills / required_skills) × 100
- If score < `soft_reject.weak_stack_overlap_below` → SOFT_REJECT

### Step 5: Negotiate or Request Interview

If the opportunity passes all checks:
- Read `rules/negotiate-terms.md` → verify terms compliance
- Read `rules/request-interview.md` → follow the handoff protocol

## Privacy Zones (MUST RESPECT)

| Zone | Data | Access |
|------|------|--------|
| Zone 1 (Public) | title, seniority, domains, availability | Free |
| Zone 2 (Verified) | full profile, evidence, experience details | Requires authentication |
| Zone 3 (Private) | email, phone, exact salary | Candidate approval only |

**NEVER** share Zone 3 data without explicit candidate consent.

## Repository Structure

```
scoutica-protocol/
├── README.md                    # Project overview and quick start
├── GENERATE_MY_CARD.md          # AI-guided card creation prompt
├── SKILL.md                     # ← You are here (agent instructions)
├── schemas/                     # JSON Schema definitions
│   ├── candidate_profile.schema.json
│   ├── evidence.schema.json
│   └── rules_of_engagement.schema.json
├── tools/                       # CLI and utilities
│   ├── scoutica                 # Bash CLI (macOS/Linux)
│   ├── scoutica.ps1             # PowerShell CLI (Windows)
│   ├── validate_card.py         # Card validator
│   └── SCAN_PROMPT.md           # AI scan system prompt
├── templates/rules/             # Evaluation rule templates
├── protocol/                    # Protocol specifications
│   ├── examples/sample_card/    # Working example card
│   └── platform/                # Platform build specs
├── install.sh                   # macOS/Linux installer
├── install.ps1                  # Windows installer
└── .specs/                      # Architecture specs and flow docs
    ├── protocol_flows.md        # Sequence diagrams for all scenarios
    ├── protocol_ecosystem.md    # Ecosystem analysis
    └── cli_audit.md             # Cross-platform CLI audit report
```

## CLI Commands

```bash
scoutica init                    # Interactive card creation wizard
scoutica init --ai               # AI-assisted card creation
scoutica scan ./docs/            # Auto-generate card from documents (local AI CLI)
scoutica validate [dir]          # Validate card against schemas
scoutica publish [dir]           # Push card to GitHub
scoutica info [dir]              # Display card summary
```

## Cross-Cutting Rules (ALL AGENTS MUST FOLLOW)

1. **NEVER invent skills** not present in `profile.json`
2. **NEVER add demographic fields** (gender, age, ethnicity, photo, nationality)
3. **ALWAYS respect Rules of Engagement** — if `rules.yaml` says REJECT, do not override
4. **ALWAYS follow privacy zones** — never leak Zone 3 data
5. **Candidate sovereignty** — the candidate owns their data and can revoke access at any time

## Supported Providers for Card Generation

| Provider | CLI | How It's Used |
|----------|-----|---------------|
| Gemini CLI | `gemini` | `scoutica scan --with gemini` |
| Claude Code | `claude` | `scoutica scan --with claude` |
| Ollama | `ollama` | `scoutica scan --with ollama` |
| switchAILocal | `ail` | `scoutica scan --with ail` |

## Learn More

- Repository: [github.com/traylinx/scoutica-protocol](https://github.com/traylinx/scoutica-protocol)
- License: Open source
