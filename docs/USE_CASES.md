# Scoutica Protocol — Use Cases & Scenarios

> **Real-world scenarios showing how the Scoutica Protocol is used by candidates, recruiters, and platforms.**
>
> [User Manual](USER_MANUAL.md) | [Developer Guide](DEVELOPER_GUIDE.md) | [Architecture](ARCHITECTURE.md) | [Flow Diagrams](../.specs/protocol_flows.md)

---

## Scenario 1: Candidate Creates Their Card

> **Maria**, a senior backend engineer, wants to make her skills discoverable by AI agents without sharing her data with job boards.

```mermaid
sequenceDiagram
    participant M as 👤 Maria
    participant CLI as ⚡ Scoutica CLI
    participant AI as 🤖 Gemini CLI (local)
    participant GH as 🐙 GitHub

    M->>CLI: scoutica scan ~/maria-cv/ --with gemini
    CLI->>CLI: Read CV.pdf, certs.md, portfolio.md
    CLI->>AI: Pipe prompt + docs (local, never leaves machine)
    AI-->>CLI: JSON {profile, rules, evidence}
    CLI->>CLI: Write 4 card files + scoutica.json
    CLI-->>M: ✅ Card created! 4 files generated.

    M->>CLI: scoutica validate
    CLI-->>M: ✅ 5 checks passed

    M->>CLI: scoutica publish
    CLI->>GH: git commit + push
    GH-->>M: Card is live at github.com/maria/skills
```

**Result:** Maria's Skill Card is published. Her data never left her laptop. Any AI agent can now discover and evaluate her profile.

---

## Scenario 2: AI Recruiter Finds Candidates

> **TechCorp's AI agent** needs to fill a "Senior DevOps Engineer" position. It searches the Scoutica Protocol registry.

```mermaid
sequenceDiagram
    participant HA as 🏢 TechCorp Agent
    participant REG as 📋 Registry
    participant C1 as 🃏 Card: Maria
    participant C2 as 🃏 Card: Alex
    participant C3 as 🃏 Card: Sam

    HA->>REG: Search(skills=["Kubernetes","Terraform"], seniority="senior")
    REG-->>HA: [maria_url, alex_url, sam_url]

    par Evaluate all candidates in parallel
        HA->>C1: GET profile.json + rules.yaml
        C1-->>HA: {score: 85, salary: PASS, remote: PASS}
        HA->>C2: GET profile.json + rules.yaml
        C2-->>HA: {score: 72, salary: PASS, remote: FAIL}
        HA->>C3: GET profile.json + rules.yaml
        C3-->>HA: {score: 91, salary: REJECTED, remote: PASS}
    end

    Note over HA: Maria: 85 ✅ | Alex: 72 ⚠️ remote | Sam: REJECTED 💰

    HA->>C1: Contact Maria's agent → schedule interview
    HA->>C2: Contact Alex (note: requires on-site option)
    Note over HA,C3: Sam auto-rejected: salary below minimum
```

**Key insight:** Sam was never contacted — the agent respected the `rules.yaml` auto-reject for salary. No wasted time for either party.

---

## Scenario 3: Job Board Auto-Import

> **DevJobs.io** lets applicants import their Scoutica Protocol card instead of filling forms.

```mermaid
sequenceDiagram
    participant C as 👤 Candidate
    participant JB as 🌐 DevJobs.io
    participant GH as 🐙 GitHub

    C->>JB: "Import Scoutica Card" → pastes URL
    JB->>GH: GET scoutica.json
    GH-->>JB: {name, title, domains, card_url}
    JB->>GH: GET profile.json
    GH-->>JB: {skills, experience, seniority}
    JB->>JB: Auto-fill: name, title, skills, experience

    JB->>GH: GET rules.yaml
    GH-->>JB: {minimum_salary: 85K, remote: remote_first}

    JB->>JB: Pre-screen: "This role pays 75K, candidate minimum is 85K"
    JB-->>C: ⚠️ "This role may not match your salary requirements. Apply anyway?"

    alt Candidate applies anyway
        JB->>JB: Submit with flag
    else Candidate skips
        JB-->>C: "Saved you time! Here are matching roles."
    end
```

**Benefit:** Candidates don't fill forms. The platform pre-screens and warns about mismatches upfront.

---

## Scenario 4: Agent-to-Agent Negotiation

> **Maria's personal AI agent** receives an inbound opportunity and negotiates autonomously.

```mermaid
sequenceDiagram
    participant HA as 🏢 Hiring Agent
    participant MA as 🤖 Maria's Agent
    participant M as 👤 Maria

    HA->>MA: POST /opportunity {role: "Lead DevOps", salary: 95K, remote: hybrid}

    MA->>MA: Load rules.yaml
    MA->>MA: Check: salary 95K > minimum 85K ✅
    MA->>MA: Check: remote hybrid ✅ (policy: flexible)
    MA->>MA: Check: industry fintech ✅ (not blocked)

    MA-->>HA: {status: "INTERESTED", counter: {salary: 110K, equity: "1%"}}

    HA->>HA: Counter within budget? 110K > max 105K
    HA-->>MA: {status: "COUNTER", salary: 105K, equity: "0.5%", signing_bonus: 5K}

    MA->>MA: 105K + equity + bonus = acceptable
    MA-->>HA: {status: "ACCEPT", next: "schedule_interview"}

    MA->>M: 📧 "Interview scheduled: Lead DevOps at FinTech Corp, 105K + equity"
```

