# 📐 Complete JSON Schema Definitions — Recruiter Side

> All new schemas introduced by the Recruiter Network extension. These complement the existing candidate-side schemas (`profile.json`, `rules.yaml`, `evidence.json`).

---

## 1. `recruiter_profile.json` Schema

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "Scoutica Recruiter Profile",
  "description": "Machine-readable identity for a recruiting organization on the Scoutica network.",
  "type": "object",
  "required": ["scoutica_version", "entity_type", "organization", "engagement_types"],
  "additionalProperties": false,
  "properties": {
    "scoutica_version": {
      "type": "string",
      "pattern": "^\\d+\\.\\d+\\.\\d+$",
      "description": "Protocol version (e.g., 0.3.0)"
    },
    "entity_type": {
      "type": "string",
      "enum": ["in-house", "agency", "fractional", "platform"],
      "description": "Type of recruiting entity"
    },
    "organization": {
      "type": "object",
      "required": ["name", "domain"],
      "properties": {
        "name": { "type": "string", "maxLength": 200 },
        "domain": { "type": "string", "format": "hostname" },
        "domain_verified": { "type": "boolean", "default": false },
        "verified_at": { "type": "string", "format": "date-time" },
        "description": { "type": "string", "maxLength": 1000 },
        "founded_year": { "type": "integer", "minimum": 1900, "maximum": 2100 },
        "team_size": {
          "type": "string",
          "enum": ["1-10", "11-50", "51-200", "201-500", "501-1000", "1000+"]
        },
        "headquarters": { "type": "string", "maxLength": 200 }
      }
    },
    "industries": {
      "type": "array",
      "items": { "type": "string" },
      "minItems": 1,
      "maxItems": 10,
      "description": "Industries the org operates in"
    },
    "engagement_types": {
      "type": "array",
      "items": {
        "type": "string",
        "enum": ["permanent", "contract", "fractional", "advisory", "freelance", "internship"]
      },
      "minItems": 1
    },
    "tech_stack": {
      "type": "array",
      "items": { "type": "string" },
      "description": "Primary technologies used in the organization"
    },
    "team": {
      "type": "object",
      "description": "Team management model. Git repo access = team access.",
      "properties": {
        "model": {
          "type": "string",
          "enum": ["solo", "organization", "agency"],
          "description": "solo: 1 person. organization: GitHub org with collaborators. agency: external entity managing client orgs."
        },
        "members_can_post_roles": { "type": "boolean", "default": true },
        "require_approval_for_publish": { "type": "boolean", "default": false }
      }
    },
    "contact": {
      "type": "object",
      "properties": {
        "agent_endpoint": {
          "type": "string",
          "format": "uri",
          "description": "Webhook URL for agent-to-agent communication"
        },
        "human_fallback": {
          "type": "string",
          "format": "email",
          "description": "Human-readable contact for non-automated interactions"
        },
        "careers_page": {
          "type": "string",
          "format": "uri"
        }
      }
    },
    "card_url": {
      "type": "string",
      "format": "uri",
      "description": "URL where this recruiter card is hosted"
    },
    "created_at": { "type": "string", "format": "date-time" },
    "updated_at": { "type": "string", "format": "date-time" }
  }
}
```

---

## 2. `hiring_rules.yaml` Schema

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "Scoutica Hiring Rules",
  "description": "Public commitments from a recruiter about their hiring practices.",
  "type": "object",
  "required": ["commitments"],
  "properties": {
    "commitments": {
      "type": "object",
      "properties": {
        "max_response_time_days": {
          "type": "integer",
          "minimum": 1,
          "maximum": 30,
          "description": "SLA: maximum days to respond to a candidate's acceptance"
        },
        "salary_transparency_guaranteed": {
          "type": "boolean",
          "description": "Whether compensation ranges are always disclosed upfront"
        },
        "feedback_provided_on_rejection": {
          "type": "boolean",
          "description": "Whether candidates receive structured feedback when rejected"
        },
        "gdpr_compliance": {
          "type": "boolean",
          "description": "Whether the org is GDPR-compliant"
        },
        "interview_process_max_rounds": {
          "type": "integer",
          "minimum": 1,
          "maximum": 10,
          "description": "Maximum number of interview rounds"
        },
        "response_time_sla_hours": {
          "type": "integer",
          "minimum": 1,
          "description": "Target response time in hours for initial reply"
        }
      }
    },
    "limits": {
      "type": "object",
      "properties": {
        "max_unsolicited_pings_per_week": {
          "type": "integer",
          "minimum": 1,
          "maximum": 1000,
          "description": "Self-declared cap on outbound opportunity messages per week"
        },
        "max_active_roles": {
          "type": "integer",
          "minimum": 1,
          "description": "Maximum concurrent open roles"
        }
      }
    },
    "preferences": {
      "type": "object",
      "properties": {
        "preferred_seniority": {
          "type": "array",
          "items": {
            "type": "string",
            "enum": ["entry", "junior", "mid", "senior", "lead", "manager", "director", "executive"]
          }
        },
        "preferred_engagement": {
          "type": "array",
          "items": { "type": "string" }
        },
        "preferred_regions": {
          "type": "array",
          "items": { "type": "string" }
        }
      }
    }
  }
}
```

