# 📋 Scoutica Network — Specification Index

> The complete blueprint for the Scoutica Protocol's **two-sided talent network** — from identity to discovery to negotiation.

## Status: v0.4.0

The protocol now has a fully operational **bidirectional pipeline** with live scoring, messaging, and registry discovery:

- **Candidate Side:** `scan`, `validate`, `publish`, `preview`, `inbox`, `reply`, `evaluate`
- **Employer Side:** `org init`, `role create`, `send`, `jobs search`, `register`
- **Network:** Git-native messaging, Nostr identity (placeholder), deterministic scoring engine
- **Registry:** Candidates + Roles index schemas, seed data, search with filtering

---

## Document Map

| Doc | Title | Status |
|-----|-------|--------|
| [01_AUDIT](./01_AUDIT.md) | Gap Analysis | ✅ Complete |
| [02_RECRUITER_CARD](./02_RECRUITER_CARD.md) | Recruiter Identity | ✅ Implemented |
| [03_JOB_POSTING_CARD](./03_JOB_POSTING_CARD.md) | Structured Job Postings | ✅ Implemented |
| [04_SEARCH_API](./04_SEARCH_API.md) | Discovery Infrastructure | ✅ Registry + CLI search live |
| [05_AGENT_COMMUNICATION](./05_AGENT_COMMUNICATION.md) | Agent-to-Agent Protocol | ✅ 8 msg types, send/inbox/reply live |
| [06_IMPLEMENTATION_ROADMAP](./06_IMPLEMENTATION_ROADMAP.md) | Phased Build Plan | 🔧 Phase 1-2 done, Phase 3-4 next |
| [07_SCENARIOS](./07_SCENARIOS.md) | End-to-End Scenarios | ✅ Tested end-to-end |
| [08_TRUST_REPUTATION](./08_TRUST_REPUTATION.md) | Trust & Reputation Engine | 📋 Spec only |
| [09_PRIVACY_GDPR](./09_PRIVACY_GDPR.md) | Privacy & GDPR Compliance | ✅ Privacy log live |
| [10_SCHEMAS](./10_SCHEMAS.md) | Complete JSON Schemas | ✅ All schemas live |
| [11_STARGATE_INTEGRATION](./11_STARGATE_INTEGRATION.md) | ⚠️ ARCHIVED | Replaced by open transport |
| [12_ARCHITECTURE_DEEP_DIVE](./12_ARCHITECTURE_DEEP_DIVE.md) | Execution Audit | ✅ Updated |
| [13_TRANSPORT_ARCHITECTURE](./13_TRANSPORT_ARCHITECTURE.md) | Transport ADR | ✅ Git + Nostr identity live |

## New in v0.4.0

| Component | File | Description |
|-----------|------|-------------|
| Scoring Engine | `tools/scoring.py` | Deterministic 4-step fit pipeline (zero deps) |
| Registry Schemas | `schemas/registry/` | `candidates_index.schema.json`, `roles_index.schema.json` |
| Seed Data | `protocol/registry/` | 5 candidates + 4 roles (network bootstrap) |
| 10 CLI Commands | `tools/scoutica` | evaluate, jobs, send, inbox, reply, deliver, register, identity |

---

## Core Thesis

> The winning product is not an AI resume builder.
> The winning product is the **trust and negotiation layer** between candidate agents and hiring agents.

— *From [01_THESIS_AND_CATEGORY_SHIFT](../.specs/strategy_docs/research_audits/01_THESIS_AND_CATEGORY_SHIFT.md)*

## Design Principles

1. **Symmetry:** If candidates have structured cards, recruiters must too.
2. **Accountability:** Recruiter behavior is tracked and scored (not just candidate behavior).
3. **Privacy-First:** PII is never exposed until mutual interest is established.
4. **Open Transport:** Ship V1 with Git-native, evolve to Nostr relays. No proprietary dependencies.
5. **Anti-Spam by Default:** Every recruiter interaction costs reputation; ghosting degrades trust.
6. **Deterministic Matching:** Fit scoring is algorithmic and reproducible, not AI-hallucinated.

