#!/bin/bash
set -euo pipefail

NODE_VERSION=24
REPO_BASE="https://raw.githubusercontent.com/Marshall-Hallenbeck/dot_files/main"
CLAUDE_BASE="$REPO_BASE/.claude"

# ── System packages ──────────────────────────────────────────────
echo "Installing system packages..."
sudo apt update
# only install what's missing
for pkg in zsh tmux vim python3-pip git virtualenvwrapper curl wget jq bc xclip net-tools; do
    dpkg -s "$pkg" &>/dev/null || sudo apt install -y "$pkg"
done

# ── Shell dotfiles (always overwrite with repo version) ──────────
echo "Installing shell dotfiles..."
wget -q "$REPO_BASE/.bash_aliases" -O ~/.bash_aliases
wget -q "$REPO_BASE/.vimrc" -O ~/.vimrc
wget -q "$REPO_BASE/.zshrc" -O ~/.zshrc

# .gitconfig: only install if not present (preserves host-specific user/email)
if [ ! -f ~/.gitconfig ]; then
    wget -q "$REPO_BASE/.gitconfig" -O ~/.gitconfig
else
    echo "~/.gitconfig already exists, skipping (update manually if needed)"
fi

# ── Set zsh as default shell ─────────────────────────────────────
if [ "$(basename "$SHELL")" != "zsh" ]; then
    echo "Setting zsh as default shell..."
    chsh -s "$(which zsh)"
fi

# ── tmux ─────────────────────────────────────────────────────────
echo "Installing tmux configuration..."
wget -q "$REPO_BASE/.tmux.conf" -O ~/.tmux.conf
mkdir -p ~/.tmux
wget -q "$REPO_BASE/.tmux/copy-to-clipboard.sh" -O ~/.tmux/copy-to-clipboard.sh
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
SKILL_DIRS="safe-commit summarize-changes postflight lookup-docs create-pr git-status recall-memory commit codex-review fix-tests orchestrate-plan pre-commit-validate"
for skill in $SKILL_DIRS; do
    mkdir -p ~/.claude/skills/$skill
done
mkdir -p ~/.claude/rules ~/.claude/agents

# Global instructions (always overwrite — repo is canonical)
wget -q "$CLAUDE_BASE/CLAUDE.md" -O ~/.claude/CLAUDE.md

# Rules
for rule in verification coding-practices git-conventions web-dev error-handling; do
    wget -q "$CLAUDE_BASE/rules/$rule.md" -O ~/.claude/rules/$rule.md
done

# Skills
for skill in $SKILL_DIRS; do
    wget -q "$CLAUDE_BASE/skills/$skill/SKILL.md" -O ~/.claude/skills/$skill/SKILL.md
done

# Agents
wget -q "$CLAUDE_BASE/agents/unit-test-writer.md" -O ~/.claude/agents/unit-test-writer.md

# Hooks and hookify rules (always overwrite)
wget -q "$CLAUDE_BASE/hooks.json" -O ~/.claude/hooks.json
wget -q "$CLAUDE_BASE/hookify.require-flakiness-investigation.local.md" -O ~/.claude/hookify.require-flakiness-investigation.local.md
wget -q "$CLAUDE_BASE/hookify.warn-duplicate-docs.local.md" -O ~/.claude/hookify.warn-duplicate-docs.local.md

# Statusline script
wget -q "$CLAUDE_BASE/statusline.sh" -O ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh

# settings.json: only install if not present (preserves host-specific accumulated permissions)
if [ ! -f ~/.claude/settings.json ]; then
    wget -q "$CLAUDE_BASE/settings.json" -O ~/.claude/settings.json
else
    echo "~/.claude/settings.json already exists, skipping (update manually if needed)"
fi

# settings.local.json: only install if not present (host-specific overrides)
if [ ! -f ~/.claude/settings.local.json ]; then
    wget -q "$CLAUDE_BASE/settings.local.json" -O ~/.claude/settings.local.json
else
    echo "~/.claude/settings.local.json already exists, skipping"
fi

echo "Environment setup complete!"
