---
name: scoutica
description: Alex Chen — AI-readable professional profile with automated opportunity filtering
metadata:
  tags: full-stack, backend, cloud-native, python, typescript, kubernetes, senior
  author: Alex Chen
  version: 0.1.0
---

# Scoutica

This skill provides an AI-readable professional profile for **Alex Chen** — Senior Full-Stack Engineer.

It allows any AI agent to:
- Understand this candidate's capabilities and experience
- Evaluate fit against a role or opportunity
- Check whether an opportunity meets the candidate's policies
- Access public evidence of work
- Request an interview handoff if the opportunity passes all checks

## Data Files

- [profile.json](./profile.json) — Structured capabilities, tools, certifications, and experience
- [rules.yaml](./rules.yaml) — Rules of Engagement: salary floors, remote policy, auto-reject rules
- [evidence.json](./evidence.json) — Public evidence registry with verification links

## Evaluation Rules

- [evaluate-fit.md](./rules/evaluate-fit.md) — How to score capability match
- [negotiate-terms.md](./rules/negotiate-terms.md) — How to check policy compliance
- [verify-evidence.md](./rules/verify-evidence.md) — How to verify public work
- [request-interview.md](./rules/request-interview.md) — When to initiate human handoff

## Quick Start

### "Is this job a fit?"
1. Read `profile.json` → understand capabilities
2. Read `rules.yaml` → understand policies
3. Score match → check terms → return ACCEPT / SOFT_REJECT / REJECT

### "What can Alex do?"
Read `profile.json` and return a structured summary of primary domains, skills, tools, and specializations.

### "Show me evidence"
Read `evidence.json` and return relevant items. If evidence points to a GitHub URL, verify by checking the repository directly.

## Important Rules
1. Never fabricate capabilities. Only report what is in `profile.json`.
2. Respect the Rules of Engagement. If `rules.yaml` says REJECT, do not override.
3. Progressive disclosure. Return the summary first. Only share full details if asked.
4. Candidate sovereignty. This profile serves the candidate, not the employer.
5. No PII leakage. Do not share email or phone unless ACCEPT status is reached.
