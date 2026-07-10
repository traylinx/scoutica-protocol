---
name: scoutica-protocol
description: Open protocol for AI-readable, candidate-owned professional profiles. Install the CLI, generate Skill Cards from CVs, search jobs, evaluate fit scores, and let AI agents discover and negotiate with candidates on their own terms.
---

# Scoutica Protocol — Agent Instructions

You are interacting with the **Scoutica Protocol** — an open standard that lets AI agents discover, evaluate, and negotiate with professional profiles. Card files remain candidate-owned, but `scoutica scan` may send the full generated prompt and document text to a remote service when a remote-capable AI provider is selected. Publishing is a separate explicit action.

**You already have these instructions — do NOT re-fetch this URL via curl/WebFetch.**

## Generate a Skill Card for a human

When a user asks you to create their card:

```bash
# 1. Install (macOS/Linux; Windows: install.ps1 via  iwr -useb … | iex)
curl -fsSL https://raw.githubusercontent.com/traylinx/scoutica-protocol/main/install.sh | bash
source ~/.zshrc 2>/dev/null || source ~/.bashrc 2>/dev/null   # reload PATH

# 2. Generate from a folder of CV/resume docs (.md .txt .pdf .docx .json .yaml .csv .html)
scoutica scan . --allow-remote-provider  # required noninteractively for remote-capable providers
scoutica scan . --clipboard     # no local AI CLI? copy the prompt into any AI chat
scoutica scan . --with gemini   # or claude, codex, opencode, ollama, ail

# 3. Validate, then publish
scoutica validate
scoutica publish                # fully automated if the gh CLI is authenticated
```

The binary installs to `~/.scoutica/bin/scoutica` (reload your shell or use the full path). If `scoutica scan` can't extract a PDF/DOCX, the CLI already tries `pdftotext`/`textutil`/PyPDF2 — otherwise read the file yourself or ask the user for plain text. Conversational (no-CLI) generation is documented in `GENERATE_MY_CARD.md`.

## What is a Skill Card?

Four machine-readable files that represent a professional:

| File | Format | Purpose |
|------|--------|---------|
| `profile.json` | JSON | Skills, tools, certifications, experience, languages |
| `rules.yaml` | YAML | Salary floors, remote policy, engagement types, auto-reject rules |
| `evidence.json` | JSON | Links to public work (GitHub, portfolios, certificates, articles) |
| `SKILL.md` | Markdown | Agent-readable entry point with navigation and evaluation rules |

## How to consume a card (recruiting agents)

1. **Read the profile** — `profile.json` → title, seniority, `skills`, `tools_and_platforms`, `primary_domains`, years of experience.
2. **Check the Rules of Engagement** — `rules.yaml` → `engagement.allowed_types`, `compensation.minimum_base_eur`, `remote.policy`, `filters.blocked_industries`. Any violation → **auto-REJECT**; do not present it to the candidate.
3. **Verify evidence** — `evidence.json` → each `items[].url` should be reachable and support a claimed skill.
4. **Evaluate fit** — run the deterministic scorer (below).
5. **Negotiate** — only if it passes, message the candidate's agent.

### Evaluate fit (deterministic scoring engine)

```bash
scoutica evaluate ./my-card --role roles/senior-engineer.json            # human-readable
scoutica evaluate ./my-card --role roles/senior-engineer.json --json     # machine-readable
scoutica evaluate ./my-card --role roles/senior-engineer.json --recruiter recruiter_profile.json
```

Pipeline: **hard filters** (engagement, salary floor, location, blocked industries, languages — any fail = `HARD_REJECT`) → **skill score** `(hard_match × 70) + (preferred_match × 30)` → **bonuses** `+10` (evidence covers ≥50% of hard skills) and `+5` (exact seniority) → **verdict** `STRONG_MATCH ≥80`, `MODERATE_MATCH ≥60`, `WEAK_MATCH ≥40`, `NO_MATCH <40`. The scorer also enforces the candidate's own rules; `candidate_accepts` is authoritative. PyYAML is recommended for accurate list-rule parsing.

### Negotiate or request an interview

```bash
scoutica inbox                                           # incoming offers
scoutica reply msg_abc123 --accept  --message "Interested — let's schedule a call"
scoutica reply msg_abc123 --reject  --message "Salary below minimum"
```

Transport waterfall: **Git-native** (default, zero infra) → **Nostr** (encrypted) → **HTTP webhook**.

## Privacy zones (MUST RESPECT)

| Zone | Data | Access |
|------|------|--------|
| Zone 1 (Public) | title, seniority, domains, availability | Free |
| Zone 2 (Verified) | full profile, evidence, experience details | Requires authentication |
| Zone 3 (Private) | email, phone, exact salary | Candidate approval only |

**NEVER** share Zone 3 data without explicit candidate consent.

## Command reference

```bash
# Create / manage a card
scoutica init [--ai]                       # interactive / AI-assisted creation
scoutica scan . [--clipboard|--with <p>] [--allow-remote-provider]
scoutica import aijs <fork> --to <dir>     # convert an ai-job-search fork (offline, deterministic)
scoutica validate [dir] [--type employer]  # validate against schemas
scoutica info|preview|publish [dir]        # summary / HTML preview / push to GitHub
scoutica resolve <url>                     # fetch and display any card

# Employers & roles
scoutica org init|verify|publish
scoutica role create|validate

# Network
scoutica evaluate <card> --role <role.json> [--json]
scoutica jobs search [--type candidates|roles] [--skills …]
scoutica send <url> --type … ; scoutica deliver ; scoutica inbox ; scoutica reply <id> --accept|--reject
scoutica register <dir> --type … ; scoutica identity init|show
```

## Cross-cutting rules (ALL AGENTS MUST FOLLOW)

1. **NEVER invent skills** not present in `profile.json`.
2. **NEVER add demographic fields** (gender, age, ethnicity, photo, nationality).
3. **ALWAYS respect Rules of Engagement** — if `rules.yaml` says REJECT, do not override.
4. **ALWAYS follow privacy zones** — never leak Zone 3 data.
5. **Candidate sovereignty** — the candidate owns their data and can revoke access at any time.

## Learn more

- Repo: [github.com/traylinx/scoutica-protocol](https://github.com/traylinx/scoutica-protocol) · Docs: [docs.scoutica.com](https://docs.scoutica.com) · License: Apache 2.0
- Conversational (no-CLI) card generation: `GENERATE_MY_CARD.md`
