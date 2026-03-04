# Global Claude Code Instructions

These principles apply to ALL projects. Project-specific CLAUDE.md files override or extend these.

## Environment & Preferences

- Primary OS: Kali Linux (Debian-based)
- Shell: zsh with oh-my-zsh
- Primary use cases: security tooling, full-stack web development, infrastructure automation
- Shell scripts: bash (`#!/bin/bash` with `set -euo pipefail`)

## Debugging

When investigating issues, verify the actual infrastructure routing (e.g., nginx, reverse proxies) BEFORE assuming the problem is in application code. Check how URLs are routed at the infrastructure level first.

## Planning & Refactoring

When creating plans or reviewing code, do NOT assume codebase state — always read the actual files to verify existing abstractions, function signatures, and current behavior before proposing changes. Never guess at what exists.

## Simplicity

Always prefer simple, minimal solutions first. Avoid over-engineering with unnecessary features like color output, complex abstractions, or multi-layered architectures unless explicitly requested. If you believe a more complex approach is genuinely needed, explain why BEFORE implementing it and let me decide.

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
