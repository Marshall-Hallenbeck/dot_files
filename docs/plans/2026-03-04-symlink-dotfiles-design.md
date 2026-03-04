# Design: Clone + Symlink Dotfiles

**Date:** 2026-03-04
**Status:** Approved

## Problem

The install script downloads individual files from GitHub raw URLs and copies them to their destinations. Changes to the repo require re-running the install script to propagate. There's no way to keep per-host overrides separate from the shared config.

## Solution

Clone the repo to `$HOME/.dot_files`, symlink managed files to their destinations, and support `.local` override files for per-host customization.

## Architecture

### Install Flow

1. Clone repo to `$HOME/.dot_files` (or `git pull` if already exists)
2. Install system packages (apt)
3. Install tools (oh-my-zsh, nvm, node, atuin, gh, claude)
4. Back up existing non-symlink config files
5. Create symlinks from repo → destination paths
6. Install community skills (npx-based, not symlinked)

### File Mapping

| Repo path | Symlink target |
|---|---|
| `.zshrc` | `~/.zshrc` |
| `.bash_aliases` | `~/.bash_aliases` |
| `.vimrc` | `~/.vimrc` |
| `.gitconfig` | `~/.gitconfig` |
| `.tmux.conf` | `~/.tmux.conf` |
| `.tmux/copy-to-clipboard.sh` | `~/.tmux/copy-to-clipboard.sh` |
| `.claude/CLAUDE.md` | `~/.claude/CLAUDE.md` |
| `.claude/hooks.json` | `~/.claude/hooks.json` |
| `.claude/settings.json` | `~/.claude/settings.json` |
| `.claude/settings.local.json` | `~/.claude/settings.local.json` |
| `.claude/statusline.sh` | `~/.claude/statusline.sh` |
| `.claude/rules/*` | `~/.claude/rules/*` (individual files) |
| `.claude/skills/<managed>/*` | `~/.claude/skills/<managed>/*` (individual files) |
| `.claude/agents/*` | `~/.claude/agents/*` (individual files) |
| `.claude/hookify.*.local.md` | `~/.claude/hookify.*.local.md` (individual files) |

### .local Override Pattern

Each config file sources a `.local` counterpart at the end if it exists:

- `.zshrc` → `[ -f ~/.zshrc.local ] && source ~/.zshrc.local`
- `.bash_aliases` → `[ -f ~/.bash_aliases.local ] && source ~/.bash_aliases.local`
- `.tmux.conf` → `if-shell "test -f ~/.tmux.conf.local" "source-file ~/.tmux.conf.local"`
- `.gitconfig` → `[include] path = ~/.gitconfig.local`

These `.local` files are NOT in the repo, not symlinked, and gitignored. They hold per-host paths, secrets, custom aliases, etc.

### Node Path Fix

Remove the hardcoded node version from `.zshrc` PATH. The lazy-loading nvm wrappers already handle `node`/`npm`/`npx` on first use. No `sed` patching needed.

### `dotfiles` Helper Script

Located at `$HOME/.dot_files/scripts/dotfiles`, added to PATH or aliased.

Subcommands:
- `dotfiles promote <path>` — Move a local file into the repo, create symlink back, stage the change
- `dotfiles status` — Show which managed files are properly symlinked vs out of sync
- `dotfiles pull` — Run `git -C ~/.dot_files pull`

The global CLAUDE.md will document this tool so Claude Code uses `dotfiles promote` when adding new global configs.

## Changes Required

1. **install_environment.sh** — Replace `install_file()` with `link_file()`, add repo clone logic, remove `sed` patching, remove raw URL downloads
2. **.zshrc** — Remove hardcoded node path from PATH, add `.zshrc.local` sourcing at bottom
3. **.bash_aliases** — Add `.bash_aliases.local` sourcing at bottom
4. **.tmux.conf** — Add `.tmux.conf.local` sourcing at bottom
5. **.gitconfig** — Add `[include]` for `.gitconfig.local`
6. **scripts/dotfiles** — New helper script for promote/status/pull
7. **.claude/CLAUDE.md** — Document the dotfiles helper and symlink architecture
8. **.gitignore** — Add `*.local` patterns (the override files, not the hookify ones)
