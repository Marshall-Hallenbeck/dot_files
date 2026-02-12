#!/bin/bash

# first, force IPv4 address because sometimes you'll get an ipv6 and no ipv4
echo 'Acquire::ForceIPv4 "true";' | sudo tee /etc/apt/apt.conf.d/1000-force-ipv4-transport

sudo apt update
sudo apt install -y zsh tmux vim python3-pip git virtualenvwrapper

wget "https://raw.githubusercontent.com/Marshall-Hallenbeck/dot_files/main/.bash_aliases" -O ~/.bash_aliases
wget "https://raw.githubusercontent.com/Marshall-Hallenbeck/dot_files/main/.vimrc" -O ~/.vimrc
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
wget "https://raw.githubusercontent.com/Marshall-Hallenbeck/dot_files/main/.tmux.conf" -O ~/.tmux.conf
tmux source ~/.tmux.conf
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
wget "https://raw.githubusercontent.com/Marshall-Hallenbeck/dot_files/main/.zshrc" -O ~/.zshrc
curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh

# Claude Code global configuration
echo "Setting up Claude Code configuration..."
mkdir -p ~/.claude/rules \
         ~/.claude/skills/safe-commit ~/.claude/skills/summarize-changes \
         ~/.claude/skills/postflight ~/.claude/skills/lookup-docs \
         ~/.claude/skills/create-pr ~/.claude/skills/git-status \
         ~/.claude/skills/recall-memory ~/.claude/agents

CLAUDE_BASE="https://raw.githubusercontent.com/Marshall-Hallenbeck/dot_files/main/.claude"

# Global instructions, rules, skills, and agents (always safe to overwrite)
wget "$CLAUDE_BASE/CLAUDE.md" -O ~/.claude/CLAUDE.md
for rule in verification coding-practices git-conventions web-dev; do
    wget "$CLAUDE_BASE/rules/$rule.md" -O ~/.claude/rules/$rule.md
done
for skill in safe-commit summarize-changes postflight lookup-docs create-pr git-status recall-memory; do
    wget "$CLAUDE_BASE/skills/$skill/SKILL.md" -O ~/.claude/skills/$skill/SKILL.md
done
wget "$CLAUDE_BASE/agents/unit-test-writer.md" -O ~/.claude/agents/unit-test-writer.md

# settings.json: only install if not present (preserves host-specific accumulated permissions)
if [ ! -f ~/.claude/settings.json ]; then
    wget "$CLAUDE_BASE/settings.json" -O ~/.claude/settings.json
else
    echo "~/.claude/settings.json already exists, skipping (update manually if needed)"
fi

echo "Environment should now be set up!"
