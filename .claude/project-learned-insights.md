# Project Learned Insights

## Git config deployment

- `~/.gitconfig` must be a real file that includes `~/.dot_files/.gitconfig`, not a symlink to it. `install_git_wrapper()` (`install_environment.sh:80`) creates that wrapper. Hosts installed before that function existed still carry the old symlink, so any tool writing to `--global` (for example `gh auth setup-git`) edits the tracked repo file and makes the repo dirty.
- The repo `.gitconfig` includes `~/.gitconfig.local` as its last directive. Keep that include last: Git applies included values at the point of inclusion, so an include placed before a section cannot override that section.
- `git config --global --list` does not follow includes. Use `git config --list --show-origin` to see the fully expanded chain and which file supplies each value.

## dotfiles CLI

- `AI_REMOTE_CONTROL_PATHS` in `scripts/dotfiles` is hand-maintained and read by both `cmd_status` and `cmd_feature_enable`. A tracked Remote Control file left out of it is reported MISSING on hosts that never enabled the feature, and `feature-enable` never deploys it. `test/verify-dotfiles-cli.sh` now enforces set-equality against `git ls-files .config/systemd .local`.
- `~/.codex/config.toml` is live per-host state that Codex and `codex-config-sync.py` rewrite in place; it is never symlinked from the repo. `codex-config-sync.py:351` also writes `<project-root>/.codex/config.toml`, so running it inside dot_files creates a repo-side file.

## Docs tracking

- `docs/` is deliberately gitignored (`.gitignore:20`). Shareable docs (plans, agents) are force-added with `git add -f`; a new doc under `docs/` stays untracked until you `-f` it.

## Hook deployment

- A hook file added to `.claude/hooks/` is not live until its per-file symlink exists in `~/.claude/hooks/` (created by `install_environment.sh`). Until then every matching tool call reports "not found" because `settings.json` invokes `$HOME/.claude/hooks/<file>`.
