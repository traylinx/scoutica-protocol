# Contributing to The Scoutica Protocol

Welcome to Scoutica Protocol! This document provides guidelines for contributing to the core CLI, templates, and schemas.

## Architecture Overview

- **`tools/scoutica`**: The main Bash CLI script (~1600 lines). It relies on Python 3 for safe JSON/YAML generation to prevent injection vulnerabilities.
- **`schemas/`**: JSON Schemas for validating `profile.json`, `rules.yaml`, and `evidence.json`.
- **`.agents/skills/`**: Operational AI skills that process Scoutica cards.
- **`protocol/templates/`**: Template files copied during `scoutica init`.

## Development Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/traylinx/scoutica-protocol.git
   cd scoutica-protocol
   ```

2. Link the CLI for local development:
   ```bash
   ln -s $(pwd)/tools/scoutica /usr/local/bin/scoutica
   ```
   Or explicitly run `./tools/scoutica` during testing.

## Making Changes

### 1. Modifying the CLI
When editing `tools/scoutica`:
- **Security First**: All file writing and parsing MUST use Python's built-in `json` and `yaml` libraries. Do not use Bash heredocs with raw user variable interpolation (this prevents injection).
- **Symlink Protection**: If adding a command that writes files, ensure symlinks are not blindly overwritten.
- **Tests**: Run your command locally to ensure no syntax errors. Run `scoutica doctor` to verify environment health.

### 2. Adding a New AI Provider
To add a new AI CLI to `scoutica scan`:
1. Update the help text in `cmd_scan()` to list the provider.
2. In `cmd_scan()`, update the provider auto-detection logic (`command -v ...`).
3. Add the provider mapping array in the scanning section (e.g., `["newcli"]="newcli prompt '...'"`).

### 3. Creating a New Agent Skill
If adding a new operational skill for agents to read cards:
1. Create a folder in `.agents/skills/my-skill/`.
2. Create `.agents/skills/my-skill/SKILL.md`.
3. Ensure it has strict YAML frontmatter (`name` and `description`).

## Pull Request Guidelines

1. **Keep it focused**: One PR = one feature or bugfix.
2. **Review security**: Ensure your changes do not leak personal data or expose local files.
3. **Commit hygiene**: Write clear, concise commit messages. 
4. **Validation**: Before opening a PR, run:
   ```bash
   # Verify CLI syntax
   bash -n tools/scoutica
   
   # Run system check
   scoutica doctor
   ```

## Getting Help

If you have questions about architecture or proposed changes, please open an Issue for discussion before starting major work.
