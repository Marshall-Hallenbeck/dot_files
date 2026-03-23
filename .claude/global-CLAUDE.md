# Global Claude Code Instructions

These principles apply to ALL projects. Project-specific CLAUDE.md files override or extend these.

## Environment & Preferences

- Primary OS: Ubuntu or Kali Linux (Debian-based)
- Shell: zsh with oh-my-zsh
- Primary use cases: security tooling, full-stack web development, infrastructure automation
- Shell scripts: bash (`#!/bin/bash` with `set -euo pipefail`)

## Git Operations

When resolving merge conflicts, ALWAYS preserve upstream/remote changes unless explicitly told otherwise. Never silently drop incoming changes.

## Debugging

When investigating issues, verify the actual infrastructure routing (e.g., Docker containers and networking, nginx, reverse proxies) BEFORE assuming the problem is in application code. Check how URLs are routed at the infrastructure level first.

When testing or debugging, focus on the actual reported symptom. Do not try random exploratory fixes — diagnose the root cause first, then apply a single targeted fix.

## External Limitations

If a task is blocked by external limitations (third-party APIs, minified code, CAPTCHAs), stop after 2 failed attempts, explain why it's blocked, and propose alternative approaches.

## Execution Style

Always execute commands directly. Never provide manual steps for the user to run unless the command is destructive, requires credentials you don't have, or affects systems outside the current machine. Do the work — don't describe the work.

## Asking Questions

When anything is ambiguous, unclear, or open to interpretation, use AskUserQuestion to clarify BEFORE proceeding. Do not guess, assume, or pick a default — ask. This applies everywhere: code, architecture, agent configuration, skill design, and operational decisions. Specific examples:

- Ambiguous requirements or feature scope
- Unclear implementation approach (multiple reasonable options)
- Uncertainty about intended behavior or edge cases
- File placement, naming, or architectural decisions that aren't obvious
- Whether to add defensive checks, guards, or safety measures
- Whether to fix source code vs test assertions
- Anything where a wrong assumption would waste effort or produce the wrong result

Asking a quick question is always preferable to guessing wrong. The user expects to be consulted. Never silently give up, silently pick a default, or make "reasonable assumptions" — ask.

## Planning & Approach

For any task involving more than 2 file changes: outline your approach in numbered steps first. Wait for user approval before executing. If unsure between approaches, list the options with tradeoffs.

Before creating any plan, complete a codebase grounding phase. Do not skip this.

1. **Discovery** — Use Grep and Glob to find all files relevant to the area. List every file found.
2. **Fact extraction** — For each relevant file, read it and extract: exported functions/types with exact signatures, key business logic (status transitions, validation rules, enum values), existing abstractions and helpers, and current test coverage.
3. **Fact document** — Create a structured summary with sections: Existing Types & Interfaces, Current Behavior (with `file:line` citations), Existing Abstractions Available for Reuse, Current Test Coverage & Gaps. Present this to the user first.
4. **Plan with citations** — After user confirms the fact document, create the implementation plan. Every assertion must include a `[file:line]` citation. Flag any assumption that cannot be verified with `UNVERIFIED`.
5. **Diff preview** — For each planned change, show the specific before/after for affected lines so the user can validate behavioral correctness.

Stay focused on the stated goal. If you think work should extend beyond the original request, or if the goal is ambiguous, ask before acting — do not pursue tangential fixes, refactors, or improvements unprompted.

## Code Style

- Use `.yml` extension (not `.yaml`) for YAML files unless the project already uses `.yaml`.
- Use dot notation for attribute access in Python. Do not use `getattr`/`setattr` patterns or `pyright: ignore`/`type: ignore` comments unless absolutely unavoidable for third-party library compatibility.
- For Python, use f-strings for string interpolation. Do not use `str.format()` or concatenation.

## Testing

When developing an API or web application, there should always be the most simple checks that each endpoint or page is responding at a basic level. For example, if you create a new API route, add a smoke test that hits the route and checks for a 200 response. This ensures the route is wired up correctly before adding more complex tests. Loading the homepage of a web app and checking for a 200 with no console errors is another example of a simple smoke test. For databases, ensure there is a test that can connect to the database and perform a simple query. These basic checks catch fundamental issues early.

Always run the full test suite after multi-file changes and before committing. Verify 0 failures. If tests fail, fix them before proceeding — do not commit with known failures.

## Static Analysis

For Python, run both Ruff and Pyright as part of the quality gate. Both must pass clean before claiming completion:
- `ruff check src/ tests/` — linting and style
- `pyright` (or project-specific type checker) — type checking
For other languages, use the applicable alternatives, such as tsx, etc.

Fix issues from both tools, not just one. If a project's CLAUDE.md specifies different commands (e.g., `uv run ruff`, `uv run pyright`), use those.

## Claude Code Configuration

When creating skills or plugins, check whether the context is global (`~/.claude/`) vs project-level (`.claude/`) and place files accordingly. Ask if unsure.

## Simplicity

Always prefer simple, minimal solutions first. Avoid over-engineering with unnecessary features like color output, complex abstractions, or multi-layered architectures unless explicitly requested. If you believe a more complex approach is genuinely needed, explain why BEFORE implementing it and let me decide.

## Safety / Dangerous Operations

Never modify shell config files (`.zshrc`, `.bashrc`, `.zshenv`) with `sed`. Use targeted `echo`/append or manual instructions instead. Always back up before any changes.

## Docker / Deployment

After modifying any code in Docker-deployed services, consider if a rebuild or restart is needed before testing. Check if the code is mounted in the container, if hot-reload is enabled, or if the change is system/Docker configuration requiring a rebuild. Don't rebuild out of caution or habit — ensure a rebuild is necessary.

## Learned Insights

Cross-project insights are accumulated in `~/.claude/global-learned-insights.md`. Read this file at the start of each session to benefit from prior observations. Per-project insights are stored in `<project-root>/.claude/project-learned-insights.md` when present.

## Dotfiles Management

Config files are symlinked from `~/.dot_files` (a clone of the dot_files repo). Global configs go in `~/.dot_files/` at the correct relative path. Promote local files with `dotfiles promote <path>`. Per-host overrides use `.local` files (`.zshrc.local`, `.gitconfig.local`, etc.).
