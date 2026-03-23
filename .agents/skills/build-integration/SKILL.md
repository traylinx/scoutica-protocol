---
name: build-integration
description: Build a plugin, SDK, or integration that consumes the Scoutica Protocol. Use when asked to connect Scoutica with a job board, ATS, website, or any external application. Provides the API contract, data schemas, and integration patterns.
---

# build-integration

Build applications, plugins, or integrations that consume Scoutica Skill Cards.

## When to Use

- User wants to build a job board that reads Scoutica cards
- User wants to add "Import Scoutica Profile" to their app
- User wants to build an ATS integration
- User wants to create a badge or widget for a website
- User wants to build a registry or search engine for cards

## How to Fetch a Card

### From GitHub (Most Common)

```bash
# Raw GitHub URLs
BASE="https://raw.githubusercontent.com/{user}/{repo}/main"

curl -s "$BASE/profile.json"   | jq .
curl -s "$BASE/rules.yaml"     # Parse with any YAML parser
curl -s "$BASE/evidence.json"  | jq .
curl -s "$BASE/SKILL.md"       # Read as markdown
```

### From Any URL

Cards can be hosted anywhere. The standard structure is:

```
<base_url>/
├── profile.json
├── rules.yaml
├── evidence.json
└── SKILL.md
```

### Discovery: scoutica.json

Check for a `scoutica.json` at the root of any repo to find cards:

```json
{
  "scoutica": "0.1.0",
  "card_url": "https://raw.githubusercontent.com/user/my-card/main/",
  "name": "Full Name",
  "title": "Professional Title",
  "updated": "2026-03-23"
}
```

## Integration Patterns

### Pattern 1: Read-Only Import

The simplest integration — fetch and display a card.

```python
import requests, json, yaml

def fetch_card(base_url):
    """Fetch all 4 card files from a base URL."""
    card = {}
    card['profile'] = requests.get(f"{base_url}/profile.json").json()
    card['rules'] = yaml.safe_load(requests.get(f"{base_url}/rules.yaml").text)
    card['evidence'] = requests.get(f"{base_url}/evidence.json").json()
    card['skill_md'] = requests.get(f"{base_url}/SKILL.md").text
    return card

# Usage
card = fetch_card("https://raw.githubusercontent.com/user/card/main")
print(card['profile']['name'])       # "Sebastian Schkudlara"
print(card['profile']['skills'])     # {languages: [...], frameworks: [...]}
print(card['rules']['compensation']) # {minimum_base_eur: "negotiable"}
```

```javascript
// JavaScript/Node.js
async function fetchCard(baseUrl) {
  const [profile, rules, evidence] = await Promise.all([
    fetch(`${baseUrl}/profile.json`).then(r => r.json()),
    fetch(`${baseUrl}/rules.yaml`).then(r => r.text()),
    fetch(`${baseUrl}/evidence.json`).then(r => r.json()),
  ]);
  return { profile, rules, evidence };
}
```

### Pattern 2: Search & Match

Build a search engine that indexes cards.

```python
def search_cards(registry_index, query):
    """Search the registry for matching candidates."""
    results = []
    for entry in registry_index:
        card = fetch_card(entry['card_url'])
        score = calculate_match(card['profile'], query)
        if score > 40:  # minimum threshold
            results.append({
                'name': card['profile']['name'],
                'score': score,
                'url': entry['card_url']
            })
    return sorted(results, key=lambda x: x['score'], reverse=True)
```

### Pattern 3: Rules Pre-Screening

Check if an offer would be auto-rejected BEFORE contacting the candidate.

```python
def pre_screen(card, offer):
    """Check if an offer passes the candidate's rules."""
    rules = card['rules']
    
    # Auto-reject checks
    if offer.get('industry') in rules.get('auto_reject', {}).get('blocked_industries', []):
        return {"status": "REJECTED", "reason": "blocked_industry"}
    
    if offer.get('engagement_type') not in rules.get('engagement', {}).get('allowed_types', []):
        return {"status": "REJECTED", "reason": "engagement_type_mismatch"}
    
    min_salary = rules.get('compensation', {}).get('minimum_base_eur')
    if min_salary != 'negotiable' and offer.get('salary', 0) < int(min_salary):
        return {"status": "REJECTED", "reason": "salary_below_minimum"}
    
    return {"status": "PASS"}
```

### Pattern 4: Embeddable Widget

```html
<!-- Badge for personal website -->
<div id="scoutica-card" data-url="https://github.com/user/card"></div>
<script src="https://unpkg.com/scoutica-widget@latest"></script>
```

## Data Security Rules for Integrations

1. **Cache responsibly** — cards can be cached but refresh at least every 24h
2. **Respect privacy zones** — Zone 1 is public, Zone 2 needs auth, Zone 3 needs approval
3. **Never store Zone 3 data** — email, phone, exact salary are ephemeral only
4. **Audit trail** — log every card access (who, when, what fields) for EU AI Act
5. **Candidate can revoke** — if card is deleted, purge all cached data

## Schema Validation

Always validate fetched cards against the JSON schemas:

```bash
# Schemas are in the schemas/ directory
python3 tools/validate_card.py <card-folder>
```

Or in code:

```python
import jsonschema, json

schema = json.load(open('schemas/candidate_profile.schema.json'))
profile = json.load(open('profile.json'))
jsonschema.validate(profile, schema)  # Raises if invalid
```

## File References

- Schemas: `schemas/*.schema.json`
- Sample card: `protocol/examples/sample_card/`
- CLI source: `tools/scoutica`
- Flow diagrams: `.specs/protocol_flows.md`
