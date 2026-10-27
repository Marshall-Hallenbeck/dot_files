#!/usr/bin/env python3
"""Exercise installer helpers only; never run the installer or real sudo."""
from __future__ import annotations

import os
import pathlib
import shlex
import subprocess
import tempfile
import unittest

REPO = pathlib.Path(__file__).resolve().parents[1]
INSTALLER = REPO / "install_environment.sh"


class CodexSSHInstallTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="codex ssh install-")
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        self.home = self.root / "home"
        self.launchers = self.home / ".local/bin"
        self.launchers.mkdir(parents=True)
        self.system_bin = self.root / "usr/local/bin"
        self.fake_bin = self.root / "fake-bin"
        self.fake_bin.mkdir()
        self.log = self.root / "sudo-calls"
        sudo = self.fake_bin / "sudo"
        # Only a narrowly permitted command may mutate the sandbox. Never
        # delegate to host sudo, even if a future helper changes its arguments.
        sudo.write_text(
            "#!/usr/bin/env python3\n"
            "import json, os, pathlib, subprocess, sys\n"
            "args = sys.argv[1:]\n"
            "root = pathlib.Path(os.environ['SANDBOX'])\n"
            "assert args[0] in ('mkdir', 'ln'), args\n"
            "for arg in args[1:]:\n"
            "    if not arg.startswith('-'):\n"
            "        assert pathlib.Path(arg).is_relative_to(root), args\n"
            "with open(os.environ['SUDO_LOG'], 'a') as log:\n"
            "    log.write(json.dumps(args) + '\\n')\n"
            "sys.exit(subprocess.call(args))\n"
        )
        sudo.chmod(0o755)
        self.make_launcher("codex")
        self.make_launcher("codex-rc")

    def make_launcher(self, name):
        path = self.launchers / name
        path.write_text("#!/bin/sh\nexit 0\n")
        path.chmod(0o755)

    def run_helper(self):
        source = INSTALLER.read_text()
        prefix = source.split("# ── Clone or update repo", 1)[0]
        self.assertIn("install_codex_ssh_links()", prefix)
        return subprocess.run(
            ["bash", "-c", prefix + "\ninstall_codex_ssh_links " + shlex.quote(str(self.system_bin))],
            env={**os.environ, "HOME": str(self.home),
                 "PATH": str(self.fake_bin) + os.pathsep + os.environ["PATH"],
                 "SANDBOX": str(self.root), "SUDO_LOG": str(self.log)},
            capture_output=True, text=True, timeout=10,
        )

    def assert_links(self):
        for name in ("codex", "codex-rc"):
            self.assertEqual(os.readlink(self.system_bin / name), str(self.launchers / name))

    def test_new_install_links_managed_user_launchers(self):
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_links()

    def test_installer_invokes_after_codex_install_and_optional_feature(self):
        source = INSTALLER.read_text()
        prefix, body = source.split("# ── Clone or update repo", 1)
        self.assertIn('${1:-/usr/local/bin}', prefix)
        calls = [index for index, line in enumerate(body.splitlines())
                 if line.strip() == "install_codex_ssh_links /usr/local/bin"]
        self.assertEqual(len(calls), 2, "link after install and again after optional feature setup")
        lines = body.splitlines()
        install = next(i for i, line in enumerate(lines)
                       if "https://chatgpt.com/codex/install.sh" in line)
        agents = next(i for i, line in enumerate(lines) if "~/.codex/AGENTS.md" in line)
        feature = next(i for i, line in enumerate(lines)
                       if "feature-enable ai-remote-control" in line)
        hooks = next(i for i, line in enumerate(lines) if line.startswith("commit_reference_hook="))
        self.assertLess(install, calls[0])
        self.assertLess(calls[0], agents)
        self.assertLess(feature, calls[1])
        self.assertLess(calls[1], hooks)
        sync = body.split("# ── Automatic Claude and Codex configuration sync", 1)[1]
        sync = sync.split("# ── Commit-reference hooks", 1)[0]
        self.assertTrue(sync.rstrip().endswith("fi\ninstall_codex_ssh_links /usr/local/bin"),
                        "second call must also run after the non-systemd sync branch")

    def test_matching_links_are_not_replaced(self):
        first = self.run_helper()
        self.assertEqual(first.returncode, 0, first.stderr)
        before = {name: (self.system_bin / name).lstat().st_ino
                  for name in ("codex", "codex-rc")}
        self.log.write_text("")
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_links()
        for name, inode in before.items():
            self.assertEqual((self.system_bin / name).lstat().st_ino, inode)
        self.assertNotIn('"ln"', self.log.read_text())

    def test_stale_and_broken_links_are_repaired(self):
        self.system_bin.mkdir(parents=True)
        package = self.home / "package-codex"
        package.write_text("unrelated package binary")
        (self.system_bin / "codex").symlink_to(package)
        (self.system_bin / "codex-rc").symlink_to(self.home / "missing")
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_links()
        self.assertEqual(package.read_text(), "unrelated package binary")

    def test_symlink_to_directory_is_replaced_not_traversed(self):
        self.system_bin.mkdir(parents=True)
        old = self.root / "old-directory"
        old.mkdir()
        marker = old / "keep"
        marker.write_text("untouched")
        (self.system_bin / "codex").symlink_to(old, target_is_directory=True)
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_links()
        self.assertEqual(list(old.iterdir()), [marker])
        self.assertEqual(marker.read_text(), "untouched")

    def test_absent_optional_launcher_is_skipped(self):
        (self.launchers / "codex-rc").unlink()
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(os.readlink(self.system_bin / "codex"), str(self.launchers / "codex"))
        self.assertFalse((self.system_bin / "codex-rc").is_symlink())
        self.assertFalse((self.system_bin / "codex-rc").exists())

    def test_unrelated_files_and_directories_are_refused(self):
        self.system_bin.mkdir(parents=True)
        for name in ("codex", "codex-rc"):
            for kind in ("file", "directory"):
                with self.subTest(name=name, kind=kind):
                    self.system_bin = self.root / f"conflict-{name}-{kind}"
                    self.system_bin.mkdir()
                    conflict = self.system_bin / name
                    if kind == "file":
                        conflict.write_text("do not delete")
                        marker = conflict
                    else:
                        conflict.mkdir()
                        marker = conflict / "keep"
                        marker.write_text("do not delete")
                    inode = conflict.stat().st_ino
                    result = self.run_helper()
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("refusing to replace", result.stderr)
                    self.assertFalse(conflict.is_symlink())
                    self.assertEqual(conflict.stat().st_ino, inode)
                    self.assertEqual(marker.read_text(), "do not delete")
                    marker.unlink()
                    if kind == "directory":
                        conflict.rmdir()


if __name__ == "__main__":
    unittest.main()
