#!/bin/bash
set -euo pipefail

NODE_VERSION=24
REPO_BASE="https://raw.githubusercontent.com/Marshall-Hallenbeck/dot_files/main"
CLAUDE_BASE="$REPO_BASE/.claude"
BACKUP_DIR="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"

# ── Helper functions ─────────────────────────────────────────────

# Install a file, backing up the existing one if it differs.
# Always installs the repo version. If the host file differs, backs it up first.
install_file() {
    local url="$1" dest="$2"
    local tmp
    tmp=$(mktemp)
    wget -q "$url" -O "$tmp"
    if [ ! -s "$tmp" ]; then
        echo "  ERROR: failed to download $url" >&2
        rm "$tmp"
        return 1
    fi

    if [ -f "$dest" ]; then
        if diff -q "$tmp" "$dest" &>/dev/null; then
            rm "$tmp"
            return 0
        fi
        mkdir -p "$BACKUP_DIR"
        local backup_path="$BACKUP_DIR/$(echo "$dest" | sed "s|$HOME/||; s|/|__|g")"
        cp "$dest" "$backup_path"
        echo "  backed up: $dest -> $backup_path"
    fi
    mv "$tmp" "$dest"
}

# Install a file only if it doesn't exist yet.
# If it exists but differs from the repo version, show the diff.
install_if_missing() {
    local url="$1" dest="$2" label="$3"
    if [ -f "$dest" ]; then
        local tmp
        tmp=$(mktemp)
        if ! wget -q "$url" -O "$tmp" || [ ! -s "$tmp" ]; then
            echo "  WARNING: failed to download $url for diff comparison" >&2
            rm -f "$tmp"
            return 0
        fi
        if ! diff -q "$tmp" "$dest" &>/dev/null; then
            echo "  $label exists and differs from repo:"
            local diff_output
            diff_output=$(diff --color=auto -u "$dest" "$tmp") && :
            echo "$diff_output" | head -30
            echo "  (skipping overwrite — review diff above and update manually if needed)"
        fi
        rm "$tmp"
    else
        wget -q "$url" -O "$dest"
        echo "  installed: $dest"
    fi
}

# ── System packages ──────────────────────────────────────────────
echo "Installing system packages..."
sudo apt update
for pkg in zsh tmux vim python3-pip git virtualenvwrapper curl wget jq bc xclip net-tools; do
    dpkg -s "$pkg" &>/dev/null || sudo apt install -y "$pkg"
done

# ── Shell dotfiles (overwrite with backup) ───────────────────────
echo "Installing shell dotfiles..."
install_file "$REPO_BASE/.bash_aliases" ~/.bash_aliases
install_file "$REPO_BASE/.vimrc" ~/.vimrc
install_file "$REPO_BASE/.zshrc" ~/.zshrc

# .gitconfig: preserve host-specific user/email
install_if_missing "$REPO_BASE/.gitconfig" ~/.gitconfig ".gitconfig"

# ── Set zsh as default shell ─────────────────────────────────────
if [ "$(basename "$SHELL")" != "zsh" ]; then
    echo "Setting zsh as default shell..."
    chsh -s "$(which zsh)"
fi

# ── tmux ─────────────────────────────────────────────────────────
echo "Installing tmux configuration..."
install_file "$REPO_BASE/.tmux.conf" ~/.tmux.conf
mkdir -p ~/.tmux
install_file "$REPO_BASE/.tmux/copy-to-clipboard.sh" ~/.tmux/copy-to-clipboard.sh
chmod +x ~/.tmux/copy-to-clipboard.sh

if [ ! -d ~/.tmux/plugins/tpm ]; then
    git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
fi

# ── nvm + Node.js ────────────────────────────────────────────────
export NVM_DIR="$HOME/.nvm"
if [ ! -d "$NVM_DIR" ]; then
    echo "Installing nvm..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
fi
# load nvm for the rest of this script
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

if ! nvm ls "$NODE_VERSION" &>/dev/null; then
    echo "Installing Node.js $NODE_VERSION..."
    nvm install "$NODE_VERSION"
fi
nvm alias default "$NODE_VERSION"

# Patch .zshrc with the actual installed node version (avoids loading nvm on every shell)
NODE_FULL_VERSION=$(nvm version "$NODE_VERSION")
sed -i "s|/node/v[0-9.]*/bin|/node/${NODE_FULL_VERSION}/bin|" ~/.zshrc

# ── oh-my-zsh ────────────────────────────────────────────────────
if [ ! -d ~/.oh-my-zsh ]; then
    echo "Installing oh-my-zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

# ── atuin ────────────────────────────────────────────────────────
if [ ! -f "$HOME/.atuin/bin/env" ]; then
    echo "Installing atuin..."
    curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh
fi

# ── Claude Code global configuration ─────────────────────────────
echo "Setting up Claude Code configuration..."

# Create all required directories
SKILL_DIRS="review summarize-changes lookup-docs create-pr commit codex-review fix-tests orchestrate-plan pre-commit-validate complete-github-issue multi-model-review opencode-review overcautious-check"
for skill in $SKILL_DIRS; do
    mkdir -p ~/.claude/skills/$skill
done
mkdir -p ~/.claude/rules ~/.claude/agents

# Global instructions (always overwrite with backup)
install_file "$CLAUDE_BASE/CLAUDE.md" ~/.claude/CLAUDE.md

# Rules (always overwrite with backup)
for rule in verification coding-practices git-conventions web-dev error-handling docker; do
    install_file "$CLAUDE_BASE/rules/$rule.md" ~/.claude/rules/$rule.md
done

# Skills (always overwrite with backup)
for skill in $SKILL_DIRS; do
    install_file "$CLAUDE_BASE/skills/$skill/SKILL.md" ~/.claude/skills/$skill/SKILL.md
done

# Agents (always overwrite with backup)
install_file "$CLAUDE_BASE/agents/unit-test-writer.md" ~/.claude/agents/unit-test-writer.md

# Hooks and hookify rules (always overwrite with backup)
install_file "$CLAUDE_BASE/hooks.json" ~/.claude/hooks.json
for hookify_file in \
    hookify.block-backwards-compat.local.md \
    hookify.block-error-swallowing.local.md \
    hookify.block-graceful-degradation.local.md \
    hookify.completion-check.local.md \
    hookify.require-flakiness-investigation.local.md \
    hookify.warn-duplicate-docs.local.md; do
    install_file "$CLAUDE_BASE/$hookify_file" ~/.claude/$hookify_file
done

# Statusline script (always overwrite with backup)
install_file "$CLAUDE_BASE/statusline.sh" ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh

# Settings files: preserve host-specific accumulated permissions
install_if_missing "$CLAUDE_BASE/settings.json" ~/.claude/settings.json "settings.json"
install_if_missing "$CLAUDE_BASE/settings.local.json" ~/.claude/settings.local.json "settings.local.json"

# ── Community skills (installed via npx, not vendored) ───────────
echo "Installing community skills..."

# next-best-practices: Next.js 15+ conventions from Vercel
if [ ! -d ~/.claude/skills/next-best-practices ]; then
    npx skills add https://github.com/vercel-labs/next-skills --skill next-best-practices -y -g
else
    echo "  next-best-practices already installed"
fi

# supabase-postgres-best-practices: Postgres optimization guide from Supabase
if [ ! -d ~/.claude/skills/supabase-postgres-best-practices ]; then
    npx skills add https://github.com/supabase/agent-skills --skill supabase-postgres-best-practices -y -g
else
    echo "  supabase-postgres-best-practices already installed"
fi

# windows-protocols: Microsoft Open Specifications corpus (217MB)
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
