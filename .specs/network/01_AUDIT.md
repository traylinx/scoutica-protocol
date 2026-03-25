# 🔍 Scoutica Protocol — Recruiter Side Gap Analysis

## 1. Current State
- The Scoutica protocol is currently **100% candidate-centric**.
- Candidates can generate structured `profile.json`, `evidence.json`, and `rules.yaml` files.
- Candidates can serve their profiles via decentralized URLs (GitHub, IPFS, private servers).
- **GAP:** There are absolutely zero specifications for how recruiters, headhunters, or hiring platforms interact with these cards natively.

## 2. Identified Gaps

### 2.1 Missing Recruiter Identity
- Recruiters pinging candidate agents currently have no verifiable identity format.
- No reputation layer to prevent "spray-and-pray" recruiter spam.
- No structured `recruiter.json` format to declare corporate identity.

### 2.2 Missing Structured Job Listings
- Candidates are structured, but job postings are still unstructured text.
- No deterministic way for a candidate agent to score a job posting against `rules.yaml`.
- Ghost jobs cannot be programmatically detected or filtered.

### 2.3 Discovery & Search Void
- No mechanism for recruiters to run structured queries (e.g., `FIND Senior Go Developer WHERE remote=EU AND salary_expectation<=120k`).
- Requires a multi-tier search architecture (V1 plain GitHub scrapers, V2 REST gateways, V3 Federated search nodes).

### 2.4 Unstandardized Agent-to-Agent Handshake
- How does a Recruiter Agent ping a Candidate Agent?
- What are the required message payloads? (Offer, Rule Check, Interview Request, Decline)
- How is anti-spam enforced?

### 2.5 Missing Dual-Agent Model
- A single person can be both a Candidate AND an Employer simultaneously (e.g., a Fractional CTO who hires for clients while being open to advisory roles).
- No mechanism to link a Candidate Card and an Employer Card to the same human identity without leaking PII.
- The agent must route inbound messages correctly: "Is this for my Candidate hat or my Employer hat?"

### 2.6 Missing Team/Organization Model
- An Employer Card may be managed by multiple humans (5 recruiters at the same company).
- No team management layer — who can post roles? Who can respond to candidates?
- External agencies may manage cards for multiple client organizations.

## 3. The Goal
Shift the Scoutica Protocol from a **Candidate Specification** to a **Two-Sided Market Protocol** by standardizing recruiter identities, job definitions, search pipelines, communication handshakes, dual-identity support, and team collaboration.
