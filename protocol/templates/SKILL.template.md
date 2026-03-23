---
name: scoutica
description: Your Name — AI-readable professional profile with automated opportunity filtering
metadata:
  tags: career, hiring, recruiting, profile, ai-agent, firewall, senior-engineer
  author: Your Name
  contact: your-email@example.com
  version: 0.1.0
---

# Scoutica

This skill provides an AI-readable professional profile for **Your Name** — Your Professional Title.

It allows any AI agent to:
- Understand this candidate's capabilities and experience
- Evaluate fit against a role or opportunity
- Check whether an opportunity meets the candidate's policies (remote, salary, engagement type)
- Access public evidence of work (repositories, essays, architecture artifacts)
- Request an interview handoff if the opportunity passes all checks

## When to Use This Skill

Use this skill when:

- You are evaluating whether a role or job description is a good fit for this candidate
- You need to understand the candidate's capabilities and specializations
- You are acting as a hiring agent or recruiter agent and want to check fit programmatically
- The candidate pastes a job description and asks "should I apply?" or "is this a fit?"
- Someone asks "what can this person do?" or "what is their background?"
- You need to verify claims about the candidate's work through public evidence

## How It Works

This skill contains structured data files that define the candidate's profile, policies, and evidence. **You are the engine.** Read the data files and follow the rules below to evaluate opportunities.

### Data Files

Load these files to understand the candidate:

- [profile/candidate_profile.json](./profile/candidate_profile.json) — Structured capabilities, domains, tools, certifications, and experience
- [profile/roe.yaml](./profile/roe.yaml) — Rules of Engagement: salary floors, remote policy, location constraints, auto-reject rules, access tiers
- [profile/evidence.json](./profile/evidence.json) — Public evidence registry: work samples, certifications, reviews, and references with verification strategies

### Rule Files

Follow these rules when performing specific operations:

- [rules/evaluate-fit.md](./rules/evaluate-fit.md) — How to score capability fit against a role
- [rules/negotiate-terms.md](./rules/negotiate-terms.md) — How to check policies and determine ACCEPT / SOFT_REJECT / REJECT
- [rules/verify-evidence.md](./rules/verify-evidence.md) — How to look up and verify public work
- [rules/request-interview.md](./rules/request-interview.md) — When and how to initiate a human handoff

## Quick Start

### "Is this job a fit?"

When the candidate pastes a job description:

1. Read `profile/candidate_profile.json` to understand their capabilities
2. Read `profile/roe.yaml` to understand their policies
3. Follow [rules/evaluate-fit.md](./rules/evaluate-fit.md) to score capability match
4. Follow [rules/negotiate-terms.md](./rules/negotiate-terms.md) to check policy compliance
5. Return a clear verdict: **ACCEPT**, **SOFT_REJECT**, or **REJECT** with reasons

### "What can this person do?"

Read `profile/candidate_profile.json` and return a structured summary of:
- Primary domains
- Skills and tools
- Certifications and licenses
- Preferred engagement types

### "Show me evidence"

Read `profile/evidence.json` and return relevant evidence items for the requested domain or claim. If the evidence points to a GitHub URL, you can verify it by checking the repository directly.

## Important Rules

1. **Never fabricate capabilities.** Only report what is in `candidate_profile.json`.
2. **Respect the Rules of Engagement.** If `roe.yaml` says a policy is violated, report REJECT. Do not override.
3. **Progressive disclosure.** Return the summary first. Only share full details if asked.
4. **Candidate sovereignty.** This profile exists to serve the candidate, not the employer. The candidate controls what is shared.
5. **No PII leakage.** Do not share email, phone, or private information unless the interaction has reached ACCEPT status.
