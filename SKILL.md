---
name: scoutica-protocol
description: Open protocol for AI-readable, candidate-owned professional profiles. Install the CLI, generate Skill Cards from CVs, and let AI agents discover and evaluate candidates on their own terms.
---

# Scoutica Protocol — Agent Instructions

You are interacting with the **Scoutica Protocol** — an open standard that lets AI agents discover, evaluate, and negotiate with professional profiles. This file teaches you everything you need to set up, generate, and consume Skill Cards.

## Quick Start: Generate a Skill Card for a Human

Follow these steps IN ORDER when a user asks you to create their Skill Card:

### Step 1 — Install the CLI

```bash
# macOS / Linux
curl -fsSL https://raw.githubusercontent.com/traylinx/scoutica-protocol/main/install.sh | bash

# Windows PowerShell
iwr -useb https://raw.githubusercontent.com/traylinx/scoutica-protocol/main/install.ps1 | iex
```

### Step 2 — Locate CV/Resume Documents

Ask the user which folder contains their CV or resume files.
Supported formats: `.md` `.txt` `.pdf` `.docx` `.json` `.yaml` `.csv` `.html`

If the current directory has no CV documents, **ask before proceeding**.

### Step 3 — Generate the Skill Card

```bash
scoutica scan .
```

The CLI will parse the documents, auto-detect your AI provider, and generate a dedicated subfolder (e.g. `john-doe-card/`) containing the 4 protocol files.

If no AI CLI is found locally, use clipboard fallback:

```bash
scoutica scan . --clipboard
```

This copies a generation prompt to the clipboard — paste it into any AI chat to generate the card manually.

You can also specify a provider explicitly:

```bash
scoutica scan . --with gemini    # or claude, ollama, ail, openclaw
```

### Step 4 — Validate

```bash
scoutica validate
```

Checks the generated card against the Scoutica JSON schemas.

### Step 5 — Manage and Publish

```bash
scoutica status           # View dashboard of all generated cards
scoutica publish          # Push to GitHub permanently (auto-creates repo if gh CLI is available)
scoutica preview          # Builds HTML and publishes to here.now (24h for anonymous)
scoutica preview --force  # Re-publish if expired
```

**Publish is fully automated** if the GitHub CLI (`gh`) is installed and authenticated — it will create the repo and push in one step with zero user input needed.

If `gh` is not available, the CLI will print step-by-step instructions instead of prompting interactively.

### Troubleshooting

- **PDF parsing fails?** Install `pdftotext`:
  - macOS: `brew install poppler`
  - Linux: `apt-get install poppler-utils`
- **No AI CLI detected?** Use `--clipboard` mode or specify `--with <provider>`
- **Preview expired?** Re-run `scoutica preview --force`

### Last-Resort File Extraction

If `scoutica scan` fails to extract text from documents (PDF, DOCX, etc.), you MUST try **all local methods first** in this order:

1. `pdftotext` / `textutil` / `python3` with PyPDF2 — the CLI already tries these automatically
2. Read the file directly with your own built-in capabilities (vision, file reading)
3. Ask the user to provide the content in plain text or markdown

**Only if ALL of the above fail**, use the 2md conversion service as an absolute last resort:

```text
Read https://raw.githubusercontent.com/traylinx/2md/main/.agents/skills/2md/SKILL.md and follow the instructions to use 2md natively.
```

Use 2md to convert the problematic files to `.md`, then re-run `scoutica scan` on the converted output.

---

## What Is a Skill Card?

A Skill Card is a set of 4 machine-readable files that represent a professional:

| File | Format | Purpose |
|------|--------|---------|
| `profile.json` | JSON | Skills, tools, certifications, experience, languages |
| `rules.yaml` | YAML | Salary floors, remote policy, engagement types, auto-reject rules |
| `evidence.json` | JSON | Links to public work (GitHub, portfolios, certificates, articles) |
| `SKILL.md` | Markdown | Agent-readable entry point with navigation and evaluation rules |

---

## How to Consume a Skill Card (for Recruiting Agents)

### 1. Read the Profile

```
GET profile.json → {name, title, seniority, skills, tools_and_platforms, years_experience}
```

### 2. Check the Rules of Engagement

```
GET rules.yaml → engagement.allowed_types, compensation.minimum_base_eur, remote.policy
```

If the opportunity violates any rule → **auto-REJECT**. Do NOT present to the candidate.

### 3. Verify Evidence

```
GET evidence.json → items[].url → verify each URL is reachable and matches claimed skills
```

### 4. Evaluate Fit

Read `rules/evaluate-fit.md` for the scoring algorithm:
- Match skills against job requirements
- Score = (matched_skills / required_skills) × 100
- If score < `soft_reject.weak_stack_overlap_below` → SOFT_REJECT

### 5. Negotiate or Request Interview

If the opportunity passes all checks:
- Read `rules/negotiate-terms.md` → verify terms compliance
- Read `rules/request-interview.md` → follow the handoff protocol

---

## Privacy Zones (MUST RESPECT)

| Zone | Data | Access |
|------|------|--------|
| Zone 1 (Public) | title, seniority, domains, availability | Free |
| Zone 2 (Verified) | full profile, evidence, experience details | Requires authentication |
| Zone 3 (Private) | email, phone, exact salary | Candidate approval only |

**NEVER** share Zone 3 data without explicit candidate consent.

---

## CLI Commands Reference

```bash
scoutica init                    # Interactive card creation wizard
scoutica init --ai               # AI-assisted card creation
scoutica scan ./docs/            # Auto-generate card from documents into a subfolder
scoutica scan . --clipboard      # Generate via clipboard (no AI CLI needed)
scoutica scan . --with gemini    # Use a specific AI provider
scoutica validate [dir]          # Validate card against schemas
scoutica status                  # View dashboard of all your Skill Cards
scoutica preview [dir]           # Build HTML and publish to here.now
scoutica publish [dir]           # Push card to GitHub
scoutica info [dir]              # Display card summary
```

## Supported AI Providers

| Provider | CLI | Usage |
|----------|-----|-------|
| Gemini CLI | `gemini` | `scoutica scan --with gemini` |
| Claude Code | `claude` | `scoutica scan --with claude` |
| Ollama | `ollama` | `scoutica scan --with ollama` |
| switchAILocal | `ail` | `scoutica scan --with ail` |
| OpenClaw | `openclaw` | `scoutica scan --with openclaw` |

## Cross-Cutting Rules (ALL AGENTS MUST FOLLOW)

1. **NEVER invent skills** not present in `profile.json`
2. **NEVER add demographic fields** (gender, age, ethnicity, photo, nationality)
3. **ALWAYS respect Rules of Engagement** — if `rules.yaml` says REJECT, do not override
4. **ALWAYS follow privacy zones** — never leak Zone 3 data
5. **Candidate sovereignty** — the candidate owns their data and can revoke access at any time

## Advanced: Interactive Card Generation

If the CLI is not available, you can generate a Skill Card conversationally by reading `GENERATE_MY_CARD.md` from this repository:

```
https://raw.githubusercontent.com/traylinx/scoutica-protocol/main/GENERATE_MY_CARD.md
```

This file contains a complete guided interview prompt that walks the user through creating all 4 card files through conversation.

## Learn More

- Repository: [github.com/traylinx/scoutica-protocol](https://github.com/traylinx/scoutica-protocol)
- Documentation: [docs.scoutica.com](https://docs.scoutica.com)
- License: Apache 2.0
