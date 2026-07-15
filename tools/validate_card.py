#!/usr/bin/env python3
"""
Scoutica Card Validator
Validates a Scoutica Skill Card (candidate or employer) against protocol JSON schemas.

Usage:
    python validate_card.py ./path/to/my-card/                     # Candidate (default)
    python validate_card.py ./path/to/employer-card/ --type employer  # Employer

Requirements:
    python3 -m pip install 'jsonschema[format]' PyYAML

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
import re
import sys
from functools import lru_cache
from pathlib import Path
from typing import Any, Optional

try:
    import jsonschema
except ImportError:
    print("❌ Missing dependency: jsonschema")
    print("   Run: python3 -m pip install 'jsonschema[format]' PyYAML")
    sys.exit(1)

try:
    import yaml
    from yaml.constructor import ConstructorError
    from yaml.nodes import MappingNode
    from yaml.tokens import AliasToken, AnchorToken
except ImportError:
    print("❌ Missing dependency: pyyaml")
    print("   Run: python3 -m pip install 'jsonschema[format]' PyYAML")
    sys.exit(1)


# Resolve schemas only relative to this trusted checkout/install. A custom schema
# tree is accepted only through the explicit, absolute --schema-dir option.
SCRIPT_DIR = Path(__file__).resolve().parent
TRUSTED_SCHEMA_DIRS = (
    (SCRIPT_DIR.parent / "protocol" / "platform" / "01_schemas").resolve(),
    (SCRIPT_DIR.parent / "schemas").resolve(),
)
SCHEMA_SEARCH_PATHS = [path for path in TRUSTED_SCHEMA_DIRS if path.is_dir()]
REQUIRED_FORMAT_CHECKERS = {"date", "date-time", "email", "hostname", "uri"}


def ensure_format_support() -> tuple:
    """Refuse validation when optional jsonschema format support is incomplete."""
    available = set(jsonschema.FormatChecker.checkers)
    missing = sorted(REQUIRED_FORMAT_CHECKERS - available)
    if missing:
        return False, (
            "❌ Missing dependency [FORMAT_CHECKERS_MISSING]: "
            f"jsonschema format checkers unavailable: {', '.join(missing)}\n"
            "   Run: python3 -m pip install 'jsonschema[format]' PyYAML"
        )
    return True, None


def configure_schema_search(schema_override: Optional[str] = None) -> tuple:
    """Configure trusted schema roots, or one explicit absolute custom root."""
    global SCHEMA_SEARCH_PATHS

    if schema_override is None:
        SCHEMA_SEARCH_PATHS = [path for path in TRUSTED_SCHEMA_DIRS if path.is_dir()]
        return True, None

    override = Path(schema_override).expanduser()
    if not override.is_absolute():
        return False, "❌ Schema directory [SCHEMA_DIR_NOT_ABSOLUTE]: --schema-dir must be an absolute path"
    if not override.is_dir():
        return False, f"❌ Schema directory [SCHEMA_DIR_NOT_FOUND]: not a directory — {override}"

    SCHEMA_SEARCH_PATHS = [override.resolve()]
    return True, None


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
    # Return a deterministic candidate for error messages.
    if SCHEMA_SEARCH_PATHS:
        return SCHEMA_SEARCH_PATHS[0] / schema_name
    return TRUSTED_SCHEMA_DIRS[0] / schema_name


def schema_search_display() -> str:
    if SCHEMA_SEARCH_PATHS:
        return ", ".join(str(path) for path in SCHEMA_SEARCH_PATHS)
    return "<no trusted schema directory found>"


@lru_cache(maxsize=None)
def load_schema_validator(schema_path: Path):
    """Load, check, and compile a schema with its declared JSON Schema draft."""
    schema = load_json(schema_path)
    validator_class = jsonschema.validators.validator_for(schema)
    validator_class.check_schema(schema)
    return validator_class(schema, format_checker=jsonschema.FormatChecker())


def validation_error_message(label: str, error: jsonschema.ValidationError) -> str:
    path = "$"
    for component in error.absolute_path:
        path += f"[{component}]" if isinstance(component, int) else f".{component}"
    return (
        f"❌ {label} [VALIDATION_ERROR] path={path} rule={error.validator}: "
        f"{error.message}"
    )


class UniqueKeySafeLoader(yaml.SafeLoader):
    """Safe YAML loader that rejects duplicate keys at every mapping depth."""


class DuplicateKeyError(ConstructorError):
    """Raised when a YAML mapping repeats a key."""


def _construct_unique_mapping(
    loader: UniqueKeySafeLoader, node: MappingNode, deep: bool = False
) -> dict[Any, Any]:
    mapping: dict[Any, Any] = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        try:
            duplicate = key in mapping
        except TypeError as exc:
            raise DuplicateKeyError(
                "while constructing a mapping",
                node.start_mark,
                "found an unhashable mapping key",
                key_node.start_mark,
            ) from exc
        if duplicate:
            raise DuplicateKeyError(
                "while constructing a mapping",
                node.start_mark,
                f"found duplicate key {key!r}",
                key_node.start_mark,
            )
        mapping[key] = loader.construct_object(value_node, deep=deep)
    return mapping


UniqueKeySafeLoader.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG,
    _construct_unique_mapping,
)


SEMVER_PATTERN = re.compile(
    r"^(0|[1-9][0-9]*)\."
    r"(0|[1-9][0-9]*)\."
    r"(0|[1-9][0-9]*)"
    r"(?:-(?:0|[1-9][0-9]*|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*)"
    r"(?:\.(?:0|[1-9][0-9]*|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*))*)?"
    r"(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$"
)


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
        return False, (
            f"❌ {label} [SCHEMA_NOT_FOUND]: {validation['schema']} "
            f"(searched {schema_search_display()})"
        )

    # Load data
    try:
        if validation["loader"] == "json":
            data = load_json(file_path)
        else:
            data = load_yaml(file_path)
    except Exception as e:
        return False, f"❌ {label}: Failed to parse {validation['file']} — {e}"

    # Load and compile the declared draft once, including schema self-validation.
    try:
        validator = load_schema_validator(schema_path)
    except jsonschema.SchemaError as e:
        path = ".".join(str(part) for part in e.absolute_path) or "$"
        return False, f"❌ {label} [SCHEMA_INVALID] path={path}: {e.message}"
    except Exception as e:
        return False, f"❌ {label} [SCHEMA_PARSE_ERROR]: {e}"

    # Validate
    errors = sorted(
        validator.iter_errors(data),
        key=lambda error: (
            tuple(str(part) for part in error.absolute_path),
            str(error.validator),
            error.message,
        ),
    )
    if errors:
        return False, validation_error_message(label, errors[0])
    return True, f"✅ {label}: Valid"


def check_skill_md(card_dir: Path) -> tuple:
    """Validate candidate SKILL.md frontmatter against the protocol contract."""
    skill_path = card_dir / "SKILL.md"
    if not skill_path.exists():
        return False, "❌ SKILL.md: File not found"

    try:
        content = skill_path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as exc:
        return False, f"❌ SKILL.md [SKILL_READ_ERROR]: {exc}"

    lines = content.splitlines()
    if not lines or lines[0] != "---":
        return False, "❌ SKILL.md [FRONTMATTER_FENCE]: first line must be exactly ---"

    try:
        closing_fence = lines.index("---", 1)
    except ValueError:
        return False, "❌ SKILL.md [FRONTMATTER_FENCE]: missing closing --- fence"
    if closing_fence == 1:
        return False, "❌ SKILL.md [FRONTMATTER_EMPTY]: frontmatter must not be empty"

    frontmatter_text = "\n".join(lines[1:closing_fence]) + "\n"
    try:
        for token in yaml.scan(frontmatter_text):
            if isinstance(token, (AnchorToken, AliasToken)):
                return False, "❌ SKILL.md [FRONTMATTER_ALIAS]: YAML anchors and aliases are not allowed"
        documents = list(yaml.load_all(frontmatter_text, Loader=UniqueKeySafeLoader))
    except DuplicateKeyError as exc:
        return False, f"❌ SKILL.md [FRONTMATTER_DUPLICATE_KEY]: {exc}"
    except yaml.YAMLError as exc:
        return False, f"❌ SKILL.md [FRONTMATTER_YAML]: {exc}"

    if len(documents) != 1:
        return False, "❌ SKILL.md [FRONTMATTER_DOCUMENTS]: exactly one YAML document is required"
    frontmatter = documents[0]
    if not isinstance(frontmatter, dict):
        return False, "❌ SKILL.md [FRONTMATTER_ROOT_TYPE]: frontmatter root must be a mapping"

    allowed_root = {"name", "description", "metadata"}
    unknown_root = sorted(str(key) for key in set(frontmatter) - allowed_root)
    missing_root = sorted({"name", "description"} - set(frontmatter))
    if unknown_root:
        return False, f"❌ SKILL.md [FRONTMATTER_ROOT_KEYS]: unknown keys: {', '.join(unknown_root)}"
    if missing_root:
        return False, f"❌ SKILL.md [FRONTMATTER_ROOT_KEYS]: missing keys: {', '.join(missing_root)}"
    if frontmatter["name"] != "scoutica":
        return False, "❌ SKILL.md [FRONTMATTER_NAME]: name must be the string scoutica"

    description = frontmatter["description"]
    if not isinstance(description, str) or not description.strip() or "\n" in description or "\r" in description:
        return False, "❌ SKILL.md [FRONTMATTER_DESCRIPTION]: description must be a nonempty single-line string"

    if "metadata" in frontmatter:
        metadata = frontmatter["metadata"]
        if not isinstance(metadata, dict):
            return False, "❌ SKILL.md [FRONTMATTER_METADATA_TYPE]: metadata must be a mapping"
        allowed_metadata = {"tags", "author", "contact", "version"}
        unknown_metadata = sorted(str(key) for key in set(metadata) - allowed_metadata)
        missing_metadata = sorted({"tags", "author", "version"} - set(metadata))
        if unknown_metadata:
            return False, f"❌ SKILL.md [FRONTMATTER_METADATA_KEYS]: unknown keys: {', '.join(unknown_metadata)}"
        if missing_metadata:
            return False, f"❌ SKILL.md [FRONTMATTER_METADATA_KEYS]: missing keys: {', '.join(missing_metadata)}"
        if not isinstance(metadata["tags"], str):
            return False, "❌ SKILL.md [FRONTMATTER_TAGS]: metadata.tags must be a string"
        if not isinstance(metadata["author"], str) or not metadata["author"].strip():
            return False, "❌ SKILL.md [FRONTMATTER_AUTHOR]: metadata.author must be a nonempty string"
        if "contact" in metadata and not isinstance(metadata["contact"], str):
            return False, "❌ SKILL.md [FRONTMATTER_CONTACT]: metadata.contact must be a string"
        version = metadata["version"]
        if not isinstance(version, str) or not SEMVER_PATTERN.fullmatch(version):
            return False, "❌ SKILL.md [FRONTMATTER_VERSION]: metadata.version must be a SemVer string"

    return True, "✅ SKILL.md: Valid"


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
        results.append((False, f"❌ Role Schema [SCHEMA_NOT_FOUND]: {ROLE_SCHEMA}"))
        return results

    try:
        validator = load_schema_validator(schema_path)
    except jsonschema.SchemaError as e:
        path = ".".join(str(part) for part in e.absolute_path) or "$"
        results.append((False, f"❌ Role Schema [SCHEMA_INVALID] path={path}: {e.message}"))
        return results
    except Exception as e:
        results.append((False, f"❌ Role Schema [SCHEMA_PARSE_ERROR]: {e}"))
        return results

    for role_file in role_files:
        label = f"Role ({role_file.name})"
        try:
            data = load_json(role_file)
        except Exception as e:
            results.append((False, f"❌ {label}: Failed to parse — {e}"))
            continue

        errors = sorted(
            validator.iter_errors(data),
            key=lambda error: (
                tuple(str(part) for part in error.absolute_path),
                str(error.validator),
                error.message,
            ),
        )
        if errors:
            results.append((False, validation_error_message(label, errors[0])))
        else:
            results.append((True, f"✅ {label}: Valid"))

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
    schema_override = None
    positional = []

    index = 0
    while index < len(args):
        argument = args[index]
        if argument in ("--type", "--schema-dir"):
            if index + 1 >= len(args):
                print(f"❌ {argument} requires a value")
                sys.exit(1)
            value = args[index + 1]
            if argument == "--type":
                card_type = value
            else:
                schema_override = value
            index += 2
        elif argument in ("-h", "--help"):
            print("Usage: python validate_card.py <card-directory> [--type candidate|employer] [--schema-dir /absolute/path]")
            sys.exit(0)
        elif argument.startswith("-"):
            print(f"❌ Unknown option: {argument}")
            sys.exit(1)
        else:
            positional.append(argument)
            index += 1

    if card_type not in ("candidate", "employer"):
        print(f"❌ Unknown card type: {card_type}")
        print("   Valid types: candidate, employer")
        sys.exit(1)

    if not positional:
        print("Scoutica Card Validator")
        print("Usage: python validate_card.py <card-directory> [--type candidate|employer] [--schema-dir /absolute/path]")
        print()
        print("Examples:")
        print("  python validate_card.py ./my-scoutica-card/")
        print("  python validate_card.py ./employer-card/ --type employer")
        sys.exit(1)
    if len(positional) != 1:
        print(f"❌ Expected one card directory, got {len(positional)}")
        sys.exit(1)

    formats_ready, formats_error = ensure_format_support()
    if not formats_ready:
        print(formats_error)
        sys.exit(1)

    configured, configuration_error = configure_schema_search(schema_override)
    if not configured:
        print(configuration_error)
        sys.exit(1)

    card_dir = Path(positional[0]).resolve()
    if not card_dir.is_dir():
        print(f"❌ Not a directory: {card_dir}")
        sys.exit(1)

    type_label = "Employer Card" if card_type == "employer" else "Candidate Card"
    print(f"🔍 Validating Scoutica {type_label}: {card_dir}")
    schema_label = "Schema override" if schema_override is not None else "Schema directories"
    print(f"   {schema_label}: {schema_search_display()}")
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
