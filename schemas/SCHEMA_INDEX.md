# Scoutica Schema Index

Scoutica's JSON Schemas live in **two intentional homes** reflecting how the protocol grew.
This split is deliberate (temporal evolution) — do **not** merge the trees. This index is the
map so the two homes do not drift.

## Homes

| Home | Owns | Landed |
|------|------|--------|
| `protocol/platform/01_schemas/` | **Candidate protocol core** — `candidate_profile`, `roe`, `evidence` | launch |
| `schemas/recruiter/` | **Employer network** — `role`, `recruiter_profile`, `hiring_rules`, `message`, `reputation` | employer network |
| `schemas/registry/` | **Registry indexes** — `candidates_index`, `roles_index` | v0.4.0 |
| `schemas/scoutica_discovery.schema.json` | discovery file (`scoutica.json`) | v0.4.0 |

Every schema now carries a stable `$id` of the form `https://scoutica.com/schemas/<file>`.

## Canonical shared enums (single source of truth)

To stop cross-home drift, these enum values are canonical wherever they appear:

- **`engagement.type` / `allowed_types`** — canonical set is
  **`permanent`, `contract`, `fractional`, `advisory`, `internship`**.
  `freelance` is an accepted **input alias of `contract`** (normalized in `tools/scoring.py`
  via `_norm_engagement`) and is **not** a first-class type — it must not appear in any enum.
  Owner reference: `protocol/platform/01_schemas/roe.schema.json`.

When adding or changing a shared enum, update every home listed above and the normalizer in
`tools/scoring.py`, and add/extend the drift check in `tests/phase4.test.sh`.

## Version field

Card writers historically stamp different version keys (`scoutica`, `scoutica_version`,
`schema_version`, `version`). Normalizing the persisted key across all writers is a card-format
migration and is **parked** (out of scope for the remediation sprint); it is tracked here so the
inconsistency is documented rather than silent.
