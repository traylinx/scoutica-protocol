# 🗺️ Implementation Roadmap (Recruiter Network)

> **Revised 2026-03-31** — Stargate removed from implementation path.
> Transport: Git-native V1, Nostr V2. No proprietary dependencies.

## 4-Phase Build Plan

The Scoutica Network rolls out in four phases, each building on the previous one's infrastructure.

### Phase 1: Schemas, Registry & Discovery (Weeks 1-6)

**Objective:** Establish data models for the Employer side AND make cards discoverable.

**Part A — Schemas & Identity (Weeks 1-3):**
- [ ] Finalize `recruiter_profile.json` JSON schema (already drafted in `schemas/recruiter/`)
- [ ] Finalize `role.json` (Job Posting) schema (already drafted)
- [ ] Finalize `rules.yaml` ↔ `role.json` compatibility mapping
- [ ] `scoutica org init` setup wizard — test and harden
- [ ] DNS TXT record verification for `scoutica org verify`
- [ ] `scoutica org publish` to GitHub

**Part B — Registry & Search (Weeks 4-6):**
- [ ] Create `traylinx/scoutica-registry` GitHub repo
- [ ] `candidates/index.json` format — card_url, name, title, seniority, skills[], availability, updated
- [ ] `roles/index.json` format — role_url, title, hard_skills[], compensation_range, location, status, posted_at
- [ ] `scoutica publish` auto-submits PR to registry (candidate side)
- [ ] `scoutica role publish` auto-submits PR to registry (employer side)
- [ ] `scoutica jobs search --skills "..." --seniority "..."` — downloads index.json, filters locally
- [ ] GitHub Action `traylinx/scoutica-action` — auto-validate + auto-register on push
- [ ] Seed registry with 10+ real candidate cards

### Phase 2: Scoring Engine & Git-Native Messaging (Weeks 7-13)

**Objective:** Deterministic evaluation + first working message exchange using Git as transport.

**Part A — Fit Scoring (Weeks 7-9):**
- [ ] Deterministic fit scoring algorithm (portable function, no external deps)
- [ ] `scoutica evaluate <card_url> <role_url>` — CLI scoring command
- [ ] `scoutica evaluate --batch <role_url>` — Score all registry candidates against a role
- [ ] Hard filter engine with structured rejection reasons
- [ ] Evidence bonus computation (URL reachability verification)
- [ ] Unit tests with known-score test fixtures

**Part B — Git-Native Handshake (Weeks 10-13):**
- [ ] Registry inbox structure: `inbox/<recipient_hash>/<msg_id>.json`
- [ ] Message envelope validation against `message.schema.json`
- [ ] `scoutica send <recipient_url> --type opportunity.offer --role <role.json>`
- [ ] `scoutica inbox` — Pull pending messages from registry inbox
- [ ] `scoutica reply <message_id> --accept` / `--reject`
- [ ] Conversation threading (conversation_id lifecycle)
- [ ] Optional: HTTP webhook POST if `contact.agent_endpoint` configured
- [ ] Local transparency log (`~/.scoutica/privacy/access_log.json`)
- [ ] Auto-response handler: auto-evaluate incoming offers against rules.yaml

### Phase 3: Nostr Transport (Weeks 14-20)

**Objective:** Upgrade from Git-native inbox to Nostr-based decentralized messaging.

- [ ] Define Scoutica Nostr event kind (parameterized replaceable event)
- [ ] Add `transport.nostr` to `scoutica.json` schema: `pubkey`, `relays[]`
- [ ] `scoutica identity init` — Generate secp256k1 keypair, store in `~/.scoutica/identity/`
- [ ] Nostr event bridge: `message.json` ↔ signed Nostr event translation
- [ ] `scoutica send` upgrade: if recipient has `nostr.pubkey`, publish to declared relays
- [ ] `scoutica inbox` upgrade: subscribe to Nostr relays for own-pubkey events
- [ ] NIP-44 encryption for Zone 2/3 data in transit
- [ ] `scoutica relay add` / `scoutica relay list` — relay management
- [ ] Transport resolution waterfall: webhook → Nostr → Git inbox fallback
- [ ] NIP-13 proof-of-work for anti-spam on unknown senders
- [ ] Submit NIP proposal for Scoutica event kind standardization

