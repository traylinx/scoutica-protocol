# tests/fixtures

Canonical, reusable inputs for the Scoutica test suite. Fixtures contain **mock data only**
(AGENTS.md rule 1 — never real names/emails/salaries).

| Fixture | Used by | Purpose |
|---------|---------|---------|
| `ai_response_malicious.txt` | Phase 1 RCE regression (`F-CRIT-RCE-001`) | An AI *scan* response carrying injection breakers (`'''`, `;`, heredoc/backtick terminators) plus a valid fenced JSON profile. Tests substitute the literal token `__CANARY__` with an absolute path under `$WORK`, then assert (via `assert_no_exec`) that parsing the response never creates that path. |
| `card_valid/profile.json` | scoring / summary tests (Phase 2) | A minimal schema-valid candidate profile using the mock persona "Alice Developer". |

## Conventions

- Tests never mutate a fixture in place. Copy into `$WORK` (provided by `run.sh`) first.
- Any path a payload might try to touch is templated as `__CANARY__` and resolved at run time
  so the canary lives inside the per-run temp dir and is auto-cleaned.
