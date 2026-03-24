# dot_files — Development Environment Bootstrap

Personal dotfiles and Claude Code config repo. Bootstraps a complete dev environment on any Debian-based system.

## Commands

```bash
# Run tests (requires Docker)
make test-ubuntu          # Test on Ubuntu 24.04
make test-debian          # Test on Debian Bookworm
make test-kali            # Test on Kali Linux
make test-all             # All three distros
make test-security-kali   # Security tools on Kali
make test-clean           # Remove test images

# Lint shell scripts
shellcheck install_environment.sh security.sh
```

## Architecture

- `install_environment.sh` — Main bootstrap: clones repo to `~/.dot_files`, installs packages/tools, symlinks config files
- `security.sh` — Security/pentest tool installer (Impacket, NetExec, Sliver, Burp, etc.)
- `scripts/dotfiles` — Helper CLI for promote/status/pull operations
- `.claude/` — Claude Code global config (symlinked to `~/.claude/` by install script)
  - `global-CLAUDE.md` — Source for `~/.claude/CLAUDE.md` (global instructions for all projects)
  - `skills/` — Custom slash commands (/commit, /review, /fix-tests, etc.)
  - `rules/` — Rule files (verification, coding, git, error-handling, docker, web-dev)
  - `agents/` — Custom agents (test-writer, code-reviewer, debugger)
  - `hookify.*.local.md` — Hookify enforcement rules
- `test/` — Docker-based verification (Dockerfile + verify scripts)

## Key Patterns

- `link_file()` creates symlinks from `~/.dot_files/` to destinations, backing up existing non-symlink files. Safe to re-run.
- Per-host overrides via `.local` files (`.zshrc.local`, `.bash_aliases.local`, etc.) — gitignored, never symlinked.
- `dotfiles promote <path>` moves a local file into the repo and symlinks it back.
- Community skills are installed via `npx skills add` (not vendored).
- Tests use a parameterized Dockerfile with `BASE_IMAGE` build arg for multi-distro support.
- The install script MUST be idempotent — every block should check before acting.

## Gotchas

- Never create `-team`, `-max`, or model-variant copies of skills. Subagents inherit the parent session's model and effort level. Variant skills drift silently from the canonical version.
- Agent frontmatter `model: haiku` (or any explicit model) overrides session inheritance. Omit the `model` field to inherit from the session.
- `/full-review` phases are numbered and cross-referenced. When inserting/removing a phase, update ALL phase number references (forward refs in earlier phases, "Phases 1-N" in final review, output template).
- `/full-review` composes: `/simplify`, `/review`, `/security-review`, `/overcautious-check`, `/run-quality-gate`, `/fix-tests`, `/test-coverage-review`, `/summarize-changes`. When adding behavior, add it to the composed skill — not to `/full-review` directly.
- Multiple skills use the same test runner detection table (fix-tests, write-tests, run-unit-tests, review). Keep them in sync when adding runners.
- Docker tests need `.dockerignore` (excludes `.git`) and `COPY --chown=testuser:testuser` in the Dockerfile — `git init` inside the container fails without correct ownership.
- Plugins are declared in `settings.json` (`enabledPlugins`) but NOT yet installed by the script — `claude plugin install` commands are still needed.
- `settings.local.json` contains machine-specific permissions — don't put global settings there.
- Shell scripts use `set -euo pipefail` — any unhandled error exits immediately.
- The `global-CLAUDE.md` file is deployed as `~/.claude/CLAUDE.md` — this file (`CLAUDE.md`) is project-specific only.
