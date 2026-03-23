#!/usr/bin/env python3
"""
Scoutica Card Validator
Validates a Scoutica Skill Card directory against the protocol JSON schemas.

Usage:
    python validate_card.py ./path/to/my-card/

Requirements:
    pip install jsonschema pyyaml

The card directory must contain:
    - profile.json  (validated against candidate_profile.schema.json)
    - evidence.json (validated against evidence.schema.json)
    - rules.yaml    (validated against roe.schema.json)
    - SKILL.md      (checked for existence and frontmatter)
"""

import json
import sys
import os
from pathlib import Path

try:
    import jsonschema
except ImportError:
    print("❌ Missing dependency: jsonschema")
    print("   Install with: pip install jsonschema")
    sys.exit(1)

try:
    import yaml
except ImportError:
    print("❌ Missing dependency: pyyaml")
    print("   Install with: pip install pyyaml")
    sys.exit(1)


# Resolve schema directory relative to this script
SCRIPT_DIR = Path(__file__).resolve().parent.parent
SCHEMA_DIR = SCRIPT_DIR / "protocol" / "platform" / "01_schemas"

VALIDATIONS = [
    {
        "file": "profile.json",
        "schema": "candidate_profile.schema.json",
        "loader": "json",
        "label": "Candidate Profile",
    },
    {
        "file": "evidence.json",
        "schema": "evidence.schema.json",
        "loader": "json",
        "label": "Evidence Registry",
    },
    {
        "file": "rules.yaml",
        "schema": "roe.schema.json",
        "loader": "yaml",
        "label": "Rules of Engagement",
    },
]


def load_json(path: Path) -> dict:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def load_yaml(path: Path) -> dict:
    with open(path, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def validate_file(card_dir: Path, validation: dict) -> tuple[bool, str]:
    """Validate a single file. Returns (passed, message)."""
    file_path = card_dir / validation["file"]
    schema_path = SCHEMA_DIR / validation["schema"]
    label = validation["label"]

    # Check file exists
    if not file_path.exists():
        return False, f"❌ {label}: File not found — {validation['file']}"

    # Check schema exists
    if not schema_path.exists():
        return False, f"❌ {label}: Schema not found — {validation['schema']}"

    # Load data
    try:
        if validation["loader"] == "json":
            data = load_json(file_path)
        else:
            data = load_yaml(file_path)
    except Exception as e:
        return False, f"❌ {label}: Failed to parse {validation['file']} — {e}"

    # Load schema
    try:
        schema = load_json(schema_path)
    except Exception as e:
        return False, f"❌ {label}: Failed to parse schema — {e}"

    # Validate
    try:
        jsonschema.validate(instance=data, schema=schema)
        return True, f"✅ {label}: Valid"
    except jsonschema.ValidationError as e:
        path = " → ".join(str(p) for p in e.absolute_path) if e.absolute_path else "root"
        return False, f"❌ {label}: {e.message} (at {path})"


def check_skill_md(card_dir: Path) -> tuple[bool, str]:
    """Check that SKILL.md exists and has frontmatter."""
    skill_path = card_dir / "SKILL.md"
    if not skill_path.exists():
        return False, "❌ SKILL.md: File not found"

    content = skill_path.read_text(encoding="utf-8")
    if not content.startswith("---"):
        return False, "❌ SKILL.md: Missing YAML frontmatter (must start with ---)"

    parts = content.split("---", 2)
    if len(parts) < 3:
        return False, "❌ SKILL.md: Invalid frontmatter (missing closing ---)"

    return True, "✅ SKILL.md: Valid (frontmatter present)"


def check_rules_dir(card_dir: Path) -> tuple[bool, str]:
    """Check that the rules directory exists with required files."""
    rules_dir = card_dir / "rules"
    if not rules_dir.exists():
        return False, "⚠️  rules/: Directory not found (optional but recommended)"

    required_rules = ["evaluate-fit.md", "negotiate-terms.md", "verify-evidence.md", "request-interview.md"]
    missing = [r for r in required_rules if not (rules_dir / r).exists()]
    if missing:
        return False, f"⚠️  rules/: Missing files — {', '.join(missing)}"

    return True, "✅ rules/: All 4 rule files present"


def main():
    if len(sys.argv) < 2:
        print("Scoutica Card Validator")
        print("Usage: python validate_card.py <card-directory>")
        print()
        print("Example:")
        print("  python validate_card.py ./my-scoutica-card/")
        print("  python validate_card.py protocol/examples/sample_card/")
        sys.exit(1)

    card_dir = Path(sys.argv[1]).resolve()
    if not card_dir.is_dir():
        print(f"❌ Not a directory: {card_dir}")
        sys.exit(1)

    print(f"🔍 Validating Scoutica Card: {card_dir}")
    print()

    results = []

    # Validate SKILL.md
    results.append(check_skill_md(card_dir))

    # Validate data files against schemas
    for validation in VALIDATIONS:
        results.append(validate_file(card_dir, validation))

    # Check rules directory
    results.append(check_rules_dir(card_dir))

    # Print results
    passed = 0
    failed = 0
    warnings = 0
    for success, message in results:
        print(message)
        if success:
            passed += 1
        elif message.startswith("⚠️"):
            warnings += 1
        else:
            failed += 1

    print()
    print(f"Results: {passed} passed, {failed} failed, {warnings} warnings")

    if failed == 0:
        print("🎉 Card is valid!")
        sys.exit(0)
    else:
        print("💥 Card has validation errors. Fix the issues above and re-run.")
        sys.exit(1)


if __name__ == "__main__":
    main()
