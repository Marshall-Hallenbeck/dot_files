#!/bin/sh
'''exec' "$HOME/.local/share/codex-config-sync-venv/bin/python" "$0" "$@"
' '''
"""Monthly no-agent audit for the local Claude/Codex/Hermes configuration."""
import json
import re
import stat
import subprocess
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

import yaml

HOME = Path.home()
HERMES = HOME / ".local/bin/hermes"
RETAINED_MCPS = ("playwright", "grafana", "ssh", "context7", "garminconnect", "cua-win88")


def is_secret_key(key: str) -> bool:
    normalized = key.lower().replace("-", "_")
    return not normalized.endswith("_env") and any(
        part in normalized
        for part in ("password", "token", "secret", "api_key", "credential", "authorization", "cookie")
    )


def unsafe_secret_paths(value: Any, path: str = "") -> list[str]:
    findings: list[str] = []
    if isinstance(value, dict):
        for key, child in value.items():
            child_path = f"{path}.{key}" if path else str(key)
            if (
                is_secret_key(str(key))
                and isinstance(child, str)
                and child
                and not child.startswith(("op://", "${", "/", "[REDACTED]"))
            ):
                findings.append(child_path)
            findings.extend(unsafe_secret_paths(child, child_path))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            findings.extend(unsafe_secret_paths(child, f"{path}[{index}]"))
    return findings


def config_policy_findings(config: dict[str, Any]) -> list[str]:
    findings: list[str] = []
    security = config.get("security")
    if not isinstance(security, dict) or security.get("redact_secrets") is not True:
        findings.append("Hermes secret redaction is not enabled")
    return findings


def scan_memory_literals(root: Path) -> list[str]:
    findings: list[str] = []
    label = re.compile(r"(?i)(api key|token|secret|password|credential)")
    shape = re.compile(r"^[A-Za-z0-9_+\-=]{24,}$")
    for path in sorted(root.glob("**/memory/*.md")):
        for line_number, line in enumerate(path.read_text(errors="replace").splitlines(), 1):
            if not label.search(line):
                continue
            for value in re.findall(r"`([^`]+)`", line):
                if (
                    shape.fullmatch(value)
                    and "/" not in value
                    and not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", value)
                ):
                    findings.append(f"{path}:{line_number}")
            bare = re.search(r"(?i)password:\s*([^\s`]+)", line)
            if bare and bare.group(1) not in {"stored", "[REDACTED]"}:
                findings.append(f"{path}:{line_number}")
    return sorted(set(findings))


def run(command: list[str], timeout: int = 120) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, text=True, capture_output=True, timeout=timeout, check=False)


def report(findings: list[str], checks: list[str]) -> int:
    if findings:
        print("⚠️ Monthly AI configuration audit found issues")
        for finding in findings:
            print(f"- {finding}")
        return 1

    print("✅ Monthly AI configuration audit: healthy")
    for check in checks:
        print(f"- {check}")
    return 0


def main() -> int:
    findings: list[str] = []
    checks: list[str] = []
    config_path = HOME / ".hermes/config.yaml"
    try:
        loaded_config = yaml.safe_load(config_path.read_text())
    except (OSError, yaml.YAMLError) as error:
        print(f"🚨 Monthly AI configuration audit failed to parse config: {type(error).__name__}")
        return 1
    if not isinstance(loaded_config, dict):
        print("🚨 Monthly AI configuration audit failed: Hermes config must be a mapping")
        return 1
    config: dict[str, Any] = loaded_config

    unsafe = unsafe_secret_paths(config)
    if unsafe:
        findings.append(f"raw secret-like config values: {', '.join(unsafe)}")
    else:
        checks.append("no raw secret literals in Hermes config")
    findings.extend(config_policy_findings(config))

    env_keys = {
        line.split("=", 1)[0].strip()
        for line in (HOME / ".hermes/.env").read_text(errors="replace").splitlines()
        if "=" in line and not line.lstrip().startswith("#")
    }
    if "OP_SERVICE_ACCOUNT_TOKEN_READ_WRITE" in env_keys:
        findings.append("read-write 1Password token returned to ~/.hermes/.env")

    memory_findings = scan_memory_literals(HOME / ".claude/projects")
    if memory_findings:
        findings.append(f"Claude memory secret-like literals: {len(memory_findings)}")
    memory_modes = {
        stat.S_IMODE(path.stat().st_mode)
        for path in (HOME / ".claude/projects").glob("**/memory/*.md")
    }
    if any(mode != 0o600 for mode in memory_modes):
        findings.append(f"Claude memory has non-0600 modes: {sorted(oct(mode) for mode in memory_modes)}")
    else:
        checks.append("Claude memory is 0600 and has no high-confidence credential literals")

    config_check = run([str(HERMES), "config", "check"])
    if config_check.returncode:
        findings.append("hermes config check failed")

    try:
        with urllib.request.urlopen("http://127.0.0.1:9177/health", timeout=10) as response:
            health = json.load(response)
        if health.get("status") != "healthy" or health.get("database") != "connected":
            findings.append("Hindsight health/database state is not healthy")
        else:
            checks.append("Hindsight healthy and database connected")
    except (OSError, ValueError, urllib.error.URLError):
        findings.append("Hindsight health endpoint unavailable")

    failed_mcps: list[str] = []
    for server in RETAINED_MCPS:
        try:
            result = run([str(HERMES), "mcp", "test", server], timeout=150)
            if "✓ Connected" not in result.stdout or "✓ Tools discovered:" not in result.stdout:
                failed_mcps.append(server)
        except subprocess.TimeoutExpired:
            failed_mcps.append(f"{server}(timeout)")
    if failed_mcps:
        findings.append(f"retained MCP failures: {', '.join(failed_mcps)}")
    else:
        checks.append(f"all {len(RETAINED_MCPS)} retained Hermes MCPs connected")

    sync = run([str(HOME / ".local/bin/agent-sync"), "check", "--all", "--no-restart", "--quiet"])
    if sync.returncode:
        findings.append("Ruler/agent-sync check reported drift")
    else:
        checks.append("Ruler/agent-sync outputs current")

    timer = run(["systemctl", "--user", "is-active", "agent-sync.timer"])
    if timer.returncode:
        findings.append("agent-sync.timer is not active")
    legacy_timer = run(["systemctl", "--user", "is-active", "dotfiles-update.timer"])
    if legacy_timer.returncode == 0:
        findings.append("redundant dotfiles-update.timer is active again")

    claude_state = json.loads((HOME / ".claude.json").read_text())
    if "zetsu_lab" in claude_state.get("mcpServers", {}):
        findings.append("unused Claude zetsu_lab MCP returned")
    claude_settings = json.loads((HOME / ".claude/settings.json").read_text())
    if claude_settings.get("enabledPlugins", {}).get("context7@claude-plugins-official"):
        findings.append("duplicate local Claude Context7 plugin returned")

    prompt = run([str(HERMES), "prompt-size", "--platform", "cli", "--json"])
    if prompt.returncode:
        findings.append("hermes prompt-size failed")
    else:
        try:
            budget = json.loads(prompt.stdout)
            if budget["tools"]["count"] > 40:
                findings.append(f"direct Hermes tool count grew to {budget['tools']['count']}")
            if budget["skills_index"]["chars"] > 14_000:
                findings.append(f"Hermes skills index grew to {budget['skills_index']['chars']} chars")
        except (KeyError, TypeError, ValueError):
            findings.append("could not parse Hermes prompt-size output")

    return report(findings, checks)


if __name__ == "__main__":
    raise SystemExit(main())
