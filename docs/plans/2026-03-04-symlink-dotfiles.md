# Symlink Dotfiles Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Refactor install_environment.sh to clone this repo and symlink config files, so changes to the repo propagate instantly to all hosts.

**Architecture:** Clone repo to `$HOME/.dot_files`, symlink each managed file to its destination. Per-host overrides via `.local` files sourced at the end of each config. A `dotfiles` helper script manages promote/status/pull operations.

**Tech Stack:** Bash, git, symlinks, Docker (testing)

---

### Task 1: Create .gitignore

**Files:**
- Create: `.gitignore`

**Step 1: Create the file**

```gitignore
# Per-host override files (created locally, never committed)
*.local
# Re-include files that happen to have .local in their name but ARE managed
!.claude/hookify.*.local.md
!.claude/settings.local.json
```

**Step 2: Verify**

Run: `git status`
Expected: `.gitignore` shows as untracked. No existing tracked files are hidden.

**Step 3: Commit**

```bash
git add .gitignore
git commit -m "chore: add .gitignore for per-host .local override files"
```

---

### Task 2: Add .local override sourcing to config files

These changes are independent of the install mechanism and won't break anything.

**Files:**
- Modify: `.zshrc` (add sourcing at bottom, before `#zprof`)
- Modify: `.bash_aliases` (add sourcing at bottom)
- Modify: `.tmux.conf` (add sourcing before TPM init)
- Modify: `.gitconfig` (add `[include]` directive)

**Step 1: Edit .zshrc**

Add before the final `#zprof` line (line 80):

```bash
# Per-host overrides (not in repo, not symlinked)
[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"
```

**Step 2: Edit .bash_aliases**

Add at the end:

```bash
# Per-host overrides (not in repo, not symlinked)
[ -f "$HOME/.bash_aliases.local" ] && source "$HOME/.bash_aliases.local"
```

**Step 3: Edit .tmux.conf**

Add before the final `run '~/.tmux/plugins/tpm/tpm'` line (line 55):

```tmux
# Per-host overrides (not in repo, not symlinked)
if-shell "test -f ~/.tmux.conf.local" "source-file ~/.tmux.conf.local"
```

**Step 4: Edit .gitconfig**

Add at the end:

```ini
[include]
	path = ~/.gitconfig.local
```

**Step 5: Verify no syntax errors**

Run: `zsh -n .zshrc && echo OK` (syntax check)
Run: `bash -n .bash_aliases && echo OK` (syntax check)
Expected: Both print `OK`

**Step 6: Commit**

```bash
git add .zshrc .bash_aliases .tmux.conf .gitconfig
git commit -m "feat: add .local override sourcing to all config files

Per-host customization (paths, secrets, aliases) goes in
~/.zshrc.local, ~/.bash_aliases.local, ~/.tmux.conf.local,
~/.gitconfig.local — these are gitignored and never symlinked."
```

---

### Task 3: Fix .zshrc node PATH

With symlinks, we can't `sed`-patch .zshrc per host. Remove the hardcoded node version from PATH — the lazy-loading nvm wrappers (lines 48-56) already handle node/npm/npx.

**Files:**
- Modify: `.zshrc:8` (remove node version from PATH)

**Step 1: Edit .zshrc line 8**

Replace:
```bash
export PATH=$HOME/.nvm/versions/node/v24.0.0/bin:$HOME/node/bin/:$HOME/bin:/usr/local/bin:$PATH:$HOME/.local/bin:$HOME/.dotnet/
```

With:
```bash
export PATH=$HOME/bin:/usr/local/bin:$PATH:$HOME/.local/bin:$HOME/.dotnet/
```

The nvm lazy-load wrappers on lines 48-56 intercept `node`, `npm`, and `npx` and load nvm on first use. No hardcoded path needed. The `$HOME/node/bin/` path is also legacy cruft — remove it.

Also remove the comment on line 7 about the install script patching this line:
```
# The install script patches this line with the actual installed version
```

**Step 2: Verify syntax**

Run: `zsh -n .zshrc && echo OK`
Expected: `OK`

**Step 3: Commit**

```bash
git add .zshrc
git commit -m "refactor: remove hardcoded node path from .zshrc PATH

The lazy-loading nvm wrappers handle node/npm/npx on first use.
This removes the need for sed-patching during install, which is
incompatible with the symlink approach."
```

---

### Task 4: Create scripts/dotfiles helper

**Files:**
- Create: `scripts/dotfiles`