### Phase 4: Trust Engine & Accountability (Weeks 21-26)

**Objective:** Network-computed reputation and anti-gaming enforcement.

- [ ] Local interaction log (append-only JSONL at `~/.scoutica/interactions/`)
- [ ] Trust score computation function (response rate, ghosting, hire rate, spam, tenure)
- [ ] V1: Local trust — each agent computes from own interaction history
- [ ] V2: Nostr trust — signed interaction receipts published as events; any client aggregates
- [ ] Ghosting detection (SLA timer → auto-log `event.ghosting`)
- [ ] `scoutica trust <org_url>` — Display trust score for any org
- [ ] Candidate-controlled trust thresholds in `rules.yaml`
- [ ] Rate limiting per trust level in `scoutica jobs search`
- [ ] Mass-ping spam detection (>50 offers/24h + >80% rejection → flag)
- [ ] `scoutica privacy audit <org>` / `scoutica privacy block <org>`
- [ ] Nostr Web of Trust: trust from endorsement graph (NIP-32 labels)

---

## Priority Matrix & Dependency Graph

```
Phase 1A: Schemas
  ├── recruiter_profile.schema.json ──┐
  └── role.schema.json ──────────────┤
                                      ▼
                               Phase 1B: Registry
                                 ├── candidates/index.json
                                 ├── roles/index.json
                                 └── scoutica jobs search
                                      │
                                      ▼
                               Phase 2A: Scoring Engine
                                 ├── scoutica evaluate
                                 └── Hard filter engine
                                      │
                                      ▼
                               Phase 2B: Git-Native Messaging
                                 ├── scoutica send / inbox / reply
                                 └── Auto-response handler
                                      │
                                      ▼
                               Phase 3: Nostr Transport
                                 ├── scoutica identity init
                                 ├── Nostr event bridge
                                 └── NIP-44 encryption
                                      │
                                      ▼
                               Phase 4: Trust Engine
                                 ├── Trust score computation
                                 ├── Ghosting detection
                                 └── Web of Trust
```

---

## Resolved Design Decisions

### Q1: Boolean vs Weighted Scoring?

**Decision: Hybrid.** Hard filters (salary, location, blocked industries, engagement type) are strictly **boolean pass/fail**. Soft scoring (skill overlap, evidence quality, title match) is **weighted** on a 0-100 scale. See `03_JOB_POSTING_CARD.md` §2 for the exact algorithm.

### Q2: Registry Funding Model?

**Decision: Deferred to Phase 3+.** In Phase 1-2, the registry is a GitHub-hosted static `index.json` (zero-cost infrastructure). Funding only becomes relevant when we deploy the Nostr relay. Potential models:
- Freemium (free for `new/building` tier, paid for premium API)
- Community-funded relay infrastructure
- Nostr relay micropayments (Lightning sats per event)

### Q3: DNS Verification Required for Search?

**Decision: Yes, but phased.**
- **V1** (GitHub topics): No DNS required — publicly accessible data.
- **V2+** (Nostr/API): DNS verification **required** for any trust level above `new`.

### Q4: Agency vs In-House Schema Differences?

**Decision: Already resolved.** The `entity_type` field in `recruiter_profile.json` distinguishes between `"in-house"`, `"agency"`, `"fractional"`, and `"platform"`. Trust accrues per-org, not per-agency.

### Q5: Transport Layer?

**Decision: Layered, open, no proprietary dependencies.** See `13_TRANSPORT_ARCHITECTURE.md` for the full ADR.
- V1 Default: Git-Native Inbox (zero infrastructure)
- V2 Default: Nostr Relays (decentralized, encrypted, offline-tolerant)
- Optional: HTTP Webhooks (power users with live endpoints)
- No proprietary transport requirements at any tier.
