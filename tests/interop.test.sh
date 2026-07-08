#!/bin/sh
# tests/interop.test.sh — Track A regression tests for `scoutica import aijs`.
#
# Contract under test (SPRINT-AIJS-INTEROP):
#   scoutica import aijs <src-dir> [--to <dir>] [--salary-floor-eur N] [--force]
#   exit 0 = success · 2 = placeholder-abort (required field unfilled) ·
#           3 = enum-unresolvable in non-TTY · 4 = target refusal (non-empty dir / symlink)
#
# Written TDD-first in Phase 0: every case FAILs until Phase 1 lands the importer, so all
# finding-ids below are seeded in tests/EXPECTED_FAIL.txt (XFAIL). As each is implemented the
# case flips to PASS (XPASS) and its id is removed from the allowlist.
. "$TESTLIB/assert.sh"

JAA=".claude/skills/job-application-assistant"

# ── T-A1-CLI-001 — happy path: import the filled fixture, get 4 schema-shaped files ──
t_begin T-A1-CLI-001 "import aijs filled -> exit 0, four card files created"
out="$WORK/cli_ok"
assert_exit 0 "$SCOUTICA" import aijs "$FIXTURES/aijs_filled" --to "$out"
for f in profile.json rules.yaml evidence.json SKILL.md; do
    assert_exit 0 test -f "$out/$f"
done
t_end

# ── T-A1-EMIT-001 — produced card validates; non-empty & symlinked targets refused (exit 4) ──
t_begin T-A1-EMIT-001 "produced card validates; non-empty + symlinked targets refused (exit 4)"
out="$WORK/emit_ok"
"$SCOUTICA" import aijs "$FIXTURES/aijs_filled" --to "$out" </dev/null >/dev/null 2>&1
assert_exit 0 "$SCOUTICA" validate "$out"
# a non-empty target without --force is refused (exit 4), leaving the pre-existing file untouched
ne="$WORK/emit_nonempty"; mkdir -p "$ne"; : > "$ne/pre_existing.txt"
"$SCOUTICA" import aijs "$FIXTURES/aijs_filled" --to "$ne" </dev/null >/dev/null 2>&1
assert_eq 4 "$?" "non-empty target without --force must be refused"
# a symlinked profile.json in the target is refused EVEN with --force (symlink guard beats --force)
sym="$WORK/emit_sym"; mkdir -p "$sym"; ln -s "$WORK/evil_target" "$sym/profile.json"
"$SCOUTICA" import aijs "$FIXTURES/aijs_filled" --to "$sym" --force </dev/null >/dev/null 2>&1
assert_eq 4 "$?" "symlinked profile.json target must be refused"
assert_exit 1 test -e "$WORK/evil_target"
# a symlinked PARENT dir is refused (symlink-escape via the directory we would create into)
mkdir -p "$WORK/real_elsewhere"; ln -s "$WORK/real_elsewhere" "$WORK/emit_symparent"
"$SCOUTICA" import aijs "$FIXTURES/aijs_filled" --to "$WORK/emit_symparent/card" </dev/null >/dev/null 2>&1
assert_eq 4 "$?" "symlinked parent directory must be refused"
t_end

# ── T-A1-HIDDEN-001 — a dir holding ONLY hidden files is not empty; refuse without --force ──
t_begin T-A1-HIDDEN-001 "hidden-only target (.env/.git) is not empty -> refuse (exit 4), no clobber"
hd="$WORK/hidden_only"; mkdir -p "$hd"; printf 'SECRET=keep-me\n' > "$hd/.env"
"$SCOUTICA" import aijs "$FIXTURES/aijs_filled" --to "$hd" </dev/null >/dev/null 2>&1
assert_eq 4 "$?" "dir containing only a dotfile must be refused without --force"
assert_grep 'SECRET=keep-me' "$hd/.env"                       # the pre-existing dotfile is untouched
_n=0; for f in profile.json rules.yaml evidence.json SKILL.md; do [ -f "$hd/$f" ] && _n=$((_n + 1)); done
assert_eq 0 "$_n" "no card files written into the refused hidden-only target"
t_end

