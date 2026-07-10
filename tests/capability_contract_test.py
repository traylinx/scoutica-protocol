#!/usr/bin/env python3
"""Behavior-neutral checks for the canonical CLI support contract."""

from __future__ import annotations

import json
import posixpath
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONTRACT_PATH = ROOT / "protocol" / "platform" / "cli_support_contract.json"
POSIX_CLI = ROOT / "tools" / "scoutica"
WINDOWS_CLI = ROOT / "tools" / "scoutica.ps1"
WINDOWS_INSTALLER = ROOT / "install.ps1"


def load_contract() -> dict:
    with CONTRACT_PATH.open(encoding="utf-8") as handle:
        return json.load(handle)


class CapabilityContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.contract = load_contract()
        cls.posix_source = POSIX_CLI.read_text(encoding="utf-8")
        cls.windows_source = WINDOWS_CLI.read_text(encoding="utf-8")
        cls.windows_installer_source = WINDOWS_INSTALLER.read_text(encoding="utf-8")

    def test_contract_identity(self) -> None:
        self.assertEqual(self.contract["contract_version"], "1.0.0")
        self.assertEqual(self.contract["protocol_version"], "0.4.0")

    def test_implementation_versions_match_shipped_entrypoints(self) -> None:
        implementations = self.contract["implementations"]
        self.assertEqual(implementations["posix"]["entrypoint"], "tools/scoutica")
        self.assertEqual(implementations["windows"]["entrypoint"], "tools/scoutica.ps1")

        posix_match = re.search(r'^VERSION="([^"]+)"', self.posix_source, re.MULTILINE)
        protocol_match = re.search(
            r'^\$PROTOCOL_VERSION\s*=\s*"([^"]+)"',
            self.windows_source,
            re.MULTILINE,
        )
        windows_match = re.search(
            r'^\$IMPLEMENTATION_VERSION\s*=\s*"([^"]+)"',
            self.windows_source,
            re.MULTILINE,
        )
        capability_match = re.search(
            r'^\$CAPABILITY_SET\s*=\s*"([^"]+)"',
            self.windows_source,
            re.MULTILINE,
        )
        self.assertIsNotNone(posix_match)
        self.assertIsNotNone(protocol_match)
        self.assertIsNotNone(windows_match)
        self.assertIsNotNone(capability_match)
        self.assertEqual(
            implementations["posix"]["implementation_version"],
            posix_match.group(1),
        )
        self.assertEqual(
            implementations["windows"]["implementation_version"],
            windows_match.group(1),
        )
        self.assertEqual(self.contract["protocol_version"], protocol_match.group(1))
        self.assertEqual(
            implementations["windows"]["capability_set"],
            capability_match.group(1),
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

        aliases = windows["command_aliases"]
        self.assertEqual(aliases, {"help": ["--help", "-h"], "version": ["--version", "-v"]})

        unsupported_match = re.search(
            r'^\$KNOWN_UNSUPPORTED_COMMANDS\s*=\s*@\((.*?)^\)',
            self.windows_source,
            re.MULTILINE | re.DOTALL,
        )
        self.assertIsNotNone(unsupported_match)
        source_unsupported = re.findall(r'"([a-z]+)"', unsupported_match.group(1))
        self.assertEqual(source_unsupported, windows["known_unsupported_commands"])

        help_match = re.search(
            r'^function Invoke-Help \{(.*?)^\}',
            self.windows_source,
            re.MULTILINE | re.DOTALL,
        )
        self.assertIsNotNone(help_match)
        help_source = help_match.group(1)
        for command in expected:
            self.assertIn(command, help_source)
        for command in windows["known_unsupported_commands"]:
            self.assertNotRegex(help_source, rf'(?<![a-z]){re.escape(command)}(?![a-z])')

    def test_windows_exit_semantics_are_deliberate(self) -> None:
        self.assertRegex(
            self.windows_source,
            r'(?s)\$KNOWN_UNSUPPORTED_COMMANDS\s+-contains\s+\$command.*?exit 2',
        )
        self.assertRegex(
            self.windows_source,
            r'(?s)Unknown command: \{0\}" -f \$command.*?Invoke-Help.*?exit 1',
        )

    def test_install_manifest_is_complete_and_safe(self) -> None:
        installation = self.contract["installation"]
        self.assertEqual(installation["manifest_version"], "1.0.0")
        self.assertEqual(
            installation["contract_source"],
            "protocol/platform/cli_support_contract.json",
        )
        self.assertEqual(installation["contract_destination"], "cli_support_contract.json")

        resources = installation["resources"]
        windows_resources = [
            resource
            for resource in resources
            if "windows" in resource["platforms"]
        ]
        posix_resources = [
            resource
            for resource in resources
            if "posix" in resource["platforms"]
        ]
        self.assertTrue(windows_resources)
        self.assertTrue(posix_resources)
        destinations = [resource["destination"] for resource in windows_resources]
        self.assertEqual(len(destinations), len(set(destinations)))
        self.assertNotIn(installation["contract_destination"], destinations)

        required_destinations = {
            "bin/scoutica.ps1",
            "bin/validate_card.py",
            "bin/scan_runtime.py",
            "GENERATE_MY_CARD.md",
            "schemas/candidate_profile.schema.json",
            "schemas/roe.schema.json",
            "schemas/evidence.schema.json",
            "templates/card.gitignore",
            "templates/rules/evaluate-fit.md",
            "templates/rules/negotiate-terms.md",
            "templates/rules/verify-evidence.md",
            "templates/rules/request-interview.md",
        }
        self.assertTrue(required_destinations.issubset(destinations))
        for required_destination in required_destinations:
            self.assertIn(f'"{required_destination}"', self.windows_installer_source)

        posix_destinations = [resource["destination"] for resource in posix_resources]
        self.assertEqual(len(posix_destinations), len(set(posix_destinations)))
        required_posix_destinations = {
            "bin/scoutica",
            "bin/validate_card.py",
            "bin/scan_runtime.py",
            "bin/scoring.py",
            "bin/import_aijs.py",
            "bin/safe_fetch.py",
            "bin/message_runtime.py",
            "schemas/candidate_profile.schema.json",
            "schemas/roe.schema.json",
            "schemas/evidence.schema.json",
            "templates/card.gitignore",
            "templates/EMPLOYER_CARD.template.md",
            "protocol/examples/sample_card/profile.json",
            "protocol/examples/employer_card/roles/senior-ai-architect.json",
        }
        self.assertTrue(required_posix_destinations.issubset(posix_destinations))

        for resource in resources:
            source = resource["source"]
            destination = resource["destination"]
            self.assertTrue(resource["platforms"])
            self.assertTrue(set(resource["platforms"]).issubset({"posix", "windows"}))
            self.assertFalse(source.startswith(("/", "\\")), source)
            self.assertFalse(destination.startswith(("/", "\\")), destination)
            self.assertNotIn("..", source.split("/"), source)
            self.assertNotIn("..", destination.split("/"), destination)
            self.assertEqual(posixpath.normpath(source), source)
            self.assertEqual(posixpath.normpath(destination), destination)
            self.assertTrue((ROOT / source).is_file(), source)

        self.assertIn("$contract.installation.resources", self.windows_installer_source)
        self.assertIn("Install-Resource", self.windows_installer_source)
        self.assertIn("Assert-NoReparseComponents", self.windows_installer_source)
        self.assertIn("$seenDestinations.ContainsKey", self.windows_installer_source)
        self.assertIn('"templates/card.gitignore"', self.windows_installer_source)
        self.assertNotIn(
            'Invoke-WebRequest -Uri "$REPO_RAW/tools/scan_runtime.py"',
            self.windows_installer_source,
        )

    def test_windows_wrappers_preserve_installer_host(self) -> None:
        self.assertIn("$CURRENT_POWERSHELL_EXE = (Get-Process -Id $PID).Path", self.windows_installer_source)
        self.assertIn('"$batchHost" -NoProfile', self.windows_installer_source)
        self.assertIn("[scriptblock]::Create($functionBody)", self.windows_installer_source)
        self.assertNotRegex(
            self.windows_installer_source,
            r'(?m)^powershell\s+-ExecutionPolicy\s+Bypass',
        )

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