---

## 3. `role.json` Schema

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "Scoutica Role Posting",
  "description": "A machine-readable job definition for deterministic candidate matching.",
  "type": "object",
  "required": ["scoutica_version", "job_id", "title", "status", "requirements", "location"],
  "additionalProperties": false,
  "properties": {
    "scoutica_version": {
      "type": "string",
      "pattern": "^\\d+\\.\\d+\\.\\d+$"
    },
    "job_id": {
      "type": "string",
      "pattern": "^req_[a-f0-9]{6,}$",
      "description": "Unique role identifier"
    },
    "title": { "type": "string", "maxLength": 200 },
    "status": {
      "type": "string",
      "enum": ["draft", "active", "paused", "filled", "expired"],
      "description": "Current role status"
    },
    "posted_at": { "type": "string", "format": "date-time" },
    "expires_at": { "type": "string", "format": "date-time" },
    "refreshed_at": {
      "type": "string",
      "format": "date-time",
      "description": "Last time the recruiter confirmed the role is still active (ghost prevention)"
    },
    "requirements": {
      "type": "object",
      "required": ["hard_skills"],
      "properties": {
        "hard_skills": {
          "type": "array",
          "items": { "type": "string" },
          "minItems": 1,
          "maxItems": 20
        },
        "preferred_skills": {
          "type": "array",
          "items": { "type": "string" }
        },
        "soft_skills": {
          "type": "array",
          "items": { "type": "string" },
          "description": "Non-technical skills (e.g., System Design, Leadership, Mentorship)"
        },
        "minimum_years_experience": {
          "type": "integer",
          "minimum": 0,
          "maximum": 50
        },
        "seniority": {
          "type": "string",
          "enum": ["entry", "junior", "mid", "senior", "lead", "manager", "director", "executive"]
        },
        "education": {
          "type": "string",
          "enum": ["none", "bootcamp", "bachelors", "masters", "phd"]
        },
        "languages_required": {
          "type": "array",
          "items": { "type": "string" },
          "description": "Human languages (e.g., 'English', 'German')"
        }
      }
    },
    "compensation": {
      "type": "object",
      "properties": {
        "currency": { "type": "string", "pattern": "^[A-Z]{3}$" },
        "base_min": { "type": "number", "minimum": 0 },
        "base_max": { "type": "number", "minimum": 0 },
        "equity_offered": { "type": "boolean" },
        "bonus_structure": { "type": "string", "maxLength": 500 }
      }
    },
    "location": {
      "type": "object",
      "required": ["type"],
      "properties": {
        "type": {
          "type": "string",
          "enum": ["remote", "hybrid", "onsite"]
        },
        "regions_allowed": {
          "type": "array",
          "items": { "type": "string" },
          "description": "Allowed candidate regions (e.g., 'EU', 'US-East', 'LATAM')"
        },
        "office_location": { "type": "string" },
        "timezone_overlap_required": {
          "type": "string",
          "description": "Minimum timezone overlap (e.g., 'CET ±2h')"
        }
      }
    },
    "engagement": {
      "type": "object",
      "properties": {
        "type": {
          "type": "string",
          "enum": ["permanent", "contract", "fractional", "freelance"]
        },
        "duration_months": {
          "type": "integer",
          "description": "For contract/fractional: expected duration"
        },
        "start_date": { "type": "string", "format": "date" }
      }
    },
    "description": {
      "type": "string",
      "maxLength": 5000,
      "description": "Human-readable role description"
    },
    "recruiter_card_url": {
      "type": "string",
      "format": "uri",
      "description": "Link to the posting org's recruiter_profile.json"
    }
  }
}
```

---

## 4. `reputation.json` Schema (Network-Generated)

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "Scoutica Recruiter Reputation",
  "description": "Computed by the network — NOT self-declared. Measures observable recruiter behavior.",
  "type": "object",
  "properties": {
    "trust_score": { "type": "number", "minimum": 0, "maximum": 100 },
    "trust_level": {
      "type": "string",
      "enum": ["new", "building", "established", "trusted", "elite"]
    },
    "metrics": {
      "type": "object",
      "properties": {
        "response_rate_pct": { "type": "number" },
        "ghosting_rate_pct": { "type": "number" },
        "hire_rate_pct": { "type": "number" },
        "rejection_rate_pct": { "type": "number" },
        "avg_response_time_hours": { "type": "number" },
        "total_conversations_30d": { "type": "integer" },
        "total_hires_90d": { "type": "integer" },
        "spam_flags_30d": { "type": "integer" }
      }
    },
    "computed_at": { "type": "string", "format": "date-time" },
    "member_since": { "type": "string", "format": "date" }
  }
}
```

