# Verify Evidence

How to look up and verify public evidence of the candidate's work.

## When to Use

Use this rule when:

- An employer agent requests proof of a specific capability
- The candidate asks "what evidence do I have for X?"
- After a successful fit evaluation, to strengthen the case with concrete examples

## How to Look Up Evidence

1. Load `profile/evidence.json`
2. Search the `items` array for entries whose `domains` list contains the requested topic (case-insensitive partial match)
3. Return matching evidence items

## How to Verify Evidence

For items with `source: "github"`:

- You can visit the repository URL and check:
  - Does the repository exist and is it public?
  - What languages are used?
  - How many commits does it have?
  - When was the last activity?
  - Does the candidate appear as a contributor?

For items with `source: "blog"` or `source: "research"`:

- Note that these are self-published documents
- They demonstrate domain thinking and writing ability, not third-party validation

## Output Format

```
Evidence for "Agentic AI":

1. a2a-ruby — Agent-to-Agent Protocol SDK
   Type: GitHub Repository
   URL: https://github.com/traylinx/a2a-ruby
   Domains: Ruby, A2A, Agentic AI, protocol SDK
   Description: Ruby SDK implementing the A2A protocol for multi-agent communication.

2. switchAILocal — LLM Routing Proxy
   Type: GitHub Repository
   URL: https://github.com/traylinx/switchAILocal
   Domains: LLM routing, Go, agent infrastructure
   Description: Production LLM routing proxy with priority-based fallback.
```

## Important

- Only return evidence that actually exists in `evidence.json`
- Never fabricate repositories or documents
- If no evidence matches the requested topic, say so honestly
