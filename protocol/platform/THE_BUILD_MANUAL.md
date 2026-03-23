# THE BUILD MANUAL
## Scoutica Protocol — Scalable Implementation Guide

**Version:** 0.1.0
**Status:** Active Implementation Environment
**Last Updated:** 2026-03-13

---

## What Is This Folder?

`docs_and_research/` contains the **"Why"** — the 6 pillars, economics, theory, and architecture.
`platform_build/` contains the **"How"** — every concrete file, schema, prompt, and contract needed to build the system.

This manual is your **single source of truth for implementation**. Every module backlinks to the specific research document, section, and data point that defines what to build.

---

## Complete Project Map

```
scoutica-protocol/
│
├── README.md                    ← Project overview and quick start
├── SKILL.md                     ← Agent instructions for working with this protocol
├── GENERATE_MY_CARD.md          ← Open in any AI assistant to create your card
├── CONTRIBUTING.md              ← How to contribute
│
├── protocol/                    ← THE PROTOCOL (open source, generic)
│   ├── docs/                    ← Public documentation
│   │   └── HOW_TO_CREATE_YOUR_CARD.md
│   │
│   ├── platform/                ← THE BUILD — concrete implementation files
│   │   ├── THE_BUILD_MANUAL.md  ← This file
│   │   ├── 01_schemas/          ← JSON Schemas (profile, RoE, evidence)
│   │   ├── 02_skill_patterns/   ← Card templates (human, agent, robot, team)
│   │   ├── 03_agent_rules/      ← AI agent prompts (match, negotiate, EU compliance)
│   │   ├── 04_registry_api/     ← OpenAPI spec for federated registries (future)
│   │   ├── 05_verification/     ← Trust score math, SBTs, ZKPs (future)
│   │   └── 06_economics/        ← Micro-fee routing, reputation engine (future)
│   │
│   ├── templates/               ← STARTER TEMPLATES for new users
│   │   ├── SKILL.template.md
│   │   └── rules/               ← Standard agent rule files
│   │
│   └── examples/                ← WORKING EXAMPLES
│       └── sample_card/         ← Complete example card (Alex Chen)
│
├── schemas/                     ← CAPABILITY TAXONOMY
│   └── CAPABILITY_TAXONOMY.md
│
├── reference/                   ← REFERENCE IMPLEMENTATIONS
│   ├── agent-templates/         ← FastAPI agent boilerplate
│   └── python/                  ← Pydantic models aligned with schemas
│
├── tools/                       ← CLI TOOLS
│   └── validate_card.py         ← Validate a card against JSON schemas
│
└── .specs/                      ← INTERNAL SPECS AND RESEARCH
    ├── architecture/
    ├── raw_research/
    ├── strategy_docs/
    ├── historic_prototype/
    └── test_card/               ← Test card with real data
```

---

## Module 01: Schemas — The Data Structures

📁 **Path:** `platform_build/01_schemas/`

### What to Build
The JSON Schemas that validate every card in the network. If a card doesn't pass schema validation, it's invalid. 

### Source Material (Backlinks)

