#!/usr/bin/env python3
"""
Scoutica Card Validator
Validates a Scoutica Skill Card (candidate or employer) against protocol JSON schemas.

Usage:
    python validate_card.py ./path/to/my-card/                     # Candidate (default)
    python validate_card.py ./path/to/employer-card/ --type employer  # Employer

Requirements:
    pip install jsonschema pyyaml

Candidate Card must contain:
    - profile.json  (validated against candidate_profile.schema.json)
    - evidence.json (validated against evidence.schema.json)
    - rules.yaml    (validated against roe.schema.json)
    - SKILL.md      (checked for existence and frontmatter)

Employer Card must contain:
    - recruiter_profile.json  (validated against recruiter_profile.schema.json)
    - hiring_rules.yaml       (validated against hiring_rules.schema.json)
    - roles/*.json (optional)  (validated against role.schema.json)
"""

import json
import sys
import os
import glob
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


# Resolve schema directories — collect ALL valid search paths
SCRIPT_DIR = Path(__file__).resolve().parent

# All directories to search for schemas (in priority order):
SCHEMA_SEARCH_PATHS = []
_candidate_dirs = [
    # 1. SCOUTICA_HOME env var (user override)
    Path(os.environ.get("SCOUTICA_HOME", "")) / "schemas",
    # 2. Installed location: ~/.scoutica/schemas/
    Path.home() / ".scoutica" / "schemas",
    # 3. Dev repo: script is in tools/, candidate schemas in protocol/platform/01_schemas/
    SCRIPT_DIR.parent / "protocol" / "platform" / "01_schemas",
    # 4. Dev repo: script is in tools/, recruiter schemas in schemas/
    SCRIPT_DIR.parent / "schemas",
    # 5. Same directory as the script (edge case)
    SCRIPT_DIR / "schemas",
]

for d in _candidate_dirs:
    if d.is_dir():
        SCHEMA_SEARCH_PATHS.append(d)

# Primary display directory (first found, for user messages)
SCHEMA_DIR = SCHEMA_SEARCH_PATHS[0] if SCHEMA_SEARCH_PATHS else (Path.home() / ".scoutica" / "schemas")


# ─── Candidate Validations ──────────────────────────────────────────

