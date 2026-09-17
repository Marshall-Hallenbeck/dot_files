import importlib.util
import io
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from types import ModuleType

REPO = Path(__file__).resolve().parents[1]


def load_module(name: str, relative: str) -> ModuleType:
    path = REPO / relative
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CodexAppServerWatchdogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.watchdog = load_module(
            "codex_app_server_watchdog",
            ".local/libexec/codex-app-server-watchdog.py",
        )

    def make_process(self, root: Path, pid: int, argv: list[str], rss_kib: int) -> None:
        proc = root / str(pid)
        proc.mkdir()
        (proc / "cmdline").write_bytes(b"\0".join(part.encode() for part in argv) + b"\0")
        (proc / "status").write_text(f"Name:\tcodex\nVmRSS:\t{rss_kib} kB\n")

    def test_normal_primary_and_proxy_are_silent(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.make_process(root, 10, ["codex", "app-server", "--remote-control"], 400_000)
            self.make_process(root, 11, ["codex", "app-server", "proxy"], 25_000)
            snapshot = self.watchdog.collect_processes(root)
            self.assertEqual(self.watchdog.evaluate(snapshot), [])

    def test_duplicate_primary_is_reported(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.make_process(root, 10, ["codex", "app-server", "--remote-control"], 400_000)
            self.make_process(root, 11, ["codex", "app-server", "--remote-control"], 400_000)
            findings = self.watchdog.evaluate(self.watchdog.collect_processes(root))
            self.assertTrue(any("primary" in finding for finding in findings))

    def test_excess_rss_is_reported(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.make_process(root, 10, ["codex", "app-server", "--remote-control"], 2_200_000)
            findings = self.watchdog.evaluate(self.watchdog.collect_processes(root))
            self.assertTrue(any("RSS" in finding for finding in findings))

    def test_findings_return_failure(self) -> None:
        output = io.StringIO()
        with redirect_stdout(output):
            result = self.watchdog.report(["duplicate primary"], [], False)
        self.assertEqual(result, 1)
        self.assertIn("duplicate primary", output.getvalue())


class AiConfigAuditTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.audit = load_module("ai_config_audit", ".local/libexec/ai-config-audit.py")

    def test_secret_scan_ignores_references_templates_and_env_identifiers(self) -> None:
        config = {
            "safe_op": {"api_key": "op://Hermes/item/credential"},
            "safe_template": {"token": "${TOKEN}"},
            "safe_env_name": {"service_account_token_env": "TOKEN_ENV"},
            "unsafe": {"password": "literal-password"},
        }
        self.assertEqual(self.audit.unsafe_secret_paths(config), ["unsafe.password"])

    def test_security_policy_flags_disabled_secret_redaction(self) -> None:
        config = {"security": {"redact_secrets": False}}
        findings = self.audit.config_policy_findings(config)
        self.assertTrue(any("redaction" in finding for finding in findings))

    def test_memory_scan_reports_literal_api_key(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            memory = root / "project/memory"
            memory.mkdir(parents=True)
            (memory / "safe.md").write_text("API key `op://Hermes/Service/credential`\n")
            (memory / "unsafe.md").write_text("API key `0123456789abcdef0123456789abcdef`\n")
            findings = self.audit.scan_memory_literals(root)
            self.assertEqual(len(findings), 1)
            self.assertIn("unsafe.md", findings[0])

    def test_findings_return_failure(self) -> None:
        output = io.StringIO()
        with redirect_stdout(output):
            result = self.audit.report(["redaction disabled"], [])
        self.assertEqual(result, 1)
        self.assertIn("redaction disabled", output.getvalue())


if __name__ == "__main__":
    unittest.main()