# ── T-A1-SALARY-001 — salary floor emits only schema-legal keys; negatives rejected ──
t_begin T-A1-SALARY-001 "salary floor: compensable keys only, negatives rejected, valid output"
# permanent fork + floor -> minimum_base_eur.permanent present and card validates
"$SCOUTICA" import aijs "$FIXTURES/aijs_filled" --to "$WORK/sal_perm" --salary-floor-eur 90000 </dev/null >/dev/null 2>&1
assert_grep "permanent: 90000" "$WORK/sal_perm/rules.yaml"
assert_exit 0 "$SCOUTICA" validate "$WORK/sal_perm"
# internship-only fork + floor -> internship is NOT a compensable key, so no minimum_base_eur emitted
isrc="$WORK/sal_src"; mkdir -p "$isrc/$JAA"
cat > "$isrc/$JAA/01-candidate-profile.md" <<'EOF'
# Candidate Profile

## Identity
- **Name:** Intern Person
- **Status:** seeking an internship

## Professional Experience

### Senior Engineer - Acme (2018 - 2024)
- built things

## Technical Skills

### Programming & ML
- **Python** (expert): x

### Domain Expertise
- Backend
EOF
"$SCOUTICA" import aijs "$isrc" --to "$WORK/sal_intern" --salary-floor-eur 1000 </dev/null >/dev/null 2>&1
assert_eq 0 "$?" "internship-only + floor still succeeds"
assert_no_grep "minimum_base_eur" "$WORK/sal_intern/rules.yaml"
assert_exit 0 "$SCOUTICA" validate "$WORK/sal_intern"
# negative floor is rejected before anything is written
"$SCOUTICA" import aijs "$FIXTURES/aijs_filled" --to "$WORK/sal_neg" --salary-floor-eur -5 </dev/null >/dev/null 2>&1
assert_eq 1 "$?" "negative salary floor rejected"
t_end

# ── T-A1-PARSE-001 — hostile values become literal JSON; NOTHING executes ──
t_begin T-A1-PARSE-001 "hostile fixture: metachars land as literal data, no code execution"
out="$WORK/parse_host"
rm -f "$WORK"/aijs_pwned_canary* aijs_pwned_canary* 2>/dev/null
( cd "$WORK" && "$SCOUTICA" import aijs "$FIXTURES/aijs_hostile" --to "$out" </dev/null ) >/dev/null 2>&1
# the injection payloads must never have executed (no canary files anywhere reachable)
assert_exit 1 test -e "$WORK/aijs_pwned_canary"
assert_exit 1 test -e "$WORK/aijs_pwned_canary2"
assert_exit 1 test -e "$WORK/aijs_pwned_canary3"
assert_exit 1 test -e aijs_pwned_canary
# the hostile card IS produced (title yields a resolvable seniority); it must be well-formed JSON
# and the injection text must have survived VERBATIM as a string value (proves data, not code)
assert_exit 0 test -f "$out/profile.json"
assert_exit 0 python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$out/profile.json"
assert_grep 'touch aijs_pwned_canary' "$out/profile.json"
t_end

# ── T-B3-YAML-001 — a YAML-metachar skill can't corrupt or inject into SKILL.md frontmatter ──
# The hostile fixture's skill set includes "Go: bad". build_skill_md serializes the frontmatter
# (never string-interpolates), so it must remain well-formed YAML with EXACTLY the expected keys.
# validate_card.py does not parse SKILL.md frontmatter, so this test is the only guard for it.
t_begin T-B3-YAML-001 "hostile skill (\"Go: bad\") -> SKILL.md frontmatter stays valid YAML, no injection"
yout="$WORK/yaml_host"
"$SCOUTICA" import aijs "$FIXTURES/aijs_hostile" --to "$yout" </dev/null >/dev/null 2>&1
assert_exit 0 test -f "$yout/SKILL.md"
assert_exit 0 python3 - "$yout/SKILL.md" <<'PY'
import sys
try:
    import yaml
except Exception:
    sys.exit(0)  # PyYAML absent: frontmatter uses the JSON fallback (a valid YAML subset); skip
