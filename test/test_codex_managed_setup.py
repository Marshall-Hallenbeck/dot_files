import os
import pathlib
import runpy
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

REPO = pathlib.Path(__file__).resolve().parents[1]
SETUP = REPO / ".local/libexec/codex-rc-setup"


class ManagedSetupTests(unittest.TestCase):
    def setUp(self):
        self.enterContext(mock.patch.dict(os.environ))
        os.environ.pop("CODEX_HOME", None)

    def test_custom_codex_home_refuses_before_preflight_or_mutation(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = pathlib.Path(tmp) / "home"
            home.mkdir()
            custom = pathlib.Path(tmp) / "custom"
            module = runpy.run_path(str(SETUP))
            with (
                mock.patch.dict(
                    os.environ, {"HOME": str(home), "CODEX_HOME": str(custom)}
                ),
                mock.patch.dict(
                    module["main"].__globals__,
                    {"collect_servers": mock.Mock(return_value=([], [], []))},
                ),
                mock.patch("subprocess.run") as run,
                mock.patch("sys.stderr") as stderr,
            ):
                self.assertEqual(module["main"](), 75)
                module["main"].__globals__["collect_servers"].assert_not_called()
                run.assert_not_called()
                self.assertIn(
                    "CODEX_HOME",
                    "".join(call.args[0] for call in stderr.write.call_args_list),
                )
            self.assertFalse((home / ".codex").exists())
            self.assertFalse(custom.exists())

    def test_running_managed_validation_failure_reports_executable_and_error(self):
        for contents, expected in (
            ("#!/bin/sh\nexit 42\n", "42"),
            ("#!/missing/codex-interpreter\n", "No such file"),
        ):
            with self.subTest(expected=expected), tempfile.TemporaryDirectory() as tmp:
                home = pathlib.Path(tmp)
                managed = home / ".codex/packages/app-server-daemon/current/bin/codex"
                managed.parent.mkdir(parents=True)
                managed.write_text(contents)
                managed.chmod(0o755)
                runner = home / "runner.py"
                runner.write_text("""import runpy, sys
module = runpy.run_path(sys.argv[1])
module['main'].__globals__['collect_servers'] = lambda home: ([], [125], [])
sys.exit(module['main']())
""")
                result = subprocess.run(
                    [sys.executable, str(runner), str(SETUP)],
                    env=os.environ | {"HOME": tmp},
                    capture_output=True,
                    text=True,
                    check=False,
                    timeout=10,
                )
                self.assertEqual(result.returncode, 75)
                self.assertEqual(result.stdout, "")
                self.assertIn(str(managed), result.stderr)
                self.assertIn(expected, result.stderr)
                self.assertFalse(
                    (home / ".codex/app-server-daemon-setup-started").exists()
                )

    def test_concurrent_setup_cannot_use_stale_preflight(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = pathlib.Path(tmp)
            cli = home / ".codex/packages/standalone/current/bin/codex"
            cli.parent.mkdir(parents=True)
            cli.write_text("""#!/bin/bash
printf '%s\\n' "$*" >> "$HOME/calls"
if [[ "$*" == 'app-server daemon update --from-cli --yes' ]]; then
  mkdir -p "$HOME/.codex/packages/app-server-daemon/current/bin"
  cp "$0" "$HOME/.codex/packages/app-server-daemon/current/bin/codex"
fi
""")
            cli.chmod(0o755)
            # Real competing OS processes and CLI calls; isolate process discovery
            # from live services and pause exactly after preflight, before mutation.
            runner = home / "runner.py"
            runner.write_text("""import os, pathlib, runpy, sys, time
module = runpy.run_path(sys.argv[1])
def collect(home):
    with (home / 'preflights').open('a') as log:
        log.write('checked\\n')
    managed = home / '.codex/packages/app-server-daemon/current/bin/codex'
    return ([], [125] if managed.exists() else [], [])
module['main'].__globals__['collect_servers'] = collect
original_touch = pathlib.Path.touch
def touch(path, *args, **kwargs):
    if path.name == 'app-server-daemon-setup-started' and os.environ.get('DELAY'):
        original_touch(pathlib.Path.home() / 'paused')
        deadline = time.monotonic() + 15
        while not (pathlib.Path.home() / 'release').exists():
            if time.monotonic() > deadline:
                raise RuntimeError('test barrier timed out')
            time.sleep(0.01)
    return original_touch(path, *args, **kwargs)
pathlib.Path.touch = touch
sys.exit(module['main']())
""")
            command = [sys.executable, str(runner), str(SETUP)]
            env = os.environ | {"HOME": tmp}
            first = subprocess.Popen(
                command,
                env=env | {"DELAY": "1"},
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            try:
                deadline = time.monotonic() + 10
                while (
                    not (home / "paused").exists()
                    and first.poll() is None
                    and time.monotonic() < deadline
                ):
                    time.sleep(0.01)
                self.assertTrue(
                    (home / "paused").exists(),
                    "setup never reached pre-mutation barrier",
                )
                second = subprocess.run(
                    command,
                    env=env,
                    capture_output=True,
                    text=True,
                    timeout=10,
                    check=False,
                )
                (home / "release").touch()
                stdout, stderr = first.communicate(timeout=10)
                retry = subprocess.run(
                    command,
                    env=env,
                    capture_output=True,
                    text=True,
                    timeout=10,
                    check=False,
                )
                calls = (home / "calls").read_text().splitlines()
                self.assertEqual(
                    calls.count("app-server daemon bootstrap --remote-control"),
                    1,
                    calls,
                )
                self.assertEqual(
                    calls.count("app-server daemon update --from-cli --yes"), 1, calls
                )
                self.assertEqual(second.returncode, 75, second.stderr)
                self.assertEqual(
                    (home / "preflights").read_text().splitlines(),
                    ["checked", "checked"],
                    "contending setup must refuse before process discovery",
                )
                self.assertEqual(first.returncode, 0, stderr)
                self.assertEqual(retry.returncode, 0, retry.stderr)
                self.assertIn("already running", retry.stderr)
                self.assertEqual(stdout + second.stdout + retry.stdout, "")
                self.assertFalse(
                    (home / ".codex/app-server-daemon-setup-started").exists()
                )
            finally:
                if first.poll() is None:
                    first.kill()
                first.communicate()

    def test_partial_marker_refuses_even_if_managed_process_exists(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = pathlib.Path(tmp)
            managed = home / ".codex/packages/app-server-daemon/current/bin/codex"
            managed.parent.mkdir(parents=True)
            managed.write_text("#!/bin/sh\nexit 0\n")
            managed.chmod(0o755)
            (home / ".codex/app-server-daemon-setup-started").touch()
            module = runpy.run_path(str(SETUP))
            with (
                mock.patch.dict(os.environ, {"HOME": tmp}),
                mock.patch.dict(
                    module["main"].__globals__,
                    {"collect_servers": lambda home: ([], [125], [])},
                ),
                mock.patch("subprocess.run") as run,
            ):
                self.assertEqual(module["main"](), 75)
                run.assert_not_called()

    def test_setup_marker_blocks_desktop_even_with_package(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = pathlib.Path(tmp)
            for relative in (
                ".codex/packages/standalone/current/bin/codex",
                ".codex/packages/app-server-daemon/current/bin/codex",
            ):
                exe = home / relative
                exe.parent.mkdir(parents=True)
                exe.write_text('#!/bin/sh\nprintf "UNSAFE\\n"\n')
                exe.chmod(0o755)
            (home / ".codex/app-server-daemon-setup-started").touch()
            result = subprocess.run(
                [str(REPO / ".local/bin/codex"), "app-server", "proxy"],
                env=os.environ | {"HOME": tmp},
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(result.returncode, 75)
            self.assertEqual(result.stdout, "")

    def test_explicit_command_and_installer_opt_in(self):
        command = (REPO / "scripts/dotfiles").read_text()
        installer = (REPO / "install_environment.sh").read_text()
        self.assertIn("feature-setup)", command)
        self.assertIn('python3 "$DOTFILES_DIR/.local/libexec/codex-rc-setup"', command)
        self.assertIn("DOTFILES_SETUP_REMOTE_CONTROL:-0", installer)
        self.assertIn(
            '"$DOTFILES_DIR/scripts/dotfiles" feature-setup ai-remote-control',
            installer,
        )

    def test_installer_preserves_existing_guard(self):
        installer = (REPO / "install_environment.sh").read_text()
        section = installer[
            installer.index("# Let the official installer") : installer.index(
                "install_codex_ssh_links /usr/local/bin",
                installer.index("# Let the official installer"),
            )
        ]
        with tempfile.TemporaryDirectory() as tmp:
            home = pathlib.Path(tmp)
            wrapper = home / ".local/bin/codex"
            wrapper.parent.mkdir(parents=True)
            source = home / ".dot_files/.local/bin/codex"
            source.parent.mkdir(parents=True)
            source.write_text("#!/bin/sh\nexit 75\n")
            source.chmod(0o755)
            wrapper.symlink_to(source)
            fake = home / "fake"
            fake.mkdir()
            curl = fake / "curl"
            curl.write_text("#!/bin/sh\nexit 99\n")
            curl.chmod(0o755)
            result = subprocess.run(
                ["bash", "-ec", section],
                env=os.environ | {"HOME": tmp, "PATH": f"{fake}:/usr/bin:/bin"},
                capture_output=True,
                check=False,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertTrue(
                wrapper.is_symlink(), "installer removed Desktop guard on failed repair"
            )
            self.assertEqual(wrapper.resolve(), source)

    def test_partial_failure_retains_marker_and_refuses_retry(self):
        for fail in ("bootstrap", "update", "missing"):
            with self.subTest(fail=fail), tempfile.TemporaryDirectory() as tmp:
                home = pathlib.Path(tmp)
                cli = home / ".codex/packages/standalone/current/bin/codex"
                cli.parent.mkdir(parents=True)
                cli.write_text("#!/bin/sh\nexit 0\n")
                cli.chmod(0o755)
                module = runpy.run_path(str(SETUP))

                def run(args, fail=fail, **kwargs):
                    if fail in args:
                        raise subprocess.CalledProcessError(1, args)

                with (
                    mock.patch.dict(os.environ, {"HOME": tmp}),
                    mock.patch.dict(
                        module["main"].__globals__,
                        {"collect_servers": lambda home: ([], [], [])},
                    ),
                    mock.patch("subprocess.run", side_effect=run) as calls,
                ):
                    self.assertEqual(module["main"](), 1)
                    count = calls.call_count
                    self.assertEqual(module["main"](), 75)
                    self.assertEqual(calls.call_count, count)
                    self.assertEqual(count, 1 if fail == "bootstrap" else 2)
                self.assertTrue(
                    (home / ".codex/app-server-daemon-setup-started").exists()
                )

    def test_existing_workloads_are_never_mutated(self):
        for servers, package, expected in [
            (([123], [], []), False, 75),
            (([], [], [124]), False, 75),
            (([], [125], [124]), True, 0),
            (([123], [125], []), True, 75),
            (([], [125], []), False, 75),
            (([], [], []), True, 75),
        ]:
            with (
                self.subTest(servers=servers, package=package),
                tempfile.TemporaryDirectory() as tmp,
            ):
                home = pathlib.Path(tmp)
                managed = home / ".codex/packages/app-server-daemon/current/bin/codex"
                if package:
                    managed.parent.mkdir(parents=True)
                    managed.write_text("#!/bin/sh\nexit 0\n")
                    managed.chmod(0o755)
                module = runpy.run_path(str(SETUP))
                with (
                    mock.patch.dict(os.environ, {"HOME": tmp}),
                    mock.patch.dict(
                        module["main"].__globals__,
                        {"collect_servers": lambda home, servers=servers: servers},
                    ),
                    mock.patch("subprocess.run") as run,
                ):
                    self.assertEqual(module["main"](), expected)
                    self.assertTrue(
                        all(
                            call.args[0] == [str(managed), "--version"]
                            for call in run.call_args_list
                        )
                    )

    def test_clean_setup_provisions_package_and_verifies(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = pathlib.Path(tmp)
            cli = home / ".codex/packages/standalone/current/bin/codex"
            cli.parent.mkdir(parents=True)
            cli.write_text("""#!/bin/bash
printf '%s\\n' "$*" >> "$HOME/calls"
if [[ "$*" == 'app-server daemon update --from-cli --yes' ]]; then
  mkdir -p "$HOME/.codex/packages/app-server-daemon/current/bin"
  cp "$0" "$HOME/.codex/packages/app-server-daemon/current/bin/codex"
fi
""")
            cli.chmod(0o755)
            self.assertTrue(SETUP.exists(), "explicit safe setup entrypoint missing")
            # Exercise the public shell dispatch with only process discovery isolated.
            dotfiles = home / ".dot_files"
            dotfiles.symlink_to(REPO, target_is_directory=True)
            marker = home / ".config/dotfiles/features/ai-remote-control"
            marker.parent.mkdir(parents=True)
            marker.touch()
            fake = home / "fake-bin"
            fake.mkdir()
            python = fake / "python3"
            python.write_text(
                f'#!{sys.executable}\nimport runpy, sys\nm = runpy.run_path(sys.argv[1])\nm["main"].__globals__["collect_servers"] = lambda home: ([], [], [])\nsys.exit(m["main"]())\n'
            )
            python.chmod(0o755)
            result = subprocess.run(
                [str(REPO / "scripts/dotfiles"), "feature-setup", "ai-remote-control"],
                env=os.environ | {"HOME": tmp, "PATH": f"{fake}:/usr/bin:/bin"},
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("pins", result.stderr)
            self.assertEqual(result.stdout, "")
            self.assertFalse((home / ".codex/app-server-daemon-setup-started").exists())
            self.assertEqual(
                (home / "calls").read_text().splitlines(),
                [
                    "app-server daemon bootstrap --remote-control",
                    "app-server daemon update --from-cli --yes",
                    "--version",
                ],
            )
            self.assertTrue(
                (home / ".codex/packages/app-server-daemon/current/bin/codex").is_file()
            )


if __name__ == "__main__":
    unittest.main()
