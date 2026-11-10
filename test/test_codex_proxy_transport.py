"""Exercise the real launcher without starting a daemon or opening a socket."""
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
WRAPPER = Path(os.environ.get("CODEX_WRAPPER_UNDER_TEST", REPO / ".local/bin/codex"))


class CodexProxyTransportTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.home = Path(self.temporary.name)
        native = self.home / ".codex/packages/standalone/current/bin/codex"
        native.parent.mkdir(parents=True)
        native.write_text('''#!/bin/bash
set -eu
printf '%s\\n' "$*" >> "$HOME/calls"
if [[ "$*" == "app-server daemon start" ]]; then
    printf '{"alreadyRunning":true}\\n'
    exit "${START_STATUS:-0}"
fi
printf 'HTTP/1.1 101 Switching Protocols\\r\\n\\r\\n'
''')
        native.chmod(0o755)
        managed = self.home / ".codex/packages/app-server-daemon/current/bin/codex"
        managed.parent.mkdir(parents=True)
        managed.symlink_to(native)
        marker = self.home / ".config/dotfiles/features/ai-remote-control"
        marker.parent.mkdir(parents=True)
        marker.touch()
        self.env = os.environ | {"HOME": str(self.home)}

    def run_wrapper(self, *args):
        return subprocess.run(["bash", str(WRAPPER), *args], env=self.env,
                              capture_output=True, timeout=10, check=False)

    def test_missing_managed_package_refuses_desktop_launches_without_mutation(self):
        (self.home / ".codex/packages/app-server-daemon/current/bin/codex").unlink()
        for args in (("app-server", "proxy"),
                     ("-c", "features.code_mode_host=true", "app-server", "--listen", "unix://"),
                     ("-c", "features.code_mode_host=true", "app-server", "--listen=unix://")):
            with self.subTest(args=args):
                result = self.run_wrapper(*args)
                self.assertEqual(result.returncode, 75)
                self.assertEqual(result.stdout, b"")
                self.assertIn(b"managed daemon package is missing", result.stderr)
                self.assertFalse((self.home / "calls").exists())

    def test_missing_package_does_not_block_normal_cli_or_explicit_lifecycle(self):
        (self.home / ".codex/packages/app-server-daemon/current/bin/codex").unlink()
        for args in ((), ("exec", "hello"), ("--version",),
                     ("app-server", "daemon", "start"),
                     ("app-server", "daemon", "bootstrap", "--remote-control"),
                     ("app-server", "daemon", "update", "--from-cli", "--yes")):
            with self.subTest(args=args):
                result = self.run_wrapper(*args)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stderr, b"")

    def test_unopted_host_preserves_proxy_passthrough_without_package(self):
        (self.home / ".codex/packages/app-server-daemon/current/bin/codex").unlink()
        (self.home / ".config/dotfiles/features/ai-remote-control").unlink()
        result = self.run_wrapper("app-server", "proxy")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.home / "calls").read_text(), "app-server proxy\n")

    def test_managed_code_mode_host_routes_to_daemon_start(self):
        result = self.run_wrapper("-c", "features.code_mode_host=true",
                                  "app-server", "--listen", "unix://")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.home / "calls").read_text(), "app-server daemon start\n")

    def test_proxy_stdout_contains_only_protocol_bytes(self):
        result = self.run_wrapper("app-server", "proxy")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, b"HTTP/1.1 101 Switching Protocols\r\n\r\n")
        self.assertIn(b'{"alreadyRunning":true}', result.stderr)
        self.assertEqual((self.home / "calls").read_text(),
                         "app-server daemon start\napp-server proxy\n")

    def test_failed_start_does_not_run_proxy_or_pollute_stdout(self):
        self.env["START_STATUS"] = "42"
        result = self.run_wrapper("app-server", "proxy")
        self.assertEqual(result.returncode, 42)
        self.assertEqual(result.stdout, b"")
        self.assertIn(b'{"alreadyRunning":true}', result.stderr)
        self.assertEqual((self.home / "calls").read_text(), "app-server daemon start\n")

    def test_explicit_daemon_start_keeps_its_normal_stdout(self):
        result = self.run_wrapper("app-server", "daemon", "start")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, b'{"alreadyRunning":true}\n')
        self.assertEqual(result.stderr, b"")

    def test_migration_rejects_proxy_before_start(self):
        (self.home / ".codex/app-server-daemon-migrating").touch()
        result = self.run_wrapper("app-server", "proxy")
        self.assertEqual(result.returncode, 75)
        self.assertEqual(result.stdout, b"")
        self.assertIn(b"migration is in progress", result.stderr)
        self.assertFalse((self.home / "calls").exists())


if __name__ == "__main__":
    unittest.main()
