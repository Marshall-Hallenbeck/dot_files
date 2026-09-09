#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import pathlib
import signal
import subprocess
import sys
import tempfile
import textwrap
import time
import unittest

REPO = pathlib.Path(__file__).resolve().parents[1]
UPDATER = REPO / ".local/bin/claude-auto-update"


class ClaudeAutoUpdateTests(unittest.TestCase):
    def make_executable(self, path: pathlib.Path, content: str) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(textwrap.dedent(content).lstrip())
        path.chmod(0o755)

    def make_environment(
        self,
        root: pathlib.Path,
        *,
        current: str = "2.1.260",
        updated: str = "2.1.266",
        unit_state: str = "active",
        live_version: str | None = None,
        agents: list[dict[str, str]] | None = None,
        logged_in: bool = True,
        update_delay: float = 0,
        hidden_service_pids: list[int] | None = None,
        agents_after_freeze: list[dict[str, str]] | None = None,
        become_current_on_freeze: bool = False,
        thaw_fails: bool = False,
        hang_after_freeze: bool = False,
    ) -> tuple[dict[str, str], pathlib.Path, pathlib.Path, pathlib.Path]:
        if agents is None:
            agents = [{"kind": "interactive", "status": "active"}]
        if hidden_service_pids is None:
            hidden_service_pids = []
        agents_json = json.dumps(agents)
        agents_after_freeze_json = json.dumps(
            agents if agents_after_freeze is None else agents_after_freeze
        )
        freeze_action = (
            'rm -f "$PROC_ROOT/1234/exe"; '
            'ln -s "$UPDATED_BINARY" "$PROC_ROOT/1234/exe"'
            if become_current_on_freeze
            else ":"
        )
        thaw_action = "exit 1" if thaw_fails else ":"
        auth_json = json.dumps({"loggedIn": logged_in})
        if hang_after_freeze:
            (root / "hang-after-freeze").touch()
        home = root / "home"
        versions = home / ".local/share/claude/versions"
        launcher = home / ".local/bin/claude"
        calls = root / "calls"
        proc = root / "proc"
        cgroup = root / "cgroup/test.slice/claude-rc@example.service"
        state = root / "state"
        launcher.parent.mkdir(parents=True)
        proc.mkdir()
        cgroup.mkdir(parents=True)
        (cgroup / "cgroup.procs").write_text(
            "".join(f"{pid}\n" for pid in [1234, *hidden_service_pids])
        )

        for version in {current, updated, live_version or current}:
            binary = versions / version
            self.make_executable(
                binary,
                f"""
                #!/usr/bin/env bash
                set -euo pipefail
                printf 'claude %s\\n' "$*" >> "$CALLS"
                case "${{1:-}}" in
                  --version) printf '{version} (Claude Code)\\n' ;;
                  update)
                    sleep {update_delay}
                    ln -sfn "$UPDATED_BINARY" "$CLAUDE_BIN.next"
                    mv -Tf "$CLAUDE_BIN.next" "$CLAUDE_BIN"
                    ;;
                  agents)
                    if [[ -e "$AGENTS_AFTER_FREEZE" ]]; then
                      if [[ -e "$HANG_AFTER_FREEZE" ]]; then sleep 10; fi
                      printf '%s\n' '{agents_after_freeze_json}'
                    else
                      printf '%s\n' '{agents_json}'
                    fi
                    ;;
                  auth) printf '%s\n' '{auth_json}' ;;
                  *) exit 2 ;;
                esac
                """,
            )
        launcher.symlink_to(versions / current)

        systemctl = root / "bin/systemctl"
        self.make_executable(
            systemctl,
            f"""
            #!/usr/bin/env bash
            set -euo pipefail
            printf 'systemctl %s\\n' "$*" >> "$CALLS"
            case "$*" in
              "--user list-units --all --type=service --plain --no-legend --full claude-rc@*.service")
                printf 'claude-rc@example.service loaded {unit_state} running example\\n'
                ;;
              "--user show claude-rc@example.service --property=ActiveState --property=MainPID")
                printf 'MainPID=%s\nActiveState=%s\n' "${{MAIN_PID:-1234}}" "{unit_state}"
                ;;
              "--user show claude-rc@example.service --property=ActiveState --property=MainPID --property=ControlGroup")
                printf 'MainPID=%s\nActiveState=%s\nControlGroup=/test.slice/claude-rc@example.service\n' "${{MAIN_PID:-1234}}" "{unit_state}"
                ;;
              "--user freeze claude-rc@example.service")
                touch "$AGENTS_AFTER_FREEZE"
                {freeze_action}
                ;;
              "--user thaw claude-rc@example.service")
                {thaw_action}
                ;;
              "--user kill --kill-whom=main --signal=SIGKILL claude-rc@example.service")
                rm -f "$PROC_ROOT/1234/exe"
                ln -s "$UPDATED_BINARY" "$PROC_ROOT/1234/exe"
                ;;
              "--user try-restart claude-rc@example.service")
                ;;
              *) exit 64 ;;
            esac
            """,
        )
        if unit_state == "active":
            process = proc / "1234"
            process.mkdir()
            (process / "exe").symlink_to(versions / (live_version or current))

        env = os.environ | {
            "HOME": str(home),
            "XDG_RUNTIME_DIR": str(root / "run"),
            "XDG_STATE_HOME": str(state),
            "CLAUDE_AUTO_UPDATE_CLAUDE_BIN": str(launcher),
            "CLAUDE_AUTO_UPDATE_SYSTEMCTL_BIN": str(systemctl),
            "CLAUDE_AUTO_UPDATE_PROC_ROOT": str(proc),
            "CLAUDE_AUTO_UPDATE_CGROUP_ROOT": str(root / "cgroup"),
            "CLAUDE_AUTO_UPDATE_TIMEOUT": "1",
            "CALLS": str(calls),
            "PROC_ROOT": str(proc),
            "UPDATED_BINARY": str(versions / updated),
            "CLAUDE_BIN": str(launcher),
            "AGENTS_AFTER_FREEZE": str(root / "agents-after-freeze"),
            "HANG_AFTER_FREEZE": str(root / "hang-after-freeze"),
        }
        pending = state / "claude-auto-update/pending-restart.json"
        return env, launcher, calls, pending

    def run_updater(self, env: dict[str, str]) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(UPDATER)],
            env=env,
            capture_output=True,
            text=True,
            check=False,
        )

    def test_native_update_defers_stale_active_remote_control_without_restart(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            env, launcher, calls, pending = self.make_environment(root)

            result = self.run_updater(env)

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(launcher.resolve().name, "2.1.266")
            self.assertEqual(
                json.loads(pending.read_text()),
                {
                    "installedVersion": "2.1.266",
                    "staleUnits": ["claude-rc@example.service"],
                },
            )
            call_log = calls.read_text()
            self.assertIn("claude update", call_log)
            self.assertNotIn("restart", call_log)
            self.assertNotIn("stop", call_log)
            self.assertIn("deferred", result.stdout)

    def test_restarts_stale_active_unit_only_when_no_agents_are_active(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            env, launcher, calls, pending = self.make_environment(root, agents=[])

            result = self.run_updater(env)

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(launcher.resolve().name, "2.1.266")
            self.assertFalse(pending.exists())
            call_log = calls.read_text()
            self.assertIn(
                "systemctl --user freeze claude-rc@example.service", call_log
            )
            self.assertIn(
                "systemctl --user kill --kill-whom=main --signal=SIGKILL claude-rc@example.service",
                call_log,
            )
            self.assertIn(
                "systemctl --user thaw claude-rc@example.service", call_log
            )
            self.assertNotIn("try-restart", call_log)
            self.assertIn("restarted", result.stdout)

    def test_frozen_cgroup_barrier_defers_when_a_hidden_child_exists(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            env, _, calls, pending = self.make_environment(
                root, agents=[], hidden_service_pids=[5678]
            )

            result = self.run_updater(env)

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(pending.exists())
            call_log = calls.read_text()
            self.assertIn("freeze claude-rc@example.service", call_log)
            self.assertIn("thaw claude-rc@example.service", call_log)
            self.assertNotIn("--signal=SIGKILL", call_log)
            self.assertIn("deferred", result.stdout)

    def test_frozen_barrier_defers_when_an_agent_appears_after_initial_snapshot(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            env, _, calls, pending = self.make_environment(
                root,
                agents=[],
                agents_after_freeze=[{"kind": "interactive", "status": "active"}],
            )

            result = self.run_updater(env)

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(pending.exists())
            self.assertEqual(calls.read_text().count("claude agents --json"), 2)
            self.assertNotIn("--signal=SIGKILL", calls.read_text())

    def test_frozen_barrier_does_not_kill_a_process_that_became_current(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            env, _, calls, pending = self.make_environment(
                root, agents=[], become_current_on_freeze=True
            )

            result = self.run_updater(env)

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(pending.exists())
            self.assertNotIn("--signal=SIGKILL", calls.read_text())

    def test_thaw_failure_raises_and_keeps_pending_marker(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            env, _, calls, pending = self.make_environment(
                root, agents=[], thaw_fails=True
            )

            result = self.run_updater(env)

            self.assertNotEqual(result.returncode, 0)
            self.assertTrue(pending.exists())
            self.assertIn("systemctl --user thaw", calls.read_text())

    def test_termination_after_freeze_thaws_unit_before_exit(self) -> None:
        for signum in (signal.SIGTERM, signal.SIGHUP):
            with self.subTest(signal=signum), tempfile.TemporaryDirectory() as temporary:
                root = pathlib.Path(temporary)
                env, _, calls, pending = self.make_environment(
                    root, agents=[], hang_after_freeze=True
                )
                process = subprocess.Popen(
                    [sys.executable, str(UPDATER)],
                    env=env,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                )
                deadline = time.monotonic() + 5
                while (
                    not calls.exists()
                    or "systemctl --user freeze claude-rc@example.service"
                    not in calls.read_text()
                ) and time.monotonic() < deadline:
                    time.sleep(0.01)
                self.assertIn("freeze claude-rc@example.service", calls.read_text())

                process.send_signal(signum)
                _, stderr = process.communicate(timeout=5)

                self.assertNotEqual(process.returncode, 0, stderr)
                self.assertIn(
                    "systemctl --user thaw claude-rc@example.service",
                    calls.read_text(),
                )
                self.assertTrue(pending.exists())

    def test_defers_restart_when_auth_is_not_ready(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            env, _, calls, pending = self.make_environment(
                root, agents=[], logged_in=False
            )

            result = self.run_updater(env)

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(pending.exists())
            self.assertNotIn("try-restart", calls.read_text())
            self.assertIn("authentication", result.stdout)
            self.assertIn("deferred", result.stdout)

    def test_concurrent_invocation_does_not_run_a_second_native_update(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            env, _, calls, _ = self.make_environment(root, update_delay=0.5)
            first = subprocess.Popen(
                [sys.executable, str(UPDATER)],
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            deadline = time.monotonic() + 2
            while (
                (not calls.exists() or "claude update" not in calls.read_text())
                and time.monotonic() < deadline
            ):
                time.sleep(0.01)

            second = self.run_updater(env)
            first_stdout, first_stderr = first.communicate(timeout=5)

            self.assertEqual(first.returncode, 0, first_stderr)
            self.assertEqual(second.returncode, 0, second.stderr)
            self.assertEqual(calls.read_text().count("claude update"), 1)
            self.assertIn("already running", first_stdout + second.stdout)

    def test_agent_sync_service_runs_claude_updater_after_codex_updater(self) -> None:
        service = (
            REPO / ".config/systemd/user/agent-sync.service"
        ).read_text().splitlines()
        codex_line = "ExecStart=%h/.local/bin/codex-auto-update"
        claude_line = "ExecStart=%h/.local/bin/claude-auto-update"
        self.assertIn(claude_line, service)
        self.assertGreater(service.index(claude_line), service.index(codex_line))

    def test_remote_control_feature_deploys_claude_updater(self) -> None:
        deployer = (REPO / "scripts/dotfiles").read_text()
        self.assertIn(".local/bin/claude-auto-update", deployer)


if __name__ == "__main__":
    unittest.main()
