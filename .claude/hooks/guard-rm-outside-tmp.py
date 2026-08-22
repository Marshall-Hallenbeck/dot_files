#!/usr/bin/env python3
import json
import os
import pathlib
import shlex
import sys

TMP_ROOT = pathlib.Path("/tmp")
SHELL_OPERATOR_CHARS = frozenset(";&|<>()")
SHELL_EXPANSION_CHARS = frozenset("$`{}*?[]")
ALLOWED_RM_EXECUTABLES = frozenset(("rm", "/usr/bin/rm"))


def emit(decision: str, reason: str) -> None:
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": decision,
            "permissionDecisionReason": reason,
        }
    }))


def ask(reason: str) -> int:
    emit("ask", reason)
    return 0


def main() -> int:
    payload = json.loads(sys.stdin.read())
    command = payload["tool_input"]["command"]
    lexer = shlex.shlex(command, posix=True, punctuation_chars=True)
    lexer.whitespace_split = True
    lexer.commenters = ""
    tokens = list(lexer)
    if not tokens:
        return 0

    rm_indexes = [
        index for index, token in enumerate(tokens)
        if pathlib.Path(token).name == "rm"
    ]
    if not rm_indexes:
        return 0
    if rm_indexes != [0]:
        return ask("The rm command is not a direct command.")
    if tokens[0] not in ALLOWED_RM_EXECUTABLES:
        return ask("The rm executable is not allowed.")
    if "\n" in command or "\r" in command:
        return ask("The rm command contains a newline.")
    if any(token and set(token) <= SHELL_OPERATOR_CHARS for token in tokens):
        return ask("The rm command contains a shell operator.")
    if any(set(token) & SHELL_EXPANSION_CHARS for token in tokens[1:]):
        return ask("The rm command contains shell expansion syntax.")

    targets: list[str] = []
    options = True
    for token in tokens[1:]:
        if options and token == "--":
            options = False
        elif options and token.startswith("-") and token != "-":
            continue
        else:
            targets.append(token)
    if not targets:
        return ask("The rm command has no target.")

    cwd = pathlib.Path(payload["cwd"]).resolve(strict=False)
    for target in targets:
        expanded = pathlib.Path(os.path.expanduser(target))
        if ".." in expanded.parts:
            return ask("An rm target contains a parent-directory component.")
        candidate = expanded if expanded.is_absolute() else cwd / expanded
        candidate = pathlib.Path(os.path.normpath(candidate))
        if candidate == TMP_ROOT or TMP_ROOT not in candidate.parents:
            return ask("An rm target is not below /tmp.")
        resolved_parent = candidate.parent.resolve(strict=False)
        if resolved_parent != TMP_ROOT and TMP_ROOT not in resolved_parent.parents:
            return ask("An rm target has a parent outside /tmp.")

    emit("allow", "Every rm target stays below /tmp.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