**Result:** Three negotiation rounds happened in seconds. Maria only gets notified when there's a concrete interview to schedule.

---

## Scenario 5: Evidence Verification

> **Before an interview**, an employer's agent verifies Maria's claimed evidence.

```mermaid
sequenceDiagram
    participant EA as 🏢 Employer Agent
    participant GH as 🐙 GitHub API
    participant EV as 🌐 External URLs

    EA->>EA: Load evidence.json (5 items)

    EA->>GH: GET /repos/maria/infra-toolkit
    GH-->>EA: {stars: 234, languages: {Go: 60%, Python: 30%}, commits: 892}
    EA->>EA: ✅ Go + Python match claimed skills

    EA->>EV: HEAD https://terraform-cert.verify/maria-2025
    EV-->>EA: 200 OK
    EA->>EA: ✅ Terraform certification verified

    EA->>GH: GET /repos/maria/k8s-operator
    GH-->>EA: {stars: 89, languages: {Go: 95%}, commits: 234}
    EA->>EA: ✅ Kubernetes expertise confirmed

    EA->>EV: HEAD https://maria.dev/portfolio
    EV-->>EA: 200 OK
    EA->>EA: ✅ Portfolio site is live

    EA->>EV: HEAD https://old-cert.example.com/maria
    EV-->>EA: 404 Not Found
    EA->>EA: ❌ One certification link is dead

    Note over EA: Trust Score: 4/5 verified (80%)
    EA->>EA: Proceed — strong evidence with one minor dead link
```

---

## Scenario 6: Team Card

> **SquadAlpha** — a team of 4 engineers — publishes a composite team card.

```mermaid
graph TD
    TEAM[🏗️ SquadAlpha Team Card]
    TEAM --> M[👤 Maria - Lead DevOps]
    TEAM --> A[👤 Alex - Senior Backend]
    TEAM --> S[👤 Sam - ML Engineer]
    TEAM --> R[🤖 CodeBot - AI Agent]

    style TEAM fill:#2d3748,stroke:#4fd1c5,color:#fff
    style M fill:#1a202c,stroke:#63b3ed,color:#fff
    style A fill:#1a202c,stroke:#63b3ed,color:#fff
    style S fill:#1a202c,stroke:#63b3ed,color:#fff
    style R fill:#1a202c,stroke:#f6ad55,color:#fff
```

The team card aggregates:
- **Combined skills** across all members
- **Team rules** (availability, rate, engagement model)
- **Collective evidence** (team projects, joint publications)

This enables companies to hire entire teams, not just individuals.

---

## Scenario 7: Blockchain-Verified Card (Future)

> In the future, cards can be verified on-chain using Soulbound Tokens (SBTs).

```mermaid
sequenceDiagram
    participant C as 👤 Candidate
    participant SC as ⛓️ Smart Contract
    participant V as ✅ Verifier
    participant E as 🏢 Employer

    C->>SC: Mint SBT with profile hash
    SC-->>C: Token ID: #42

    V->>SC: Endorse skill: "Kubernetes Expert"
    SC->>SC: Record endorsement (non-transferable)

    E->>SC: Query: "Is #42 endorsed for Kubernetes?"
    SC-->>E: {endorsed: true, verifier: "TechCorp", date: "2026-01"}

    E->>E: Trust level: Blockchain-verified ✅
```

**SBTs (Soulbound Tokens)** are non-transferable — they prove endorsement without being sellable.

---

## Summary: Which Scenario Applies to You?

| If You Are... | Start Here |
|----------------|-----------|
| A professional creating your card | [Scenario 1](#scenario-1-candidate-creates-their-card) |
| A company building a recruiting agent | [Scenario 2](#scenario-2-ai-recruiter-finds-candidates) |
| A platform adding Scoutica Protocol import | [Scenario 3](#scenario-3-job-board-auto-import) |
| Building autonomous agent negotiation | [Scenario 4](#scenario-4-agent-to-agent-negotiation) |
| Implementing evidence verification | [Scenario 5](#scenario-5-evidence-verification) |
| Creating team or org cards | [Scenario 6](#scenario-6-team-card) |
| Exploring blockchain verification | [Scenario 7](#scenario-7-blockchain-verified-card-future) |

---

## Further Reading

- [User Manual](USER_MANUAL.md) — CLI commands and card creation
- [Developer Guide](DEVELOPER_GUIDE.md) — Build integrations with code
- [Architecture](ARCHITECTURE.md) — Protocol design and schemas
- [Roadmap](../.specs/ROADMAP.md) — What's coming next
