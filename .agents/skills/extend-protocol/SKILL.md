---
name: extend-protocol
description: Extend the Scoutica Protocol with new schemas, entity types, rule templates, or CLI commands. Use when asked to add new features, modify the card format, add support for new entity types (agents, teams, robots), or contribute to the protocol specification.
---

# extend-protocol

Add new capabilities to the Scoutica Protocol — new schemas, entity types, rules, or CLI features.

## When to Use

- User wants to add a new field to the card schema
- User wants to support a new entity type (AI agent, team, robot)
- User wants to add a new CLI command
- User wants to create a new evaluation rule template
- User wants to modify the protocol specification

## Extension Points

### 1. Add a New Schema Field

**Source:** `schemas/candidate_profile.schema.json`

```diff
 "skills": {
   "languages": [...],
   "frameworks": [...],
+  "ai_models": {
+    "type": "array",
+    "items": {"type": "string"},
+    "description": "AI/ML models the candidate has trained or deployed"
+  }
 }
```

**Checklist:**
- [ ] Add to JSON Schema with description and type
- [ ] Update `SCAN_PROMPT.md` so AI generation includes the new field
- [ ] Update `tools/scoutica` `cmd_init()` to ask for the new field
- [ ] Update sample card in `protocol/examples/sample_card/`
- [ ] Update `SKILL.md` agent instructions

### 2. Add a New Entity Type

The protocol supports multiple entity types beyond humans:

| Type | Card For | Example |
|------|----------|---------|
| `human` | Individual professional | Software engineer |
| `ai_agent` | Autonomous AI agent | Coding assistant, trading bot |
| `service` | API or SaaS product | Translation service, CDN |
| `robot` | Physical autonomous system | Warehouse robot, drone |
| `team` | Group of entities | Engineering squad |
| `organization` | Company or department | DevOps team at Company X |

**To add a new entity type:**

1. Create a schema variant: `schemas/<type>_profile.schema.json`
2. Create a card template: `protocol/platform/02_skill_patterns/template_<type>_skill.md`
3. Update the base schema's `entity_type` enum
4. Add CLI support: `scoutica init --type <type>`

### 3. Add a New Rule Template

**Location:** `templates/rules/`

Create a new `.md` file that follows this pattern:

```markdown
# Rule: <rule-name>

## Purpose
What this rule evaluates.

## Input
- `profile.json` fields used
- `rules.yaml` fields used

## Algorithm
1. Step-by-step evaluation logic
2. Clear decision criteria

## Output
- PASS / FAIL / SOFT_REJECT
- Reason string
- Confidence score (0-100)
```

**Checklist:**
- [ ] Create the rule file in `templates/rules/`
- [ ] Reference it in `SKILL.md` evaluation section
- [ ] Add to `cmd_scan()` so generated cards include it
- [ ] Update `protocol/examples/sample_card/rules/`

### 4. Add a New CLI Command

**Source:** `tools/scoutica` (bash) and `tools/scoutica.ps1` (PowerShell)

```bash
# In tools/scoutica — add the function:
cmd_newcommand() {
    # Implementation here
}

# In the main router:
case "$command" in
    init)       cmd_init "$@" ;;
    scan)       cmd_scan "$@" ;;
    newcommand) cmd_newcommand "$@" ;;  # ← add here
    ...
esac

# In cmd_help():
echo -e "  ${CYAN}newcommand${NC}       Description of what it does"
```

**Checklist:**
- [ ] Implement in `tools/scoutica` (bash)
- [ ] Implement in `tools/scoutica.ps1` (PowerShell)
- [ ] Add to `cmd_help()` in both CLIs
- [ ] Add to README.md commands section
- [ ] Update `SKILL.md` agent instructions
- [ ] Update `install.sh` / `install.ps1` if new files needed

### 5. Add a New AI Provider for Scan

**Source:** `tools/scoutica` → `cmd_scan()` function

```bash
# In the auto-detection order:
if command -v gemini &>/dev/null; then
    provider="gemini"
elif command -v claude &>/dev/null; then
    provider="claude"
elif command -v newcli &>/dev/null; then   # ← add here
    provider="newcli"
fi

# In the provider case statement:
case "$provider" in
    newcli)
        response=$(newcli --prompt "$(cat "$tmp_prompt")" 2>/dev/null)
        ;;
esac
```

## Development Workflow

1. Fork the repo
2. Create a feature branch
3. Make changes following the checklists above
4. Run `scoutica validate` on the sample card
5. Test with `scoutica scan` using your changes
6. Submit a PR with a clear description

## File Map

| What | Where |
|------|-------|
| JSON Schemas | `schemas/` |
| CLI (bash) | `tools/scoutica` |
| CLI (PowerShell) | `tools/scoutica.ps1` |
| Card templates | `templates/` |
| Rule templates | `templates/rules/` |
| AI scan prompt | `tools/SCAN_PROMPT.md` |
| Sample card | `protocol/examples/sample_card/` |
| Protocol specs | `protocol/platform/` |
| Flow diagrams | `.specs/protocol_flows.md` |
| Agent instructions | `SKILL.md` |
