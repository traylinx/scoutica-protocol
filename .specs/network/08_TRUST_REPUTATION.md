# 🛡️ Trust & Reputation Engine

> Recruiters earn trust through behavior, not self-declaration. The network enforces accountability algorithmically.

---

## 1. The Trust Score

Every recruiter entity has a `trust_score` (0-100) computed from observable on-chain behavior.

### 1.1 Score Components

| Component | Weight | Signals |
|-----------|--------|---------|
| **Response Rate** | 30% | % of accepted candidates who receive a follow-up within 7 days |
| **Ghosting Penalty** | 25% | Inverse of ghosting incidents (post-acceptance silence >14 days) |
| **Hire Rate** | 20% | % of conversations that lead to confirmed hires |
| **Spam Score** | 15% | Ratio of rejections (auto + manual) to total pitches sent |
| **Tenure** | 10% | Days since org verification (longer = more stable) |

### 1.2 Formula
```
trust_score = (
    response_rate * 0.30 +
    (1 - ghosting_rate) * 100 * 0.25 +
    hire_rate * 100 * 0.20 +
    (1 - rejection_rate) * 100 * 0.15 +
    min(tenure_days / 365 * 100, 100) * 0.10
)
```

### 1.3 Example Calculation
```
NovaTech AI:
  response_rate:   92% → 92 * 0.30 = 27.6
  ghosting_rate:   2%  → 98 * 0.25 = 24.5
  hire_rate:       12% → 12 * 0.20 = 2.4
  rejection_rate:  35% → 65 * 0.15 = 9.75
  tenure_days:     180 → 49 * 0.10 = 4.9
  ──────────────────────────────────
  TOTAL: 69.15 → Trust Level: "established"
```

---

## 2. The 5 Trust Levels

| Level | Score Range | Permissions | Rate Limits |
|-------|------------|-------------|-------------|
| `new` | 0-25 | Read public cards only | 10 searches/day, 5 pings/day |
| `building` | 26-50 | Send `rules.check` + `opportunity.pitch` | 50 searches/day, 20 pings/day |
| `established` | 51-75 | Full negotiation, evidence requests | 500 searches/day, 100 pings/day |
| `trusted` | 76-90 | Priority ranking in candidate inboxes | 2,000 searches/day, 500 pings/day |
| `elite` | 91-100 | Endorsed by network, premium badge | 10,000 searches/day, unlimited pings |

---

## 3. Trust Decay Functions

Trust is not static. It decays if the recruiter stops engaging.

### 3.1 Inactivity Decay
```
If no activity for 30 days: trust_score -= 2 points/month
If no activity for 90 days: trust_score -= 5 points/month
If no activity for 180 days: trust_level drops to "new"
```

### 3.2 Ghosting Decay (Acute)
Each ghosting event applies an immediate penalty:
```
First ghost:  -5 points
Second ghost: -10 points
Third ghost:  -20 points + forced cool-down (7 days no new pings)
```

### 3.3 Recovery
Trust can be rebuilt through consistent good behavior:
```
Each successful hire interaction: +3 points
Each on-time response (within SLA): +0.5 points
Domain re-verification: +5 points (once per quarter)
```

---

## 4. Anti-Gaming Measures

### 4.1 Sybil Prevention
- One recruiter card per verified domain.
- DNS TXT verification required for `building` level and above.
- Multiple cards from the same IP/domain are flagged automatically.

### 4.2 Fake Hire Prevention
- Hire rate is only counted when both sides confirm (bilateral acknowledgment).
- A candidate must separately confirm "I was hired" for it to count.

### 4.3 Mass-Ping Detection
- If a recruiter sends >50 `opportunity.offer` messages in 24 hours with >80% rejection rate → automatic `spam_flag` applied.
- Flag triggers: 7-day cool-down, trust_score penalty of -15.

### 4.4 Evidence Manipulation
- Recruiter reputation data is stored on the registry (not self-hosted).
- Recruiters cannot modify their own `reputation.json` — it is computed by the network.

---

## 5. Candidate-Controlled Trust Thresholds

Candidates can set their own minimum trust requirements in `rules.yaml`:
```yaml
recruiter_filters:
  min_trust_level: "established"     # Ignore anything below this
  min_trust_score: 60                # Hard floor on numeric score
  block_unverified_domains: true     # Require DNS verification
  require_salary_transparency: true  # Reject roles without compensation range
```

---

## 6. Trust Score Visibility

### 6.1 Public (Readable by anyone)
- `trust_level` (enum: new → elite)
- `verified_domain` (boolean)
- `member_since` (date)

### 6.2 Gated (Readable by verified candidates only)
- `trust_score` (numeric 0-100)
- `ghosting_count_90d`
- `avg_response_time_hours`
- `hire_rate`
- `spam_flags`
