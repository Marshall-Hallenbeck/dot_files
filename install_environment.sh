#!/bin/bash
set -euo pipefail

NODE_VERSION=24
# Pinned: .local/bin/agent-sync refuses to run against any other release
# (EXPECTED_RULER_VERSION). Change both together.
RULER_VERSION=0.3.44
DOTFILES_DIR="$HOME/.dot_files"
DOTFILES_REPO="https://github.com/Marshall-Hallenbeck/dot_files.git"
BACKUP_DIR="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"

# ── Helper functions ─────────────────────────────────────────────

# Report whether a command is installed on the Linux side. WSL inherits the
# Windows PATH, where extensionless npm global shims (codex, ruler) resolve but
# cannot run — they exec `node`, which exists only as node.exe on that side. A
# plain `command -v` guard sees those and skips the install, leaving the tool
# permanently broken, so treat anything under /mnt as absent.
have_command() {
    local resolved
    resolved=$(command -v "$1" 2>/dev/null) || return 1
    case "$resolved" in
        /mnt/*) return 1 ;;
    esac
    return 0
}

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

# Install a shell wrapper that sources the tracked configuration. Tool installers
# can safely append host-specific entries to ~/.zshrc.local.
install_shell_wrapper() {
    local dest="$HOME/.zshrc" local_file="$HOME/.zshrc.local"
    if [ -L "$dest" ] && [ "$(readlink -f "$dest")" = "$(readlink -f "$DOTFILES_DIR/.zshrc")" ]; then
        rm "$dest"
    elif [ -f "$dest" ] && ! grep -Fq '.dot_files/.zshrc' "$dest"; then
        mkdir -p "$BACKUP_DIR"
        cp "$dest" "$BACKUP_DIR/zshrc-pre-wrapper"
        [ -e "$local_file" ] || cp "$dest" "$local_file"
        rm "$dest"
    fi
    cat > "$dest" <<'EOF'
source "$HOME/.dot_files/.zshrc"
EOF
}

# Install a local Git wrapper. Shared defaults stay tracked. Credentials,
# safe.directory entries, and other host-only state stay in ~/.gitconfig.local.
install_git_wrapper() {
    local dest="$HOME/.gitconfig" local_file="$HOME/.gitconfig.local"
    if [ -L "$dest" ] && [ "$(readlink -f "$dest")" = "$(readlink -f "$DOTFILES_DIR/.gitconfig")" ]; then
        rm "$dest"
    elif [ -f "$dest" ] && ! grep -Fq '.dot_files/.gitconfig' "$dest"; then
        mkdir -p "$BACKUP_DIR"
        cp "$dest" "$BACKUP_DIR/gitconfig-pre-wrapper"
        [ -e "$local_file" ] || cp "$dest" "$local_file"
        rm "$dest"
    fi
    cat > "$dest" <<EOF
[include]
    path = $DOTFILES_DIR/.gitconfig
EOF
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
for pkg in zsh tmux vim python3-pip python3-venv git git-lfs virtualenvwrapper curl wget jq bc xclip net-tools shellcheck ripgrep build-essential unzip ca-certificates; do
    dpkg -s "$pkg" &>/dev/null || sudo apt install -y "$pkg"
done

# gh (GitHub CLI) requires its own apt repo
if ! have_command gh; then
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
if ! have_command docker; then
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
            # Kali's /etc/debian_version says "kali-rolling", not a usable Debian codename.
            # Derive it from Kali's Debian base version instead.
            kali_debian_ver=$(grep -oP 'VERSION_ID="\K[^"]+' /etc/os-release | cut -d. -f1)
            case "$kali_debian_ver" in
                2024|2025|2026) DOCKER_CODENAME="bookworm" ;;
                2023)           DOCKER_CODENAME="bookworm" ;;
                2022)           DOCKER_CODENAME="bullseye" ;;
                *)              DOCKER_CODENAME="bookworm" ;; # safe default
            esac
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
        # Only enable the service where systemd is the init system — systemctl
        # aborts on containers / WSL-without-systemd, which would kill the install.
        if [ -d /run/systemd/system ]; then
            sudo systemctl enable docker --now
        fi
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

# Every npm-installed CLI below uses a `#!/usr/bin/env node` shebang, but nvm
# only puts node on PATH in interactive shells. Expose the default node
# system-wide so those CLIs also run from systemd user units (agent-sync.service
# has PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin) and
# from non-login shells. Without this every /usr/local/bin npm shim fails with
# "env: 'node': No such file or directory".
sudo ln -sf "$(nvm which default)" /usr/local/bin/node

if [ ! -f "$HOME/.atuin/bin/env" ]; then
    echo "Installing atuin..."
    # atuin's installer declares #!/bin/sh but uses bashisms — it exits 2 under
    # dash (Ubuntu's /bin/sh). Pipe to bash explicitly.
    curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | bash
fi

# curlconverter
if ! have_command curlconverter; then
    echo "Installing curlconverter..."
    npm install --global curlconverter
fi

# ── Claude Code (native installer, auto-updates) ────────────────
if ! have_command claude; then
    echo "Installing Claude Code..."
    curl -fsSL https://claude.ai/install.sh | bash
fi

# ── OpenAI Codex ─────────────────────────────────────────────────
# Guard on the package, not the command: once Remote Control is enabled,
# ~/.local/bin/codex is a dotfiles wrapper that delegates to the real binary, so
# a command-name check would report Codex present and skip installing it.
if [ ! -d "$(npm prefix -g)/lib/node_modules/@openai/codex" ]; then
    echo "Installing OpenAI Codex..."
    npm install -g @openai/codex
    sudo ln -sf "$(npm prefix -g)/bin/codex" /usr/local/bin/codex
fi
# The Remote Control wrapper (.local/bin/codex) and codex-app-server.service both
# run ~/.codex/packages/standalone/current/codex. npm installs the native binary
# under a per-platform vendor directory instead, so publish it at the path they
# expect. Point at the native binary, not the npm shim: the shim spawns a child
# node process, which would sit between systemd and the long-lived app server.
codex_vendor_bin=$(find "$(npm prefix -g)/lib/node_modules/@openai/codex/node_modules/@openai" \
    -type d -path '*/vendor/*/bin' -print -quit)
mkdir -p ~/.codex/packages/standalone
ln -sfn "$codex_vendor_bin" ~/.codex/packages/standalone/current

link_file "$DOTFILES_DIR/.codex/AGENTS.md" ~/.codex/AGENTS.md
link_file "$DOTFILES_DIR/.codex/hooks.json" ~/.codex/hooks.json
link_file "$DOTFILES_DIR/.claude/global-learned-insights.md" ~/.codex/global-learned-insights.md

# ── GitHub Copilot ───────────────────────────────────────────────
if ! have_command copilot; then
    echo "Installing GitHub Copilot..."
    npm install -g @github/copilot
    sudo ln -sf "$(npm prefix -g)/bin/copilot" /usr/local/bin/copilot
fi

# ── Google Gemini CLI ────────────────────────────────────────────
if ! have_command gemini; then
    echo "Installing Gemini CLI..."
    npm install -g @google/gemini-cli
    sudo ln -sf "$(npm prefix -g)/bin/gemini" /usr/local/bin/gemini
fi

# ── Ruler (canonical agent configuration) ────────────────────────
# agent-sync calls ~/.local/bin/ruler by absolute path and verifies the version,
# so link both that path and /usr/local/bin (which precedes the Windows npm
# directory inherited into WSL PATH, where a same-named shim would win).
if [ "$("$(npm prefix -g)/bin/ruler" --version 2>/dev/null)" != "$RULER_VERSION" ]; then
    echo "Installing Ruler $RULER_VERSION..."
    npm install -g "@intellectronica/ruler@$RULER_VERSION"
fi
sudo ln -sf "$(npm prefix -g)/bin/ruler" /usr/local/bin/ruler
mkdir -p "$HOME/.local/bin"
ln -sfn "$(npm prefix -g)/bin/ruler" "$HOME/.local/bin/ruler"

# ── Claude Code LSP servers ─────────────────────────────────────
echo "Installing Claude Code LSP servers..."
if ! have_command typescript-language-server; then
    npm install -g typescript-language-server typescript
    sudo ln -sf "$(npm prefix -g)/bin/typescript-language-server" /usr/local/bin/typescript-language-server
fi
if ! have_command pyright-langserver; then
    npm install -g pyright
    sudo ln -sf "$(npm prefix -g)/bin/pyright-langserver" /usr/local/bin/pyright-langserver
fi

# ── Shell dotfiles (symlink with backup) ─────────────────────────
# Installed AFTER tools so our versions are the final word.
echo "Deploying shell configuration..."
link_file "$DOTFILES_DIR/.bash_aliases" ~/.bash_aliases
link_file "$DOTFILES_DIR/.vimrc" ~/.vimrc
install_shell_wrapper
install_git_wrapper
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
link_file "$DOTFILES_DIR/.claude/settings.json" ~/.claude/settings.json
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

# Remove dangling symlinks left behind by hooks/settings deleted from the repo
find ~/.claude/hooks -maxdepth 1 -xtype l -delete || true
if [ -L ~/.claude/settings.local.json ] && [ ! -e ~/.claude/settings.local.json ]; then
    rm ~/.claude/settings.local.json
fi
if [ -L ~/.claude/hooks.json ] && [ ! -e ~/.claude/hooks.json ]; then
    rm ~/.claude/hooks.json
fi

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

# Commands
mkdir -p ~/.claude/commands
for cmd_file in "$DOTFILES_DIR"/.claude/commands/*.md; do
    [ -f "$cmd_file" ] || continue
    link_file "$cmd_file" ~/.claude/commands/"$(basename "$cmd_file")"
done

# Hookify rules
for hookify_file in "$DOTFILES_DIR"/.claude/hookify.*.local.md; do
    [ -f "$hookify_file" ] || continue
    link_file "$hookify_file" ~/.claude/"$(basename "$hookify_file")"
done

# ── dotfiles helper on PATH ──────────────────────────────────────
mkdir -p "$HOME/.local/bin"
link_file "$DOTFILES_DIR/scripts/dotfiles" "$HOME/.local/bin/dotfiles"

# ── Commit-reference hooks and Codex trust gate ──────────────────
# This gate exits nonzero when Codex has not trusted the hooks, so it runs after
# every symlink above. An aborted run then leaves a fully configured machine
# rather than the half-deployed state that ordering it earlier produced.
commit_reference_hook="$HOME/.claude/hooks/validate-commit-references.sh"
bash "$commit_reference_hook" --install "$DOTFILES_DIR"
codex_trust_checker="$DOTFILES_DIR/.codex/verify-hook-trust.py"
if ! python3 "$codex_trust_checker" "$DOTFILES_DIR"; then
    echo "Codex must trust the commit-reference hooks before setup can continue."
    echo "Trust both hooks in /hooks. Then run /exit."
    if [ -t 0 ] && [ -t 1 ]; then
        codex --no-alt-screen -C "$DOTFILES_DIR"
    else
        echo "Run Codex, use /hooks, and run this installer again." >&2
        exit 1
    fi
    if ! python3 "$codex_trust_checker" "$DOTFILES_DIR"; then
        echo "Codex commit-reference hooks are not trusted. Setup stopped." >&2
        exit 1
    fi
fi

# ── Community skills (windows-protocols is too large for git, lives in ~/.agents/) ──
echo "Installing community skills..."

# --agent is required. Left to auto-detect, the tool aborts the whole install
# when any detected agent rejects a global install ("PromptScript does not
# support global skill installation") and the skill is silently never added.
# The skill lands in ~/.agents/skills or ~/.claude/skills depending on the
# release, so accept either as already-installed.
if [ ! -d ~/.agents/skills/windows-protocols ] && [ ! -d ~/.claude/skills/windows-protocols ]; then
    npx skills add awakecoding/openspecs --skill windows-protocols --agent claude-code -y -g
else
    echo "  windows-protocols already installed"
fi

# Some releases link the skill into ~/.claude/skills with a relative path. That
# directory is itself a symlink into this repo, so the path resolves against the
# repo root instead of the home directory and the link dangles. Repair only that
# case: a working link, or content installed directly, is already correct.
if [ -L ~/.claude/skills/windows-protocols ] && [ ! -e ~/.claude/skills/windows-protocols ]; then
    ln -sfn "$HOME/.agents/skills/windows-protocols" ~/.claude/skills/windows-protocols
fi

# ── Summary ──────────────────────────────────────────────────────
if [ -d "$BACKUP_DIR" ]; then
    echo ""
    echo "Backed up files that differed from repo to: $BACKUP_DIR"
    ls -1 "$BACKUP_DIR"
fi

echo "Environment setup complete!"
echo "Run 'dotfiles status' to verify symlinks."
