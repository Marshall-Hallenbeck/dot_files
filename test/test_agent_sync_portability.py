#!/usr/bin/env python3
from __future__ import annotations

import importlib.machinery
import importlib.util
import os
import pathlib
import subprocess
import tempfile
import types
import unittest
from unittest import mock

REPO = pathlib.Path(__file__).resolve().parents[1]
AGENT_SYNC = REPO / ".local/bin/agent-sync"


def load_agent_sync():
    loader = importlib.machinery.SourceFileLoader("agent_sync", str(AGENT_SYNC))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    if spec is None:
        raise RuntimeError("could not create module spec for agent-sync")
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


class AgentSyncPortabilityTests(unittest.TestCase):
    def test_aggregate_return_code_preserves_failures_and_signals(self) -> None:
        agent_sync = load_agent_sync()
        self.assertEqual(agent_sync.aggregate_return_code(0, 3), 3)
        self.assertEqual(agent_sync.aggregate_return_code(0, -9), 137)
        self.assertEqual(agent_sync.aggregate_return_code(3, 0), 3)
        self.assertEqual(agent_sync.aggregate_return_code(3, 5), 3)

    def test_all_sync_runs_global_compat_once_before_project_children(self) -> None:
        agent_sync = load_agent_sync()
        roots = [pathlib.Path("/projects/a"), pathlib.Path("/projects/b")]
        compat_calls: list[tuple[list[str], bool]] = []
        child_commands: list[list[str]] = []

        def fake_checked(command: list[str], quiet: bool) -> None:
            compat_calls.append((command, quiet))

        def fake_run(command, *args, **kwargs):
            child_commands.append(list(command))
            return types.SimpleNamespace(returncode=0)

        with (
            mock.patch.object(agent_sync, "discover_roots", return_value=roots),
            mock.patch.object(agent_sync, "run_checked", side_effect=fake_checked),
            mock.patch.object(agent_sync.subprocess, "run", side_effect=fake_run),
            mock.patch.object(agent_sync.sys, "argv", ["agent-sync", "--all", "--no-restart", "--quiet"]),
        ):
            self.assertEqual(agent_sync.main(), 0)

        self.assertEqual(len(compat_calls), 1)
        self.assertIn("--compat-only", compat_calls[0][0])
        self.assertEqual(len(child_commands), 2)
        for command in child_commands:
            self.assertIn("--skip-compat", command)
            self.assertIn("--no-restart", command)

    def test_discover_roots_only_returns_unique_ruler_projects(self) -> None:
        agent_sync = load_agent_sync()
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            projects = root / "projects"
            projects.mkdir()

            ruler_project = root / "ruler-project"
            (ruler_project / ".ruler").mkdir(parents=True)
            (ruler_project / ".ruler/ruler.toml").write_text("[agents]\n")
            plain_project = root / "plain-project"
            plain_project.mkdir()

            (projects / "alpha").symlink_to(ruler_project, target_is_directory=True)
            (projects / "alpha-alias").symlink_to(ruler_project, target_is_directory=True)
            (projects / "plain").symlink_to(plain_project, target_is_directory=True)
            (projects / "broken").symlink_to(root / "missing", target_is_directory=True)

            self.assertEqual(agent_sync.discover_roots(projects), [ruler_project.resolve()])

    def test_claude_units_for_root_matches_all_project_aliases_without_fixed_names(self) -> None:
        agent_sync = load_agent_sync()
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            projects = root / "projects"
            projects.mkdir()
            target = root / "target"
            target.mkdir()
            other = root / "other"
            other.mkdir()
            (projects / "fabius").symlink_to(target, target_is_directory=True)
            (projects / "research env").symlink_to(target, target_is_directory=True)
            (projects / "-dash").symlink_to(target, target_is_directory=True)
            (projects / "other").symlink_to(other, target_is_directory=True)

            units = agent_sync.claude_units_for_root(
                target,
                projects_dir=projects,
                active=lambda unit: not unit.startswith("claude-rc@other"),
            )

            self.assertEqual(
                units,
                [
                    "claude-rc@\\x2ddash.service",
                    "claude-rc@fabius.service",
                    "claude-rc@research\\x20env.service",
                ],
            )

    def test_runtime_assets_have_no_user_or_project_specific_paths(self) -> None:
        runtime_assets = [
            REPO / ".local/bin/agent-sync",
            REPO / ".local/bin/claude-rc",
            REPO / ".local/bin/codex-rc",
            REPO / ".local/bin/codex-config-sync",
            REPO / ".local/libexec/codex-config-sync.py",
            REPO / ".config/systemd/user/agent-sync.service",
            REPO / ".config/systemd/user/codex-app-server.service",
            REPO / ".claude/skills/claude-remote-control-service/SKILL.md",
            REPO / ".claude/commands/preflight.md",
            REPO / ".zshrc",
        ]
        forbidden = (
            "turins_tavern",
            "turins-tavern",
            "fabius",
            "cawl-dev",
            "/home/marshall",
            "/home/kali",
            "192.168.8.",
        )
        violations: list[str] = []
        for path in runtime_assets:
            text = path.read_text()
            for value in forbidden:
                if value in text:
                    violations.append(f"{path.relative_to(REPO)} contains {value}")
        self.assertEqual(violations, [])

    def test_systemd_sync_entrypoints_discover_registered_projects(self) -> None:
        agent_service = (REPO / ".config/systemd/user/agent-sync.service").read_text()
        codex_service = (REPO / ".config/systemd/user/codex-app-server.service").read_text()
        self.assertNotIn("WorkingDirectory=", agent_service)
        self.assertIn("agent-sync --all --no-restart --quiet", agent_service)
        self.assertIn("codex-config-sync --compat-only --quiet", codex_service)
        self.assertNotIn("agent-sync --all", codex_service)

    def test_feature_enable_provisions_pinned_codex_sync_dependency(self) -> None:
        deployer = (REPO / "scripts/dotfiles").read_text()
        wrapper = (REPO / ".local/bin/codex-config-sync").read_text()
        self.assertIn("tomlkit==0.13.3", deployer)
        self.assertIn("codex-config-sync-venv/bin/python", wrapper)

    def test_codex_config_sync_wrapper_uses_managed_interpreter(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            home = pathlib.Path(temporary)
            libexec = home / ".local/libexec/codex-config-sync.py"
            libexec.parent.mkdir(parents=True)
            libexec.write_text("# implementation placeholder\n")
            fake_python = home / "managed-python"
            log = home / "python.log"
            fake_python.write_text("#!/usr/bin/env bash\nprintf '%s\\n' \"$*\" > \"$PYTHON_LOG\"\n")
            fake_python.chmod(0o755)
            env = os.environ | {
                "HOME": str(home),
                "CODEX_CONFIG_SYNC_PYTHON": str(fake_python),
                "PYTHON_LOG": str(log),
            }

            result = subprocess.run(
                [str(REPO / ".local/bin/codex-config-sync"), "--compat-only", "--quiet"],
                env=env,
                capture_output=True,
                text=True,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                log.read_text().strip(),
                f"{libexec} --compat-only --quiet",
            )

    def test_claude_rc_sync_resolves_named_project_link(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            home = pathlib.Path(temporary)
            root = home / "src/project"
            root.mkdir(parents=True)
            projects = home / ".config/claude-rc/projects"
            projects.mkdir(parents=True)
            (projects / "alpha").symlink_to(root, target_is_directory=True)
            log = home / "sync.log"
            helper = home / ".local/bin/agent-sync"
            helper.parent.mkdir(parents=True)
            helper.write_text("#!/usr/bin/env bash\nprintf '%s\\n' \"$*\" > \"$SYNC_LOG\"\n")
            helper.chmod(0o755)
            env = os.environ | {"HOME": str(home), "SYNC_LOG": str(log)}

            result = subprocess.run(
                [str(REPO / ".local/bin/claude-rc"), "sync-status", "alpha"],
                env=env,
                capture_output=True,
                text=True,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(log.read_text().strip(), f"status --root {root}")

    def test_codex_rc_sync_accepts_explicit_root(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            home = pathlib.Path(temporary)
            root = home / "src/project"
            root.mkdir(parents=True)
            log = home / "sync.log"
            helper = home / ".local/bin/agent-sync"
            helper.parent.mkdir(parents=True)
            helper.write_text("#!/usr/bin/env bash\nprintf '%s\\n' \"$*\" > \"$SYNC_LOG\"\n")
            helper.chmod(0o755)
            env = os.environ | {"HOME": str(home), "SYNC_LOG": str(log)}

            result = subprocess.run(
                [str(REPO / ".local/bin/codex-rc"), "sync-status", str(root)],
                env=env,
                capture_output=True,
                text=True,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(log.read_text().strip(), f"status --root {root}")

    def test_codex_rc_prefers_registered_name_over_relative_directory(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            home = pathlib.Path(temporary)
            registered_root = home / "registered"
            registered_root.mkdir()
            projects = home / ".config/claude-rc/projects"
            projects.mkdir(parents=True)
            (projects / "alpha").symlink_to(registered_root, target_is_directory=True)

            cwd = home / "work"
            cwd.mkdir()
            (cwd / "alpha").mkdir()
            log = home / "sync.log"
            helper = home / ".local/bin/agent-sync"
            helper.parent.mkdir(parents=True)
            helper.write_text("#!/usr/bin/env bash\nprintf '%s\\n' \"$*\" > \"$SYNC_LOG\"\n")
            helper.chmod(0o755)
            env = os.environ | {"HOME": str(home), "SYNC_LOG": str(log)}

            result = subprocess.run(
                [str(REPO / ".local/bin/codex-rc"), "sync-status", "alpha"],
                cwd=cwd,
                env=env,
                capture_output=True,
                text=True,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(log.read_text().strip(), f"status --root {registered_root}")

    def test_dotfiles_status_only_requires_opted_in_remote_control_assets(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            home = pathlib.Path(temporary)
            dotfiles = home / ".dot_files"
            (dotfiles / ".local/bin").mkdir(parents=True)
            (dotfiles / ".zshrc").write_text("# shared\n")
            (dotfiles / ".local/bin/agent-sync").write_text("#!/usr/bin/env python3\n")
            subprocess.run(["git", "init", "-q", str(dotfiles)], check=True)
            subprocess.run(["git", "-C", str(dotfiles), "add", "."], check=True)
            env = os.environ | {"HOME": str(home)}

            without_feature = subprocess.run(
                [str(REPO / "scripts/dotfiles"), "status"],
                env=env,
                capture_output=True,
                text=True,
                check=True,
            )
            self.assertNotIn(str(home / ".local/bin/agent-sync"), without_feature.stdout)
            self.assertIn("Status: 0 linked, 0 issues, 1 missing", without_feature.stdout)

            marker = home / ".config/dotfiles/features/ai-remote-control"
            marker.parent.mkdir(parents=True)
            marker.touch()
            with_feature = subprocess.run(
                [str(REPO / "scripts/dotfiles"), "status"],
                env=env,
                capture_output=True,
                text=True,
                check=True,
            )
            self.assertIn(str(home / ".local/bin/agent-sync"), with_feature.stdout)
            self.assertIn("Status: 0 linked, 0 issues, 2 missing", with_feature.stdout)

    def test_feature_enable_links_and_reloads_without_restarting_services(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            home = pathlib.Path(temporary)
            dotfiles = home / ".dot_files"
            source_script = dotfiles / ".local/bin/agent-sync"
            source_unit = dotfiles / ".config/systemd/user/agent-sync.service"
            source_script.parent.mkdir(parents=True)
            source_unit.parent.mkdir(parents=True)
            source_script.write_text("#!/usr/bin/env python3\n")
            source_unit.write_text("[Service]\nType=oneshot\n")

            target_unit = home / ".config/systemd/user/agent-sync.service"
            target_unit.parent.mkdir(parents=True)
            target_unit.write_text("legacy unit\n")
            target_script = home / ".local/bin/agent-sync"
            target_script.mkdir(parents=True)
            (target_script / "legacy.txt").write_text("legacy directory\n")

            fake_bin = home / "fake-bin"
            fake_bin.mkdir()
            systemctl_log = home / "systemctl.log"
            fake_systemctl = fake_bin / "systemctl"
            fake_systemctl.write_text("#!/usr/bin/env bash\nprintf '%s\\n' \"$*\" >> \"$SYSTEMCTL_LOG\"\n")
            fake_systemctl.chmod(0o755)
            fake_date = fake_bin / "date"
            fake_date.write_text("#!/usr/bin/env bash\nprintf '20260727-120000\\n'\n")
            fake_date.chmod(0o755)
            env = os.environ | {
                "HOME": str(home),
                "PATH": f"{fake_bin}:{os.environ['PATH']}",
                "SYSTEMCTL_LOG": str(systemctl_log),
            }

            result = subprocess.run(
                [str(REPO / "scripts/dotfiles"), "feature-enable", "ai-remote-control"],
                env=env,
                capture_output=True,
                text=True,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            target_unit.unlink()
            target_unit.write_text("second legacy unit\n")
            second_result = subprocess.run(
                [str(REPO / "scripts/dotfiles"), "feature-enable", "ai-remote-control"],
                env=env,
                capture_output=True,
                text=True,
            )
            self.assertEqual(second_result.returncode, 0, second_result.stderr)

            self.assertTrue((home / ".local/bin/agent-sync").is_symlink())
            self.assertTrue(target_unit.is_symlink())
            self.assertEqual(target_unit.resolve(), source_unit.resolve())
            self.assertTrue((home / ".config/dotfiles/features/ai-remote-control").is_file())
            backups = list(home.glob(".dotfiles-backup-ai-remote-control-*/.config/systemd/user/agent-sync.service"))
            self.assertEqual(len(backups), 2)
            self.assertEqual(
                sorted(path.read_text() for path in backups),
                ["legacy unit\n", "second legacy unit\n"],
            )
            directory_backups = list(home.glob(".dotfiles-backup-ai-remote-control-*/.local/bin/agent-sync/legacy.txt"))
            self.assertEqual(len(directory_backups), 1)
            self.assertEqual(directory_backups[0].read_text(), "legacy directory\n")
            self.assertEqual(
                systemctl_log.read_text().splitlines(),
                ["--user daemon-reload", "--user daemon-reload"],
            )
            self.assertNotIn("restart", systemctl_log.read_text())
            self.assertNotIn("enable", systemctl_log.read_text())

    def test_feature_enable_validates_managed_python_before_changes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            home = pathlib.Path(temporary)
            wrapper = home / ".dot_files/.local/bin/codex-config-sync"
            implementation = home / ".dot_files/.local/libexec/codex-config-sync.py"
            wrapper.parent.mkdir(parents=True)
            implementation.parent.mkdir(parents=True)
            wrapper.write_text("#!/usr/bin/env bash\n")
            implementation.write_text("# implementation\n")
            target = home / ".local/bin/codex-config-sync"
            target.parent.mkdir(parents=True)
            target.write_text("legacy wrapper\n")
            env = os.environ | {
                "HOME": str(home),
                "CODEX_CONFIG_SYNC_PYTHON": str(home / "missing-python"),
            }

            result = subprocess.run(
                [str(REPO / "scripts/dotfiles"), "feature-enable", "ai-remote-control"],
                env=env,
                capture_output=True,
                text=True,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(target.read_text(), "legacy wrapper\n")
            self.assertFalse((home / ".config/dotfiles/features/ai-remote-control").exists())

    def test_feature_enable_backs_up_conflicting_parent_paths(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            home = pathlib.Path(temporary)
            source = home / ".dot_files/.local/bin/agent-sync"
            source.parent.mkdir(parents=True)
            source.write_text("#!/usr/bin/env python3\n")
            (home / ".local").write_text("legacy parent\n")

            fake_bin = home / "fake-bin"
            fake_bin.mkdir()
            fake_systemctl = fake_bin / "systemctl"
            fake_systemctl.write_text("#!/usr/bin/env bash\nexit 0\n")
            fake_systemctl.chmod(0o755)
            env = os.environ | {"HOME": str(home), "PATH": f"{fake_bin}:{os.environ['PATH']}"}

            result = subprocess.run(
                [str(REPO / "scripts/dotfiles"), "feature-enable", "ai-remote-control"],
                env=env,
                capture_output=True,
                text=True,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue((home / ".local/bin/agent-sync").is_symlink())
            backups = list(home.glob(".dotfiles-backup-ai-remote-control-*/.local"))
            self.assertEqual(len(backups), 1)
            self.assertEqual(backups[0].read_text(), "legacy parent\n")

    def test_feature_enable_backs_up_symlinked_parent_directories(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            home = pathlib.Path(temporary)
            source = home / ".dot_files/.local/bin/agent-sync"
            source.parent.mkdir(parents=True)
            source.write_text("#!/usr/bin/env python3\n")
            outside = home / "outside"
            outside.mkdir()
            sentinel = outside / "sentinel"
            sentinel.write_text("untouched\n")
            (home / ".local").symlink_to(outside, target_is_directory=True)

            fake_bin = home / "fake-bin"
            fake_bin.mkdir()
            fake_systemctl = fake_bin / "systemctl"
            fake_systemctl.write_text("#!/usr/bin/env bash\nexit 0\n")
            fake_systemctl.chmod(0o755)
            env = os.environ | {"HOME": str(home), "PATH": f"{fake_bin}:{os.environ['PATH']}"}

            result = subprocess.run(
                [str(REPO / "scripts/dotfiles"), "feature-enable", "ai-remote-control"],
                env=env,
                capture_output=True,
                text=True,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse((home / ".local").is_symlink())
            self.assertTrue((home / ".local/bin/agent-sync").is_symlink())
            self.assertEqual(sentinel.read_text(), "untouched\n")
            self.assertFalse((outside / "bin/agent-sync").exists())
            backups = list(home.glob(".dotfiles-backup-ai-remote-control-*/.local"))
            self.assertEqual(len(backups), 1)
            self.assertTrue(backups[0].is_symlink())
            self.assertEqual(backups[0].resolve(), outside.resolve())


if __name__ == "__main__":
    unittest.main()