---

## 5. `scoutica_message.json` Schema

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "Scoutica Agent Message",
  "description": "Standard message envelope for agent-to-agent communication.",
  "type": "object",
  "required": ["message_id", "type", "sender", "recipient", "timestamp"],
  "properties": {
    "message_id": {
      "type": "string",
      "pattern": "^msg_[a-f0-9]{6,}$"
    },
    "type": {
      "type": "string",
      "enum": [
        "rules.check",
        "opportunity.pitch",
        "opportunity.offer",
        "response.accept",
        "response.reject",
        "response.withdraw",
        "status.check",
        "event.ghosting"
      ]
    },
    "sender": {
      "type": "object",
      "required": ["card_url"],
      "properties": {
        "card_url": { "type": "string", "format": "uri" },
        "signature": { "type": "string", "description": "Ed25519 signature (V3)" }
      }
    },
    "recipient": {
      "type": "string",
      "format": "uri",
      "description": "URL of the recipient's card"
    },
    "conversation_id": {
      "type": "string",
      "pattern": "^conv_[a-f0-9]{6,}$",
      "description": "Groups messages into a conversation thread"
    },
    "in_reply_to": {
      "type": "string",
      "description": "message_id of the message being replied to"
    },
    "timestamp": { "type": "string", "format": "date-time" },
    "payload": {
      "type": "object",
      "description": "Message-type-specific data (role_url, reasons, calendar link, etc.)"
    },
    "ttl_hours": {
      "type": "integer",
      "minimum": 1,
      "default": 168,
      "description": "Message expiration in hours (default: 7 days)"
    }
  }
}
```

---

## 6. Schema Registry & Versioning

All schemas are published to `https://schema.scoutica.com/v1/` and follow semantic versioning:
- **Breaking changes** (field removals, type changes) → major version bump (`v2`)
- **Additions** (new optional fields) → minor version bump (`v1.1`)
- **Fixes** (description clarifications) → patch version bump (`v1.0.1`)

### File Locations
```
scoutica-protocol/schemas/
├── candidate/
│   ├── profile.schema.json          (existing)
│   ├── rules.schema.json            (existing)
│   ├── evidence.schema.json         (existing)
│   └── scoutica_discovery.schema.json (existing)
└── recruiter/
    ├── recruiter_profile.schema.json (NEW)
    ├── hiring_rules.schema.json      (NEW)
    ├── role.schema.json              (NEW)
    ├── reputation.schema.json        (NEW)
    └── message.schema.json           (NEW)
```
