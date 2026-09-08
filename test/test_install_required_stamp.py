#!/usr/bin/env python3
from __future__ import annotations

import os
import pathlib
import subprocess
import tempfile
import unittest

REPO = pathlib.Path(__file__).resolve().parents[1]
UPDATER = REPO / ".local/bin/dotfiles-update"
DOTFILES_CLI = REPO / "scripts/dotfiles"

GIT_ENV = {
    "GIT_AUTHOR_NAME": "Test",
    "GIT_AUTHOR_EMAIL": "test@example.com",
    "GIT_COMMITTER_NAME": "Test",
    "GIT_COMMITTER_EMAIL": "test@example.com",
}


class InstallRequiredStampTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = pathlib.Path(self.tmp.name)
        self.home = root / "home"
        self.home.mkdir()
        self.origin = root / "origin.git"
        self.workdir = root / "seed"
        self.dotfiles = self.home / ".dot_files"
        self.stamp = self.home / ".config/dotfiles/install-required"

        self.git(["init", "--bare", "-b", "main", str(self.origin)], cwd=root)
        self.git(["clone", str(self.origin), str(self.workdir)], cwd=root)
        (self.workdir / "install_environment.sh").write_text("#!/bin/bash\necho install\n")
        (self.workdir / "README.md").write_text("seed\n")
        units = self.workdir / ".config/systemd/user"
        units.mkdir(parents=True)
        (units / "dummy.service").write_text("[Unit]\n")
        self.git(["add", "-A"], cwd=self.workdir)
        self.git(["commit", "-m", "seed"], cwd=self.workdir)
        self.git(["push", "origin", "main"], cwd=self.workdir)
        self.git(["clone", str(self.origin), str(self.dotfiles)], cwd=root)

    def git(self, args: list[str], cwd: pathlib.Path) -> None:
        subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True, env={**os.environ, **GIT_ENV})

    def push_upstream_change(self, relpath: str, content: str) -> None:
        target = self.workdir / relpath
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content)
        if relpath.endswith(".sh"):
            target.chmod(0o755)
        self.git(["add", relpath], cwd=self.workdir)
        self.git(["commit", "-m", f"change {relpath}"], cwd=self.workdir)
        self.git(["push", "origin", "main"], cwd=self.workdir)

    def run_script(self, argv: list[str]) -> subprocess.CompletedProcess[str]:
        env = {
            **GIT_ENV,
            "HOME": str(self.home),
            "PATH": os.environ["PATH"],
            "XDG_RUNTIME_DIR": self.tmp.name,
            "DOTFILES_DIR": str(self.dotfiles),
        }
        return subprocess.run(argv, capture_output=True, text=True, env=env)

    def test_updater_stamps_on_installer_change(self) -> None:
        self.push_upstream_change("install_environment.sh", "#!/bin/bash\necho v2\n")
        result = self.run_script([str(UPDATER)])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self.stamp.is_file())
        self.assertRegex(self.stamp.read_text().strip(), r"^[0-9a-f]{40}\.\.[0-9a-f]{40}$")
        self.assertIn("run install_environment.sh", result.stderr)

    def test_updater_stamps_on_systemd_unit_change(self) -> None:
        self.push_upstream_change(".config/systemd/user/dummy.service", "[Unit]\nDescription=x\n")
        result = self.run_script([str(UPDATER)])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self.stamp.is_file())

    def test_updater_skips_stamp_on_unrelated_change(self) -> None:
        self.push_upstream_change("README.md", "updated\n")
        result = self.run_script([str(UPDATER)])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.stamp.exists())

    def test_pull_runs_installer_on_trigger(self) -> None:
        marker = self.home / "installer-ran"
        self.push_upstream_change(
            "install_environment.sh",
            f'#!/bin/bash\ntouch "{marker}"\n',
        )
        result = self.run_script([str(DOTFILES_CLI), "pull"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(marker.is_file())
        self.assertTrue(self.stamp.is_file())
        self.assertIn("running install_environment.sh", result.stdout)

    def test_pull_skips_installer_on_unrelated_change(self) -> None:
        self.push_upstream_change("README.md", "updated\n")
        result = self.run_script([str(DOTFILES_CLI), "pull"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.home / "installer-ran").exists())
        self.assertFalse(self.stamp.exists())


if __name__ == "__main__":
    unittest.main()
