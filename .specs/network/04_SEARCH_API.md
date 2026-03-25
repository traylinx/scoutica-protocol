# 🔎 Scoutica Protocol Search & Discovery API

## 1. 3-Layer Search Architecture 
We are evolving the search capabilities for Scoutica across three distinct phases, transitioning from zero-infrastructure to fully decentralized.

### 1.1 `V1` GitHub Topics & Scripts (Immediate)
- **Mechanism:** Repositories tag themselves with `scoutica-card`.
- **Crawling:** A simple python script loops over the GitHub Search API, fetching metadata and maintaining a static `index.json`.
- **Search:** Client-side filtering over the `index.json` file.

### 1.2 `V2` REST API Registry (Mid-Term)
- **Mechanism:** A centralized indexer (e.g., `registry.scoutica.com`).
- **Endpoint:** `GET /search?skills=python&location=eu`
- **Indexing:** Candidates `POST /register { "url": "github.com/my/card" }` to be added.
- **Why:** Faster response times and complex vector/semantic searches (via `pgvector`).

### 1.3 `V3` Federated Network (Long-Term Moonshot)
- **Mechanism:** P2P indexer nodes.
- **Protocol:** Nodes share candidate profiles over a gossip network.
- **Scale:** Nobody owns the database, eliminating single points of failure.

## 2. API Endpoint Specification (V2)

### `GET /api/v1/search`

**Request:**
```json
{
  "q": "Senior AI Engineer",
  "skills_required": ["Python", "Docker"],
  "location": "remote",
  "limit": 50,
  "recruiter_id": "org_7b82f" 
}
```

**Response:**
```json
{
  "results": [
    {
      "card_url": "https://github.com/rschumann/sebastian-schkudlara-card",
      "score": 95,
      "last_updated": "2026-03-24T18:00:00Z"
    }
  ],
  "next_cursor": "c2hvd19tb3Jl"
}
```

## 3. The Ranking Algorithm
When ranking candidates, the registry uses:
1. **Freshness:** Decay function on `last_updated` (stale profiles rank lower).
2. **Skill Density:** Exact keyword overlap in `profile.json`.
3. **Evidence Weighting:** Candidates with a populated `evidence.json` (verified links) get a +20% boost.

## 4. Rate-Limiting & Trust Verification
To prevent recruiters from scraping the entire candidate database:
- `anonymous`: 10 searches / day
- `new` recruiter: 50 searches / day
- `verified` recruiter: 500 searches / day
- `trusted` recruiter: 5,000 searches / day
