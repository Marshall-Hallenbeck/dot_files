#!/usr/bin/env python3
"""Silent no-agent watchdog for abnormal Codex app-server multiplication/RSS."""
from __future__ import annotations

import argparse
from pathlib import Path
from typing import TypedDict

RSS_LIMIT_KIB = 2 * 1024 * 1024
PROCESS_LIMIT = 6


class ProcessRecord(TypedDict):
    pid: int
    rss_kib: int
    primary: bool
    proxy: bool


def collect_processes(proc_root: Path = Path("/proc")) -> list[ProcessRecord]:
    processes: list[ProcessRecord] = []
    for entry in proc_root.iterdir():
        if not entry.name.isdigit():
            continue
        try:
            argv = [
                part.decode(errors="replace")
                for part in (entry / "cmdline").read_bytes().split(b"\0")
                if part
            ]
            joined = " ".join(argv).lower()
            if "app-server" not in joined or "codex-app-server-watchdog" in joined:
                continue
            rss_kib = 0
            for line in (entry / "status").read_text(errors="replace").splitlines():
                if line.startswith("VmRSS:"):
                    rss_kib = int(line.split()[1])
                    break
            processes.append(
                {
                    "pid": int(entry.name),
                    "rss_kib": rss_kib,
                    "primary": "--remote-control" in argv and "proxy" not in argv,
                    "proxy": "proxy" in argv,
                }
            )
        except (FileNotFoundError, PermissionError, ProcessLookupError, ValueError):
            continue
    return processes


def evaluate(processes: list[ProcessRecord]) -> list[str]:
    findings: list[str] = []
    primary_count = sum(bool(process["primary"]) for process in processes)
    total_rss_kib = sum(process["rss_kib"] for process in processes)
    if primary_count > 1:
        findings.append(f"duplicate primary app-server processes: {primary_count}")
    if len(processes) > PROCESS_LIMIT:
        findings.append(f"app-server process count is {len(processes)} (limit {PROCESS_LIMIT})")
    if total_rss_kib > RSS_LIMIT_KIB:
        findings.append(
            f"aggregate app-server RSS is {total_rss_kib / 1024:.0f} MiB "
            f"(limit {RSS_LIMIT_KIB / 1024:.0f} MiB)"
        )
    return findings


def report(findings: list[str], processes: list[ProcessRecord], verbose: bool) -> int:
    if findings:
        print("🚨 Codex app-server watchdog")
        for finding in findings:
            print(f"- {finding}")
        print("No process was killed. Inspect active Codex/Remote Control sessions before remediation.")
        return 1

    if verbose:
        rss_mib = sum(process["rss_kib"] for process in processes) / 1024
        print(f"Codex app-server watchdog healthy: processes={len(processes)} rss={rss_mib:.0f} MiB")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()
    processes = collect_processes()
    findings = evaluate(processes)
    return report(findings, processes, args.verbose)


if __name__ == "__main__":
    raise SystemExit(main())
