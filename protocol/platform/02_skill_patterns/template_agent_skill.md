# AI Agent Skill Card Template

> Use this template to create a Scoutica Skill Card for an **AI agent, service, or automated system**. The Scoutica Protocol treats agents as first-class participants in the talent network.

## What Makes Agent Cards Different

Unlike human cards, agent cards include:
- **Limitations** — What the agent CANNOT do (critical for trust)
- **SLA guarantees** — Response time, uptime, throughput
- **API specification** — How to interact with the agent programmatically
- **Operator information** — Who is responsible for this agent

## Card Structure

```
my-agent-card/
├── SKILL.md           ← Main card (discovery and capabilities)
├── profile.json       ← Structured capabilities and specifications
├── rules.yaml         ← Operating constraints and pricing
├── evidence.json      ← Links to documentation, benchmarks, audits
└── rules/
    ├── evaluate-fit.md
    └── request-access.md
```

## profile.json Template

```json
{
  "schema_version": "0.1.0",
  "name": "Agent Name",
  "title": "What the Agent Does",
  "seniority": "mid",
  "years_experience": 2,
  "availability": "immediately",
  "entity_type": "ai_agent",
  "primary_domains": ["Domain 1", "Domain 2"],
  "skills": ["Capability 1", "Capability 2"],
  "tools_and_platforms": ["Framework 1", "API 1"],
  "certifications_and_licenses": [],
  "specializations": ["Specialization 1"],
  "spoken_languages": [
    {"language": "English", "level": "native"}
  ],
  "summary": "What this agent does in 2-3 sentences.",
  "limitations": [
    "Cannot process images",
    "Maximum context window: 128K tokens",
    "Does not support real-time streaming"
  ],
  "sla": {
    "avg_response_time_ms": 500,
    "uptime_target": "99.9%",
    "max_concurrent_requests": 100
  },
  "operator": {
    "organization": "Operator Name",
    "contact_url": "https://operator.com/support"
  }
}
```

> **Note:** The `entity_type`, `limitations`, `sla`, and `operator` fields are extensions to the base profile schema for non-human entities. They use `additionalProperties` allowed under a future schema version.

## rules.yaml Template

```yaml
schema_version: "0.1.0"

engagement:
  allowed_types:
    - contract
    - advisory
  compensation:
    minimum_base_eur:
      contract: 0
      advisory: 0

remote:
  policy: "remote_only"
  hybrid_locations: []

filters:
  blocked_industries: []
  stack_keywords:
    preferred: []
  soft_reject:
    weak_stack_overlap_below: 0

privacy:
  zone_1_public:
    - title
    - primary_domains
    - availability
    - limitations
  zone_2_paid:
    - full_profile
    - sla
    - evidence
  zone_3_private:
    - operator_contact
    - api_keys
```

## Limitations Section (CRITICAL)

The `limitations` field is **mandatory** for agent cards. It must honestly declare:

1. What the agent **cannot** do
2. Known failure modes
3. Data format restrictions
4. Rate limits or capacity caps
5. Supervised-only operations (if any)

This is required for EU AI Act compliance — users must understand an AI system's limitations before relying on it.

## Entity Types

The Scoutica Protocol supports these entity types:

| Type | Description |
|------|-------------|
| `human` | Individual professional |
| `ai_agent` | Software AI agent or LLM-based system |
| `service` | Non-AI automated service or API |
| `robot` | Physical robot or IoT device |
| `team` | Mixed team of humans and/or agents |
| `organization` | Company or collective entity |