text = open(sys.argv[1], encoding="utf-8").read()
assert text.startswith("---\n"), "SKILL.md must open with a frontmatter fence"
fm = text.split("---\n", 2)[1]               # block between the first two fences
doc = yaml.safe_load(fm)                      # raises on corruption -> non-zero exit -> test FAIL
assert isinstance(doc, dict), "frontmatter is not a mapping"
assert set(doc) == {"name", "description", "metadata"}, "unexpected/injected frontmatter keys: %s" % sorted(doc)
assert doc["name"] == "scoutica"
assert "Go: bad" in doc["metadata"]["tags"], "hostile skill was dropped, not neutralised"
PY
t_end

# ── T-A1-REFUSE-001 — pristine placeholders -> abort, ZERO files written ──
t_begin T-A1-REFUSE-001 "placeholder fixture -> abort (exit 2), no partial writes"
out="$WORK/refuse_ph"
"$SCOUTICA" import aijs "$FIXTURES/aijs_placeholders" --to "$out" </dev/null >/dev/null 2>&1
assert_eq 2 "$?" "placeholder abort exit code"
_n=0
for f in profile.json rules.yaml evidence.json SKILL.md; do [ -f "$out/$f" ] && _n=$((_n + 1)); done
assert_eq 0 "$_n" "no partial card files after abort"
t_end

# ── T-A1-MAP-001 — an unresolvable REQUIRED enum aborts (exit 3) in non-TTY (never guessed) ──
t_begin T-A1-MAP-001 "unresolvable seniority in non-TTY -> abort (exit 3)"
src="$WORK/mapsrc"; mkdir -p "$src/$JAA"
cat > "$src/$JAA/01-candidate-profile.md" <<'EOF'
# Candidate Profile

## Identity
- **Name:** Sam Sample
- **Status:** available in 2 weeks

## Professional Experience

### Zorblax Wrangler - Acme
Somewhere
- Wrangled zorblaxes

## Technical Skills

### Programming & ML
- **Python** (expert): things

### Domain Expertise
- Zorblaxing

### Software & Tools
- Docker
EOF
"$SCOUTICA" import aijs "$src" --to "$WORK/map_out" </dev/null >/dev/null 2>&1
assert_eq 3 "$?" "enum-unresolvable abort in non-TTY (no dates, no seniority word)"
t_end

# ── T-A1-CONSENT-001 — importer prints no imported PII values; touches no git ──
t_begin T-A1-CONSENT-001 "importer emits field names only (no PII values), creates no git repo"
out="$WORK/consent_out"; log="$WORK/consent.log"
"$SCOUTICA" import aijs "$FIXTURES/aijs_filled" --to "$out" </dev/null >"$log" 2>&1
assert_exit 0 test -f "$out/profile.json"   # precondition: the import actually ran and succeeded
assert_no_grep "alice@example\.com" "$log"
assert_no_grep "Alice Developer" "$log"
assert_exit 1 test -d "$out/.git"
t_end

# ── T-F4-E2E-001 — the whole funnel on one profile: import -> validate -> score (accept AND reject) ──
t_begin T-F4-E2E-001 "funnel: import -> validate -> score; matching role accepted, contract role rejected"
out="$WORK/e2e_card"
"$SCOUTICA" import aijs "$FIXTURES/aijs_filled" --to "$out" </dev/null >/dev/null 2>&1
assert_exit 0 "$SCOUTICA" validate "$out"
# the role fixtures must themselves be role-schema-valid, else the scorer silently ignores their fields
assert_exit 0 python3 -c "import json,jsonschema,sys; jsonschema.validate(json.load(open(sys.argv[1])), json.load(open(sys.argv[2])))" \
    "$FIXTURES/sample_role.json" "$REPO_ROOT/schemas/recruiter/role.schema.json"
# `scoutica evaluate --json` stdout must be pure JSON — the apply-to-role gate parses it
"$SCOUTICA" evaluate --json "$out" --role "$FIXTURES/sample_role.json" 2>/dev/null | python3 -c "import sys,json; json.load(sys.stdin)"
assert_eq 0 "$?" "scoutica evaluate --json emits parseable JSON"
# SEMANTIC funnel proof (not just "no crash"): a matching role is accepted; a contract role is rejected
# by the candidate's own permanent-only rule — the gate the apply-to-role skill relies on actually fires.
_acc=$(python3 "$REPO_ROOT/tools/scoring.py" --json "$out/profile.json" "$out/rules.yaml" "$FIXTURES/sample_role.json" 2>/dev/null \
       | python3 -c "import sys,json; print(json.load(sys.stdin)['candidate_accepts'])")