CANDIDATE_VALIDATIONS = [
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

# ─── Employer Validations ────────────────────────────────────────────

EMPLOYER_VALIDATIONS = [
    {
        "file": "recruiter_profile.json",
        "schema": "recruiter/recruiter_profile.schema.json",
        "loader": "json",
        "label": "Recruiter Profile",
    },
    {
        "file": "hiring_rules.yaml",
        "schema": "recruiter/hiring_rules.schema.json",
        "loader": "yaml",
        "label": "Hiring Rules",
    },
]

ROLE_SCHEMA = "recruiter/role.schema.json"


def load_json(path: Path) -> dict:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def load_yaml(path: Path) -> dict:
    with open(path, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def resolve_schema_path(schema_name: str) -> Path:
    """Resolve a schema file path by searching all known schema directories."""
    for search_dir in SCHEMA_SEARCH_PATHS:
        candidate = search_dir / schema_name
        if candidate.exists():
            return candidate
    # Return the primary dir path for error messages
    return SCHEMA_DIR / schema_name


def validate_file(card_dir: Path, validation: dict) -> tuple:
    """Validate a single file. Returns (passed, message)."""
    file_path = card_dir / validation["file"]
    schema_path = resolve_schema_path(validation["schema"])
    label = validation["label"]

    # Check file exists
    if not file_path.exists():
        return False, f"❌ {label}: File not found — {validation['file']}"

    # Check schema exists
    if not schema_path.exists():
        return False, f"❌ {label}: Schema not found — {validation['schema']} (searched {SCHEMA_DIR})"

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


def check_skill_md(card_dir: Path) -> tuple:
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


def check_rules_dir(card_dir: Path) -> tuple:
    """Check that the rules directory exists with required files."""
    rules_dir = card_dir / "rules"
    if not rules_dir.exists():
        return False, "⚠️  rules/: Directory not found (optional but recommended)"

    required_rules = ["evaluate-fit.md", "negotiate-terms.md", "verify-evidence.md", "request-interview.md"]
    missing = [r for r in required_rules if not (rules_dir / r).exists()]
    if missing:
        return False, f"⚠️  rules/: Missing files — {', '.join(missing)}"

    return True, "✅ rules/: All 4 rule files present"


def validate_roles(card_dir: Path) -> list:
    """Validate all role JSON files in roles/ directory."""
    results = []
    roles_dir = card_dir / "roles"
    if not roles_dir.exists():
        results.append((True, "ℹ️  roles/: No roles directory found (optional)"))
        return results

    role_files = sorted(roles_dir.glob("*.json"))
    if not role_files:
        results.append((True, "ℹ️  roles/: Directory exists but no .json files"))
        return results

    schema_path = resolve_schema_path(ROLE_SCHEMA)
    if not schema_path.exists():
        results.append((False, f"❌ Role Schema: Not found — {ROLE_SCHEMA}"))
        return results

    try:
        schema = load_json(schema_path)
    except Exception as e:
        results.append((False, f"❌ Role Schema: Failed to parse — {e}"))
        return results

    for role_file in role_files:
        label = f"Role ({role_file.name})"
        try:
            data = load_json(role_file)
        except Exception as e:
            results.append((False, f"❌ {label}: Failed to parse — {e}"))
            continue

        try:
            jsonschema.validate(instance=data, schema=schema)
            results.append((True, f"✅ {label}: Valid"))
        except jsonschema.ValidationError as e:
            path = " → ".join(str(p) for p in e.absolute_path) if e.absolute_path else "root"
            results.append((False, f"❌ {label}: {e.message} (at {path})"))

    return results


def validate_candidate(card_dir: Path) -> list:
    """Validate a candidate card."""
    results = []
    results.append(check_skill_md(card_dir))
    for validation in CANDIDATE_VALIDATIONS:
        results.append(validate_file(card_dir, validation))
    results.append(check_rules_dir(card_dir))
    return results


def validate_employer(card_dir: Path) -> list:
    """Validate an employer card."""
    results = []
    for validation in EMPLOYER_VALIDATIONS:
        results.append(validate_file(card_dir, validation))
    results.extend(validate_roles(card_dir))
    return results


def main():
    # Parse arguments
    args = sys.argv[1:]
    card_type = "candidate"  # default

    # Extract --type flag
    if "--type" in args:
        idx = args.index("--type")
        if idx + 1 < len(args):
            card_type = args[idx + 1]
            args = args[:idx] + args[idx + 2:]
        else:
            print("❌ --type requires a value (candidate or employer)")
            sys.exit(1)

    if card_type not in ("candidate", "employer"):
        print(f"❌ Unknown card type: {card_type}")
        print("   Valid types: candidate, employer")
        sys.exit(1)

    if not args:
        print("Scoutica Card Validator")
        print("Usage: python validate_card.py <card-directory> [--type candidate|employer]")
        print()
        print("Examples:")
        print("  python validate_card.py ./my-scoutica-card/")
        print("  python validate_card.py ./employer-card/ --type employer")
        sys.exit(1)

    card_dir = Path(args[0]).resolve()
    if not card_dir.is_dir():
        print(f"❌ Not a directory: {card_dir}")
        sys.exit(1)

    type_label = "Employer Card" if card_type == "employer" else "Candidate Card"
    print(f"🔍 Validating Scoutica {type_label}: {card_dir}")
    print(f"   Schema directory: {SCHEMA_DIR}")
    print()

    # Run validation
    if card_type == "employer":
        results = validate_employer(card_dir)
    else:
        results = validate_candidate(card_dir)

    # Print results
    passed = 0
    failed = 0
    warnings = 0
    for is_ok, message in results:
        print(message)
        if is_ok:
            passed += 1
        elif message.startswith("⚠️"):
            warnings += 1
        else:
            failed += 1

    print()
    print(f"Results: {passed} passed, {failed} failed, {warnings} warnings")

    if failed == 0:
        print(f"🎉 {type_label} is valid!")
        sys.exit(0)
    else:
        print(f"💥 {type_label} has validation errors. Fix the issues above and re-run.")
        sys.exit(1)


if __name__ == "__main__":
    main()
