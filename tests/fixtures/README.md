# tests/fixtures

Canonical, reusable inputs for the Scoutica test suite. Fixtures contain **mock data only**
(AGENTS.md rule 1 — never real names/emails/salaries).

| Fixture | Used by | Purpose |
|---------|---------|---------|
| `ai_response_malicious.txt` | Phase 1 RCE regression (`F-CRIT-RCE-001`) | An AI *scan* response carrying injection breakers (`'''`, `;`, heredoc/backtick terminators) plus a valid fenced JSON profile. Tests substitute the literal token `__CANARY__` with an absolute path under `$WORK`, then assert (via `assert_no_exec`) that parsing the response never creates that path. |
| `card_valid/profile.json` | scoring / summary tests (Phase 2) | A minimal schema-valid candidate profile using the mock persona "Alice Developer". |
| `bin/fake-provider` | scan/provider lifecycle tests | Environment-driven provider double with argv/stdin/PID/readiness/signal capture. |
| `hostile_cwd/schemas/` | schema trust tests | Deliberately permissive schemas that must never shadow trusted schemas through cwd lookup. |
| `http_server.py` | bounded fetch tests | Loopback server exposing valid, redirect, private redirect, invalid, wrong-type, oversized, and slow responses. |
| `scan_runtime/valid_response.json` | scan provider/runtime tests | Minimal strict card response shared by provider, cleanup, state, and promotion cases. |
| `scan_runtime/invalid_response.json` | scan provider/runtime tests | Deterministic invalid policy response that must never replace a prior card or state. |
| `scan_runtime/pty_run.py` | scan consent tests | Runs the CLI in a PTY and feeds yes, no, or EOF without depending on platform-specific `script` flags. |
| `scan_runtime/signal_run.py` | scan lifecycle tests | Signals the scan parent only after the provider double reports readiness. |
| `scan_runtime/ail_server.py` | switchAILocal adapter tests | Fixed-loopback OpenAI-compatible response server that captures the request body. |

## Conventions

- Tests never mutate a fixture in place. Copy into `$WORK` (provided by `run.sh`) first.
- Any path a payload might try to touch is templated as `__CANARY__` and resolved at run time
  so the canary lives inside the per-run temp dir and is auto-cleaned.
- Source `tests/lib/fixtures.sh` for isolated HOME/SCOUTICA_HOME/PATH/git configuration, fake
  provider installation, bare Git remotes, symlink victims, HTTP lifecycle, and PID coordination.
