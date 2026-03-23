# Scoutica Protocol — Repository Guidelines

## Architecture

- **CLI:** `tools/scoutica` (Bash, ~1600 lines cross-platform design)
- **Schemas:** `schemas/` (JSON Schema)
- **Agent skills:** `.agents/skills/` (YAML frontmatter + Markdown)
- **Templates:** `protocol/templates/`
- **Docs:** `docs/`

## Rules for Contributing Agents

1. **Never commit personal data** (names, emails, salaries). Always mock data with generic terms like "Alice Developer" in examples.
2. **Use explicit commits.** Scope your commits to specifically modified files using `git add <file>`. Never run `git add -A` or `git commit -a` at the repository root blindly.
3. **Keep `SKILL.md` under 150 lines.** The `SKILL.md` file in the root is specifically for AI agents reading *candidate* cards; keep it concise and strictly protocol-focused. Do not put repo contribution guidelines into `SKILL.md`.
4. **Symlink Compatibility:** If you modify `AGENTS.md`, do not break the `CLAUDE.md` symlink.

## Security Posture

- **All file generation must use Python (`json.dump`/`yaml.dump`).** No bash heredocs with raw user variable interpolation (C3/LFI prevention).
- **Symlink protection** is enforced on all file writes (e.g., `cmd_init()` checks if the target is a symlink before writing).
- **Staging bounds.** Commands like `scoutica publish` must only stage canonical card files (`profile.json`, `rules.yaml`, etc.), preventing accidental commit of raw artifacts.
- **URL Validation.** Remote fetching (e.g., in `scoutica resolve`) must strictly validate URLs, enforcing HTTPS and rejecting Localhost/Private IPs (SSRF prevention).
- **Temporary file cleanup.** All transient data (like `.scan_response_raw.txt` or temporary PDFs) must be cleaned up via `trap` on EXIT/INT/TERM.