**Step 1: Write the script**

```bash
#!/bin/bash
set -euo pipefail

DOTFILES_DIR="$HOME/.dot_files"

usage() {
    echo "Usage: dotfiles <command>"
    echo ""
    echo "Commands:"
    echo "  promote <path>  Move a local file into the repo and symlink it back"
    echo "  status          Show symlink status of managed files"
    echo "  pull            Pull latest changes from remote"
    echo ""
    echo "Examples:"
    echo "  dotfiles promote ~/.claude/rules/my-rule.md"
    echo "  dotfiles status"
    echo "  dotfiles pull"
}

cmd_promote() {
    local src="$1"

    if [ ! -f "$src" ]; then
        echo "ERROR: $src does not exist or is not a file" >&2
        exit 1
    fi

    if [ -L "$src" ]; then
        echo "ERROR: $src is already a symlink" >&2
        exit 1
    fi

    # Determine the relative path from $HOME
    local rel_path="${src#$HOME/}"
    if [ "$rel_path" = "$src" ]; then
        echo "ERROR: $src is not under \$HOME" >&2
        exit 1
    fi

    local dest="$DOTFILES_DIR/$rel_path"
    local dest_dir
    dest_dir=$(dirname "$dest")

    mkdir -p "$dest_dir"
    mv "$src" "$dest"
    ln -s "$dest" "$src"

    echo "Promoted: $src -> $dest (symlinked back)"
    echo ""
    echo "To commit:"
    echo "  cd $DOTFILES_DIR && git add '$rel_path' && git commit -m 'feat: add $rel_path'"
}

cmd_status() {
    local ok=0 broken=0 missing=0

    # Read managed file list from the repo
    while IFS= read -r rel_path; do
        local target="$HOME/$rel_path"
        if [ -L "$target" ]; then
            local link_dest
            link_dest=$(readlink -f "$target")
            local expected="$DOTFILES_DIR/$rel_path"
            if [ "$link_dest" = "$(readlink -f "$expected")" ]; then
                ok=$((ok + 1))
            else
                echo "  WRONG:   $target -> $link_dest (expected $expected)"
                broken=$((broken + 1))
            fi
        elif [ -f "$target" ]; then
            echo "  NOT LINK: $target (regular file, not symlinked)"
            broken=$((broken + 1))
        else
            echo "  MISSING:  $target"
            missing=$((missing + 1))
        fi
    done < <(cd "$DOTFILES_DIR" && git ls-files | grep -E '^\.' | grep -v '^\.(git|claude/(skills|plugins|memory|projects|worktrees))')

    echo ""
    echo "Status: $ok linked, $broken issues, $missing missing"
}

cmd_pull() {
    git -C "$DOTFILES_DIR" pull
}

if [ $# -lt 1 ]; then
    usage
    exit 1
fi

case "$1" in
    promote)
        if [ $# -lt 2 ]; then
            echo "ERROR: promote requires a file path" >&2
            exit 1
        fi
        cmd_promote "$2"
        ;;
    status)
        cmd_status
        ;;
    pull)
        cmd_pull
        ;;
    *)
        echo "ERROR: Unknown command '$1'" >&2
        usage
        exit 1
        ;;
esac
```

**Step 2: Make executable**

Run: `chmod +x scripts/dotfiles`

**Step 3: Verify**

Run: `bash -n scripts/dotfiles && echo OK`
Expected: `OK`

Run: `scripts/dotfiles` (no args)
Expected: Prints usage info, exits 1

**Step 4: Commit**

```bash
git add scripts/dotfiles
git commit -m "feat: add dotfiles helper script for promote/status/pull

Manages the symlink lifecycle:
- promote: move local file into repo and symlink back
- status: check which managed files are properly symlinked
- pull: update repo from remote"
```

---

### Task 5: Rewrite install_environment.sh

This is the core change. Replace `install_file()` with `link_file()`, add repo cloning, remove wget/curl downloads, remove sed patching.

**Files:**
- Modify: `install_environment.sh` (full rewrite of install logic)

**Step 1: Rewrite the script**

The new script structure:

