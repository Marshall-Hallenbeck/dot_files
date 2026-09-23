#!/usr/bin/env python3
from __future__ import annotations

import os
import pathlib
import subprocess
import tempfile
import unittest

REPO = pathlib.Path(__file__).resolve().parents[1]
DOTFILES_CLI = REPO / "scripts/dotfiles"


class DotfilesStatusTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.home = pathlib.Path(self.temporary.name) / "home"
        self.dotfiles = self.home / ".dot_files"
        self.dotfiles.mkdir(parents=True)

        tracked = {
            ".codex/config.toml": 'model = "gpt-5"\n',
            ".config/systemd/user/ai-agents.slice": "[Slice]\n",
            ".config/systemd/user/agent-sync.service": "[Service]\n",
            ".config/systemd/user/agent-sync.timer": "[Timer]\n",
            ".config/systemd/user/claude-rc@.service.d/40-reattach.conf": "[Service]\n",
            ".gitattributes": ".codex/config.toml filter=codex-projects\n",
            "AGENTS.md": "# project\n",
            "global-AGENTS.md": "# global\n",
            ".local/bin/claude-rc-reattach": "#!/bin/bash\n",
            ".local/bin/codex-config-sync": "#!/bin/bash\n",
            ".local/libexec/codex-config-sync.py": "# implementation\n",
            ".vimrc": 'set nocompatible\n',
        }
        for relative, content in tracked.items():
            source = self.dotfiles / relative
            source.parent.mkdir(parents=True, exist_ok=True)
            source.write_text(content)

        subprocess.run(
            ["git", "init", "-q"],
            cwd=self.dotfiles,
            check=True,
        )
        subprocess.run(
            ["git", "add", "-A"],
            cwd=self.dotfiles,
            check=True,
        )

        home_config = self.home / ".codex/config.toml"
        home_config.parent.mkdir(parents=True)
        home_config.write_text('model = "gpt-5"\n')
        (self.home / ".vimrc").symlink_to(self.dotfiles / ".vimrc")
        for relative in (
            ".config/systemd/user/ai-agents.slice",
            ".config/systemd/user/agent-sync.service",
            ".config/systemd/user/agent-sync.timer",
            ".local/bin/codex-config-sync",
            ".local/libexec/codex-config-sync.py",
        ):
            target = self.home / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.symlink_to(self.dotfiles / relative)
        for instructions in (".claude/CLAUDE.md", ".codex/AGENTS.md"):
            target = self.home / instructions
            target.parent.mkdir(parents=True, exist_ok=True)
            target.symlink_to(self.dotfiles / "global-AGENTS.md")

    def run_status(self) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(DOTFILES_CLI), "status"],
            capture_output=True,
            text=True,
            env={**os.environ, "HOME": str(self.home)},
            check=False,
        )

    def test_status_skips_repo_only_and_disabled_feature_paths(self) -> None:
        result = self.run_status()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("NOT LINK", result.stdout)
        self.assertNotIn("MISSING", result.stdout)
        self.assertIn("Status: 8 linked, 0 issues, 0 missing", result.stdout)

    def test_status_checks_all_remote_control_assets_when_enabled(self) -> None:
        marker = self.home / ".config/dotfiles/features/ai-remote-control"
        marker.parent.mkdir(parents=True)
        marker.write_text("")

        result = self.run_status()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(
            f"MISSING:  {self.home}/.config/systemd/user/claude-rc@.service.d/40-reattach.conf",
            result.stdout,
        )
        self.assertIn(
            f"MISSING:  {self.home}/.local/bin/claude-rc-reattach",
            result.stdout,
        )
        self.assertIn("Status: 8 linked, 0 issues, 2 missing", result.stdout)

    def test_status_reports_global_instructions_that_are_not_linked(self) -> None:
        (self.home / ".codex/AGENTS.md").unlink()
        (self.home / ".codex/AGENTS.md").write_text("# stale copy\n")
        (self.home / ".claude/CLAUDE.md").unlink()

        result = self.run_status()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f"NOT LINK: {self.home}/.codex/AGENTS.md", result.stdout)
        self.assertIn(f"MISSING:  {self.home}/.claude/CLAUDE.md", result.stdout)
        self.assertIn("Status: 6 linked, 1 issues, 1 missing", result.stdout)

    def test_status_reports_global_instructions_linked_elsewhere(self) -> None:
        other = self.dotfiles / "AGENTS.md"
        (self.home / ".claude/CLAUDE.md").unlink()
        (self.home / ".claude/CLAUDE.md").symlink_to(other)

        result = self.run_status()

        self.assertIn(
            f"WRONG:   {self.home}/.claude/CLAUDE.md -> {other} "
            f"(expected {self.dotfiles}/global-AGENTS.md)",
            result.stdout,
        )
        self.assertIn("Status: 7 linked, 1 issues, 0 missing", result.stdout)


if __name__ == "__main__":
    unittest.main()
