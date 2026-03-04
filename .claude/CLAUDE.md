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
  - `agents/` — Custom agents (unit-test-writer)
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

- Plugins are declared in `settings.json` (`enabledPlugins`) but NOT yet installed by the script — `claude plugin install` commands are still needed.
- `settings.local.json` contains machine-specific permissions — don't put global settings there.
- Shell scripts use `set -euo pipefail` — any unhandled error exits immediately.
- The `global-CLAUDE.md` file is deployed as `~/.claude/CLAUDE.md` — this file (`CLAUDE.md`) is project-specific only.