```bash
#!/bin/bash
set -euo pipefail

NODE_VERSION=24
DOTFILES_DIR="$HOME/.dot_files"
DOTFILES_REPO="https://github.com/Marshall-Hallenbeck/dot_files.git"
BACKUP_DIR="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"

# ── Helper functions ─────────────────────────────────────────────

# Create a symlink from repo file to destination, backing up existing non-link files.
link_file() {
    local src="$1" dest="$2"

    if [ ! -f "$src" ]; then
        echo "  WARNING: source not found: $src" >&2
        return 1
    fi

    # Already correctly symlinked
    if [ -L "$dest" ] && [ "$(readlink -f "$dest")" = "$(readlink -f "$src")" ]; then
        return 0
    fi

    # Back up existing file (but not if it's a symlink to somewhere else)
    if [ -f "$dest" ] && [ ! -L "$dest" ]; then
        mkdir -p "$BACKUP_DIR"
        local backup_path="$BACKUP_DIR/$(echo "$dest" | sed "s|$HOME/||; s|/|__|g")"
        cp "$dest" "$backup_path"
        echo "  backed up: $dest -> $backup_path"
    fi

    # Remove existing file/symlink and create new symlink
    rm -f "$dest"
    mkdir -p "$(dirname "$dest")"
    ln -s "$src" "$dest"
}

# ── Clone or update repo ─────────────────────────────────────────
if [ -d "$DOTFILES_DIR/.git" ]; then
    echo "Updating dotfiles repo..."
    git -C "$DOTFILES_DIR" pull
else
    echo "Cloning dotfiles repo..."
    git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
fi

# ── System packages ──────────────────────────────────────────────
echo "Installing system packages..."
sudo apt update
for pkg in zsh tmux vim python3-pip git virtualenvwrapper curl wget jq bc xclip net-tools; do
    dpkg -s "$pkg" &>/dev/null || sudo apt install -y "$pkg"
done

# gh (GitHub CLI) requires its own apt repo
if ! command -v gh &>/dev/null; then
    echo "Installing GitHub CLI..."
    sudo mkdir -p -m 755 /etc/apt/keyrings
    out=$(mktemp) && wget -nv -O"$out" https://cli.github.com/packages/githubcli-archive-keyring.gpg
    cat "$out" | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null && rm "$out"
    sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    sudo apt update
    sudo apt install -y gh
fi

# ── Set zsh as default shell ─────────────────────────────────────
if [ "$(basename "$SHELL")" != "zsh" ]; then
    echo "Setting zsh as default shell..."
    sudo chsh -s "$(which zsh)" "$(whoami)"
fi

# ── Tool installers (run BEFORE dotfiles — these modify .zshrc) ──
if [ ! -d ~/.oh-my-zsh ]; then
    echo "Installing oh-my-zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

export NVM_DIR="$HOME/.nvm"
if [ ! -d "$NVM_DIR" ]; then
    echo "Installing nvm..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
fi
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

if ! nvm ls "$NODE_VERSION" &>/dev/null; then
    echo "Installing Node.js $NODE_VERSION..."
    nvm install "$NODE_VERSION"
fi
nvm alias default "$NODE_VERSION"

if [ ! -f "$HOME/.atuin/bin/env" ]; then
    echo "Installing atuin..."
    curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh
fi

# ── Claude Code ──────────────────────────────────────────────────
if ! command -v claude &>/dev/null; then
    echo "Installing Claude Code..."
    npm install -g @anthropic-ai/claude-code
fi

# ── Shell dotfiles (symlink with backup) ─────────────────────────
echo "Symlinking shell dotfiles..."
link_file "$DOTFILES_DIR/.bash_aliases" ~/.bash_aliases
link_file "$DOTFILES_DIR/.vimrc" ~/.vimrc
link_file "$DOTFILES_DIR/.zshrc" ~/.zshrc
link_file "$DOTFILES_DIR/.gitconfig" ~/.gitconfig

# ── tmux ─────────────────────────────────────────────────────────
echo "Symlinking tmux configuration..."
link_file "$DOTFILES_DIR/.tmux.conf" ~/.tmux.conf
mkdir -p ~/.tmux
link_file "$DOTFILES_DIR/.tmux/copy-to-clipboard.sh" ~/.tmux/copy-to-clipboard.sh
chmod +x ~/.tmux/copy-to-clipboard.sh

if [ ! -d ~/.tmux/plugins/tpm ]; then
    git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
fi

# ── Claude Code global configuration ─────────────────────────────
echo "Symlinking Claude Code configuration..."

# Create directories that aren't in the repo (local-only)
mkdir -p ~/.claude/rules ~/.claude/agents

# Top-level config files
link_file "$DOTFILES_DIR/.claude/CLAUDE.md" ~/.claude/CLAUDE.md
link_file "$DOTFILES_DIR/.claude/hooks.json" ~/.claude/hooks.json
link_file "$DOTFILES_DIR/.claude/settings.json" ~/.claude/settings.json
link_file "$DOTFILES_DIR/.claude/settings.local.json" ~/.claude/settings.local.json
link_file "$DOTFILES_DIR/.claude/statusline.sh" ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh

# Rules
for rule_file in "$DOTFILES_DIR"/.claude/rules/*.md; do
    [ -f "$rule_file" ] || continue
    link_file "$rule_file" ~/.claude/rules/"$(basename "$rule_file")"
done

# Skills (only managed skills that have SKILL.md)
for skill_dir in "$DOTFILES_DIR"/.claude/skills/*/; do
    [ -d "$skill_dir" ] || continue
    local_skill=$(basename "$skill_dir")
    if [ -f "$skill_dir/SKILL.md" ]; then
        mkdir -p ~/.claude/skills/"$local_skill"
        link_file "$skill_dir/SKILL.md" ~/.claude/skills/"$local_skill"/SKILL.md
    fi
done

# Agents
for agent_file in "$DOTFILES_DIR"/.claude/agents/*.md; do
    [ -f "$agent_file" ] || continue
    link_file "$agent_file" ~/.claude/agents/"$(basename "$agent_file")"
done

# Hookify rules
for hookify_file in "$DOTFILES_DIR"/.claude/hookify.*.local.md; do
    [ -f "$hookify_file" ] || continue
    link_file "$hookify_file" ~/.claude/"$(basename "$hookify_file")"
done

# ── dotfiles helper on PATH ──────────────────────────────────────
mkdir -p "$HOME/.local/bin"
link_file "$DOTFILES_DIR/scripts/dotfiles" "$HOME/.local/bin/dotfiles"

# ── Community skills (installed via npx, not symlinked) ───────────
echo "Installing community skills..."

if [ ! -d ~/.claude/skills/next-best-practices ]; then
    npx skills add https://github.com/vercel-labs/next-skills --skill next-best-practices -y -g
else
    echo "  next-best-practices already installed"
fi

if [ ! -d ~/.claude/skills/supabase-postgres-best-practices ]; then
    npx skills add https://github.com/supabase/agent-skills --skill supabase-postgres-best-practices -y -g
else
    echo "  supabase-postgres-best-practices already installed"
fi

if [ ! -d ~/.claude/skills/windows-protocols ]; then
    npx skills add awakecoding/openspecs --skill windows-protocols -y -g
else
    echo "  windows-protocols already installed"
fi

# ── Summary ──────────────────────────────────────────────────────
if [ -d "$BACKUP_DIR" ]; then
    echo ""
    echo "Backed up files that differed from repo to: $BACKUP_DIR"
    ls -1 "$BACKUP_DIR"
fi

echo "Environment setup complete!"
echo "Run 'dotfiles status' to verify symlinks."
```

