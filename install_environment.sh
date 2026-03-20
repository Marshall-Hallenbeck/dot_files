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

    if [ ! -e "$src" ]; then
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
for pkg in zsh tmux vim python3-pip python3-venv git virtualenvwrapper curl wget jq bc xclip net-tools shellcheck ripgrep build-essential unzip ca-certificates; do
    dpkg -s "$pkg" &>/dev/null || sudo apt install -y "$pkg"
done

# gh (GitHub CLI) requires its own apt repo
if ! command -v gh &>/dev/null; then
    echo "Installing GitHub CLI..."
    sudo mkdir -p -m 755 /etc/apt/keyrings
    out=$(mktemp) && wget -nv -O"$out" https://cli.github.com/packages/githubcli-archive-keyring.gpg
    # shellcheck disable=SC2024
    sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg < "$out" > /dev/null && rm "$out"
    sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    sudo apt update
    sudo apt install -y gh
fi

# ── Docker ───────────────────────────────────────────────────────
if ! command -v docker &>/dev/null; then
    echo "Installing Docker..."
    sudo install -m 0755 -d /etc/apt/keyrings

    # Detect distro and set Docker repo URL + codename
    # shellcheck disable=SC1091
    . /etc/os-release
    DOCKER_URL=""
    DOCKER_CODENAME=""
    case "$ID" in
        ubuntu)
            DOCKER_URL="https://download.docker.com/linux/ubuntu"
            DOCKER_CODENAME="${UBUNTU_CODENAME:-$VERSION_CODENAME}"
            ;;
        debian)
            DOCKER_URL="https://download.docker.com/linux/debian"
            DOCKER_CODENAME="$VERSION_CODENAME"
            ;;
        kali)
            DOCKER_URL="https://download.docker.com/linux/debian"
            # Kali doesn't have its own Docker repo; use the underlying Debian codename
            DOCKER_CODENAME=$(cut -d/ -f1 < /etc/debian_version)
            ;;
        *)
            echo "  WARNING: unsupported distro '$ID' for Docker, skipping" >&2
            ;;
    esac

    if [ -n "$DOCKER_URL" ]; then
        sudo curl -fsSL "$DOCKER_URL/gpg" -o /etc/apt/keyrings/docker.asc
        sudo chmod a+r /etc/apt/keyrings/docker.asc
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] $DOCKER_URL $DOCKER_CODENAME stable" | \
            sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        sudo apt update
        sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        sudo systemctl enable docker --now
        sudo usermod -aG docker "$(whoami)"
    fi
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
# shellcheck disable=SC1091
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

# ── Claude Code (native installer, auto-updates) ────────────────
if ! command -v claude &>/dev/null; then
    echo "Installing Claude Code..."
    curl -fsSL https://claude.ai/install.sh | bash
fi

# ── OpenAI Codex ─────────────────────────────────────────────────
if ! command -v codex &>/dev/null; then
    echo "Installing OpenAI Codex..."
    npm install -g @openai/codex
    sudo ln -sf "$(npm prefix -g)/bin/codex" /usr/local/bin/codex
fi

# ── GitHub Copilot ───────────────────────────────────────────────
if ! command -v copilot &>/dev/null; then
    echo "Installing GitHub Copilot..."
    npm install -g @github/copilot
    sudo ln -sf "$(npm prefix -g)/bin/copilot" /usr/local/bin/copilot
fi

# ── Google Gemini CLI ────────────────────────────────────────────
if ! command -v gemini &>/dev/null; then
    echo "Installing Gemini CLI..."
    npm install -g @google/gemini-cli
    sudo ln -sf "$(npm prefix -g)/bin/gemini" /usr/local/bin/gemini
fi

# ── Claude Code LSP servers ─────────────────────────────────────
echo "Installing Claude Code LSP servers..."
if ! command -v typescript-language-server &>/dev/null; then
    npm install -g typescript-language-server typescript
    sudo ln -sf "$(npm prefix -g)/bin/typescript-language-server" /usr/local/bin/typescript-language-server
fi
if ! command -v pyright-langserver &>/dev/null; then
    npm install -g pyright
    sudo ln -sf "$(npm prefix -g)/bin/pyright-langserver" /usr/local/bin/pyright-langserver
fi

# ── Shell dotfiles (symlink with backup) ─────────────────────────
# Installed AFTER tools so our versions are the final word.
echo "Symlinking shell dotfiles..."
link_file "$DOTFILES_DIR/.bash_aliases" ~/.bash_aliases
link_file "$DOTFILES_DIR/.vimrc" ~/.vimrc
link_file "$DOTFILES_DIR/.zshrc" ~/.zshrc
link_file "$DOTFILES_DIR/.gitconfig" ~/.gitconfig
link_file "$DOTFILES_DIR/.conkyrc" ~/.conkyrc
mkdir -p ~/.msf4
link_file "$DOTFILES_DIR/.msf4/config" ~/.msf4/config

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
link_file "$DOTFILES_DIR/.claude/global-learned-insights.md" ~/.claude/global-learned-insights.md
chmod +x ~/.claude/statusline.sh

# Hooks — remove stale directory symlink from older installs
if [ -L ~/.claude/hooks ]; then
    rm ~/.claude/hooks
fi
mkdir -p ~/.claude/hooks
for hook_file in "$DOTFILES_DIR"/.claude/hooks/*; do
    [ -f "$hook_file" ] || continue
    link_file "$hook_file" ~/.claude/hooks/"$(basename "$hook_file")"
done

# Rules
for rule_file in "$DOTFILES_DIR"/.claude/rules/*.md; do
    [ -f "$rule_file" ] || continue
    link_file "$rule_file" ~/.claude/rules/"$(basename "$rule_file")"
done

# Skills — symlink entire directory (previous installs used per-file symlinks)
if [ -d ~/.claude/skills ] && [ ! -L ~/.claude/skills ]; then
    rm -rf ~/.claude/skills
fi
link_file "$DOTFILES_DIR/.claude/skills" ~/.claude/skills

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

# ── Community skills (windows-protocols is too large for git, lives in ~/.agents/) ──
echo "Installing community skills..."

if [ ! -d ~/.agents/skills/windows-protocols ]; then
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
