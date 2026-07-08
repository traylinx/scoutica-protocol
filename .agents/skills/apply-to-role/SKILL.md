---
name: apply-to-role
description: Draft a tailored CV and cover letter for a specific role, grounded entirely in a candidate's Scoutica Skill Card. Runs the deterministic fit scorer as a gate first and refuses to draft when the candidate's own rules reject the role. Use when a candidate asks to apply to a job, tailor their CV, or write a cover letter from their card.
---

# apply-to-role

Turn a Scoutica Skill Card + a role into a tailored, **honest** application draft. This skill adapts the
drafter–reviewer application pattern from the ai-job-search project (see Attribution) to Scoutica's model:
the card is the single source of truth, and the candidate's own `rules.yaml` is the gate.

## When to Use

- A candidate asks "help me apply to this role" / "tailor my CV for this job" / "write a cover letter".
- You have a Scoutica Skill Card (a folder with `profile.json`, `rules.yaml`, `evidence.json`, `SKILL.md`)
  and a role (a `role.json` or a pasted job description).

## Hard rule: the card is the only source of truth

Every factual claim in the CV and cover letter MUST trace to a field in `profile.json` or an item in
`evidence.json`. Nothing is invented — not a skill, not a number, not a company, not a date. If the role
wants something the card does not support, that gap stays **visible**; it is never papered over.

**Provenance requirement (stronger than the source workflow):** annotate every factual **claim** — not
merely every line — with an HTML comment naming the JSON pointer it comes from, e.g.

```markdown
- Cut p99 API latency 38% by moving hot paths to Go <!-- src: profile.json#/summary -->
- Python, Go, PostgreSQL <!-- src: profile.json#/skills -->
```

The pointer must **actually support** the claim, not merely exist. A pointer proves the source field is
present; you must also confirm the claim is entailed by that field and does not exaggerate it. A broad
field like `profile.json#/summary` cannot be used to smuggle in a specific number, tool, or achievement the
card never states. If one sentence makes two claims, it carries two pointers. Any claim with no resolving
pointer — or whose pointer does not genuinely support it — is treated as fabricated and removed.

## Step 1 (MANDATORY): run the fit gate before drafting

Do not draft until the deterministic scorer has run. The candidate's `rules.yaml` is authoritative.

```bash
scoutica evaluate --json <card-dir> --role <role.json>
# or directly. The `--json` form is required to get a parseable result. Pass the recruiter/org card as
# the optional 4th arg so recruiter-scoped rules (e.g. blocked_industries, which need the role/org's
# industry metadata) also fire. Accurate rule parsing requires PyYAML — install it if scoring warns,
# otherwise list-valued rules (allowed_types, blocked_industries) may be read as empty and skip the gate.
python3 tools/scoring.py --json <card>/profile.json <card>/rules.yaml <role.json> [recruiter_profile.json]
```

Read the JSON result and branch on its actual fields (`hard_filters_passed`, `candidate_accepts`,
`verdict`, `rejection_reasons`, `candidate_reasons`):

- **`hard_filters_passed: false`** (verdict `HARD_REJECT`), or **`candidate_accepts: false`** →
  **REFUSE to draft.** Quote the offending entries from `rejection_reasons` / `candidate_reasons` so the
  candidate sees exactly which rule rejected the role (salary floor, remote policy, blocked industry,
  engagement type) and stop. Respecting the candidate's own rules is the entire point of the protocol —
  do not override them to "get the application out".
- **Soft reject** — any entry in `candidate_reasons` beginning `manual_review:` → surface that reason
  **verbatim** to the candidate and ask whether to proceed. Do not silently draft past a soft reject.
- **Otherwise** → continue to Step 2.

## Step 2: draft (drafter role)

Produce two Markdown files. Keep everything card-grounded and provenance-annotated (see the hard rule).

- **`cv.md`** — reframe the card's skills and experience toward the role's requirements. Lead with the
  overlap the fit report found. Every bullet carries a `<!-- src: ... -->` pointer.
- **`cover_letter.md`** — a short, specific letter. Open with genuine fit, address key requirements the
  card supports, and acknowledge one honest gap with how the candidate would close it. No generic filler.

### Relevance-weighted cutting

When the CV runs long, do **not** cut oldest-first. Score each candidate line by (a) relevance to this
role's requirements, (b) uniqueness in the document, (c) whether the cover letter depends on it, and cut
the lowest total first. An older bullet that hits the role's keywords outranks a recent one that does not.

## Step 3: review (reviewer role — fresh perspective)

Re-read the drafts against the card as if you were a skeptical second reader:

- **Factual** — every claim has a `<!-- src -->` pointer that actually resolves in `profile.json` /
  `evidence.json`. Any unpointered or non-resolving claim → delete it.
- **Targeting** — the opening is specific to the role, not generic; supported requirements are addressed;
  genuine gaps are acknowledged, never hidden.
- **Consistency** — CV and cover letter agree on titles, dates, and framing.
- **Honesty** — no skill/number/experience appears that the card does not contain. Synonyms are tightened
  to the role's exact term only where the card truthfully supports it.

Revise until the checklist passes, then present the result with the checklist outcome.

## Step 4: write outputs

Write the drafts and the fit report into the card workspace:

```
applications/<company>_<role>/
  ├── cv.md
  ├── cover_letter.md
  └── fit_report.json    # the exact scoring.py output from Step 1
```

`applications/` is gitignored by the card template, so drafts (which may reference private role details)
are never accidentally staged or published. Rendering to PDF/LaTeX is out of scope — hand the Markdown to
the candidate's own toolchain (for example, the ai-job-search LaTeX pipeline).

## Privacy & honesty

- **Enforce the card's privacy zones.** Before using any pointer, read `rules.yaml`'s `privacy` block. A
  claim whose pointer resolves to a field listed under `privacy.zone_3_private` (e.g. `name`, `email`,
  `phone`, `exact_salary`) must NOT appear in a draft unless the candidate explicitly approves it for this
  application. Draft primarily from Zone 1 (public) and Zone 2 data.
- Never fabricate. A visible gap is always better than a fabricated match.
- **The scorer's decision is final.** If `candidate_accepts` is false or a hard filter failed, this skill
  does not talk the candidate past their own rules.

## Attribution

The drafter–reviewer application pattern, the PDF/ATS honesty rule, and relevance-weighted cutting are
adapted from **ai-job-search** by Mads Lorentzen (MIT, © 2026) — https://github.com/MadsLorentzen/ai-job-search.
Scoutica reimplements the *pattern* against the Skill Card; no upstream code is vendored. See `NOTICE`.