| File to Create | Source Document | Key Section |
|---|---|---|
| `candidate_profile.schema.json` | [PILLAR_1_GENERATION.md](../docs_and_research/PILLAR_1_GENERATION.md) | "Required Fields" — defines `name`, `entity_type`, `capabilities`, `seniority`, `domains` |
| | [scoutica/profile/candidate_profile.json](../scoutica/profile/candidate_profile.json) | Working example of a real profile (Alice's card) |
| | [PILLAR_4_AGENTIC_EXTENSION.md](../docs_and_research/PILLAR_4_AGENTIC_EXTENSION.md) | `entity_type` field: `human`, `ai_agent`, `service`, `robot`, `team`, `organization` |
| `roe.schema.json` | [PILLAR_1_GENERATION.md](../docs_and_research/PILLAR_1_GENERATION.md) | "Rules of Engagement" — engagement types, remote, salary bands |
| | [scoutica/profile/roe.yaml](../scoutica/profile/roe.yaml) | Working example of RoE (Alice's policies) |
| | [PILLAR_5_PRIVACY_AND_SECURITY.md](../docs_and_research/PILLAR_5_PRIVACY_AND_SECURITY.md) | Zone 2 vs Zone 3 — which RoE fields are public vs private |
| | [PILLAR_6_ECONOMICS.md](../docs_and_research/PILLAR_6_ECONOMICS.md) | "ZKP Approach" — salary stored as `range_commitment` hash + `range_band` |
| `evidence.schema.json` | [PILLAR_3_VERIFICATION.md](../docs_and_research/PILLAR_3_VERIFICATION.md) | "5 Verification Levels" — what evidence is needed at each level |
| | [scoutica/profile/evidence.json](../scoutica/profile/evidence.json) | Working example (Alice's evidence entries) |
| `taxonomy.json` | [PILLAR_1_GENERATION.md](../docs_and_research/PILLAR_1_GENERATION.md) | "Comparability Rules" — normalized taxonomy, seniority normalization |
| | [cv_as_a_skill_gemini.md](../docs_and_research/cv_as_a_skill_gemini.md) | Deep research on skill categorization (625KB) |
| `role_requirements.schema.json` | [PILLAR_6_ECONOMICS.md](../docs_and_research/PILLAR_6_ECONOMICS.md) | "Pre-Match Engine" — the Role Schema structure for employer queries |
| | [_archive/role_schemas/](../_archive/role_schemas/) | Early role schema examples from the Python prototype |

### Anti-Discrimination Constraint
From [PODCAST_ANALYSIS_AND_INTEGRATION.md](../docs_and_research/PODCAST_ANALYSIS_AND_INTEGRATION.md):
> The schema MUST NOT include fields for gender, ethnicity, age, photo, or any demographic data. Matching happens on capabilities and evidence ONLY.

---

## Module 02: Skill Patterns — The Card Templates

📁 **Path:** `platform_build/02_skill_patterns/`

### What to Build
Ready-to-use Markdown templates that anyone can fill in to create their skill card.

### Source Material (Backlinks)

| File to Create | Source Document | Key Section |
|---|---|---|
| `template_human_skill.md` | [scoutica/SKILL.md](../scoutica/SKILL.md) | The working prototype — use as base template |
| | [PILLAR_1_GENERATION.md](../docs_and_research/PILLAR_1_GENERATION.md) | "Four Generation Methods" — AI-assisted, wizard, manual, import |
| `template_agent_skill.md` | [PILLAR_4_AGENTIC_EXTENSION.md](../docs_and_research/PILLAR_4_AGENTIC_EXTENSION.md) | "AI Agent Card Example" — the YAML structure for AI agents |
| | [PILLAR_4_AGENTIC_EXTENSION.md](../docs_and_research/PILLAR_4_AGENTIC_EXTENSION.md) | `limitations` section — critical for agents (what they CANNOT do) |
| `template_robot_skill.md` | [PILLAR_4_AGENTIC_EXTENSION.md](../docs_and_research/PILLAR_4_AGENTIC_EXTENSION.md) | "Warehouse Robot Example" — `physical_specs`, safety certs, maintenance |
| `template_team_skill.md` | [PILLAR_4_AGENTIC_EXTENSION.md](../docs_and_research/PILLAR_4_AGENTIC_EXTENSION.md) | "Mixed Teams" — combined capabilities, synergies, team pricing |

---

## Module 03: Agent Rules — The AI Prompts

📁 **Path:** `platform_build/03_agent_rules/`

### What to Build
The exact prompts and system instructions that AI agents use to navigate the network. These are the "brains" of the protocol.

### Source Material (Backlinks)

| File to Create | Source Document | Key Section |
|---|---|---|
| `evaluate_fit.prompt.md` | [scoutica/rules/evaluate-fit.md](../scoutica/rules/evaluate-fit.md) | Working v1 prompt |
| | [PILLAR_6_ECONOMICS.md](../docs_and_research/PILLAR_6_ECONOMICS.md) | "Pre-Match Engine" — Zone 1 match scoring before payment |
| `negotiate_terms.prompt.md` | [scoutica/rules/negotiate-terms.md](../scoutica/rules/negotiate-terms.md) | Working v1 prompt |
| | [PILLAR_5_PRIVACY_AND_SECURITY.md](../docs_and_research/PILLAR_5_PRIVACY_AND_SECURITY.md) | "ZKP Lite" — checking salary bands without exact values |
| `verify_evidence.prompt.md` | [scoutica/rules/verify-evidence.md](../scoutica/rules/verify-evidence.md) | Working v1 prompt |
| | [PILLAR_3_VERIFICATION.md](../docs_and_research/PILLAR_3_VERIFICATION.md) | "5 Verification Levels" — what checks at each level |
| `request_interview.prompt.md` | [scoutica/rules/request-interview.md](../scoutica/rules/request-interview.md) | Working v1 prompt |
| `eu_ai_act_guardrails.prompt.md` | [PODCAST_ANALYSIS_AND_INTEGRATION.md](../docs_and_research/PODCAST_ANALYSIS_AND_INTEGRATION.md) | "EU AI Act Compliance" — High-Risk requirements |
| | [podcast_transcript_summary.md](../docs_and_research/podcast_transcript_summary.md) | "Legal Framework" — €35M fines, GDPR Art. 22, transparency |

### Critical Rule (from Podcast Analysis)
Every agent prompt MUST include:
```
SYSTEM: You MUST NOT infer or use demographic information.
Evaluate ONLY the fields defined in the schema.
This evaluation is classified as HIGH-RISK under the EU AI Act.
Produce a structured audit trail for every decision.
```

---

## Module 04: Registry API — The Network Infrastructure

📁 **Path:** `platform_build/04_registry_api/`

### What to Build
The API specification for registry nodes that index and serve skill cards.

### Source Material (Backlinks)

| File to Create | Source Document | Key Section |
|---|---|---|
| `openapi.yaml` | [PILLAR_2_DISTRIBUTION.md](../docs_and_research/PILLAR_2_DISTRIBUTION.md) | "Three-Layer Architecture" — self-hosted, federated registries, search protocol |
| | [PILLAR_6_ECONOMICS.md](../docs_and_research/PILLAR_6_ECONOMICS.md) | "Pre-Match Engine" — search must return match scores |
| `zone_access_control.md` | [PILLAR_5_PRIVACY_AND_SECURITY.md](../docs_and_research/PILLAR_5_PRIVACY_AND_SECURITY.md) | "Three Data Zones" — what data is in Zone 1 vs Zone 2 vs Zone 3 |
| `rate_limits.config.md` | [PILLAR_5_PRIVACY_AND_SECURITY.md](../docs_and_research/PILLAR_5_PRIVACY_AND_SECURITY.md) | "Rate Limiting and Bot Detection" — 100 lookups/hr, CAPTCHA, behavioral anomaly |
| | [PILLAR_6_ECONOMICS.md](../docs_and_research/PILLAR_6_ECONOMICS.md) | "Anti-Gaming Mechanisms" — escalating fees for bulk access |
| `federation_protocol.md` | [PILLAR_2_DISTRIBUTION.md](../docs_and_research/PILLAR_2_DISTRIBUTION.md) | "Federation Protocol" — how registries sync with each other |
| | [research_audits/03_PROTOCOL_AND_NETWORK_DESIGN.md](../docs_and_research/research_audits/03_PROTOCOL_AND_NETWORK_DESIGN.md) | Network protocol design research |

### Reference Data
- [crawled_data/skills.sh/](../crawled_data/) — The skills.sh registry model that we bootstrap from

---

## Module 05: Verification — The Trust Math

📁 **Path:** `platform_build/05_verification/`

### What to Build
The exact algorithms, formulas, and smart contracts for proving identity and trust.

### Source Material (Backlinks)

| File to Create | Source Document | Key Section |
|---|---|---|
| `trust_score_formula.md` | [PILLAR_3_VERIFICATION.md](../docs_and_research/PILLAR_3_VERIFICATION.md) | "5 Verification Levels" — Level 0 (self-asserted) → Level 4 (peer-verified) |
| | [PILLAR_6_ECONOMICS.md](../docs_and_research/PILLAR_6_ECONOMICS.md) | "Verification Multipliers" — Level 0 = 0x earnings, Level 4 = 2x earnings |
| `sbt_smart_contract.sol` | [PILLAR_3_VERIFICATION.md](../docs_and_research/PILLAR_3_VERIFICATION.md) | "Soulbound Tokens" — blockchain-anchored identity, non-transferable |
| | [PILLAR_5_PRIVACY_AND_SECURITY.md](../docs_and_research/PILLAR_5_PRIVACY_AND_SECURITY.md) | "Anti-Impersonation" — canonical URL + content hash on-chain |
| `zkp_salary_banding.md` | [PILLAR_5_PRIVACY_AND_SECURITY.md](../docs_and_research/PILLAR_5_PRIVACY_AND_SECURITY.md) | "ZKP Lite" — commitment hashes, range bands, Semaphore/Noir circuits |
| `anti_fraud_rules.md` | [PILLAR_3_VERIFICATION.md](../docs_and_research/PILLAR_3_VERIFICATION.md) | "Anti-Fraud Mechanisms" — anomaly detection, Sybil resistance |
| | [PILLAR_6_ECONOMICS.md](../docs_and_research/PILLAR_6_ECONOMICS.md) | "Anti-Gaming" — fake profiles, collusion, free mirrors |
| `canonical_url_validation.md` | [PILLAR_5_PRIVACY_AND_SECURITY.md](../docs_and_research/PILLAR_5_PRIVACY_AND_SECURITY.md) | "Anti-Impersonation via Ownership Proof" — content hash + signed manifest |

### Existing Code Reference
- [_archive/candidate_engine/](../_archive/candidate_engine/) — Python scoring logic (archived, but scoring patterns may be reusable)
- [_archive/tests/](../_archive/tests/) — Test cases for matching logic

---

## Module 06: Economics — The Payment & Reputation Engine

📁 **Path:** `platform_build/06_economics/`

### What to Build
The fee splitting logic, reputation algorithms, and payment infrastructure.

### Source Material (Backlinks)

| File to Create | Source Document | Key Section |
|---|---|---|
| `micro_fee_structure.md` | [PILLAR_6_ECONOMICS.md](../docs_and_research/PILLAR_6_ECONOMICS.md) | "Fee Structure" — Zone 2 = $0.05, Zone 3 = $1.00, bulk = $0.10 |
| `reputation_algorithm.md` | [PILLAR_6_ECONOMICS.md](../docs_and_research/PILLAR_6_ECONOMICS.md) | "Requester-Side Quality" — reputation balance, 5x penalty, deposit stake |
| `candidate_earnings.md` | [PILLAR_6_ECONOMICS.md](../docs_and_research/PILLAR_6_ECONOMICS.md) | "Responder-Side Quality" — verification multipliers (0x → 2x) |
| `payment_settlement.md` | [PILLAR_6_ECONOMICS.md](../docs_and_research/PILLAR_6_ECONOMICS.md) | "Payment Settlement Options" — Stripe V1, Blockchain V2, $SKILL Token V3 |
| `protocol_revenue.md` | [PILLAR_6_ECONOMICS.md](../docs_and_research/PILLAR_6_ECONOMICS.md) | "Revenue Model" — 10% commission, enterprise API, white-label |
| `pre_match_engine.md` | [PILLAR_6_ECONOMICS.md](../docs_and_research/PILLAR_6_ECONOMICS.md) | "Decentralized Pre-Match Engine" — match-before-you-pay, bi-directional scoring |
| `data_processing_agreement.json` | [PILLAR_5_PRIVACY_AND_SECURITY.md](../docs_and_research/PILLAR_5_PRIVACY_AND_SECURITY.md) | "GDPR Compliance" — machine-readable DPA template |

### Market Context
- [podcast_transcript_summary.md](../docs_and_research/podcast_transcript_summary.md) — Current market pricing: LinkedIn = $10K/year, agencies = $15-30K/hire
- [research_audits/04_BUSINESS_MODELS_AND_MARKET_POWER.md](../docs_and_research/research_audits/04_BUSINESS_MODELS_AND_MARKET_POWER.md) — Business model analysis

---

## Cross-Cutting Concerns (Apply to ALL Modules)

### EU AI Act Compliance
**Source:** [PODCAST_ANALYSIS_AND_INTEGRATION.md](../docs_and_research/PODCAST_ANALYSIS_AND_INTEGRATION.md)
- Recruiting AI = **High-Risk** under EU AI Act
- Human-in-the-loop required for all hiring decisions
- Structured audit trail for every evaluation
- No purely automated decisions with legal effect
- Penalties: up to **€35M or 7% global revenue**

### Anti-Discrimination by Design
**Source:** [PODCAST_ANALYSIS_AND_INTEGRATION.md](../docs_and_research/PODCAST_ANALYSIS_AND_INTEGRATION.md) + [podcast_transcript_summary.md](../docs_and_research/podcast_transcript_summary.md)
- Schema has NO demographic fields (gender, age, ethnicity, photo)
- Agent prompts MUST include anti-discrimination guardrails
- Evidence-based evaluation only (repos, publications, peer reviews)
- Amazon bias case as cautionary tale (training on biased historical data)

### Privacy Zones
**Source:** [PILLAR_5_PRIVACY_AND_SECURITY.md](../docs_and_research/PILLAR_5_PRIVACY_AND_SECURITY.md)
- **Zone 1 (Public):** Handle, title, top domains, seniority, availability
- **Zone 2 (Paid):** Full capabilities, evidence, experience, salary banding
- **Zone 3 (Private):** Contact info, exact salary, calendar — candidate-controlled only

### Candidate Ownership Principle
**Source:** [manifesto.md](../docs_and_research/manifesto.md) + [PILLAR_6_ECONOMICS.md](../docs_and_research/PILLAR_6_ECONOMICS.md)
- Candidate owns their data at all times
- Candidate can delete their card and disappear from the network
- Every data access generates micro-revenue for the candidate
- No platform lock-in — card is a portable GitHub repo

---

## Historical Research Index

For deep background on any decision, these are the original research sources:

| Document | Size | What It Contains |
|----------|------|------------------|
| [brainstorming.md](../docs_and_research/brainstorming.md) | 2KB | Original idea sketch |
| [manifesto.md](../docs_and_research/manifesto.md) | 4KB | First principles and vision |
| [cv_as_a_skill_perplexity.md](../docs_and_research/cv_as_a_skill_perplexity.md) | 38KB | Perplexity research: market, competitors, opportunities |
| [cv_as_a_skill_gemini.md](../docs_and_research/cv_as_a_skill_gemini.md) | 625KB | Gemini deep dive: exhaustive technical analysis |
| [research_audits/01–06](../docs_and_research/research_audits/) | 37KB | 6-part strategic audit: thesis, wedge, protocol, business, risks, moonshots |
| [DECENTRALIZED_TALENT_NETWORK.md](../docs_and_research/DECENTRALIZED_TALENT_NETWORK.md) | 16KB | Network topology and decentralization design |
| [BATTLE_PLAN.md](../docs_and_research/BATTLE_PLAN.md) | 10KB | Python prototype sprint plan (archived direction) |
| [IMPLEMENTATION_PLAN.md](../docs_and_research/IMPLEMENTATION_PLAN.md) | 11KB | Python prototype architecture (archived direction) |
| [PILOT_AUDIT_AND_SIMPLIFICATION.md](../docs_and_research/PILOT_AUDIT_AND_SIMPLIFICATION.md) | 9KB | The audit that led to the skills.sh pivot |
| [CORPUS_INDEX.md](../docs_and_research/CORPUS_INDEX.md) | 5KB | Original document inventory |

---

## Implementation Workflow

When starting to build a module:

1. **Read this manual's section** for the module you're building
2. **Open each backlinked source document** and read the referenced sections
3. **Check the working prototype** in `scoutica/` for real examples
4. **Check the archive** in `_archive/` for reusable logic patterns
5. **Write the concrete file** (JSON Schema, Solidity contract, OpenAPI spec, etc.)
6. **Validate** against the cross-cutting concerns (EU AI Act, anti-discrimination, privacy zones)
7. **Update** [IMPLEMENTATION_ROADMAP.md](../docs_and_research/IMPLEMENTATION_ROADMAP.md) to mark the task done

---

> **This manual + the 6 pillar specs + the working prototype = everything needed to build the Scoutica Protocol from scratch.**
