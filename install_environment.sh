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
        local backup_path
        backup_path="$BACKUP_DIR/$(echo "$dest" | sed "s|$HOME/||; s|/|__|g")"
        if [ -r "$dest" ]; then
            cp "$dest" "$backup_path"
            echo "  backed up: $dest -> $backup_path"
        else
            echo "  WARNING: $dest is not readable, cannot back up (check file ownership/permissions)" >&2
        fi
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
    sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg < "$out" > /dev/null && rm "$out"
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
# oh-my-zsh replaces .zshrc with its template, nvm and atuin append
# to it. We install tools first, then overwrite with our symlinks.

if [ ! -d ~/.oh-my-zsh ]; then
    echo "Installing oh-my-zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

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
# Installed AFTER tools so our versions are the final word.
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
link_file "$DOTFILES_DIR/.claude/global-CLAUDE.md" ~/.claude/CLAUDE.md
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