**Step 2: Verify syntax**

Run: `bash -n install_environment.sh && echo OK`
Expected: `OK`

**Step 3: Commit**

```bash
git add install_environment.sh
git commit -m "feat: rewrite install script to clone repo and symlink files

Instead of downloading individual files from GitHub raw URLs,
the script now clones the repo to ~/.dot_files and creates
symlinks. Changes to the repo propagate instantly to all hosts.
Backs up existing non-symlink files before replacing them."
```

---

### Task 6: Update test infrastructure

The Docker tests currently serve the repo over HTTP and patch the REPO_BASE URL. With clone+symlink, they need to set up the repo as a local git clone instead.

**Files:**
- Modify: `test/run-test.sh` (replace HTTP server with local git clone)
- Modify: `test/verify-environment.sh` (check symlinks, add .local override checks)

**Step 1: Rewrite test/run-test.sh**

```bash
#!/bin/bash
set -euo pipefail

MODE="${1:-environment}"

echo "=== Test mode: $MODE ==="
echo "=== Distro: $(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"') ==="

cd /home/testuser

if [ "$MODE" = "environment" ]; then
    # Set up /repo as a git repo so the install script can "clone" from it
    cd /repo
    git config --global user.email "test@test.com"
    git config --global user.name "Test"
    git init
    git add -A
    git commit -m "test commit"
    cd /home/testuser

    # Create patched copy of install script that clones from local /repo
    cp /repo/install_environment.sh /tmp/install_environment.sh

    # Patch to clone from local /repo instead of GitHub
    sed -i 's|^DOTFILES_REPO=.*|DOTFILES_REPO="/repo"|' /tmp/install_environment.sh

    # Strip community skills section (npx skills add downloads 200MB+)
    sed -i '/Community skills/,/Summary/{/Summary/!d}' /tmp/install_environment.sh

    echo "=== Running install_environment.sh ==="
    bash /tmp/install_environment.sh

    echo ""
    echo "=== Running verification ==="
    bash /repo/test/verify-environment.sh

elif [ "$MODE" = "security" ]; then
    {
        echo '#!/bin/bash'
        echo 'sudo apt-get update'
        sed -n '5,39p' /repo/security.sh
    } > /tmp/security_subset.sh
    chmod +x /tmp/security_subset.sh

    echo "=== Running security.sh subset ==="
    bash /tmp/security_subset.sh

    echo ""
    echo "=== Running verification ==="
    bash /repo/test/verify-security.sh

else
    echo "ERROR: Unknown mode '$MODE'. Use 'environment' or 'security'." >&2
    exit 1
fi

echo ""
echo "=== All tests passed ==="
```

