#!/usr/bin/env python3
"""Verify that Codex can run the global commit-reference hooks."""

from __future__ import annotations

import json
import os
import select
import subprocess
import sys
import time
from typing import TextIO

EXPECTED_COMMANDS = {
    "$HOME/.claude/hooks/validate-commit-references.sh",
    "$HOME/.claude/hooks/validate-commit-references.sh --install",
}
TRUSTED_STATUSES = {"managed", "trusted"}
RESPONSE_TIMEOUT_SECONDS = 10


class HookTrustError(RuntimeError):
    """Codex could not report its hook state."""


def send(stream: TextIO, message: dict[str, object]) -> None:
    stream.write(f"{json.dumps(message)}\n")
    stream.flush()


def read_response(
    stream: TextIO,
    request_id: int,
    deadline: float,
) -> dict[str, object]:
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise HookTrustError("Codex did not report hook trust before the timeout.")
        readable, _, _ = select.select([stream], [], [], remaining)
        if not readable:
            raise HookTrustError("Codex did not report hook trust before the timeout.")
        line = stream.readline()
        if not line:
            raise HookTrustError("Codex app-server stopped before it reported hook trust.")
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            continue
        if message.get("id") == request_id:
            if "error" in message:
                raise HookTrustError(f"Codex app-server error: {message['error']}")
            return message


def query_hooks(cwd: str) -> list[dict[str, object]]:
    process = subprocess.Popen(
        ["codex", "app-server"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    if process.stdin is None or process.stdout is None:
        process.kill()
        raise HookTrustError("Codex app-server streams are not available.")

    deadline = time.monotonic() + RESPONSE_TIMEOUT_SECONDS
    try:
        send(
            process.stdin,
            {
                "method": "initialize",
                "id": 0,
                "params": {
                    "clientInfo": {
                        "name": "dotfiles_installer",
                        "title": "Dotfiles Installer",
                        "version": "1",
                    }
                },
            },
        )
        read_response(process.stdout, 0, deadline)
        send(process.stdin, {"method": "initialized", "params": {}})
        send(
            process.stdin,
            {
                "method": "hooks/list",
                "id": 1,
                "params": {"cwds": [cwd]},
            },
        )
        response = read_response(process.stdout, 1, deadline)
    finally:
        process.terminate()
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()

    result = response.get("result")
    if not isinstance(result, dict):
        raise HookTrustError("Codex returned an invalid hook response.")
    data = result.get("data")
    if not isinstance(data, list):
        raise HookTrustError("Codex returned no hook data.")

    hooks: list[dict[str, object]] = []
    for entry in data:
        if not isinstance(entry, dict):
            continue
        errors = entry.get("errors")
        if isinstance(errors, list) and errors:
            raise HookTrustError(f"Codex hook discovery failed: {errors}")
        entry_hooks = entry.get("hooks")
        if isinstance(entry_hooks, list):
            hooks.extend(hook for hook in entry_hooks if isinstance(hook, dict))
    return hooks


def main() -> int:
    cwd = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.getcwd())
    try:
        hooks = query_hooks(cwd)
    except (HookTrustError, OSError) as error:
        print(f"Codex hook trust check failed: {error}", file=sys.stderr)
        return 2

    trusted_commands = {
        hook.get("command")
        for hook in hooks
        if hook.get("source") == "user"
        and hook.get("enabled") is True
        and hook.get("trustStatus") in TRUSTED_STATUSES
    }
    missing = EXPECTED_COMMANDS - trusted_commands
    if not missing:
        return 0

    print("Codex commit-reference hooks require trust review:", file=sys.stderr)
    for command in sorted(missing):
        print(f"  {command}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
