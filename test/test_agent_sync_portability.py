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
CODEX_CONFIG_SYNC = REPO / ".local/libexec/codex-config-sync.py"


def load_agent_sync():
    loader = importlib.machinery.SourceFileLoader("agent_sync", str(AGENT_SYNC))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    if spec is None:
        raise RuntimeError("could not create module spec for agent-sync")
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


def load_codex_config_sync():
    loader = importlib.machinery.SourceFileLoader("codex_config_sync", str(CODEX_CONFIG_SYNC))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    if spec is None:
        raise RuntimeError("could not create module spec for codex-config-sync")
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


class AgentSyncPortabilityTests(unittest.TestCase):
    def test_codex_config_sync_enables_default_user_input_requests(self) -> None:
        codex_config_sync = load_codex_config_sync()
        with tempfile.TemporaryDirectory() as temporary:
            config = pathlib.Path(temporary) / "config.toml"
            config.write_text('[features]\nmemories = true\n\n[tui]\nstatus_line = ["model-name"]\n')

            self.assertEqual(
                codex_config_sync.sync_global_features(config),
                ["default_mode_request_user_input:true"],
            )
            rendered = config.read_text()
            self.assertIn("default_mode_request_user_input = true", rendered)
            self.assertIn('status_line = ["model-name"]', rendered)
            self.assertEqual(codex_config_sync.sync_global_features(config), [])

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

    def test_all_sync_runs_global_compat_when_no_projects_are_registered(self) -> None:
        agent_sync = load_agent_sync()
        compat_calls: list[tuple[list[str], bool]] = []

        def fake_checked(command: list[str], quiet: bool) -> None:
            compat_calls.append((command, quiet))

        with (
            mock.patch.object(agent_sync, "discover_roots", return_value=[]),
            mock.patch.object(agent_sync, "run_checked", side_effect=fake_checked),
            mock.patch.object(agent_sync.sys, "argv", ["agent-sync", "--all", "--no-restart", "--quiet"]),
        ):
            self.assertEqual(agent_sync.main(), 0)

        self.assertEqual(len(compat_calls), 1)
        self.assertIn("--compat-only", compat_calls[0][0])

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
            REPO / ".local/bin/codex",
            REPO / ".local/bin/codex-rc",
            REPO / ".local/bin/codex-config-sync",
            REPO / ".local/libexec/codex-config-sync.py",
            REPO / ".local/libexec/codex-rc-cleanup",
            REPO / ".config/systemd/user/agent-sync.service",
            REPO / ".config/systemd/user/agent-sync.timer",
            REPO / ".config/systemd/user/claude-rc@.service",
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

    def test_installers_keep_mutable_runtime_files_outside_git_checkout(self) -> None:
        installer = (REPO / "install_environment.sh").read_text()
        self.assertNotIn('link_file "$DOTFILES_DIR/.zshrc" ~/.zshrc', installer)
        self.assertNotIn('link_file "$DOTFILES_DIR/.gitconfig" ~/.gitconfig', installer)
        self.assertNotIn(
            'link_file "$DOTFILES_DIR/.claude/global-learned-insights.md" ~/.claude/global-learned-insights.md',
            installer,
        )
        self.assertIn("install_shell_wrapper", installer)
        self.assertIn("install_git_wrapper", installer)
        self.assertIn("seed_runtime_file", installer)

        windows = (REPO / "scripts/install-claude-windows.ps1").read_text()
        self.assertNotIn(
            'Copy-File "$ClaudeSrc\\global-learned-insights.md" "$ClaudeDest\\global-learned-insights.md"',
            windows,
        )
        self.assertIn("Seed-File", windows)
        self.assertIn('Test-Path "$ClaudeSrc\\settings.local.json"', windows)
        self.assertIn("PSObject.Properties['permissions']", windows)

    def test_windows_updater_is_fail_closed_and_runs_agent_sync(self) -> None:
        updater = (REPO / "scripts/dotfiles-update-windows.ps1").read_text()
        sync = (REPO / "scripts/sync-agent-config-windows.ps1").read_text()
        self.assertIn("merge-base --is-ancestor", updater)
        self.assertIn("upstream changes overlap host-local changes", updater)
        self.assertIn("merge --ff-only", updater)
        self.assertIn("sync-agent-config-windows.ps1", updater)
        self.assertIn("install-claude-windows.ps1", sync)
        self.assertIn("ruler apply", sync)
        self.assertIn("codex-config-sync.py", sync)
        self.assertIn("uv.Source venv", sync)
        self.assertIn("uv.Source pip install", sync)
        self.assertNotIn("hermes\\hermes-agent\\venv", sync)
        self.assertIn(".agents\\skills", sync)
        self.assertNotIn("Restart", sync)

        installer = (REPO / "scripts/install-agent-sync-windows.ps1").read_text()
        launcher = (REPO / "scripts/run-agent-sync-hidden.vbs").read_text()
        self.assertIn("[System.Security.Principal.WindowsIdentity]::GetCurrent().Name", installer)
        self.assertIn("wscript.exe", installer)
        self.assertIn("run-agent-sync-hidden.vbs", installer)
        self.assertIn("//B //NoLogo", installer)
        self.assertNotIn("New-ScheduledTaskAction -Execute $powerShell", installer)
        self.assertIn("shell.Run(command, 0, True)", launcher)
        self.assertIn("WScript.Quit exitCode", launcher)
        self.assertIn("DotfilesAgentSync", installer)
        self.assertIn("New-TimeSpan -Minutes 5", installer)
        self.assertIn("StartWhenAvailable", installer)

    def test_systemd_sync_entrypoints_discover_registered_projects(self) -> None:
        agent_service = (REPO / ".config/systemd/user/agent-sync.service").read_text()
        codex_service = (REPO / ".config/systemd/user/codex-app-server.service").read_text()
        updater_service = (REPO / ".config/systemd/user/dotfiles-update.service").read_text()
        updater_timer = (REPO / ".config/systemd/user/dotfiles-update.timer").read_text()
        self.assertNotIn("WorkingDirectory=", agent_service)
        self.assertIn("agent-sync --all --no-restart --quiet", agent_service)
        self.assertIn("codex-config-sync --compat-only --quiet", codex_service)
        self.assertNotIn("agent-sync --all", codex_service)
        self.assertIn("%h/.local/bin/dotfiles-update", updater_service)
        self.assertIn("OnBootSec=2min", updater_timer)
        self.assertIn("OnUnitActiveSec=5min", updater_timer)

    def test_remote_control_feature_manages_dotfiles_updater_assets(self) -> None:
        deployer = (REPO / "scripts/dotfiles").read_text()
        for path in (
            ".config/systemd/user/dotfiles-update.service",
            ".config/systemd/user/dotfiles-update.timer",
            ".local/bin/dotfiles-update",
        ):
            self.assertIn(path, deployer)

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

    def test_dotfiles_update_fast_forwards_and_preserves_non_overlapping_changes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            remote = root / "remote.git"
            source = root / "source"
            home = root / "home"
            checkout = home / ".dot_files"
            subprocess.run(["git", "init", "--bare", "-q", str(remote)], check=True)
            subprocess.run(["git", "clone", "-q", str(remote), str(source)], check=True)
            subprocess.run(["git", "-C", str(source), "config", "user.name", "Test"], check=True)
            subprocess.run(["git", "-C", str(source), "config", "user.email", "test@example.com"], check=True)
            (source / "shared.txt").write_text("one\n")
            (source / "local.txt").write_text("base\n")
            subprocess.run(["git", "-C", str(source), "add", "."], check=True)
            subprocess.run(["git", "-C", str(source), "commit", "-qm", "initial"], check=True)
            subprocess.run(["git", "-C", str(source), "push", "-qu", "origin", "HEAD:main"], check=True)
            subprocess.run(["git", "--git-dir", str(remote), "symbolic-ref", "HEAD", "refs/heads/main"], check=True)
            subprocess.run(["git", "clone", "-q", str(remote), str(checkout)], check=True)
            (checkout / "local.txt").write_text("host-only\n")
            (source / "shared.txt").write_text("two\n")
            subprocess.run(["git", "-C", str(source), "commit", "-qam", "update shared"], check=True)
            subprocess.run(["git", "-C", str(source), "push", "-q"], check=True)

            result = subprocess.run(
                [str(REPO / ".local/bin/dotfiles-update")],
                env=os.environ | {"HOME": str(home), "DOTFILES_DIR": str(checkout)},
                capture_output=True,
                text=True,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((checkout / "shared.txt").read_text(), "two\n")
            self.assertEqual((checkout / "local.txt").read_text(), "host-only\n")
            self.assertIn("local.txt", subprocess.check_output(["git", "-C", str(checkout), "status", "--short"], text=True))

    def test_dotfiles_update_refuses_overlapping_dirty_change(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            remote = root / "remote.git"
            source = root / "source"
            home = root / "home"
            checkout = home / ".dot_files"
            subprocess.run(["git", "init", "--bare", "-q", str(remote)], check=True)
            subprocess.run(["git", "clone", "-q", str(remote), str(source)], check=True)
            subprocess.run(["git", "-C", str(source), "config", "user.name", "Test"], check=True)
            subprocess.run(["git", "-C", str(source), "config", "user.email", "test@example.com"], check=True)
            (source / "shared.txt").write_text("base\n")
            subprocess.run(["git", "-C", str(source), "add", "."], check=True)
            subprocess.run(["git", "-C", str(source), "commit", "-qm", "initial"], check=True)
            subprocess.run(["git", "-C", str(source), "push", "-qu", "origin", "HEAD:main"], check=True)
            subprocess.run(["git", "--git-dir", str(remote), "symbolic-ref", "HEAD", "refs/heads/main"], check=True)
            subprocess.run(["git", "clone", "-q", str(remote), str(checkout)], check=True)
            old_head = subprocess.check_output(["git", "-C", str(checkout), "rev-parse", "HEAD"], text=True).strip()
            (checkout / "shared.txt").write_text("host-only\n")
            (source / "shared.txt").write_text("upstream\n")
            subprocess.run(["git", "-C", str(source), "commit", "-qam", "update shared"], check=True)
            subprocess.run(["git", "-C", str(source), "push", "-q"], check=True)

            result = subprocess.run(
                [str(REPO / ".local/bin/dotfiles-update")],
                env=os.environ | {"HOME": str(home), "DOTFILES_DIR": str(checkout)},
                capture_output=True,
                text=True,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertEqual((checkout / "shared.txt").read_text(), "host-only\n")
            self.assertEqual(
                subprocess.check_output(["git", "-C", str(checkout), "rev-parse", "HEAD"], text=True).strip(),
                old_head,
            )

    def test_dotfiles_update_refuses_divergent_local_commits(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            remote = root / "remote.git"
            source = root / "source"
            home = root / "home"
            checkout = home / ".dot_files"
            subprocess.run(["git", "init", "--bare", "-q", str(remote)], check=True)
            subprocess.run(["git", "clone", "-q", str(remote), str(source)], check=True)
            for repository in (source,):
                subprocess.run(["git", "-C", str(repository), "config", "user.name", "Test"], check=True)
                subprocess.run(["git", "-C", str(repository), "config", "user.email", "test@example.com"], check=True)
            (source / "shared.txt").write_text("base\n")
            subprocess.run(["git", "-C", str(source), "add", "."], check=True)
            subprocess.run(["git", "-C", str(source), "commit", "-qm", "initial"], check=True)
            subprocess.run(["git", "-C", str(source), "push", "-qu", "origin", "HEAD:main"], check=True)
            subprocess.run(["git", "--git-dir", str(remote), "symbolic-ref", "HEAD", "refs/heads/main"], check=True)
            subprocess.run(["git", "clone", "-q", str(remote), str(checkout)], check=True)
            subprocess.run(["git", "-C", str(checkout), "config", "user.name", "Test"], check=True)
            subprocess.run(["git", "-C", str(checkout), "config", "user.email", "test@example.com"], check=True)
            (checkout / "local-commit.txt").write_text("local\n")
            subprocess.run(["git", "-C", str(checkout), "add", "."], check=True)
            subprocess.run(["git", "-C", str(checkout), "commit", "-qm", "local"], check=True)
            (source / "upstream.txt").write_text("upstream\n")
            subprocess.run(["git", "-C", str(source), "add", "."], check=True)
            subprocess.run(["git", "-C", str(source), "commit", "-qm", "upstream"], check=True)
            subprocess.run(["git", "-C", str(source), "push", "-q"], check=True)
            old_head = subprocess.check_output(["git", "-C", str(checkout), "rev-parse", "HEAD"], text=True).strip()

            result = subprocess.run(
                [str(REPO / ".local/bin/dotfiles-update")],
                env=os.environ | {"HOME": str(home), "DOTFILES_DIR": str(checkout)},
                capture_output=True,
                text=True,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(
                subprocess.check_output(["git", "-C", str(checkout), "rev-parse", "HEAD"], text=True).strip(),
                old_head,
            )

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
            self.assertIn("Status: 0 linked, 0 issues, 0 missing", without_feature.stdout)

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
            self.assertIn("Status: 0 linked, 0 issues, 1 missing", with_feature.stdout)

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
                [
                    "--user daemon-reload",
                    "--user enable --now agent-sync.timer dotfiles-update.timer",
                    "--user daemon-reload",
                    "--user enable --now agent-sync.timer dotfiles-update.timer",
                ],
            )
            self.assertNotIn("restart", systemctl_log.read_text())

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
