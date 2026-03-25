# 📋 Scoutica Network — Recruiter-Side Specification Index

> The complete blueprint for transforming Scoutica from a candidate-only format into a **two-sided talent protocol**.

## Context
The Scoutica Protocol v0.2.0 has a fully operational candidate-side pipeline:
- **CLI:** `scoutica scan`, `scoutica validate`, `scoutica publish`, `scoutica preview`
- **Card Format:** `profile.json`, `rules.yaml`, `evidence.json`, `SKILL.md`
- **Infrastructure:** Logging, SHA-256 text caching, timing, GitHub sync

**What's missing:** The entire recruiter/employer side — identity, job postings, discovery, communication, trust, and privacy.

---

## Document Map

| Doc | Title | Focus |
|-----|-------|-------|
| [01_AUDIT](./01_AUDIT.md) | Gap Analysis | What's missing from the candidate-only protocol |
| [02_RECRUITER_CARD](./02_RECRUITER_CARD.md) | Recruiter Identity | `recruiter_profile.json`, `hiring_rules.yaml`, `reputation.json` |
| [03_JOB_POSTING_CARD](./03_JOB_POSTING_CARD.md) | Structured Job Postings | `role.json` schema, deterministic matching algorithm |
| [04_SEARCH_API](./04_SEARCH_API.md) | Discovery Infrastructure | 3-layer architecture (GitHub → REST → Federated) |
| [05_AGENT_COMMUNICATION](./05_AGENT_COMMUNICATION.md) | Agent-to-Agent Protocol | 6 message types, Mermaid conversation flows, auth tiers |
| [06_IMPLEMENTATION_ROADMAP](./06_IMPLEMENTATION_ROADMAP.md) | Phased Build Plan | 4 phases, priority matrix, dependency graph |
| [07_SCENARIOS](./07_SCENARIOS.md) | End-to-End Scenarios | 11 real-world walkthroughs with sequence diagrams |
| [08_TRUST_REPUTATION](./08_TRUST_REPUTATION.md) | Trust & Reputation Engine | Scoring algorithms, decay functions, anti-gaming |
| [09_PRIVACY_GDPR](./09_PRIVACY_GDPR.md) | Privacy & GDPR Compliance | Zone model, data classification, consent flows |
| [10_SCHEMAS](./10_SCHEMAS.md) | Complete JSON Schemas | All recruiter-side schema definitions |
| [11_STARGATE_INTEGRATION](./11_STARGATE_INTEGRATION.md) | Traylinx Infrastructure | Maps Scoutica to Stargate, Sentinel, Agent Registry |

---

## Core Thesis

> The winning product is not an AI resume builder.  
> The winning product is the **trust and negotiation layer** between candidate agents and hiring agents.

— *From [01_THESIS_AND_CATEGORY_SHIFT](../.specs/strategy_docs/research_audits/01_THESIS_AND_CATEGORY_SHIFT.md)*

## Design Principles

1. **Symmetry:** If candidates have structured cards, recruiters must too.
2. **Accountability:** Recruiter behavior is tracked and scored (not just candidate behavior).
3. **Privacy-First:** PII is never exposed until mutual interest is established.
4. **Progressive Complexity:** Ship V1 with GitHub-only, evolve to REST API, then Federated.
5. **Anti-Spam by Default:** Every recruiter interaction costs reputation; ghosting degrades trust.
6. **Deterministic Matching:** Fit scoring is algorithmic and reproducible, not AI-hallucinated.
