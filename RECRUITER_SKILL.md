---
name: scoutica-recruiter-skill
description: Open protocol for AI-readable Employer identities, structured job postings, deterministic fit scoring, and agent-to-agent communication. Set up a Recruiter Card, publish roles, discover candidates, and negotiate automatically via Git-native or Nostr transport.
---

# Scoutica Protocol — Recruiter / Employer Agent Instructions

You are interacting with the **Scoutica Protocol (Employer Side) v0.4.0**. This file provides instructions on how to help users act as Employers or Recruiters in the network.

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
scoutica role validate ./
scoutica org publish
```

This pushes the `.scoutica` folder to the company's GitHub repository, effectively publishing the org identity and the active roles to the network.

---

## 🔍 How to Find Candidates (Active Sourcing)

Unlike passive job boards, Scoutica is bidirectional. Your Employer Agent can actively hunt for matching candidates in the registry.

### 1. Search the Network

```bash
# Search for senior Python engineers available immediately
scoutica jobs search --type candidates --skills "Python,Kubernetes" --seniority senior

# Search with a local registry file (for testing)
scoutica jobs search --type candidates --local protocol/registry/candidates/index.json --skills Python
```

The CLI downloads the registry index and returns matching candidates.

### 2. Evaluate Candidates (Deterministic Fit Scoring)

For each candidate, run the fit scoring engine:

```bash
# Score a candidate card against your role
scoutica evaluate ./candidate-card roles/senior-ai-architect.json --recruiter recruiter_profile.json

# Get machine-readable JSON output
scoutica evaluate ./candidate-card roles/senior-ai-architect.json --json
```

The scoring pipeline:
1. **Hard Filters** — Engagement type, minimum salary, location policy, blocked industries, language requirements. Any failure = `HARD_REJECT`.
2. **Skill Score (0-100)** — `(hard_skill_match × 70) + (preferred_skill_match × 30)`.
3. **Bonuses** — +10 evidence, +5 seniority match, +5 freshness.
4. **Verdict** — `STRONG_MATCH` (≥80), `MODERATE_MATCH` (≥60), `WEAK_MATCH` (≥40), `NO_MATCH` (<40).

The engine also runs **candidate-side evaluation** — checking if the candidate's `rules.yaml` would auto-accept or auto-reject your role.

### 3. Send the Pitch

If a candidate is a strong match (≥ 75 points), send an offer:

```bash
# Send an offer with the role attached
scoutica send https://github.com/candidate/.scoutica \
  --type opportunity.offer \
  --role roles/senior-ai-architect.json \
  --message "We think you'd be a great fit"

# Check your outbox
scoutica inbox
```

Messages are created as structured JSON envelopes and queued for delivery via the transport layer.

### 4. Register Your Roles on the Network

```bash
# Generate a registry entry from your employer card
scoutica register . --type roles

# This creates a staged entry you can submit as a PR to the registry
```

---

## 📬 Message Flow

The protocol supports 8 message types:

| Type | Direction | Description |
|------|-----------|-------------|
| `rules.check` | Employer → Candidate | Pre-screen — "Would your rules reject this?" |
| `opportunity.pitch` | Employer → Candidate | Soft interest, no commitment |
| `opportunity.offer` | Employer → Candidate | Formal offer with role + comp |
| `response.accept` | Candidate → Employer | Rules passed, candidate interested |
| `response.reject` | Candidate → Employer | Auto or manual rejection with reasons |
| `response.withdraw` | Either → Either | Withdraw from conversation |
| `status.check` | Either → Either | "Is this still active?" |
| `event.ghosting` | System | Triggered when SLA expires without response |

### Transport Layer (Resolution Waterfall)

Messages are delivered via the first available method:
1. **Webhook** — Direct HTTP POST to `agent_endpoint` (if configured)
2. **Nostr** — Encrypted event to relay (if `transport.nostr.pubkey` is set)
3. **Git Inbox** — JSON file deposited in registry inbox via PR (always available)

```bash
# Generate your Nostr identity for encrypted messaging
scoutica identity init

# Check your public key
scoutica identity show
```

---

## 📂 The Recruiter Card Structure

| File | Format | Purpose |
|------|--------|---------|
| `recruiter_profile.json` | JSON | Org details, tech stack, team model, contact endpoint |
| `hiring_rules.yaml` | YAML | Negotiation limits, allowed engagement types, interview stages |
| `roles/*.json` | JSON | Active job postings with skills, comp bands, and requirements |
| `scoutica.json` | JSON | Discovery file with transport preferences (Nostr pubkey, relays) |

---

## 🛡️ Trust and Reputation (Anti-Spam)

The network tracks **Ghosting** and **Spam** automatically.
- If an employer pitches a role below a candidate's hard minimum limits, the candidate agent auto-rejects and the employer loses trust points.
- If an employer sends an offer but ghosts the candidate post-acceptance, the trust score decays rapidly.
- Never forge matching skills just to pitch a candidate. Agents run deterministic checks and will report spam behavior.
- All message sends and replies are logged to `~/.scoutica/privacy/access_log.jsonl` for audit.

## 👥 Managing Teams and Agencies

Scoutica uses **Git as IAM** (Identity and Access Management).
- If 5 recruiters work for NovaTech, they simply share push access to the `novatech-ai/.scoutica` repository.
- If an Agency manages hiring for a client, the Agency is added as a collaborator to the Client's `.scoutica` repo. All trust points accrue to the Client, ensuring accountability.

---

## 📋 Full Command Reference (Employer-Side)

```
scoutica org init              Create Recruiter/Employer Identity Card
scoutica org verify --domain   Verify domain ownership (DNS TXT)
scoutica org publish           Push employer card to GitHub
scoutica role create           Create a structured job posting
scoutica role validate [dir]   Validate role(s) against schemas
scoutica evaluate <card> <role>  Deterministic fit scoring
scoutica jobs search           Search the registry
scoutica send <url> --type ... Send a message to another agent
scoutica inbox                 Check incoming messages
scoutica reply <id> --accept   Accept/reject/withdraw
scoutica deliver               Push pending messages
scoutica register --type roles Generate registry entry
scoutica identity init         Generate Nostr keypair
```

---

## Learn More

- Repository: [github.com/traylinx/scoutica-protocol](https://github.com/traylinx/scoutica-protocol)
- Network Specs: `/.specs/network/` (Transport Architecture, Agent Communication, Trust Engine)
- Transport Architecture: `/.specs/network/13_TRANSPORT_ARCHITECTURE.md`
- Architecture Deep-Dive: `/.specs/network/12_ARCHITECTURE_DEEP_DIVE.md`