**Step 2: Rewrite test/verify-environment.sh**

Add symlink checks alongside the existing file checks. Replace `check_file` with `check_link` for symlinked files. Keep `check_file` for non-symlinked items.

Add a new helper:

```bash
check_link() {
    local desc="$1" target="$2"
    if [ -L "$target" ] && [ -f "$target" ]; then
        echo "  PASS: $desc (symlink)"
        PASS=$((PASS + 1))
    elif [ -f "$target" ]; then
        echo "  FAIL: $desc (exists but not a symlink)"
        FAIL=$((FAIL + 1))
    else
        echo "  FAIL: $desc (missing)"
        FAIL=$((FAIL + 1))
    fi
}
```

Change all managed-file checks from `check_file` to `check_link`:
- `.bash_aliases`, `.vimrc`, `.zshrc`, `.gitconfig`, `.tmux.conf`
- `copy-to-clipboard.sh`
- All `.claude/` files (CLAUDE.md, hooks.json, settings.json, etc.)
- All rules, skills, agents, hookify files

Keep `check_file` / `check_dir` for:
- tpm directory
- nvm directory
- oh-my-zsh directory
- atuin binary

Add checks for:
- `dotfiles` helper is symlinked at `~/.local/bin/dotfiles`
- `.zshrc` does NOT contain hardcoded node version path (`v24.0.0`)
- `.zshrc` sources `.zshrc.local`
- `.bash_aliases` sources `.bash_aliases.local`

**Step 3: Run tests**

Run: `make test-ubuntu`
Expected: All checks pass, including new symlink checks.

**Step 4: Commit**

```bash
git add test/run-test.sh test/verify-environment.sh
git commit -m "test: update test infrastructure for clone+symlink approach

Tests now set up /repo as a local git repo for cloning instead
of serving files over HTTP. Verification checks that managed
files are symlinks, not regular files."
```

---

### Task 7: Update CLAUDE.md with dotfiles helper docs

**Files:**
- Modify: `.claude/CLAUDE.md` (add dotfiles helper section)

**Step 1: Add section to CLAUDE.md**

Add after the "Canonical Workflow Commands" section:

```markdown
## Dotfiles Management

This host's config files are symlinked from `~/.dot_files` (a clone of the dot_files repo).

### Adding New Global Configs

When creating new rules, skills, agents, or config files that should apply to ALL hosts:
1. Create the file directly in `~/.dot_files/` at the correct relative path
2. Run `dotfiles promote` is NOT needed (file is already in the repo)
3. The install script will symlink it on other hosts next time it runs

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
```

**Step 2: Commit**

```bash
git add .claude/CLAUDE.md
git commit -m "docs: add dotfiles management section to CLAUDE.md

Documents the symlink architecture, dotfiles helper commands,
and .local override pattern so Claude Code is aware of them."
```

---

### Task 8: Final verification

**Step 1: Run full test suite**

Run: `make test-ubuntu`
Expected: All tests pass.

Run: `make test-debian`
Expected: All tests pass.

**Step 2: Run dotfiles status locally**

Run: `scripts/dotfiles status`
Expected: Reports current state (files won't be symlinked locally since this IS the repo — that's expected).

**Step 3: Verify .gitignore**

Run: `git status`
Expected: No `.local` override files are tracked. Hookify `.local.md` files and `settings.local.json` are still tracked.
