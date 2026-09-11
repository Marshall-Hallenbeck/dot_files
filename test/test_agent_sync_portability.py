#!/usr/bin/env python3
from __future__ import annotations

import importlib.machinery
import importlib.util
import os
import pathlib
import subprocess
import sys
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
    def test_agent_sync_uses_tomlkit_when_stdlib_tomllib_is_unavailable(self) -> None:
        code = r'''
import builtins
import runpy
import sys

real_import = builtins.__import__


def import_without_tomllib(name, *args, **kwargs):
    if name == "tomllib":
        raise ModuleNotFoundError("No module named 'tomllib'", name="tomllib")
    return real_import(name, *args, **kwargs)


builtins.__import__ = import_without_tomllib
module = runpy.run_path(sys.argv[1], run_name="agent_sync_fallback")
parsed = module["tomllib"].loads('[instructions]\nclaude = ".claude/global-CLAUDE.md"\n')
assert type(parsed) is dict
assert parsed == {"instructions": {"claude": ".claude/global-CLAUDE.md"}}
print("tomlkit_fallback=plain-dict")
'''
        result = subprocess.run(
            [sys.executable, "-c", code, str(AGENT_SYNC)],
            capture_output=True,
            text=True,
            check=False,
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("tomlkit_fallback=plain-dict", result.stdout)

    def test_codex_config_sync_enables_managed_global_settings(self) -> None:
        codex_config_sync = load_codex_config_sync()
        with tempfile.TemporaryDirectory() as temporary:
            config = pathlib.Path(temporary) / "config.toml"
            config.write_text(
                '[features]\nmemories = true\n\n'
                '[sandbox_workspace_write]\n'
                'writable_roots = ["/var/tmp/existing"]\n\n'
                '[tui]\nstatus_line = ["model-name"]\n'
            )

            self.assertEqual(
                codex_config_sync.sync_global_settings(config),
                ["default_mode_request_user_input:true", "writable_root:/tmp"],
            )
            rendered = config.read_text()
            self.assertIn("default_mode_request_user_input = true", rendered)
            self.assertIn('writable_roots = ["/var/tmp/existing", "/tmp"]', rendered)
            self.assertIn('status_line = ["model-name"]', rendered)
            self.assertEqual(rendered.count('"/tmp"'), 1)
            self.assertEqual(codex_config_sync.sync_global_settings(config), [])

    def test_codex_config_sync_preserves_writable_root_array_comments(self) -> None:
        codex_config_sync = load_codex_config_sync()
        with tempfile.TemporaryDirectory() as temporary:
            config = pathlib.Path(temporary) / "config.toml"
            config.write_text(
                '[features]\ndefault_mode_request_user_input = true\n\n'
                '[sandbox_workspace_write]\n'
                'writable_roots = [\n'
                '    "/var/tmp/existing", # keep this root\n'
                ']\n'
            )

            self.assertEqual(
                codex_config_sync.sync_global_settings(config),
                ["writable_root:/tmp"],
            )

            rendered = config.read_text()
            self.assertIn('# keep this root', rendered)
            self.assertIn('    "/var/tmp/existing",', rendered)
            self.assertIn('    "/tmp",', rendered)

    def test_codex_config_sync_rejects_scalar_writable_roots(self) -> None:
        codex_config_sync = load_codex_config_sync()
        with tempfile.TemporaryDirectory() as temporary:
            config = pathlib.Path(temporary) / "config.toml"
            config.write_text(
                '[sandbox_workspace_write]\nwritable_roots = "/var/tmp/existing"\n'
            )

            with self.assertRaisesRegex(
                RuntimeError,
                r"sandbox_workspace_write\.writable_roots must be an array of strings",
            ):
                codex_config_sync.sync_global_settings(config)

    def test_codex_config_sync_rejects_non_string_writable_root(self) -> None:
        codex_config_sync = load_codex_config_sync()
        with tempfile.TemporaryDirectory() as temporary:
            config = pathlib.Path(temporary) / "config.toml"
            config.write_text(
                '[sandbox_workspace_write]\nwritable_roots = ["/tmp", 42]\n'
            )

            with self.assertRaisesRegex(
                RuntimeError,
                r"sandbox_workspace_write\.writable_roots must be an array of strings",
            ):
                codex_config_sync.sync_global_settings(config)

    def test_codex_config_sync_creates_writable_roots_on_first_run(self) -> None:
        codex_config_sync = load_codex_config_sync()
        with tempfile.TemporaryDirectory() as temporary:
            config = pathlib.Path(temporary) / "config.toml"

            self.assertEqual(
                codex_config_sync.sync_global_settings(config),
                ["default_mode_request_user_input:true", "writable_root:/tmp"],
            )
            self.assertIn(
                '[sandbox_workspace_write]\nwritable_roots = ["/tmp"]',
                config.read_text(),
            )

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

            self.assertEqual(
                agent_sync.discover_roots(
                    projects,
                    global_root=root / "missing-dotfiles",
                ),
                [ruler_project.resolve()],
            )

    def test_discover_roots_includes_global_dotfiles_without_registered_projects(self) -> None:
        agent_sync = load_agent_sync()
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            dotfiles = root / ".dot_files"
            (dotfiles / ".ruler").mkdir(parents=True)
            (dotfiles / ".ruler/ruler.toml").write_text("[agents]\n")

            self.assertEqual(
                agent_sync.discover_roots(
                    root / "missing-projects",
                    global_root=dotfiles,
                ),
                [dotfiles.resolve()],
            )

    def test_sync_skills_never_mirrors_a_community_skill_onto_itself(self) -> None:
        codex_config_sync = load_codex_config_sync()
        with tempfile.TemporaryDirectory() as temporary:
            home = pathlib.Path(temporary)
            claude_skills = home / ".claude/skills"
            agents_skills = home / ".agents/skills"
            claude_skills.mkdir(parents=True)
            agents_skills.mkdir(parents=True)

            # A community skill: real content under ~/.agents/skills, linked
            # into ~/.claude/skills so Claude can load it.
            community = agents_skills / "windows-protocols"
            community.mkdir()
            (community / "SKILL.md").write_text("# community skill\n")
            (claude_skills / "windows-protocols").symlink_to(community, target_is_directory=True)

            # An ordinary dotfiles skill, which must still be mirrored.
            (claude_skills / "commit").mkdir()
            (claude_skills / "commit/SKILL.md").write_text("# commit\n")

            with mock.patch.object(codex_config_sync, "HOME", home):
                # "windows-protocols" is in previous_managed, so the removal
                # pass would delete the installed copy if it were not excluded.
                names, changed = codex_config_sync.sync_skills({"windows-protocols"})

            self.assertEqual(names, ["commit"])
            self.assertNotIn("removed:windows-protocols", changed)
            self.assertTrue(community.is_dir())
            self.assertFalse(community.is_symlink())
            self.assertEqual((community / "SKILL.md").read_text(), "# community skill\n")
            self.assertTrue((claude_skills / "windows-protocols/SKILL.md").is_file())

    def test_instruction_paths_default_to_ruler_outputs_without_a_sync_config(self) -> None:
        agent_sync = load_agent_sync()
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            (root / ".ruler").mkdir()
            (root / ".ruler/ruler.toml").write_text(
                '[agents.codex]\noutput_path = ".ai-config/AGENTS.shared.md"\n'
            )

            paths = agent_sync.instruction_paths(root)

            # Claude has no override, so Ruler writes its final file directly.
            self.assertEqual(paths["claude"]["shared"], root / "CLAUDE.md")
            self.assertEqual(paths["claude"]["output"], root / "CLAUDE.md")
            # Codex keeps the shared/final split the overlay composition needs.
            self.assertEqual(paths["codex"]["shared"], root / ".ai-config/AGENTS.shared.md")
            self.assertEqual(paths["codex"]["output"], root / "AGENTS.md")

    def test_instruction_paths_publish_into_the_files_named_by_the_sync_config(self) -> None:
        agent_sync = load_agent_sync()
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            (root / ".ruler").mkdir()
            (root / ".ruler/ruler.toml").write_text(
                '[agents.claude]\noutput_path = ".ai-config/CLAUDE.shared.md"\n'
                '[agents.codex]\noutput_path = ".ai-config/AGENTS.shared.md"\n'
            )
            (root / ".ai-config").mkdir()
            (root / ".ai-config/agent-sync.toml").write_text(
                '[instructions]\nclaude = ".claude/global-CLAUDE.md"\n'
                'codex = ".codex/AGENTS.md"\n'
            )

            paths = agent_sync.instruction_paths(root)

            self.assertEqual(paths["claude"]["shared"], root / ".ai-config/CLAUDE.shared.md")
            self.assertEqual(paths["claude"]["output"], root / ".claude/global-CLAUDE.md")
            self.assertEqual(paths["codex"]["shared"], root / ".ai-config/AGENTS.shared.md")
            self.assertEqual(paths["codex"]["output"], root / ".codex/AGENTS.md")
            self.assertEqual(
                agent_sync.output_paths(root)["claude-instructions"],
                root / ".claude/global-CLAUDE.md",
            )

    def test_build_instructions_composes_every_tool_that_has_an_overlay(self) -> None:
        agent_sync = load_agent_sync()
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            (root / ".ruler").mkdir()
            (root / ".ruler/ruler.toml").write_text(
                '[agents.claude]\noutput_path = ".ai-config/CLAUDE.shared.md"\n'
                '[agents.codex]\noutput_path = ".ai-config/AGENTS.shared.md"\n'
            )
            (root / ".ai-config").mkdir()
            (root / ".ai-config/CLAUDE.shared.md").write_text("shared text\n")
            (root / ".ai-config/AGENTS.shared.md").write_text("shared text\n")
            (root / ".ai-config/AGENTS.claude.md").write_text("claude only\n")
            (root / ".ai-config/agent-sync.toml").write_text(
                '[instructions]\nclaude = ".claude/global-CLAUDE.md"\n'
                'codex = ".codex/AGENTS.md"\n'
            )

            agent_sync.build_instructions(root)

            claude_output = (root / ".claude/global-CLAUDE.md").read_text()
            self.assertIn("shared text", claude_output)
            self.assertIn("claude only", claude_output)
            self.assertIn("<!-- Claude-specific overlay -->", claude_output)
            # Codex has no overlay here, so Ruler's output stands unmodified and
            # no empty final file is invented.
            self.assertFalse((root / ".codex/AGENTS.md").exists())

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
            REPO / ".local/bin/codex-auto-update",
            REPO / ".local/bin/codex-rc",
            REPO / ".local/bin/codex-config-sync",
            REPO / ".local/libexec/codex-config-sync.py",
            REPO / ".local/libexec/codex-rc-cleanup",
            REPO / ".config/systemd/user/ai-agents.slice",
            REPO / ".config/systemd/user/agent-sync.service",
            REPO / ".config/systemd/user/agent-sync.service.d/40-maintenance.conf",
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
        self.assertIn("install_shell_wrapper", installer)
        self.assertIn("install_git_wrapper", installer)

        windows = (REPO / "scripts/install-claude-windows.ps1").read_text()
        self.assertNotIn(
            'Copy-File "$ClaudeSrc\\global-learned-insights.md" "$ClaudeDest\\global-learned-insights.md"',
            windows,
        )
        self.assertIn("Seed-File", windows)
        self.assertIn('Test-Path "$ClaudeSrc\\settings.local.json"', windows)
        self.assertIn("PSObject.Properties['permissions']", windows)

    def test_linux_installer_links_shared_learned_insights(self) -> None:
        installer = (REPO / "install_environment.sh").read_text()
        source = '$DOTFILES_DIR/.claude/global-learned-insights.md'

        self.assertIn(
            f'link_file "{source}" ~/.claude/global-learned-insights.md',
            installer,
        )
        self.assertIn(
            f'link_file "{source}" ~/.codex/global-learned-insights.md',
            installer,
        )
        self.assertNotIn("seed_runtime_file", installer)

    def test_linux_installer_enables_core_agent_sync(self) -> None:
        installer = (REPO / "install_environment.sh").read_text()

        self.assertIn('"$DOTFILES_DIR/scripts/dotfiles" sync-enable', installer)
        self.assertIn("DOTFILES_SKIP_SYSTEMD=1", installer)

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
        maintenance = (
            REPO
            / ".config/systemd/user/agent-sync.service.d/40-maintenance.conf"
        ).read_text()
        codex_service = (REPO / ".config/systemd/user/codex-app-server.service").read_text()
        updater_service = (REPO / ".config/systemd/user/dotfiles-update.service").read_text()
        self.assertNotIn("WorkingDirectory=", agent_service)
        self.assertIn("agent-sync --all --no-restart --quiet", agent_service)
        self.assertNotIn("dotfiles-update", agent_service)
        self.assertIn("ExecStartPre=%h/.local/bin/dotfiles-update", maintenance)
        self.assertIn("ExecStartPost=%h/.local/bin/codex-auto-update", maintenance)
        self.assertIn("ExecStartPost=%h/.local/bin/claude-auto-update", maintenance)
        self.assertIn("codex-config-sync --compat-only --quiet", codex_service)
        self.assertNotIn("agent-sync --all", codex_service)
        self.assertIn("%h/.local/bin/dotfiles-update", updater_service)
        self.assertNotIn("ExecStart=%h/.local/bin/dotfiles-update", agent_service)

    def test_remote_control_feature_manages_dotfiles_updater_assets(self) -> None:
        deployer = (REPO / "scripts/dotfiles").read_text()
        for path in (
            ".config/systemd/user/dotfiles-update.service",
            ".local/bin/dotfiles-update",
            ".local/bin/codex-auto-update",
            ".config/systemd/user/agent-sync.service.d/40-maintenance.conf",
            ".local/libexec/ai-config-audit.py",
            ".local/libexec/codex-app-server-watchdog.py",
        ):
            self.assertIn(path, deployer)
        self.assertNotIn("    .config/systemd/user/dotfiles-update.timer\n", deployer)
        self.assertFalse((REPO / ".config/systemd/user/dotfiles-update.timer").exists())
        self.assertIn("enable --now agent-sync.timer", deployer)
        self.assertIn("disable --now dotfiles-update.timer", deployer)
        self.assertNotIn("enable --now agent-sync.timer dotfiles-update.timer", deployer)

    def test_agent_sync_uses_completion_based_timer_and_resource_limits(self) -> None:
        timer = (REPO / ".config/systemd/user/agent-sync.timer").read_text()
        service = (REPO / ".config/systemd/user/agent-sync.service").read_text()

        self.assertIn("OnUnitInactiveSec=3h", timer)
        self.assertIn("RandomizedDelaySec=15min", timer)
        self.assertNotIn("OnUnitActiveSec=", timer)
        self.assertIn("Slice=ai-agents.slice", service)
        self.assertIn(
            "ExecStart=%h/.local/share/codex-config-sync-venv-current/bin/python %h/.local/bin/agent-sync --all --no-restart --quiet",
            service,
        )
        self.assertEqual(service.count("ExecStart="), 1)
        self.assertIn("CPUQuota=50%", service)
        self.assertIn("MemoryMax=1G", service)
        self.assertIn("TasksMax=64", service)
        self.assertIn("IOSchedulingClass=idle", service)

    def test_agent_services_share_a_bounded_slice(self) -> None:
        slice_unit = (REPO / ".config/systemd/user/ai-agents.slice").read_text()
        for unit_name in ("codex-app-server.service", "claude-rc@.service"):
            service = (REPO / ".config/systemd/user" / unit_name).read_text()
            self.assertIn("Slice=ai-agents.slice", service)
            self.assertIn("KillMode=control-group", service)

        self.assertIn("CPUWeight=25", slice_unit)
        self.assertIn("IOWeight=25", slice_unit)
        self.assertIn("MemoryHigh=25%", slice_unit)
        self.assertIn("MemoryMax=35%", slice_unit)
        self.assertIn("TasksMax=32768", slice_unit)
        self.assertNotIn("Persistent=true", (REPO / ".config/systemd/user/agent-sync.timer").read_text())

    def test_claude_tool_concurrency_is_bounded(self) -> None:
        settings = (REPO / ".claude/settings.json").read_text()
        self.assertIn('"CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY": "4"', settings)

    def test_sync_enable_provisions_pinned_codex_sync_dependency(self) -> None:
        deployer = (REPO / "scripts/dotfiles").read_text()
        wrapper = (REPO / ".local/bin/codex-config-sync").read_text()
        self.assertIn("tomlkit==0.13.3", deployer)
        self.assertIn("PyYAML==6.0.3", deployer)
        self.assertIn("codex-config-sync-venv-current/bin/python", wrapper)
        self.assertIn("sync-enable", deployer)
        self.assertIn("Run: dotfiles sync-enable", wrapper)

    def test_sync_enable_installs_core_assets_and_starts_timer(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            home = pathlib.Path(temporary)
            dotfiles = home / ".dot_files"
            core_assets = {
                ".config/systemd/user/ai-agents.slice": "[Slice]\n",
                ".config/systemd/user/agent-sync.service": "[Service]\nType=oneshot\n",
                ".config/systemd/user/agent-sync.timer": "[Timer]\n",
                ".local/bin/agent-sync": "#!/usr/bin/env python3\n",
                ".local/bin/codex-config-sync": "#!/usr/bin/env bash\n",
                ".local/libexec/codex-config-sync.py": "# implementation\n",
            }
            for relative, content in core_assets.items():
                source = dotfiles / relative
                source.parent.mkdir(parents=True, exist_ok=True)
                source.write_text(content)

            fake_bin = home / "fake-bin"
            fake_bin.mkdir()
            python_log = home / "python.log"
            fake_python = fake_bin / "python"
            fake_python.write_text(
                "#!/usr/bin/env bash\n"
                "set -euo pipefail\n"
                "[[ \"${1:-}\" == '-c' ]] && exit 0\n"
                "printf '%s\\n' \"$*\" > \"$PYTHON_LOG\"\n"
            )
            fake_python.chmod(0o755)
            systemctl_log = home / "systemctl.log"
            fake_systemctl = fake_bin / "systemctl"
            fake_systemctl.write_text(
                "#!/usr/bin/env bash\n"
                "printf '%s\\n' \"$*\" >> \"$SYSTEMCTL_LOG\"\n"
            )
            fake_systemctl.chmod(0o755)
            env = os.environ | {
                "HOME": str(home),
                "PATH": f"{fake_bin}:{os.environ['PATH']}",
                "CODEX_CONFIG_SYNC_PYTHON": str(fake_python),
                "PYTHON_LOG": str(python_log),
                "SYSTEMCTL_LOG": str(systemctl_log),
            }

            result = subprocess.run(
                [str(REPO / "scripts/dotfiles"), "sync-enable"],
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            for relative in core_assets:
                target = home / relative
                self.assertTrue(target.is_symlink(), relative)
                self.assertEqual(target.resolve(), (dotfiles / relative).resolve())
            self.assertFalse(
                (home / ".config/dotfiles/features/ai-remote-control").exists()
            )
            self.assertEqual(
                python_log.read_text().strip(),
                f"{home}/.local/bin/agent-sync sync --root {dotfiles} --no-restart --quiet",
            )
            self.assertEqual(
                systemctl_log.read_text().splitlines(),
                ["--user daemon-reload", "--user enable --now agent-sync.timer"],
            )

    def test_sync_enable_immediately_projects_claude_skills(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            home = pathlib.Path(temporary)
            dotfiles = home / ".dot_files"
            core_assets = (
                ".config/systemd/user/ai-agents.slice",
                ".config/systemd/user/agent-sync.service",
                ".config/systemd/user/agent-sync.timer",
                ".local/bin/agent-sync",
                ".local/bin/codex-config-sync",
                ".local/libexec/codex-config-sync.py",
            )
            for relative in core_assets:
                source = REPO / relative
                target = dotfiles / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(source.read_bytes())
                if relative.startswith(".local/bin/"):
                    target.chmod(0o755)

            (dotfiles / ".ruler").mkdir()
            (dotfiles / ".ruler/ruler.toml").write_text("[agents]\n")
            subprocess.run(
                ["git", "init", "--quiet", str(dotfiles)],
                check=True,
                capture_output=True,
                text=True,
            )

            claude = home / ".claude"
            skill = claude / "skills/full-review"
            skill.mkdir(parents=True)
            (skill / "SKILL.md").write_text("# Full review\n")
            hooks = claude / "hooks"
            hooks.mkdir()
            for name in ("reinject-on-compact.sh", "save-insights-reminder.sh"):
                (hooks / name).write_text("#!/bin/bash\nset -euo pipefail\n")
            (claude / "settings.json").write_text("{}\n")

            ruler = home / ".local/bin/ruler"
            ruler.parent.mkdir(parents=True)
            ruler.write_text(
                "#!/bin/bash\n"
                "set -euo pipefail\n"
                "if [ \"${1:-}\" = '--version' ]; then\n"
                "    printf '%s\\n' '0.3.44'\n"
                "    exit 0\n"
                "fi\n"
                "[ \"${1:-}\" = 'apply' ]\n"
            )
            ruler.chmod(0o755)

            fake_bin = home / "fake-bin"
            fake_bin.mkdir()
            fake_systemctl = fake_bin / "systemctl"
            fake_systemctl.write_text("#!/bin/bash\nset -euo pipefail\n")
            fake_systemctl.chmod(0o755)
            env = os.environ | {
                "HOME": str(home),
                "PATH": f"{fake_bin}:{os.environ['PATH']}",
                "CODEX_CONFIG_SYNC_PYTHON": sys.executable,
            }
            codex_skill = home / ".agents/skills/full-review"
            self.assertFalse(codex_skill.exists())

            result = subprocess.run(
                [str(REPO / "scripts/dotfiles"), "sync-enable"],
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(codex_skill.is_symlink())
            self.assertEqual(codex_skill.resolve(), skill.resolve())

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
                check=False,
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
                check=False,
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
                check=False,
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
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(log.read_text().strip(), f"status --root {registered_root}")

    def test_dotfiles_update_reconciles_enabled_feature_when_already_current(self) -> None:
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
            script = source / "scripts/dotfiles"
            script.parent.mkdir(parents=True)
            script.write_text(
                "#!/usr/bin/env bash\n"
                "printf 'feature %s\\n' \"$*\" >> \"$RECONCILE_LOG\"\n"
            )
            script.chmod(0o755)
            subprocess.run(["git", "-C", str(source), "add", "."], check=True)
            subprocess.run(["git", "-C", str(source), "commit", "-qm", "initial"], check=True)
            subprocess.run(["git", "-C", str(source), "push", "-qu", "origin", "HEAD:main"], check=True)
            subprocess.run(["git", "--git-dir", str(remote), "symbolic-ref", "HEAD", "refs/heads/main"], check=True)
            subprocess.run(["git", "clone", "-q", str(remote), str(checkout)], check=True)
            marker = home / ".config/dotfiles/features/ai-remote-control"
            marker.parent.mkdir(parents=True)
            marker.touch()
            agent_sync = home / ".local/bin/agent-sync"
            agent_sync.parent.mkdir(parents=True)
            agent_sync.write_text(
                "#!/usr/bin/env bash\n"
                "printf 'sync %s\\n' \"$*\" >> \"$RECONCILE_LOG\"\n"
            )
            agent_sync.chmod(0o755)
            log = root / "reconcile.log"
            env = os.environ | {
                "HOME": str(home),
                "DOTFILES_DIR": str(checkout),
                "XDG_RUNTIME_DIR": str(root / "run"),
                "RECONCILE_LOG": str(log),
            }

            result = subprocess.run(
                [str(REPO / ".local/bin/dotfiles-update")],
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                log.read_text().splitlines(),
                ["feature feature-enable ai-remote-control", "sync --all --no-restart --quiet"],
            )

    def test_parent_pull_is_reconciled_by_current_head_maintenance(self) -> None:
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
            old_script = source / "scripts/dotfiles"
            old_script.parent.mkdir(parents=True)
            old_script.write_text(
                "#!/usr/bin/env bash\n"
                "set -euo pipefail\n"
                "git -C \"$DOTFILES_DIR\" pull --ff-only origin main >/dev/null\n"
            )
            old_script.chmod(0o755)
            updater = source / ".local/bin/dotfiles-update"
            updater.parent.mkdir(parents=True)
            updater.write_text("#!/usr/bin/env bash\nexit 0\n")
            updater.chmod(0o755)
            subprocess.run(["git", "-C", str(source), "add", "."], check=True)
            subprocess.run(["git", "-C", str(source), "commit", "-qm", "parent"], check=True)
            subprocess.run(["git", "-C", str(source), "push", "-qu", "origin", "HEAD:main"], check=True)
            subprocess.run(["git", "--git-dir", str(remote), "symbolic-ref", "HEAD", "refs/heads/main"], check=True)
            subprocess.run(["git", "clone", "-q", str(remote), str(checkout)], check=True)

            old_script.write_text(
                "#!/usr/bin/env bash\n"
                "printf 'feature %s\\n' \"$*\" >> \"$RECONCILE_LOG\"\n"
            )
            old_script.chmod(0o755)
            updater.write_text((REPO / ".local/bin/dotfiles-update").read_text())
            updater.chmod(0o755)
            subprocess.run(["git", "-C", str(source), "add", "."], check=True)
            subprocess.run(["git", "-C", str(source), "commit", "-qm", "add reconciliation"], check=True)
            subprocess.run(["git", "-C", str(source), "push", "-q"], check=True)

            marker = home / ".config/dotfiles/features/ai-remote-control"
            marker.parent.mkdir(parents=True)
            marker.touch()
            local_bin = home / ".local/bin"
            local_bin.mkdir(parents=True)
            (local_bin / "dotfiles-update").symlink_to(checkout / ".local/bin/dotfiles-update")
            agent_sync = local_bin / "agent-sync"
            agent_sync.write_text(
                "#!/usr/bin/env bash\n"
                "printf 'sync %s\\n' \"$*\" >> \"$RECONCILE_LOG\"\n"
            )
            agent_sync.chmod(0o755)
            log = root / "reconcile.log"
            runtime = root / "run"
            env = os.environ | {
                "HOME": str(home),
                "DOTFILES_DIR": str(checkout),
                "XDG_RUNTIME_DIR": str(runtime),
                "RECONCILE_LOG": str(log),
            }

            pulled = subprocess.run(
                [str(checkout / "scripts/dotfiles"), "pull"],
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(pulled.returncode, 0, pulled.stderr)
            self.assertFalse(log.exists())

            reconciled = subprocess.run(
                [str(local_bin / "dotfiles-update")],
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(reconciled.returncode, 0, reconciled.stderr)
            self.assertEqual(
                log.read_text().splitlines(),
                ["feature feature-enable ai-remote-control", "sync --all --no-restart --quiet"],
            )

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
                check=False,
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
                check=False,
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
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(
                subprocess.check_output(["git", "-C", str(checkout), "rev-parse", "HEAD"], text=True).strip(),
                old_head,
            )

    def test_dotfiles_status_ignores_repo_internal_ruler_sources(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            home = pathlib.Path(temporary)
            dotfiles = home / ".dot_files"
            (dotfiles / ".ruler").mkdir(parents=True)
            (dotfiles / ".ai-config").mkdir()
            (dotfiles / ".codex").mkdir()
            (dotfiles / ".zshrc").write_text("# shared\n")
            # Ruler source and generated intermediates feed agent-sync; they are
            # never deployed to $HOME, so status must not audit them.
            (dotfiles / ".ruler/AGENTS.md").write_text("# shared\n")
            (dotfiles / ".ruler/ruler.toml").write_text("[agents.claude]\n")
            (dotfiles / ".ai-config/agent-sync.toml").write_text("[instructions]\n")
            (dotfiles / ".ai-config/CLAUDE.shared.md").write_text("# generated\n")
            (dotfiles / ".codex/verify-hook-trust.py").write_text("# helper\n")
            subprocess.run(["git", "init", "-q", str(dotfiles)], check=True)
            subprocess.run(["git", "-C", str(dotfiles), "add", "."], check=True)

            result = subprocess.run(
                [str(REPO / "scripts/dotfiles"), "status"],
                env=os.environ | {"HOME": str(home)},
                capture_output=True,
                text=True,
                check=True,
            )

            self.assertIn("Status: 0 linked, 0 issues, 0 missing", result.stdout)
            for absent in (".ruler", ".ai-config", "verify-hook-trust.py"):
                self.assertNotIn(absent, result.stdout)

    def test_dotfiles_status_always_requires_core_sync_assets(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            home = pathlib.Path(temporary)
            dotfiles = home / ".dot_files"
            (dotfiles / ".local/bin").mkdir(parents=True)
            (dotfiles / ".zshrc").write_text("# shared\n")
            (dotfiles / ".local/bin/agent-sync").write_text("#!/usr/bin/env python3\n")
            (dotfiles / ".local/bin/claude-rc").write_text("#!/usr/bin/env bash\n")
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
            self.assertIn(str(home / ".local/bin/agent-sync"), without_feature.stdout)
            self.assertNotIn(str(home / ".local/bin/claude-rc"), without_feature.stdout)
            self.assertIn("Status: 0 linked, 0 issues, 1 missing", without_feature.stdout)

            target = home / ".local/bin/agent-sync"
            target.parent.mkdir(parents=True)
            target.symlink_to(dotfiles / ".local/bin/agent-sync")
            core_installed = subprocess.run(
                [str(REPO / "scripts/dotfiles"), "status"],
                env=env,
                capture_output=True,
                text=True,
                check=True,
            )
            self.assertIn("Status: 1 linked, 0 issues, 0 missing", core_installed.stdout)

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
            self.assertIn(str(home / ".local/bin/claude-rc"), with_feature.stdout)
            self.assertIn("Status: 1 linked, 0 issues, 1 missing", with_feature.stdout)

    def test_feature_enable_links_and_reloads_without_restarting_services(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            home = pathlib.Path(temporary)
            dotfiles = home / ".dot_files"
            source_script = dotfiles / ".local/bin/agent-sync"
            source_unit = dotfiles / ".config/systemd/user/agent-sync.service"
            source_slice = dotfiles / ".config/systemd/user/ai-agents.slice"
            source_script.parent.mkdir(parents=True)
            source_unit.parent.mkdir(parents=True)
            source_script.write_text("#!/usr/bin/env python3\n")
            source_unit.write_text("[Service]\nType=oneshot\n")
            source_slice.write_text("[Slice]\nTasksMax=1536\n")

            target_unit = home / ".config/systemd/user/agent-sync.service"
            target_unit.parent.mkdir(parents=True)
            target_unit.write_text("legacy unit\n")
            legacy_timer = home / ".config/systemd/user/dotfiles-update.timer"
            legacy_timer.symlink_to(dotfiles / ".config/systemd/user/dotfiles-update.timer")
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
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            target_unit.unlink()
            target_unit.write_text("second legacy unit\n")
            second_result = subprocess.run(
                [str(REPO / "scripts/dotfiles"), "feature-enable", "ai-remote-control"],
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(second_result.returncode, 0, second_result.stderr)

            self.assertTrue((home / ".local/bin/agent-sync").is_symlink())
            target_slice = home / ".config/systemd/user/ai-agents.slice"
            self.assertTrue(target_slice.is_symlink())
            self.assertEqual(target_slice.resolve(), source_slice.resolve())
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
                    "--user disable --now dotfiles-update.timer",
                    "--user daemon-reload",
                    "--user enable --now agent-sync.timer",
                    "--user daemon-reload",
                    "--user enable --now agent-sync.timer",
                ],
            )
            self.assertNotIn("restart", systemctl_log.read_text())
            self.assertFalse(legacy_timer.exists())
            self.assertFalse(legacy_timer.is_symlink())

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
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(target.read_text(), "legacy wrapper\n")
            self.assertFalse((home / ".config/dotfiles/features/ai-remote-control").exists())

    def test_feature_enable_accepts_valid_python_override_without_sibling_pip(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            home = pathlib.Path(temporary)
            dotfiles = home / ".dot_files"
            wrapper = dotfiles / ".local/bin/codex-config-sync"
            implementation = dotfiles / ".local/libexec/codex-config-sync.py"
            wrapper.parent.mkdir(parents=True)
            implementation.parent.mkdir(parents=True)
            wrapper.write_text("#!/usr/bin/env bash\n")
            implementation.write_text("# implementation\n")
            override_dir = home / "override"
            override_dir.mkdir()
            override = override_dir / "python"
            override.write_text("#!/usr/bin/env bash\nexit 0\n")
            override.chmod(0o755)
            fake_bin = home / "fake-bin"
            fake_bin.mkdir()
            systemctl = fake_bin / "systemctl"
            systemctl.write_text("#!/usr/bin/env bash\nexit 0\n")
            systemctl.chmod(0o755)
            env = os.environ | {
                "HOME": str(home),
                "PATH": f"{fake_bin}:{os.environ['PATH']}",
                "CODEX_CONFIG_SYNC_PYTHON": str(override),
            }

            result = subprocess.run(
                [str(REPO / "scripts/dotfiles"), "feature-enable", "ai-remote-control"],
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse((override_dir / "pip").exists())

    def test_dotfiles_pull_reconciles_assets_for_enabled_remote_control(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            origin = root / "origin.git"
            seed = root / "seed"
            home = root / "home"
            home.mkdir()
            subprocess.run(["git", "init", "--bare", str(origin)], check=True, capture_output=True)
            subprocess.run(["git", "init", "-b", "main", str(seed)], check=True, capture_output=True)
            subprocess.run(["git", "-C", str(seed), "config", "user.email", "test@example.com"], check=True)
            subprocess.run(["git", "-C", str(seed), "config", "user.name", "Test"], check=True)
            source = seed / ".local/bin/agent-sync"
            source.parent.mkdir(parents=True)
            source.write_text("#!/usr/bin/env python3\n")
            subprocess.run(["git", "-C", str(seed), "add", "."], check=True)
            subprocess.run(["git", "-C", str(seed), "commit", "-m", "seed"], check=True, capture_output=True)
            subprocess.run(["git", "-C", str(seed), "remote", "add", "origin", str(origin)], check=True)
            subprocess.run(["git", "-C", str(seed), "push", "-u", "origin", "main"], check=True, capture_output=True)
            checkout = home / ".dot_files"
            subprocess.run(["git", "clone", "--branch", "main", str(origin), str(checkout)], check=True, capture_output=True)
            marker = home / ".config/dotfiles/features/ai-remote-control"
            marker.parent.mkdir(parents=True)
            marker.touch()
            fake_bin = root / "fake-bin"
            fake_bin.mkdir()
            systemctl = fake_bin / "systemctl"
            systemctl.write_text("#!/usr/bin/env bash\nexit 0\n")
            systemctl.chmod(0o755)
            env = os.environ | {
                "HOME": str(home),
                "DOTFILES_DIR": str(checkout),
                "PATH": f"{fake_bin}:{os.environ['PATH']}",
            }

            result = subprocess.run(
                [str(REPO / "scripts/dotfiles"), "pull"],
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue((home / ".local/bin/agent-sync").is_symlink())

    def test_feature_enable_rebuilds_when_managed_pip_is_missing(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            home = pathlib.Path(temporary)
            dotfiles = home / ".dot_files"
            wrapper = dotfiles / ".local/bin/codex-config-sync"
            implementation = dotfiles / ".local/libexec/codex-config-sync.py"
            wrapper.parent.mkdir(parents=True)
            implementation.parent.mkdir(parents=True)
            wrapper.write_text("#!/usr/bin/env bash\n")
            implementation.write_text("# implementation\n")
            share = home / ".local/share"
            old_generation = share / "codex-config-sync-venv.generation.old"
            (old_generation / "bin").mkdir(parents=True)
            old_python = old_generation / "bin/python"
            old_python.write_text("#!/usr/bin/env bash\nexit 0\n")
            old_python.chmod(0o755)
            current = share / "codex-config-sync-venv-current"
            current.symlink_to(old_generation, target_is_directory=True)
            fake_bin = home / "fake-bin"
            fake_bin.mkdir()
            python3 = fake_bin / "python3"
            python3.write_text(
                "#!/usr/bin/env bash\n"
                "set -euo pipefail\n"
                "[[ \"${1:-}\" != '-c' ]] || exit 0\n"
                "target=$3\n"
                "mkdir -p \"$target/bin\"\n"
                "printf '#!/usr/bin/env bash\\nexit 0\\n' > \"$target/bin/python\"\n"
                "printf '#!/usr/bin/env bash\\nexit 0\\n' > \"$target/bin/pip\"\n"
                "chmod +x \"$target/bin/python\" \"$target/bin/pip\"\n"
            )
            python3.chmod(0o755)
            systemctl = fake_bin / "systemctl"
            systemctl.write_text("#!/usr/bin/env bash\nexit 0\n")
            systemctl.chmod(0o755)
            env = os.environ | {
                "HOME": str(home),
                "PATH": f"{fake_bin}:{os.environ['PATH']}",
            }

            result = subprocess.run(
                [str(REPO / "scripts/dotfiles"), "feature-enable", "ai-remote-control"],
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotEqual(current.resolve(), old_generation)
            self.assertTrue((current / "bin/pip").is_file())

    def test_failed_venv_build_preserves_current_and_removes_partial_generation(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            home = pathlib.Path(temporary)
            dotfiles = home / ".dot_files"
            wrapper = dotfiles / ".local/bin/codex-config-sync"
            implementation = dotfiles / ".local/libexec/codex-config-sync.py"
            wrapper.parent.mkdir(parents=True)
            implementation.parent.mkdir(parents=True)
            wrapper.write_text("#!/usr/bin/env bash\n")
            implementation.write_text("# implementation\n")
            share = home / ".local/share"
            old_generation = share / "codex-config-sync-venv.generation.old"
            (old_generation / "bin").mkdir(parents=True)
            old_python = old_generation / "bin/python"
            old_python.write_text("#!/usr/bin/env bash\nexit 0\n")
            old_python.chmod(0o755)
            current = share / "codex-config-sync-venv-current"
            current.symlink_to(old_generation, target_is_directory=True)
            fake_bin = home / "fake-bin"
            fake_bin.mkdir()
            python3 = fake_bin / "python3"
            python3.write_text(
                "#!/usr/bin/env bash\n"
                "set -euo pipefail\n"
                "[[ \"${1:-}\" != '-c' ]] || exit 0\n"
                "target=$3\n"
                "mkdir -p \"$target/bin\"\n"
                "touch \"$target/partial\"\n"
                "exit 9\n"
            )
            python3.chmod(0o755)
            systemctl = fake_bin / "systemctl"
            systemctl.write_text("#!/usr/bin/env bash\nexit 0\n")
            systemctl.chmod(0o755)
            env = os.environ | {
                "HOME": str(home),
                "PATH": f"{fake_bin}:{os.environ['PATH']}",
            }

            result = subprocess.run(
                [str(REPO / "scripts/dotfiles"), "feature-enable", "ai-remote-control"],
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(current.resolve(), old_generation)
            self.assertEqual(
                subprocess.run(
                    [str(current / "bin/python"), "-c", "pass"],
                    check=False,
                ).returncode,
                0,
            )
            self.assertEqual(
                list(share.glob("codex-config-sync-venv.generation.*")),
                [old_generation],
            )

    def test_failed_venv_activation_cleans_staging_and_preserves_current(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            home = pathlib.Path(temporary)
            dotfiles = home / ".dot_files"
            wrapper = dotfiles / ".local/bin/codex-config-sync"
            implementation = dotfiles / ".local/libexec/codex-config-sync.py"
            wrapper.parent.mkdir(parents=True)
            implementation.parent.mkdir(parents=True)
            wrapper.write_text("#!/usr/bin/env bash\n")
            implementation.write_text("# implementation\n")
            share = home / ".local/share"
            old_generation = share / "codex-config-sync-venv.generation.old"
            (old_generation / "bin").mkdir(parents=True)
            old_python = old_generation / "bin/python"
            old_python.write_text("#!/usr/bin/env bash\nexit 0\n")
            old_python.chmod(0o755)
            current = share / "codex-config-sync-venv-current"
            current.symlink_to(old_generation, target_is_directory=True)
            fake_bin = home / "fake-bin"
            fake_bin.mkdir()
            python3 = fake_bin / "python3"
            python3.write_text(
                "#!/usr/bin/env bash\n"
                "set -euo pipefail\n"
                "[[ \"${1:-}\" != '-c' ]] || exit 0\n"
                "target=$3\n"
                "mkdir -p \"$target/bin\"\n"
                "printf '#!/usr/bin/env bash\\nexit 0\\n' > \"$target/bin/python\"\n"
                "printf '#!/usr/bin/env bash\\nexit 0\\n' > \"$target/bin/pip\"\n"
                "chmod +x \"$target/bin/python\" \"$target/bin/pip\"\n"
            )
            python3.chmod(0o755)
            mv = fake_bin / "mv"
            mv.write_text("#!/usr/bin/env bash\nexit 9\n")
            mv.chmod(0o755)
            systemctl = fake_bin / "systemctl"
            systemctl.write_text("#!/usr/bin/env bash\nexit 0\n")
            systemctl.chmod(0o755)
            env = os.environ | {
                "HOME": str(home),
                "PATH": f"{fake_bin}:{os.environ['PATH']}",
            }

            result = subprocess.run(
                [str(REPO / "scripts/dotfiles"), "feature-enable", "ai-remote-control"],
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(current.resolve(), old_generation)
            self.assertEqual(
                list(share.glob("codex-config-sync-venv.generation.*")),
                [old_generation],
            )
            self.assertEqual(list(share.glob(".codex-config-sync-link.*")), [])

    def test_signal_after_venv_activation_preserves_active_generation(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            home = pathlib.Path(temporary)
            dotfiles = home / ".dot_files"
            wrapper = dotfiles / ".local/bin/codex-config-sync"
            implementation = dotfiles / ".local/libexec/codex-config-sync.py"
            wrapper.parent.mkdir(parents=True)
            implementation.parent.mkdir(parents=True)
            wrapper.write_text("#!/usr/bin/env bash\n")
            implementation.write_text("# implementation\n")
            real_share = home / "real-share"
            real_share.mkdir()
            (home / ".local").mkdir()
            share = home / ".local/share"
            share.symlink_to(real_share, target_is_directory=True)
            old_generation = share / "codex-config-sync-venv.generation.old"
            (old_generation / "bin").mkdir(parents=True)
            old_python = old_generation / "bin/python"
            old_python.write_text("#!/usr/bin/env bash\nexit 0\n")
            old_python.chmod(0o755)
            current = share / "codex-config-sync-venv-current"
            current.symlink_to(old_generation, target_is_directory=True)
            fake_bin = home / "fake-bin"
            fake_bin.mkdir()
            python3 = fake_bin / "python3"
            python3.write_text(
                "#!/usr/bin/env bash\n"
                "set -euo pipefail\n"
                "[[ \"${1:-}\" != '-c' ]] || exit 0\n"
                "target=$3\n"
                "mkdir -p \"$target/bin\"\n"
                "printf '#!/usr/bin/env bash\\nexit 0\\n' > \"$target/bin/python\"\n"
                "printf '#!/usr/bin/env bash\\nexit 0\\n' > \"$target/bin/pip\"\n"
                "chmod +x \"$target/bin/python\" \"$target/bin/pip\"\n"
            )
            python3.chmod(0o755)
            rmdir = fake_bin / "rmdir"
            rmdir.write_text(
                "#!/usr/bin/env bash\n"
                "kill -TERM \"$PPID\"\n"
                "sleep 0.1\n"
                "exit 0\n"
            )
            rmdir.chmod(0o755)
            systemctl = fake_bin / "systemctl"
            systemctl.write_text("#!/usr/bin/env bash\nexit 0\n")
            systemctl.chmod(0o755)
            env = os.environ | {
                "HOME": str(home),
                "PATH": f"{fake_bin}:{os.environ['PATH']}",
            }

            result = subprocess.run(
                [str(REPO / "scripts/dotfiles"), "feature-enable", "ai-remote-control"],
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertTrue(current.is_symlink())
            self.assertNotEqual(current.resolve(), old_generation)
            self.assertTrue((current / "bin/python").is_file())
            self.assertTrue((current / "bin/pip").is_file())
            self.assertEqual(list(share.glob(".codex-config-sync-link.*")), [])

    def test_feature_enable_atomically_points_to_a_stable_venv_generation(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            home = pathlib.Path(temporary)
            dotfiles = home / ".dot_files"
            wrapper = dotfiles / ".local/bin/codex-config-sync"
            implementation = dotfiles / ".local/libexec/codex-config-sync.py"
            wrapper.parent.mkdir(parents=True)
            implementation.parent.mkdir(parents=True)
            wrapper.write_text("#!/usr/bin/env bash\n")
            implementation.write_text("# implementation\n")

            share = home / ".local/share"
            broken = share / "codex-config-sync-venv.generation.broken"
            (broken / "bin").mkdir(parents=True)
            (broken / "sentinel").write_text("broken environment\n")
            broken_python = broken / "bin/python"
            broken_python.write_text("#!/usr/bin/env bash\nexit 1\n")
            broken_python.chmod(0o755)
            current = share / "codex-config-sync-venv-current"
            current.symlink_to(broken, target_is_directory=True)

            fake_bin = home / "fake-bin"
            fake_bin.mkdir()
            fake_python = fake_bin / "python3"
            fake_python.write_text(
                "#!/usr/bin/env bash\n"
                "set -euo pipefail\n"
                "[[ \"${1:-}\" != '-c' ]] || exit 0\n"
                "[[ \"${1:-} ${2:-}\" == '-m venv' ]]\n"
                "target=$3\n"
                "[[ \"$target\" == *'.generation.'* ]] || exit 9\n"
                "mkdir -p \"$target/bin\"\n"
                "printf '#!/usr/bin/env bash\\nexit 0\\n' > \"$target/bin/python\"\n"
                "printf '#!/usr/bin/env bash\\nexit 0\\n' > \"$target/bin/pip\"\n"
                "chmod +x \"$target/bin/python\" \"$target/bin/pip\"\n"
            )
            fake_python.chmod(0o755)
            fake_systemctl = fake_bin / "systemctl"
            fake_systemctl.write_text("#!/usr/bin/env bash\nexit 0\n")
            fake_systemctl.chmod(0o755)
            env = os.environ | {
                "HOME": str(home),
                "PATH": f"{fake_bin}:{os.environ['PATH']}",
            }

            result = subprocess.run(
                [str(REPO / "scripts/dotfiles"), "feature-enable", "ai-remote-control"],
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(current.is_symlink())
            generation = current.resolve()
            self.assertIn(".generation.", generation.name)
            self.assertTrue((generation / "bin/python").is_file())
            self.assertTrue((generation / "bin/pip").is_file())
            self.assertEqual((broken / "sentinel").read_text(), "broken environment\n")

    def test_real_venv_entry_points_remain_valid_behind_generation_symlink(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            generation = root / "codex-config-sync-venv.generation.real"
            subprocess.run(
                [sys.executable, "-m", "venv", str(generation)], check=True
            )
            current = root / "codex-config-sync-venv-current"
            current.symlink_to(generation, target_is_directory=True)

            result = subprocess.run(
                [str(current / "bin/pip"), "--version"],
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            shebang = (generation / "bin/pip").read_text().splitlines()[0]
            self.assertIn(str(generation), shebang)
            self.assertTrue(generation.exists())

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
                check=False,
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
                check=False,
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
