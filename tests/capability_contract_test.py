#!/usr/bin/env python3
"""Behavior-neutral checks for the canonical CLI support contract."""

from __future__ import annotations

import json
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONTRACT_PATH = ROOT / "protocol" / "platform" / "cli_support_contract.json"
POSIX_CLI = ROOT / "tools" / "scoutica"
WINDOWS_CLI = ROOT / "tools" / "scoutica.ps1"


def load_contract() -> dict:
    with CONTRACT_PATH.open(encoding="utf-8") as handle:
        return json.load(handle)


class CapabilityContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.contract = load_contract()
        cls.posix_source = POSIX_CLI.read_text(encoding="utf-8")
        cls.windows_source = WINDOWS_CLI.read_text(encoding="utf-8")

    def test_contract_identity(self) -> None:
        self.assertEqual(self.contract["contract_version"], "1.0.0")
        self.assertEqual(self.contract["protocol_version"], "0.4.0")

    def test_implementation_versions_match_shipped_entrypoints(self) -> None:
        implementations = self.contract["implementations"]
        self.assertEqual(implementations["posix"]["entrypoint"], "tools/scoutica")
        self.assertEqual(implementations["windows"]["entrypoint"], "tools/scoutica.ps1")

        posix_match = re.search(r'^VERSION="([^"]+)"', self.posix_source, re.MULTILINE)
        windows_match = re.search(r'^\$VERSION\s*=\s*"([^"]+)"', self.windows_source, re.MULTILINE)
        self.assertIsNotNone(posix_match)
        self.assertIsNotNone(windows_match)
        self.assertEqual(
            implementations["posix"]["implementation_version"],
            posix_match.group(1),
        )
        self.assertEqual(
            implementations["windows"]["implementation_version"],
            windows_match.group(1),
        )
        self.assertNotEqual(
            implementations["windows"]["implementation_version"],
            self.contract["protocol_version"],
            "Windows implementation identity must not imply full protocol parity",
        )

    def test_windows_subset_is_exact_and_present(self) -> None:
        windows = self.contract["implementations"]["windows"]
        expected = [
            "init",
            "init --ai",
            "validate",
            "publish",
            "info",
            "help",
            "version",
        ]
        self.assertEqual(windows["capability_set"], "windows-subset-v1")
        self.assertEqual(windows["supported_commands"], expected)

        for command in ("init", "validate", "publish", "info", "help", "version"):
            router_case = re.search(
                rf'^\s*"{re.escape(command)}"\s*\{{',
                self.windows_source,
                re.MULTILINE,
            )
            self.assertIsNotNone(router_case, command)
        self.assertIn('"--ai"', self.windows_source)

    def test_runtime_support_is_explicit(self) -> None:
        runtime = self.contract["runtime_support"]
        self.assertEqual(runtime["python"]["minimum_version"], "3.11")
        self.assertEqual(runtime["bash"]["minimum_version"], "3.2")
        self.assertEqual(runtime["powershell"]["supported_versions"], ["5.1", "7"])

    def test_strict_python_dependencies_are_explicit(self) -> None:
        dependencies = {
            item["distribution"]: item for item in self.contract["python_dependencies"]
        }
        self.assertEqual(set(dependencies), {"jsonschema[format]", "PyYAML"})
        self.assertEqual(dependencies["jsonschema[format]"]["import_name"], "jsonschema")
        self.assertEqual(dependencies["jsonschema[format]"]["required_for"], ["validate"])
        self.assertEqual(dependencies["PyYAML"]["import_name"], "yaml")
        self.assertEqual(dependencies["PyYAML"]["required_for"], ["validate", "evaluate"])


if __name__ == "__main__":
    unittest.main()
