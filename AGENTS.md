# dot_files — Development Environment Bootstrap

Personal dotfiles and Claude Code / Codex config repo. Bootstraps a complete dev environment on any Debian-based system.

## Commands

```bash
# Run tests
make test-hooks           # Hook regression tests (fast, no Docker)
make test-ubuntu          # Test on Ubuntu 24.04 (requires Docker)
make test-debian          # Test on Debian Bookworm
make test-kali            # Test on Kali Linux
make test-all             # Hooks + all three distros
make test-security-kali   # Security tools on Kali
make test-clean           # Remove test images

# Lint shell scripts
shellcheck install_environment.sh security.sh
```

## Architecture

- `install_environment.sh` — Main bootstrap: clones repo to `~/.dot_files`, installs packages/tools, symlinks config files
- `security.sh` — Security/pentest tool installer (Impacket, NetExec, Sliver, Burp, etc.)
- `scripts/dotfiles` — Helper CLI for promote/status/pull operations
- `global-AGENTS.md` — Global instructions for all projects. Linked to both `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md`; edit only this file.
- `AGENTS.md` — This repo's project instructions (Claude Code and Codex both read it).
- `.claude/` — Claude Code global config (symlinked to `~/.claude/` by install script)
  - `skills/` — Custom slash commands (/commit, /review, /fix-tests, etc.)
  - `agents/` — Custom agents (test-writer, code-reviewer, debugger)
  - `commands/` — Custom slash commands (/preflight, /review-and-commit)
  - `hooks/` — Hook scripts (per-file symlinked); hook config lives in `settings.json`
- `.local/libexec/codex-config-sync.py` — Mirrors Claude skills, hooks, plugin flags and managed settings into Codex. Runs from `agent-sync.timer` and before `codex-app-server.service` starts.
- `test/` — Docker-based verification (Dockerfile + verify scripts)

## Key Patterns

- `skills/` is symlinked as a whole directory; `agents/` and `hooks/` use per-file symlinks. `~/.claude/rules/` holds only host-local files. `dotfiles status` excludes directory-level symlinks from its file checks.
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
- `global-AGENTS.md` is deployed as `~/.claude/CLAUDE.md` because Claude Code reads no user-level `AGENTS.md`. This file (`AGENTS.md`) is project-specific only.
- Claude Code reads project `AGENTS.md` only from 2.1.277; `settings.json` pins `autoUpdatesChannel` to `latest` for that reason.
- `docs/` is gitignored (`.gitignore:20`), so `git status` never lists new files under `docs/agents/` or `docs/adr/`. Add them with `git add -f`.

## Agent skills

### Issue tracker

Issues live in GitHub Issues on `Marshall-Hallenbeck/dot_files`, via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
