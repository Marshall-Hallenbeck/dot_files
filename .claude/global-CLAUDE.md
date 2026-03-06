# Global Claude Code Instructions

These principles apply to ALL projects. Project-specific CLAUDE.md files override or extend these.

## Environment & Preferences

- Primary OS: Kali Linux (Debian-based)
- Shell: zsh with oh-my-zsh
- Primary use cases: security tooling, full-stack web development, infrastructure automation
- Shell scripts: bash (`#!/bin/bash` with `set -euo pipefail`)

## Git Operations

When resolving merge conflicts, ALWAYS preserve upstream/remote changes unless explicitly told otherwise. Never silently drop incoming changes.

## Debugging

When investigating issues, verify the actual infrastructure routing (e.g., nginx, reverse proxies) BEFORE assuming the problem is in application code. Check how URLs are routed at the infrastructure level first.

When testing or debugging, focus on the actual reported symptom. Do not try random exploratory fixes — diagnose the root cause first, then apply a single targeted fix.

## Asking Questions

When anything is ambiguous, unclear, or open to interpretation, use AskUserQuestion to clarify BEFORE proceeding. Do not guess, assume, or pick a default — ask. This applies to:

- Ambiguous requirements or feature scope
- Unclear implementation approach (multiple reasonable options)
- Uncertainty about intended behavior or edge cases
- File placement, naming, or architectural decisions that aren't obvious
- Anything where a wrong assumption would waste effort or produce the wrong result

Asking a quick question is always preferable to guessing wrong. The user expects to be consulted.

## Planning & Approach

Before creating any plan, complete a codebase grounding phase. Do not skip this.

1. **Discovery** — Use Grep and Glob to find all files relevant to the area. List every file found.
2. **Fact extraction** — For each relevant file, read it and extract: exported functions/types with exact signatures, key business logic (status transitions, validation rules, enum values), existing abstractions and helpers, and current test coverage.
3. **Fact document** — Create a structured summary with sections: Existing Types & Interfaces, Current Behavior (with `file:line` citations), Existing Abstractions Available for Reuse, Current Test Coverage & Gaps. Present this to the user first.
4. **Plan with citations** — After user confirms the fact document, create the implementation plan. Every assertion must include a `[file:line]` citation. Flag any assumption that cannot be verified with `UNVERIFIED`.
5. **Diff preview** — For each planned change, show the specific before/after for affected lines so the user can validate behavioral correctness.

Stay focused on the stated goal. If you think work should extend beyond the original request, or if the goal is ambiguous, ask before acting — do not pursue tangential fixes, refactors, or improvements unprompted.

## Code Style

- Use `.yml` extension (not `.yaml`) for YAML files unless the project already uses `.yaml`.

## Error Handling

Hard-fail error handling only. No silent fallbacks, no swallowed errors, no try/catch that returns default values. Errors must propagate or be explicitly logged and re-thrown.

## Testing

Always run the full test suite after multi-file changes and before committing. Verify 0 failures. If tests fail, fix them before proceeding — do not commit with known failures.

## Claude Code Configuration

When creating skills or plugins, check whether the context is global (`~/.claude/`) vs project-level (`.claude/`) and place files accordingly. Ask if unsure.

## Simplicity

Always prefer simple, minimal solutions first. Avoid over-engineering with unnecessary features like color output, complex abstractions, or multi-layered architectures unless explicitly requested. If you believe a more complex approach is genuinely needed, explain why BEFORE implementing it and let me decide.

## Safety / Dangerous Operations

Never modify shell config files (`.zshrc`, `.bashrc`, `.zshenv`) with `sed`. Use targeted `echo`/append or manual instructions instead. Always back up before any changes.

## Docker / Deployment

After modifying any code in Docker-deployed services, consider if a rebuild or restart is needed before testing. Check if the code is mounted in the container, if hot-reload is enabled, or if the change is system/Docker configuration requiring a rebuild. Don't rebuild out of caution or habit — ensure a rebuild is necessary.

## Dotfiles Management

This host's config files are symlinked from `~/.dot_files` (a clone of the dot_files repo).

### Adding New Global Configs

When creating new rules, skills, agents, or config files that should apply to ALL hosts:
1. Create the file directly in `~/.dot_files/` at the correct relative path
2. The install script will symlink it on other hosts next time it runs

### Promoting a Local File to Global

If a config file already exists locally and should become global:
```
dotfiles promote ~/.claude/rules/my-new-rule.md
```
This moves the file into the repo and creates a symlink back.

### Per-Host Overrides

For host-specific configuration (custom paths, secrets, local aliases), use `.local` files:
- `~/.zshrc.local` — sourced at the end of `.zshrc`
- `~/.bash_aliases.local` — sourced at the end of `.bash_aliases`
- `~/.tmux.conf.local` — sourced at the end of `.tmux.conf`
- `~/.gitconfig.local` — included at the end of `.gitconfig`

These files are gitignored and never symlinked.

### Checking Status

```
dotfiles status   # show symlink health
dotfiles pull     # update from remote
```
