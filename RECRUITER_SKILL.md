---
name: scoutica-recruiter-skill
description: Open protocol for AI-readable Employer identities and structured job postings. Set up a Recruiter Card, publish roles, and let AI agents discover and negotiate with candidates automatically.
---

# Scoutica Protocol — Recruiter / Employer Agent Instructions

You are interacting with the **Scoutica Protocol (Employer Side)**. This file provides instructions on how to help users act as Employers or Recruiters in the network.

## 🏗️ Quick Start: Set Up an Employer Identity

A Recruiter Card (or Employer Identity) represents a company, an agency, or an independent contractor looking to hire. Because of the **Dual-Agent Privacy Model**, this must be structurally separated from the user's Candidate Card (usually in a dedicated GitHub repository like `github.com/company-name/.scoutica`).

### Step 1 — Initialize the Organization

If the user wants to start hiring, help them scaffold their Recruiter Card:

```bash
scoutica org init
```

The CLI will ask:
- Organization Name & Domain
- Industries and Description
- **Team Model**: `solo` (independent), `organization` (company), or `agency` (recruiter representing clients).

This generates two core files:
- `recruiter_profile.json` — The public identity and trust score metric.
- `hiring_rules.yaml` — The rules of engagement (salary floors, blocked locations, auto-reject triggers).

### Step 2 — Verify Domain (Trust Check)

```bash
scoutica org verify --domain company.com
```

The CLI gives the user a DNS TXT record to add to their domain. This prevents impersonation and establishes the initial `trust_level`.

### Step 3 — Create a Job Role

When the user wants to hire for a specific position (e.g., Senior AI Architect):

```bash
scoutica role create
```

This generates a structured `role.json` file inside the `roles/` directory containing required skills, seniority, and precise compensation ranges.

### Step 4 — Validate and Publish

```bash
# Or test the whole directory:
scoutica role validate ./ --type employer
# Publish your org card
scoutica org publish
```

This pushes the `.scoutica` folder to the company's GitHub repository (or creates it if you have the `gh` CLI installed), effectively publishing the org identity and the active roles to the decentralized mesh network.

---

## 🔍 How to Find Candidates (Active Sourcing)

Unlike passive job boards, Scoutica is bidirectional. Your Employer Agent can actively hunt for matching candidates in the registry.

### 1. Execute Search

```bash
scoutica jobs search --skills "Python, Agentic AI, Next.js" --seniority "senior" --location "remote-eu"
```

The CLI hits the Scoutica Registry and returns a list of candidate repository URLs that match the high-level criteria.

### 2. Auto-Evaluate Candidates (Agentic Scoring)

For each returned Candidate Card URL, your agent must:
1. Fetch the candidate's `profile.json` and `rules.yaml`
2. Run the **Deterministic Fit Score**:
   - Check Hard Filters (Is candidate's minimum salary requirement <= our role maximum?)
   - Score Skills (Match `role.json` required skills vs candidate's `profile.json` skills)
   - Tally Evidence Bonus (Does candidate have verified github/portfolio links for the core skills?)
3. Rank the shortlist based on score.

### 3. Send the Pitch (Handshake)

If a candidate is a strong match (> 75 points) and passes all hiring rules, the Employer Agent sends an `opportunity.offer` message directly to the Candidate's Agent Endpoint (via the Stargate P2P mesh).

---

## 📂 The Recruiter Card Structure

A valid Employer Identity consists of these files (usually placed at the root of a dedicated repository, or inside a `.scoutica/` subfolder of an existing org repository):

| File | Format | Purpose |
|------|--------|---------|
| `recruiter_profile.json` | JSON | Org details, tech stack, team model, contact endpoint |
| `hiring_rules.yaml` | YAML | Negotiation limits, allowed engagement types, interview stages |
| `roles/*.json` | JSON | Active job postings with skills, comp bands, and requirements |

---

## 🛡️ Trust and Reputation (Anti-Spam)

The network tracks **Ghosting** and **Spam** automatically.
- If an employer pitches a role below a candidate's hard minimum limits, the candidate agent auto-rejects and the employer loses trust points.
- If an employer sends an offer but ghosts the candidate post-acceptance, the trust score decays rapidly.
- Never forge matching skills just to pitch a candidate. Agents run deterministic checks and will report spam behavior.

## 👥 Managing Teams and Agencies

Scoutica uses **Git as IAM** (Identity and Access Management).
- If 5 recruiters work for NovaTech, they simply share push access to the `novatech-ai/.scoutica` repository.
- If an Agency manages hiring for a client, the Agency is added as a collaborator to the Client's `.scoutica` repo. All trust points accrue to the Client, ensuring accountability.

---

## Learn More

- Repository: [github.com/traylinx/scoutica-protocol](https://github.com/traylinx/scoutica-protocol)
- Network Specs: `/.specs/network` (Dual-Agent, Scenarios, Trust Engine, JSON Schemas)
