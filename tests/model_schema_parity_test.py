#!/usr/bin/env python3
"""Compare candidate reference models with the authoritative JSON Schemas."""

from __future__ import annotations

import copy
import importlib.util
import json
import unittest
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from jsonschema import Draft7Validator, FormatChecker
from jsonschema.exceptions import FormatError
from pydantic import BaseModel, ValidationError


ROOT = Path(__file__).resolve().parents[1]
SCHEMA_DIR = ROOT / "protocol" / "platform" / "01_schemas"
MODELS_PATH = ROOT / "reference" / "python" / "models.py"


def load_models() -> Any:
    spec = importlib.util.spec_from_file_location("scoutica_reference_models", MODELS_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load reference models from {MODELS_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def changed(document: dict[str, Any], path: tuple[Any, ...], value: Any) -> dict[str, Any]:
    result = copy.deepcopy(document)
    target: Any = result
    for key in path[:-1]:
        target = target[key]
    target[path[-1]] = value
    return result


def without(document: dict[str, Any], path: tuple[Any, ...]) -> dict[str, Any]:
    result = copy.deepcopy(document)
    target: Any = result
    for key in path[:-1]:
        target = target[key]
    del target[path[-1]]
    return result


@dataclass(frozen=True)
class ParityCase:
    name: str
    artifact: str
    document: dict[str, Any]
    expected: bool


PROFILE_MINIMAL = {
    "schema_version": "0.1.0",
    "title": "Senior Software Engineer",
    "seniority": "senior",
    "primary_domains": ["Software Engineering"],
    "skills": ["Python"],
}

PROFILE_FULL = {
    **PROFILE_MINIMAL,
    "name": "Alice Developer",
    "years_experience": 8,
    "availability": "immediately",
    "tools_and_platforms": ["Git", "Linux"],
    "certifications_and_licenses": ["Example Certificate"],
    "specializations": ["Distributed systems"],
    "spoken_languages": [{"language": "English", "level": "fluent"}],
    "education": "Example University",
    "summary": "Builds reliable systems.",
}

EVIDENCE_EMPTY = {"schema_version": "0.1.0", "items": []}
EVIDENCE_FULL = {
    "schema_version": "0.1.0",
    "items": [
        {
            "type": "github_repo",
            "title": "Example project",
            "url": "https://example.test/project",
            "description": "Demonstrates production engineering.",
            "skills_demonstrated": ["Python"],
        }
    ],
}

RULES_MINIMAL = {
    "schema_version": "0.1.0",
    "engagement": {"allowed_types": ["contract"]},
    "remote": {"policy": "remote_only"},
    "filters": {},
    "privacy": {
        "zone_1_public": [],
        "zone_2_paid": [],
        "zone_3_private": [],
    },
}

RULES_FULL = {
    "schema_version": "0.1.0",
    "engagement": {
        "allowed_types": ["permanent", "contract"],
        "compensation": {
            "minimum_base_eur": {
                "permanent": 100000,
                "contract": "negotiable",
                "fractional": 8000,
                "advisory": 250,
            }
        },
    },
    "remote": {"policy": "hybrid", "hybrid_locations": ["Berlin"]},
    "filters": {
        "blocked_industries": ["Example Blocked Industry"],
        "stack_keywords": {"preferred": ["Python", "Kubernetes"]},
        "soft_reject": {"weak_stack_overlap_below": 2},
    },
    "privacy": {
        "zone_1_public": ["title"],
        "zone_2_paid": ["experience"],
        "zone_3_private": ["contact"],
    },
}


CASES = [
    ParityCase("profile minimal", "profile", PROFILE_MINIMAL, True),
    ParityCase("profile full", "profile", PROFILE_FULL, True),
    ParityCase(
        "profile integral JSON number",
        "profile",
        changed(PROFILE_FULL, ("years_experience",), 8.0),
        True,
    ),
    ParityCase("profile missing required", "profile", without(PROFILE_MINIMAL, ("title",)), False),
    ParityCase("profile extra root field", "profile", changed(PROFILE_MINIMAL, ("extra",), True), False),
    ParityCase("profile null optional", "profile", changed(PROFILE_MINIMAL, ("name",), None), False),
    ParityCase("profile empty name", "profile", changed(PROFILE_MINIMAL, ("name",), ""), False),
    ParityCase("profile invalid version", "profile", changed(PROFILE_MINIMAL, ("schema_version",), "v1"), False),
    ParityCase("profile invalid enum", "profile", changed(PROFILE_MINIMAL, ("seniority",), "staff"), False),
    ParityCase("profile non-string enum", "profile", changed(PROFILE_MINIMAL, ("seniority",), b"senior"), False),
    ParityCase("profile empty required array", "profile", changed(PROFILE_MINIMAL, ("skills",), []), False),
    ParityCase("profile empty skill", "profile", changed(PROFILE_MINIMAL, ("skills",), [""]), False),
    ParityCase("profile duplicate skills", "profile", changed(PROFILE_MINIMAL, ("skills",), ["Python", "Python"]), False),
    ParityCase("profile non-array skills", "profile", changed(PROFILE_MINIMAL, ("skills",), ("Python",)), False),
    ParityCase("profile string years", "profile", changed(PROFILE_MINIMAL, ("years_experience",), "8"), False),
    ParityCase("profile boolean years", "profile", changed(PROFILE_MINIMAL, ("years_experience",), True), False),
    ParityCase("profile negative years", "profile", changed(PROFILE_MINIMAL, ("years_experience",), -1), False),
    ParityCase("profile long summary", "profile", changed(PROFILE_MINIMAL, ("summary",), "x" * 1001), False),
    ParityCase(
        "profile spoken language extra",
        "profile",
        changed(
            PROFILE_MINIMAL,
            ("spoken_languages",),
            [{"language": "English", "level": "fluent", "extra": True}],
        ),
        False,
    ),
    ParityCase(
        "profile spoken language empty",
        "profile",
        changed(PROFILE_MINIMAL, ("spoken_languages",), [{"language": "", "level": "fluent"}]),
        False,
    ),
    ParityCase(
        "profile spoken language non-string level",
        "profile",
        changed(
            PROFILE_MINIMAL,
            ("spoken_languages",),
            [{"language": "English", "level": b"fluent"}],
        ),
        False,
    ),
    ParityCase("evidence empty registry", "evidence", EVIDENCE_EMPTY, True),
    ParityCase("evidence full", "evidence", EVIDENCE_FULL, True),
    ParityCase(
        "evidence non-HTTP URI",
        "evidence",
        changed(EVIDENCE_FULL, ("items", 0, "url"), "urn:isbn:0451450523"),
        True,
    ),
    ParityCase(
        "evidence empty-authority URI",
        "evidence",
        changed(EVIDENCE_FULL, ("items", 0, "url"), "https://"),
        True,
    ),
    ParityCase("evidence extra root field", "evidence", changed(EVIDENCE_EMPTY, ("extra",), True), False),
    ParityCase(
        "evidence extra item field",
        "evidence",
        changed(EVIDENCE_FULL, ("items", 0, "extra"), True),
        False,
    ),
    ParityCase(
        "evidence invalid URI",
        "evidence",
        changed(EVIDENCE_FULL, ("items", 0, "url"), "relative/path"),
        False,
    ),
    ParityCase(
        "evidence malformed percent escape",
        "evidence",
        changed(EVIDENCE_FULL, ("items", 0, "url"), "https://example.test/%zz"),
        False,
    ),
    ParityCase(
        "evidence malformed IP literal URI",
        "evidence",
        changed(EVIDENCE_FULL, ("items", 0, "url"), "https://[not-ipv6]"),
        False,
    ),
    ParityCase(
        "evidence bracket outside URI authority",
        "evidence",
        changed(EVIDENCE_FULL, ("items", 0, "url"), "urn:example[invalid]"),
        False,
    ),
    ParityCase(
        "evidence invalid URI port",
        "evidence",
        changed(EVIDENCE_FULL, ("items", 0, "url"), "https://example.test:not-a-port/"),
        False,
    ),
    ParityCase(
        "evidence repeated URI fragment",
        "evidence",
        changed(EVIDENCE_FULL, ("items", 0, "url"), "https://example.test/#one#two"),
        False,
    ),
    ParityCase(
        "evidence invalid type",
        "evidence",
        changed(EVIDENCE_FULL, ("items", 0, "type"), "repository"),
        False,
    ),
    ParityCase(
        "evidence non-string type",
        "evidence",
        changed(EVIDENCE_FULL, ("items", 0, "type"), b"github_repo"),
        False,
    ),
    ParityCase(
        "evidence empty title",
        "evidence",
        changed(EVIDENCE_FULL, ("items", 0, "title"), ""),
        False,
    ),
    ParityCase(
        "evidence empty demonstrated skills",
        "evidence",
        changed(EVIDENCE_FULL, ("items", 0, "skills_demonstrated"), []),
        False,
    ),
    ParityCase(
        "evidence empty demonstrated skill",
        "evidence",
        changed(EVIDENCE_FULL, ("items", 0, "skills_demonstrated"), [""]),
        False,
    ),
    ParityCase("evidence non-array items", "evidence", changed(EVIDENCE_EMPTY, ("items",), ()), False),
    ParityCase("rules minimal", "rules", RULES_MINIMAL, True),
    ParityCase("rules full", "rules", RULES_FULL, True),
    ParityCase(
        "rules integral compensation",
        "rules",
        changed(RULES_FULL, ("engagement", "compensation", "minimum_base_eur", "permanent"), 100000.0),
        True,
    ),
    ParityCase("rules extra root field", "rules", changed(RULES_MINIMAL, ("extra",), True), False),
    ParityCase(
        "rules extra nested field",
        "rules",
        changed(RULES_MINIMAL, ("remote", "extra"), True),
        False,
    ),
    ParityCase(
        "rules duplicate engagement",
        "rules",
        changed(RULES_MINIMAL, ("engagement", "allowed_types"), ["contract", "contract"]),
        False,
    ),
    ParityCase(
        "rules empty engagement",
        "rules",
        changed(RULES_MINIMAL, ("engagement", "allowed_types"), []),
        False,
    ),
    ParityCase(
        "rules invalid engagement",
        "rules",
        changed(RULES_MINIMAL, ("engagement", "allowed_types"), ["freelance"]),
        False,
    ),
    ParityCase(
        "rules non-string engagement",
        "rules",
        changed(RULES_MINIMAL, ("engagement", "allowed_types"), [b"contract"]),
        False,
    ),
    ParityCase(
        "rules non-array engagement",
        "rules",
        changed(RULES_MINIMAL, ("engagement", "allowed_types"), ("contract",)),
        False,
    ),
    ParityCase(
        "rules negative compensation",
        "rules",
        changed(RULES_FULL, ("engagement", "compensation", "minimum_base_eur", "permanent"), -1),
        False,
    ),
    ParityCase(
        "rules arbitrary compensation string",
        "rules",
        changed(RULES_FULL, ("engagement", "compensation", "minimum_base_eur", "permanent"), "100000"),
        False,
    ),
    ParityCase(
        "rules compensation boolean",
        "rules",
        changed(RULES_FULL, ("engagement", "compensation", "minimum_base_eur", "permanent"), True),
        False,
    ),
    ParityCase("rules invalid remote policy", "rules", changed(RULES_MINIMAL, ("remote", "policy"), "anywhere"), False),
    ParityCase(
        "rules non-string remote policy",
        "rules",
        changed(RULES_MINIMAL, ("remote", "policy"), b"remote_only"),
        False,
    ),
    ParityCase(
        "rules duplicate blocked industry",
        "rules",
        changed(RULES_FULL, ("filters", "blocked_industries"), ["Gaming", "Gaming"]),
        False,
    ),
    ParityCase(
        "rules duplicate preferred keyword",
        "rules",
        changed(RULES_FULL, ("filters", "stack_keywords", "preferred"), ["Python", "Python"]),
        False,
    ),
    ParityCase(
        "rules negative soft reject threshold",
        "rules",
        changed(RULES_FULL, ("filters", "soft_reject", "weak_stack_overlap_below"), -1),
        False,
    ),
    ParityCase("rules null optional", "rules", changed(RULES_MINIMAL, ("filters", "soft_reject"), None), False),
    ParityCase(
        "rules non-array privacy zone",
        "rules",
        changed(RULES_MINIMAL, ("privacy", "zone_1_public"), ("title",)),
        False,
    ),
]


class ModelSchemaParityTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.require_format_checkers()
        models = load_models()
        cls.models: dict[str, type[BaseModel]] = {
            "profile": models.CandidateProfile,
            "evidence": models.EvidenceRegistry,
            "rules": models.RulesOfEngagement,
        }
        cls.validators = {
            "profile": cls.load_validator("candidate_profile.schema.json"),
            "evidence": cls.load_validator("evidence.schema.json"),
            "rules": cls.load_validator("roe.schema.json"),
        }

    @staticmethod
    def require_format_checkers() -> None:
        checker = FormatChecker()
        try:
            checker.check("relative/path", "uri")
        except FormatError:
            return
        raise RuntimeError(
            "JSON Schema URI format validation is unavailable; "
            "install the strict prerequisite with: pip install 'jsonschema[format]'"
        )

    @staticmethod
    def load_validator(name: str) -> Draft7Validator:
        with (SCHEMA_DIR / name).open(encoding="utf-8") as handle:
            schema = json.load(handle)
        Draft7Validator.check_schema(schema)
        return Draft7Validator(schema, format_checker=FormatChecker())

    @staticmethod
    def model_accepts(model: type[BaseModel], document: dict[str, Any]) -> bool:
        try:
            model.model_validate(document)
        except ValidationError:
            return False
        return True

    def test_valid_and_invalid_corpus_has_exact_parity(self) -> None:
        for case in CASES:
            with self.subTest(case=case.name):
                schema_valid = self.validators[case.artifact].is_valid(case.document)
                model_valid = self.model_accepts(self.models[case.artifact], case.document)
                self.assertEqual(case.expected, schema_valid, "corpus expectation disagrees with schema")
                self.assertEqual(schema_valid, model_valid, "reference model disagrees with schema")

    def test_model_serialization_remains_schema_valid(self) -> None:
        valid_documents = {
            "profile": PROFILE_MINIMAL,
            "evidence": EVIDENCE_FULL,
            "rules": RULES_MINIMAL,
        }
        for artifact, document in valid_documents.items():
            with self.subTest(artifact=artifact):
                instance = self.models[artifact].model_validate(document)
                serialized = instance.model_dump(mode="json")
                self.assertTrue(self.validators[artifact].is_valid(serialized))
                self.assertNotIn(None, serialized.values())


if __name__ == "__main__":
    unittest.main()
