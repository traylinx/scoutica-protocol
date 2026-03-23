# Scoutica Protocol — Architecture

> **Protocol design, data model, and system components.**
>
> [User Manual](USER_MANUAL.md) | [Developer Guide](DEVELOPER_GUIDE.md) | [Use Cases](USE_CASES.md) | [Roadmap](../.specs/ROADMAP.md)

---

## System Overview

```mermaid
graph TB
    subgraph "Candidate Layer"
        DOCS[📁 Documents]
        CLI[⚡ Scoutica CLI]
        CARD[🃏 Skill Card]
        AI[🤖 Local AI CLI]
    end

    subgraph "Distribution Layer"
        GH[🐙 GitHub]
        REG[📋 Registry]
        DISC[📍 scoutica.json]
    end

    subgraph "Consumption Layer"
        AGENT[🤖 AI Agents]
        JB[🌐 Job Boards]
        ATS[📊 ATS Systems]
        WIDGET[🎨 Widgets]
    end

    subgraph "Trust Layer (Future)"
        BC[⛓️ Blockchain]
        SBT[🔐 Soulbound Tokens]
        ZKP[🔒 Zero-Knowledge Proofs]
    end

    DOCS -->|scan| CLI
    CLI -->|local AI| AI
    AI -->|generate| CARD
    CARD -->|publish| GH
    GH -->|register| REG
    GH -->|discovery| DISC
    REG -->|search| AGENT
    DISC -->|resolve| AGENT
    AGENT --> JB
    AGENT --> ATS
    AGENT --> WIDGET
    CARD -.->|future: verify| BC
    BC -.-> SBT
    BC -.-> ZKP

    style CARD fill:#2d3748,stroke:#4fd1c5,color:#fff
    style REG fill:#2d3748,stroke:#63b3ed,color:#fff
    style BC fill:#2d3748,stroke:#f6ad55,color:#fff
```

---

## The 6 Pillars

The Scoutica Protocol is built on 6 foundational pillars:

### Pillar 1: Generation

How Skill Cards are created.

| Method | Command | Description |
|--------|---------|-------------|
| AI Scan | `scoutica scan` | Auto-generate from documents via local AI |
| Interactive | `scoutica init` | Step-by-step wizard |
| Manual | Create files directly | For developers |
| AI Paste | `scoutica scan --clipboard` | Copy prompt, paste in any AI |

**Schema hierarchy:**

```mermaid
graph LR
    P[profile.json] --> S[Skills Taxonomy]
    P --> E[Experience Records]
    P --> L[Language Proficiencies]
    R[rules.yaml] --> EN[Engagement Rules]
    R --> CO[Compensation Floor]
    R --> AR[Auto-Reject Criteria]
    EV[evidence.json] --> GH[GitHub Repos]
    EV --> CE[Certifications]
    EV --> PO[Portfolio Links]

    style P fill:#2d3748,stroke:#4fd1c5,color:#fff
    style R fill:#2d3748,stroke:#63b3ed,color:#fff
    style EV fill:#2d3748,stroke:#f6ad55,color:#fff
```

### Pillar 2: Distribution

How cards are discovered and accessed.

```mermaid
graph TD
    CARD[🃏 Skill Card] -->|publish| GH[GitHub Repo]
    GH -->|scoutica.json| DISC[Discovery File]
    GH -->|register| REG[Registry Index]
    REG -->|search API| SEARCH[Search Query]
    DISC -->|resolve| FETCH[Fetch Card]

    SEARCH --> RESULTS[Matched Cards]
    FETCH --> DISPLAY[Card Summary]
```

**Discovery mechanisms:**
1. **scoutica.json** — well-known file at repo root
2. **Registry index** — centralized JSON index (GitHub-based)
3. **GitHub Topics** — tag repos with `scoutica-card`
4. **Direct URL** — `scoutica resolve <url>`

### Pillar 3: Verification

How trust is established (5 levels).

| Level | Name | Trust Score | Description |
|-------|------|-------------|-------------|
| 0 | Self-Asserted | 0.0x | Candidate claims it |
| 1 | URL-Verified | 0.5x | Evidence URLs are reachable |
| 2 | Peer-Endorsed | 1.0x | Other cards vouch for skills |
| 3 | Platform-Verified | 1.5x | CI/CD: commits, contributions verified |
| 4 | Blockchain-Verified | 2.0x | Soulbound Token endorsement |

