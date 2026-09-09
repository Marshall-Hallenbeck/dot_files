#!/usr/bin/env python3
from __future__ import annotations

import importlib.machinery
import importlib.util
import json
import os
import pathlib
import subprocess
import tempfile
import textwrap
import time
import unittest

REPO = pathlib.Path(__file__).resolve().parents[1]
UPDATER = REPO / ".local/bin/codex-auto-update"


class CodexAutoUpdateTests(unittest.TestCase):
    def make_executable(self, path: pathlib.Path, content: str) -> None:
        path.write_text(textwrap.dedent(content).lstrip())
        path.chmod(0o755)

    def make_environment(
        self,
        root: pathlib.Path,
        current: str,
        latest: str,
        *,
        active_state: str = "active",
        update_to: str | None = None,
        server_version: str | None = None,
    ):
        home = root / "home"
        bin_dir = root / "bin"
        home.mkdir()
        bin_dir.mkdir()
        installed = root / "installed-version"
        installed.write_text(current)
        server = root / "server-version"
        server.write_text(server_version or current)
        service_state = root / "service-state"
        service_state.write_text(active_state)
        calls = root / "calls"
        registry = root / "registry.json"
        registry.write_text(json.dumps({"version": latest}))
        update_target = update_to or latest

        codex = bin_dir / "codex"
        self.make_executable(
            codex,
            f"""
            #!/usr/bin/env bash
            set -euo pipefail
            printf 'codex %s\\n' "$*" >> {calls!s}
            case "${{1:-}}" in
              --version)
                reads=0
                [[ ! -e {root!s}/version-reads ]] || reads=$(<{root!s}/version-reads)
                reads=$((reads + 1))
                printf '%s' "$reads" > {root!s}/version-reads
                if [[ -e {root!s}/advance-on-second-version && "$reads" -ge 2 ]]; then
                  printf '0.150.0' > {installed!s}
                fi
                printf 'codex-cli %s\\n' "$(<{installed!s})"
                ;;
              update) exit 9 ;;
              app-server)
                [[ "${{2:-}} ${{3:-}}" == "daemon version" ]]
                [[ ! -e {root!s}/hang-probe ]] || sleep 5
                printf '{{"status":"running","appServerVersion":"%s"}}\\n' "$(<{server!s})"
                ;;
              *) exit 2 ;;
            esac
            """,
        )
        systemctl = bin_dir / "systemctl"
        self.make_executable(
            systemctl,
            f"""
            #!/usr/bin/env bash
            set -euo pipefail
            printf 'systemctl %s\\n' "$*" >> {calls!s}
            state=$(<{service_state!s})
            case "$*" in
              "--user show --property=ActiveState --value codex-app-server.service")
                [[ "$state" != error ]] || exit 1
                printf '%s\\n' "$state"
                ;;
              "--user try-restart codex-app-server.service")
                [[ ! -e {root!s}/restart-fails ]] || exit 1
                if [[ "$state" == active ]]; then
                  cp {installed!s} {server!s}
                fi
                ;;
              "--user try-restart --no-block codex-app-server.service")
                [[ ! -e {root!s}/restart-fails ]] || exit 1
                ;;
              *) exit 2 ;;
            esac
            """,
        )
        npm = bin_dir / "npm"
        self.make_executable(
            npm,
            f"""
            #!/usr/bin/env bash
            set -euo pipefail
            printf 'npm %s\\n' "$*" >> {calls!s}
            if [[ -e {root!s}/term-resistant-child ]]; then
              /usr/bin/python3 -c 'import os, signal, sys, time; signal.signal(signal.SIGTERM, signal.SIG_IGN); open(sys.argv[1], "w").write(str(os.getpid())); time.sleep(60)' {root!s}/term-resistant-child.pid &
              wait "$!"
            fi
            [[ ! -e {root!s}/hang-npm ]] || sleep 5
            [[ "$*" == "install --global @openai/codex@{latest}" ]]
            printf '{update_target}' > {installed!s}
            """,
        )
        env = os.environ | {
            "HOME": str(home),
            "XDG_RUNTIME_DIR": str(root / "run"),
            "XDG_STATE_HOME": str(root / "state"),
            "CODEX_AUTO_UPDATE_CODEX_BIN": str(codex),
            "CODEX_AUTO_UPDATE_NPM_BIN": str(npm),
            "CODEX_AUTO_UPDATE_SYSTEMCTL_BIN": str(systemctl),
            "CODEX_AUTO_UPDATE_REGISTRY_URL": registry.as_uri(),
            "CODEX_AUTO_UPDATE_READY_TIMEOUT": "0.5",
            "CODEX_AUTO_UPDATE_UPDATE_TIMEOUT": "0.5",
        }
        pending = root / "state/codex-auto-update/pending-restart.json"
        return env, installed, server, service_state, calls, pending

    def run_updater(self, env: dict[str, str]) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(UPDATER)], env=env, capture_output=True, text=True, check=False
        )

    def load_updater_module(self):
        loader = importlib.machinery.SourceFileLoader("codex_auto_update", str(UPDATER))
        spec = importlib.util.spec_from_loader(loader.name, loader)
        if spec is None:
            self.fail("could not create updater module spec")
        module = importlib.util.module_from_spec(spec)
        loader.exec_module(module)
        return module

    def test_current_install_without_pending_restart_does_nothing(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            env, installed, _, _, calls, pending = self.make_environment(
                root, "0.149.1", "0.149.1"
            )

            result = self.run_updater(env)

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(installed.read_text(), "0.149.1")
            self.assertFalse(pending.exists())
            self.assertEqual(
                calls.read_text().splitlines(),
                [
                    "codex --version",
                    "systemctl --user show --property=ActiveState --value codex-app-server.service",
                    "codex app-server daemon version",
                ],
            )
            self.assertIn("already current", result.stdout)

    def test_outdated_install_updates_and_queues_graceful_restart(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            env, installed, server, _, calls, pending = self.make_environment(
                root, "0.147.0", "0.149.1", active_state="active"
            )

            result = self.run_updater(env)

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(installed.read_text(), "0.149.1")
            self.assertEqual(server.read_text(), "0.147.0")
            self.assertTrue(pending.exists())
            self.assertIn(
                "npm install --global @openai/codex@0.149.1", calls.read_text()
            )
            self.assertNotIn("codex update", calls.read_text())
            self.assertIn(
                "systemctl --user try-restart --no-block codex-app-server.service",
                calls.read_text(),
            )
            self.assertIn("restart queued", result.stdout)

    def test_outdated_install_does_not_start_an_inactive_server(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            env, installed, server, _, calls, pending = self.make_environment(
                root, "0.147.0", "0.149.1", active_state="inactive"
            )

            result = self.run_updater(env)

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(installed.read_text(), "0.149.1")
            self.assertEqual(server.read_text(), "0.147.0")
            self.assertNotIn("try-restart", calls.read_text())
            self.assertFalse(pending.exists())
            self.assertIn("inactive and remains stopped", result.stdout)

    def test_newer_or_same_core_local_install_is_not_downgraded(self) -> None:
        for current in ("0.150.0", "0.149.1+local"):
            with self.subTest(current=current), tempfile.TemporaryDirectory() as temporary:
                root = pathlib.Path(temporary)
                env, installed, _, _, calls, _ = self.make_environment(
                    root, current, "0.149.1"
                )

                result = self.run_updater(env)

                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(installed.read_text(), current)
                self.assertNotIn("npm install", calls.read_text())

    def test_matching_prerelease_updates_to_stable(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            env, installed, _, _, calls, _ = self.make_environment(
                root, "0.149.1-beta.1", "0.149.1"
            )

            result = self.run_updater(env)

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(installed.read_text(), "0.149.1")
            self.assertIn("npm install --global @openai/codex@0.149.1", calls.read_text())

    def test_current_cli_restarts_a_stale_active_app_server_without_marker(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            env, _, server, _, calls, pending = self.make_environment(
                root,
                "0.149.1",
                "0.149.1",
                active_state="active",
                server_version="0.145.0",
            )

            result = self.run_updater(env)

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(server.read_text(), "0.145.0")
            self.assertIn("try-restart --no-block", calls.read_text())
            self.assertTrue(pending.exists())

    def test_concurrent_newer_install_is_preserved_before_npm_update(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            env, installed, _, _, calls, pending = self.make_environment(
                root, "0.147.0", "0.149.1"
            )
            (root / "advance-on-second-version").touch()

            result = self.run_updater(env)

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(installed.read_text(), "0.150.0")
            self.assertNotIn("npm install", calls.read_text())
            self.assertTrue(pending.exists())

    def test_registry_race_accepts_newer_installed_version(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            env, installed, server, _, _, pending = self.make_environment(
                root, "0.147.0", "0.149.1", update_to="0.150.0"
            )

            result = self.run_updater(env)

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(installed.read_text(), "0.150.0")
            self.assertEqual(server.read_text(), "0.147.0")
            self.assertTrue(pending.exists())

    def test_service_query_failure_keeps_pending_restart(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            env, installed, _, _, _, pending = self.make_environment(
                root, "0.147.0", "0.149.1", active_state="error"
            )

            result = self.run_updater(env)

            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(installed.read_text(), "0.149.1")
            self.assertTrue(pending.exists())

    def test_current_binary_retries_a_pending_restart(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            env, _, server, _, calls, pending = self.make_environment(
                root,
                "0.149.1",
                "0.149.1",
                active_state="active",
                server_version="0.147.0",
            )
            pending.parent.mkdir(parents=True)
            pending.write_text('{"installedVersion":"0.149.1"}\n')

            result = self.run_updater(env)

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(server.read_text(), "0.147.0")
            self.assertIn("try-restart --no-block", calls.read_text())
            self.assertEqual(calls.read_text().count("try-restart --no-block"), 1)
            self.assertTrue(pending.exists())

    def test_transitional_pending_restart_is_deferred_without_reconciliation(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            env, _, _, _, calls, pending = self.make_environment(
                root, "0.149.1", "0.149.1", active_state="activating"
            )
            pending.parent.mkdir(parents=True)
            pending.write_text('{"installedVersion":"0.149.1"}\n')

            result = self.run_updater(env)

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(pending.exists())
            self.assertEqual(
                calls.read_text().count(
                    "systemctl --user show --property=ActiveState --value"
                ),
                1,
            )
            self.assertIn("deferred while state is activating", result.stdout)

    def test_restart_failure_keeps_pending_marker_for_retry(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            env, installed, _, _, _, pending = self.make_environment(
                root, "0.147.0", "0.149.1", active_state="active"
            )
            (root / "restart-fails").touch()

            result = self.run_updater(env)

            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(installed.read_text(), "0.149.1")
            self.assertTrue(pending.exists())

    def test_blocked_readiness_probe_obeys_configured_timeout(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            env, _, _, _, _, pending = self.make_environment(
                root, "0.149.1", "0.149.1", active_state="active"
            )
            pending.parent.mkdir(parents=True)
            pending.write_text('{"installedVersion":"0.149.1"}\n')
            (root / "hang-probe").touch()

            result = subprocess.run(
                [str(UPDATER)],
                env=env,
                capture_output=True,
                text=True,
                check=False,
                timeout=10,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertTrue(pending.exists())
            self.assertIn("timed out after", result.stderr)

    def test_malformed_semver_values_are_rejected(self) -> None:
        updater = self.load_updater_module()
        for value in (
            "01.2.3",
            "1.2.3.4",
            "1.2.3-",
            "1.2.3-alpha..1",
            "1.2.3+meta..x",
        ):
            with self.subTest(value=value):
                with self.assertRaises(RuntimeError):
                    updater.parse_semver(value)
                with self.assertRaises(RuntimeError):
                    updater.parse_cli_version(f"codex-cli {value}")

    def test_blocked_npm_install_is_bounded_and_later_retry_succeeds(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            env, installed, server, _, _, pending = self.make_environment(
                root, "0.147.0", "0.149.1", active_state="active"
            )
            env["CODEX_AUTO_UPDATE_UPDATE_TIMEOUT"] = "0.1"
            (root / "hang-npm").touch()

            failed = subprocess.run(
                [str(UPDATER)],
                env=env,
                capture_output=True,
                text=True,
                check=False,
                timeout=10,
            )

            self.assertNotEqual(failed.returncode, 0)
            self.assertEqual(installed.read_text(), "0.147.0")
            self.assertFalse(pending.exists())
            (root / "hang-npm").unlink()

            recovered = self.run_updater(env)

            self.assertEqual(recovered.returncode, 0, recovered.stderr)
            self.assertEqual(installed.read_text(), "0.149.1")
            self.assertEqual(server.read_text(), "0.147.0")
            self.assertTrue(pending.exists())

    def test_term_resistant_npm_descendant_is_killed_after_timeout(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            env, *_ = self.make_environment(root, "0.147.0", "0.149.1")
            env["CODEX_AUTO_UPDATE_UPDATE_TIMEOUT"] = "0.5"
            (root / "term-resistant-child").touch()

            failed = subprocess.run(
                [str(UPDATER)],
                env=env,
                capture_output=True,
                text=True,
                check=False,
                timeout=10,
            )

            self.assertNotEqual(failed.returncode, 0)
            pid = int((root / "term-resistant-child.pid").read_text())
            deadline = time.monotonic() + 1
            while pathlib.Path(f"/proc/{pid}").exists() and time.monotonic() < deadline:
                time.sleep(0.01)
            self.assertFalse(pathlib.Path(f"/proc/{pid}").exists())

    def test_timeouts_must_be_finite_and_positive(self) -> None:
        for variable, value in (
            ("CODEX_AUTO_UPDATE_READY_TIMEOUT", "nan"),
            ("CODEX_AUTO_UPDATE_READY_TIMEOUT", "0"),
            ("CODEX_AUTO_UPDATE_UPDATE_TIMEOUT", "-1"),
        ):
            with self.subTest(variable=variable, value=value), tempfile.TemporaryDirectory() as temporary:
                root = pathlib.Path(temporary)
                env, *_ = self.make_environment(root, "0.149.1", "0.149.1")
                env[variable] = value

                result = self.run_updater(env)

                self.assertNotEqual(result.returncode, 0)
                self.assertIn("finite positive number", result.stderr)

    def test_discover_npm_selects_owner_and_rejects_ambiguity(self) -> None:
        updater = self.load_updater_module()
        with tempfile.TemporaryDirectory() as temporary:
            home = pathlib.Path(temporary)
            packages = []
            for node_version in ("v20.1.0", "v24.1.0"):
                prefix = home / ".nvm/versions/node" / node_version
                package = prefix / "lib/node_modules/@openai/codex"
                vendor = package / "node_modules/@openai/codex-linux-x64/vendor"
                vendor.mkdir(parents=True)
                (vendor / "codex").write_text("binary")
                npm = prefix / "bin/npm"
                npm.parent.mkdir(parents=True)
                npm.write_text("#!/usr/bin/env bash\n")
                npm.chmod(0o755)
                packages.append((vendor, npm))
            current = home / ".codex/packages/standalone/current"
            current.parent.mkdir(parents=True)
            current.symlink_to(packages[1][0], target_is_directory=True)

            self.assertEqual(updater.discover_npm(home), str(packages[1][1]))
            current.unlink()
            with self.assertRaisesRegex(RuntimeError, "Could not identify"):
                updater.discover_npm(home)

        with tempfile.TemporaryDirectory() as temporary:
            home = pathlib.Path(temporary)
            prefix = home / ".nvm/versions/node/v24.1.0"
            package = prefix / "lib/node_modules/@openai/codex"
            package.mkdir(parents=True)
            npm = prefix / "bin/npm"
            npm.parent.mkdir(parents=True)
            npm.write_text("#!/usr/bin/env bash\n")
            npm.chmod(0o755)
            current = home / ".codex/packages/standalone/current"
            outside = home / "outside"
            outside.mkdir()
            (outside / "codex").write_text("binary")
            current.parent.mkdir(parents=True)
            current.symlink_to(outside, target_is_directory=True)

            with self.assertRaisesRegex(RuntimeError, "does not belong"):
                updater.discover_npm(home)
            current.unlink()
            self.assertEqual(updater.discover_npm(home), str(npm))

        with tempfile.TemporaryDirectory() as temporary:
            with self.assertRaisesRegex(RuntimeError, "Could not identify"):
                updater.discover_npm(pathlib.Path(temporary))

    def test_updater_is_deployed_after_configuration_sync(self) -> None:
        deployer = (REPO / "scripts/dotfiles").read_text()
        service = (REPO / ".config/systemd/user/agent-sync.service").read_text()
        updater_exec = "ExecStart=%h/.local/bin/codex-auto-update"
        sync_exec = (
            "ExecStart=%h/.local/share/codex-config-sync-venv-current/bin/python"
        )

        self.assertIn(".local/bin/codex-auto-update", deployer)
        self.assertIn(updater_exec, service)
        self.assertLess(service.index(sync_exec), service.index(updater_exec))
        updater = UPDATER.read_text()
        self.assertIn('f"@openai/codex@{target_version}"', updater)
        self.assertNotIn("@openai/codex@latest", updater)
        self.assertNotIn('subprocess.run([codex, "update"]', updater)
    def test_app_server_service_never_force_kills_a_draining_turn(self) -> None:
        unit = (REPO / ".config/systemd/user/codex-app-server.service").read_text()
        self.assertIn("TimeoutStopSec=infinity", unit)


if __name__ == "__main__":
    unittest.main()