assert_eq "True" "$_acc" "matching role accepted (candidate_accepts)"
_rej=$(python3 "$REPO_ROOT/tools/scoring.py" --json "$out/profile.json" "$out/rules.yaml" "$FIXTURES/sample_role_reject.json" 2>/dev/null \
       | python3 -c "import sys,json; print(json.load(sys.stdin)['candidate_accepts'])")
assert_eq "False" "$_rej" "contract role rejected by candidate's permanent-only rule"
t_end

# ── T-A2-DOCS-001 — import docs exist, credit upstream, are registered in nav, leak no PII ──
t_begin T-A2-DOCS-001 "import docs present + credited + navigable, no fixture PII"
DOCS="$REPO_ROOT/docs-site"
assert_exit 0 test -f "$DOCS/cli/import.mdx"
assert_exit 0 test -f "$DOCS/guides/from-ai-job-search.mdx"
assert_grep "import aijs" "$DOCS/cli/import.mdx"
assert_grep "MadsLorentzen/ai-job-search" "$DOCS/cli/import.mdx"
assert_grep "cli/import" "$DOCS/docs.json"
assert_grep "guides/from-ai-job-search" "$DOCS/docs.json"
assert_no_grep "alice@example" "$DOCS/cli/import.mdx"
assert_no_grep "alice@example" "$DOCS/guides/from-ai-job-search.mdx"
t_end

# ── T-B3-SKILL-001 — apply-to-role skill: valid frontmatter, card-provenance rule, real paths, no PII ──
t_begin T-B3-SKILL-001 "apply-to-role skill present, provenance rule, references real paths, no PII"
SK="$REPO_ROOT/.agents/skills/apply-to-role/SKILL.md"
assert_exit 0 test -f "$SK"
assert_grep "^name: apply-to-role" "$SK"
assert_grep "^description:" "$SK"
assert_grep "src: profile.json" "$SK"                 # the stronger-than-upstream provenance rule
assert_exit 0 test -f "$REPO_ROOT/tools/scoring.py"   # a path the skill references must exist
assert_no_grep "alice@example" "$SK"                  # no fixture PII leaked into the skill
t_end

# ── T-B3-GATE-001 — the fit-gate contract is in the skill AND the documented scorer call runs green ──
t_begin T-B3-GATE-001 "apply-to-role runs the scorer as a gate; refuses on hard-reject"
SK="$REPO_ROOT/.agents/skills/apply-to-role/SKILL.md"
assert_grep "scoring.py" "$SK"
assert_grep "REFUSE to draft" "$SK"
assert_grep "manual_review" "$SK"
# the exact invocation the skill documents actually runs against a produced card + the sample role
card="$WORK/b3_card"
"$SCOUTICA" import aijs "$FIXTURES/aijs_filled" --to "$card" </dev/null >/dev/null 2>&1
assert_exit 0 python3 "$REPO_ROOT/tools/scoring.py" --json "$card/profile.json" "$card/rules.yaml" "$FIXTURES/sample_role.json"
t_end

# ── T-B3-NOTICE-001 — MIT attribution for the adapted pattern is present ──
t_begin T-B3-NOTICE-001 "NOTICE credits ai-job-search (MIT, Mads Lorentzen)"
NOTICE="$REPO_ROOT/NOTICE"
assert_exit 0 test -f "$NOTICE"
assert_grep "MIT License" "$NOTICE"
assert_grep "Mads Lorentzen" "$NOTICE"
assert_grep "ai-job-search" "$NOTICE"
t_end

# ── T-B3-GITIGNORE-001 — application drafts are gitignored by the card template ──
t_begin T-B3-GITIGNORE-001 "card.gitignore excludes applications/ (drafts never staged)"
assert_grep "^applications/" "$REPO_ROOT/protocol/templates/card.gitignore"
t_end
