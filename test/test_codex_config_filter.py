#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import subprocess
import tempfile
import unittest

try:
    import tomllib

    def toml_loads(text: str) -> dict:
        return tomllib.loads(text)
except ModuleNotFoundError:  # Python 3.10 on Ubuntu 22.04
    import tomlkit

    def toml_loads(text: str) -> dict:
        return tomlkit.parse(text).unwrap()

REPO = pathlib.Path(__file__).resolve().parents[1]
FILTER = REPO / "scripts/codex-config-filter"

TRACKED = """\
model = "gpt-6-astra"
model_reasoning_effort = "high"

[mcp_servers.context7]
url = "https://mcp.context7.com/mcp"

[features]
multi_agent = true
"""

PROJECTS = """\
[projects."/home/user/code/alpha"]
trust_level = "trusted"

[projects."/home/user/code/beta"]
trust_level = "trusted"
"""


class CodexConfigFilterTests(unittest.TestCase):
    def setUp(self) -> None:
        self.home = tempfile.TemporaryDirectory()
        self.addCleanup(self.home.cleanup)
        self.side_file = pathlib.Path(self.home.name) / ".codex/projects.local.toml"

    def run_filter(self, mode: str, stdin: str) -> str:
        result = subprocess.run(
            [str(FILTER), mode],
            input=stdin,
            capture_output=True,
            text=True,
            env={"HOME": self.home.name, "PATH": "/usr/bin:/bin"},
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def test_clean_strips_projects_and_saves_side_file(self) -> None:
        mixed = TRACKED[:-len("[features]\nmulti_agent = true\n")]
        mixed += PROJECTS + "\n[features]\nmulti_agent = true\n"
        cleaned = self.run_filter("clean", mixed)
        self.assertNotIn("[projects.", cleaned)
        self.assertIn("[features]", cleaned)
        self.assertIn("[mcp_servers.context7]", cleaned)
        saved = self.side_file.read_text()
        self.assertIn('[projects."/home/user/code/alpha"]', saved)
        self.assertIn('[projects."/home/user/code/beta"]', saved)
        toml_loads(cleaned)
        toml_loads(saved)

    def test_clean_without_projects_is_identity_and_clears_side_file(self) -> None:
        self.side_file.parent.mkdir(parents=True)
        self.side_file.write_text(PROJECTS)
        cleaned = self.run_filter("clean", TRACKED)
        self.assertEqual(cleaned, TRACKED)
        self.assertFalse(self.side_file.exists())

    def test_smudge_appends_saved_projects(self) -> None:
        self.side_file.parent.mkdir(parents=True)
        self.side_file.write_text(PROJECTS)
        smudged = self.run_filter("smudge", TRACKED)
        self.assertIn('[projects."/home/user/code/alpha"]', smudged)
        parsed = toml_loads(smudged)
        self.assertEqual(parsed["projects"]["/home/user/code/alpha"]["trust_level"], "trusted")
        self.assertEqual(parsed["features"], {"multi_agent": True})

    def test_smudge_without_side_file_is_identity(self) -> None:
        self.assertEqual(self.run_filter("smudge", TRACKED), TRACKED)

    def test_smudge_skips_sections_already_present(self) -> None:
        self.side_file.parent.mkdir(parents=True)
        self.side_file.write_text(PROJECTS)
        already = TRACKED + "\n" + PROJECTS
        smudged = self.run_filter("smudge", already)
        toml_loads(smudged)
        self.assertEqual(smudged.count('[projects."/home/user/code/alpha"]'), 1)

    def test_round_trip_is_stable(self) -> None:
        self.side_file.parent.mkdir(parents=True)
        self.side_file.write_text(PROJECTS)
        smudged = self.run_filter("smudge", TRACKED)
        cleaned = self.run_filter("clean", smudged)
        self.assertEqual(cleaned, TRACKED)
        self.assertEqual(self.run_filter("smudge", cleaned), smudged)

    def test_rejects_unknown_mode(self) -> None:
        result = subprocess.run(
            [str(FILTER), "bogus"],
            input="",
            capture_output=True,
            text=True,
            env={"HOME": self.home.name, "PATH": "/usr/bin:/bin"},
        )
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
