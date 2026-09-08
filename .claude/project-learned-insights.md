# Project Learned Insights

## Git config deployment

- `~/.gitconfig` must be a real file that includes `~/.dot_files/.gitconfig`, not a symlink to it. `install_git_wrapper()` (`install_environment.sh:80`) creates that wrapper. Hosts installed before that function existed still carry the old symlink, so any tool writing to `--global` (for example `gh auth setup-git`) edits the tracked repo file and makes the repo dirty.
- The repo `.gitconfig` includes `~/.gitconfig.local` as its last directive. Keep that include last: Git applies included values at the point of inclusion, so an include placed before a section cannot override that section.
- `git config --global --list` does not follow includes. Use `git config --list --show-origin` to see the fully expanded chain and which file supplies each value.

## Docs tracking

- `docs/` is deliberately gitignored (`.gitignore:20`). Shareable docs (plans, agents) are force-added with `git add -f`; a new doc under `docs/` stays untracked until you `-f` it.

## Hook deployment

- A hook file added to `.claude/hooks/` is not live until its per-file symlink exists in `~/.claude/hooks/` (created by `install_environment.sh`). Until then every matching tool call reports "not found" because `settings.json` invokes `$HOME/.claude/hooks/<file>`.