### Pillar 4: Agentic Extension

The protocol supports multiple entity types:

| Entity Type | Description | Example |
|-------------|-------------|---------|
| `human` | Individual professional | Software engineer |
| `ai_agent` | Autonomous AI agent | Coding assistant |
| `service` | API or SaaS | Translation API |
| `robot` | Physical system | Warehouse drone |
| `team` | Group of entities | Engineering squad |
| `organization` | Company or department | DevOps team |

### Pillar 5: Privacy & Security

**Three-zone data model:**

```mermaid
graph TB
    subgraph "Zone 1 — Public (Free)"
        Z1[Title, Seniority, Domains, Availability]
    end
    subgraph "Zone 2 — Verified (Auth Required)"
        Z2[Full Profile, Evidence, Experience]
    end
    subgraph "Zone 3 — Private (Candidate Approval)"
        Z3[Email, Phone, Exact Salary]
    end

    Z1 --> Z2
    Z2 --> Z3

    style Z1 fill:#22543d,stroke:#68d391,color:#fff
    style Z2 fill:#2a4365,stroke:#63b3ed,color:#fff
    style Z3 fill:#742a2a,stroke:#fc8181,color:#fff
```

**GDPR compliance:**
- Candidate owns all data
- Right to deletion (delete repo = disappear)
- Right to portability (standard JSON/YAML)
- Transparency (candidates see exactly what agents see)

### Pillar 6: Economics

Revenue flows in the Scoutica Protocol ecosystem.

| Actor | Revenue Stream | Amount |
|-------|---------------|--------|
| Candidate | Micro-fee per Zone 2 access | ~$0.05 |
| Protocol | Commission on micro-fees | 10% |
| Verifier | Fee for endorsing skills | Market rate |
| Registry | Subscription for premium search | TBD |

**Cost comparison:**

| Channel | Cost Per Hire |
|---------|-------------|
| LinkedIn Recruiter | ~$10,000/year |
| Recruiting Agency | $15,000–$30,000 |
| **Scoutica Protocol** | **~$4** |

---

## Data Model

### Card File Relationships

```mermaid
erDiagram
    SCOUTICA_JSON ||--|| PROFILE : "discovers"
    PROFILE ||--o{ SKILLS : "has"
    PROFILE ||--o{ EXPERIENCE : "has"
    PROFILE ||--o{ LANGUAGES : "speaks"
    RULES ||--o{ ENGAGEMENT : "defines"
    RULES ||--o{ COMPENSATION : "sets"
    RULES ||--o{ AUTO_REJECT : "blocks"
    EVIDENCE ||--o{ ITEMS : "links"
    ITEMS ||--o{ SKILLS : "proves"

    SCOUTICA_JSON {
        string scoutica_version
        string card_url
        string name
        string updated
    }
    PROFILE {
        string name
        string title
        string seniority
        int years_experience
    }
    SKILLS {
        string[] languages
        string[] frameworks
        string[] tools
    }
    RULES {
        object engagement
        object compensation
        object remote
    }
    EVIDENCE {
        array items
    }
```

---

## Protocol Compliance

### EU AI Act Requirements

Recruiting AI is classified as **High-Risk** under the EU AI Act. All implementations must:

1. **Human-in-the-loop** — No fully automated hiring decisions
2. **Audit trail** — Log every evaluation with reasoning
3. **Transparency** — Candidates see the same data as employers
4. **Non-discrimination** — No demographic inference or bias
5. **Explainability** — Score breakdown with matched/missing skills

### Anti-Discrimination by Design

The profile schema **deliberately excludes**:
- Gender, age, ethnicity, nationality
- Photos or visual identifiers
- Marital status, religion, disability

Evaluation is based **solely** on: skills, experience, evidence, and engagement rules.

---

## Further Reading

- [User Manual](USER_MANUAL.md) — End-user guide
- [Developer Guide](DEVELOPER_GUIDE.md) — Build integrations
- [Use Cases](USE_CASES.md) — Real-world scenarios
- [Roadmap](../.specs/ROADMAP.md) — Future development
- [Protocol Flows](../.specs/protocol_flows.md) — Sequence diagrams
- [Ecosystem Analysis](../.specs/protocol_ecosystem.md) — Consumption analysis
