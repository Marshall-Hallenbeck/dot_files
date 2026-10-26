from __future__ import annotations

import os
import pathlib
import runpy
import subprocess
import tempfile
import unittest

REPO = pathlib.Path(__file__).resolve().parents[1]


class RemoteControlFeatureTests(unittest.TestCase):
    def make_executable(self, path: pathlib.Path, content: str) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        path.chmod(0o755)

    def test_installer_lists_optional_remote_control_command(self) -> None:
        installer = (REPO / "install_environment.sh").read_text()

        self.assertIn("Optional features:", installer)
        self.assertIn("dotfiles feature-enable ai-remote-control", installer)

    def test_cleanup_finds_deleted_unmanaged_default_server(self) -> None:
        cleanup = runpy.run_path(
            str(REPO / ".local/libexec/codex-rc-cleanup")
        )
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            home = root / "home"
            process = root / "proc/42424242"
            process.mkdir(parents=True)
            process.joinpath("cmdline").write_bytes(
                b"/usr/local/lib/node_modules/@openai/codex/bin/codex\0"
                b"-c\0features.code_mode_host=true\0"
                b"app-server\0--listen\0unix://\0"
            )
            process.joinpath("exe").symlink_to(
                "/usr/local/lib/node_modules/@openai/.codex-old/bin/codex (deleted)"
            )
            proxy = root / "proc/42424243"
            proxy.mkdir()
            proxy.joinpath("cmdline").write_bytes(
                b"/home/example/.codex/packages/standalone/current/bin/codex\0"
                b"app-server\0proxy\0"
            )
            proxy.joinpath("exe").symlink_to(
                "/home/example/.codex/packages/standalone/releases/0.1/bin/codex"
            )

            unmanaged, managed, proxies = cleanup["collect_servers"](
                home, root / "proc"
            )

        self.assertEqual(unmanaged, [42424242])
        self.assertEqual(managed, [])
        self.assertEqual(proxies, [42424243])

    def test_feature_enable_uses_native_codex_and_registered_claude_services(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            home = pathlib.Path(temporary)
            dotfiles = home / ".dot_files"
            for relative in (
                ".config/systemd/user/codex-app-server.service",
                ".config/systemd/user/claude-rc@.service",
                ".local/bin/codex",
                ".local/libexec/codex-rc-migrate",
            ):
                source = dotfiles / relative
                source.parent.mkdir(parents=True, exist_ok=True)
                source.write_bytes((REPO / relative).read_bytes())
                if relative.startswith(".local/bin/"):
                    source.chmod(0o755)

            installed_wrapper = home / ".local/bin/codex"

            cleanup_log = home / "cleanup.log"
            self.make_executable(
                dotfiles / ".local/libexec/codex-rc-cleanup",
                "#!/usr/bin/env bash\n"
                "printf '%s\\n' \"$*\" >> \"$CLEANUP_LOG\"\n"
                "exit \"${CLEANUP_STATUS:-0}\"\n",
            )

            codex_log = home / "codex.log"
            native_codex = home / ".codex/packages/standalone/current/bin/codex"
            self.make_executable(
                native_codex,
                "#!/usr/bin/env bash\n"
                "printf '%s\\n' \"$*\" >> \"$CODEX_LOG\"\n",
            )
            self.make_executable(
                home / ".local/bin/claude",
                "#!/usr/bin/env bash\nexit 0\n",
            )

            project = home / "project"
            project.mkdir()
            projects = home / ".config/claude-rc/projects"
            projects.mkdir(parents=True)
            (projects / "example").symlink_to(project, target_is_directory=True)

            fake_bin = home / "fake-bin"
            fake_bin.mkdir()
            systemctl_log = home / "systemctl.log"
            systemd_run_log = home / "systemd-run.log"
            self.make_executable(
                fake_bin / "systemctl",
                "#!/usr/bin/env bash\n"
                "printf '%s\\n' \"$*\" >> \"$SYSTEMCTL_LOG\"\n"
                "case \"$*\" in\n"
                "  '--user is-active --quiet codex-app-server.service') exit 3 ;;\n"
                "  '--user show codex-app-server.service --property=MainPID --value') printf '0\\n' ;;\n"
                "esac\n",
            )
            self.make_executable(
                fake_bin / "loginctl",
                "#!/usr/bin/env bash\nprintf 'Linger=yes\\n'\n",
            )
            self.make_executable(
                fake_bin / "systemd-run",
                "#!/usr/bin/env bash\n"
                "printf '%s\\n' \"$*\" >> \"$SYSTEMD_RUN_LOG\"\n",
            )
            env = os.environ | {
                "HOME": str(home),
                "PATH": f"{fake_bin}:{os.environ['PATH']}",
                "CODEX_LOG": str(codex_log),
                "CLEANUP_LOG": str(cleanup_log),
                "CLEANUP_STATUS": "0",
                "SYSTEMCTL_LOG": str(systemctl_log),
                "SYSTEMD_RUN_LOG": str(systemd_run_log),
            }

            result = subprocess.run(
                [str(REPO / "scripts/dotfiles"), "feature-enable", "ai-remote-control"],
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(cleanup_log.read_text(), "--check\n")
            codex_calls = codex_log.read_text() if codex_log.exists() else ""
            self.assertIn("app-server daemon bootstrap --remote-control", codex_calls)
            calls = systemctl_log.read_text()
            self.assertIn("--user enable --now codex-app-server.service", calls)
            self.assertIn("--user enable --now claude-rc@example.service", calls)
            wrapper_result = subprocess.run(
                [str(installed_wrapper), "app-server", "daemon", "start"],
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(wrapper_result.returncode, 0, wrapper_result.stderr)
            self.assertIn("app-server daemon start", codex_log.read_text())
            self.assertNotIn("codex-rc", installed_wrapper.read_text())

            self.make_executable(
                home / ".codex/packages/app-server-daemon/current/bin/codex",
                "#!/usr/bin/env bash\nexit 0\n",
            )
            codex_log.unlink()
            code_mode_result = subprocess.run(
                [
                    str(installed_wrapper),
                    "-c",
                    "features.code_mode_host=true",
                    "app-server",
                    "--listen",
                    "unix://",
                ],
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(code_mode_result.returncode, 0, code_mode_result.stderr)
            self.assertEqual(
                codex_log.read_text(), "app-server daemon start\n"
            )
            codex_log.unlink()
            proxy_result = subprocess.run(
                [str(installed_wrapper), "app-server", "proxy"],
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(proxy_result.returncode, 0, proxy_result.stderr)
            self.assertEqual(
                codex_log.read_text(),
                "app-server daemon start\napp-server proxy\n",
            )

            codex_log.unlink()
            cleanup_log.unlink()
            env["CLEANUP_STATUS"] = "75"
            result = subprocess.run(
                [str(REPO / "scripts/dotfiles"), "feature-enable", "ai-remote-control"],
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(cleanup_log.read_text(), "--check\n")
            self.assertFalse(codex_log.exists())
            self.assertIn(
                "--user --unit=codex-app-server-migration --collect --no-block",
                systemd_run_log.read_text(),
            )
            proxy_result = subprocess.run(
                [str(installed_wrapper), "app-server", "proxy"],
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(proxy_result.returncode, 75)
            self.assertIn("daemon migration is in progress", proxy_result.stderr)

            migration = (REPO / ".local/libexec/codex-rc-migrate").read_text()
            self.assertIn("codex-rc-cleanup\" --force", migration)
            self.assertIn("app-server daemon bootstrap --remote-control", migration)


if __name__ == "__main__":
    unittest.main()
