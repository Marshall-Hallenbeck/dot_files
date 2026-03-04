#!/bin/bash
# Verification assertions for install_environment.sh
# Exits 0 if all checks pass, 1 if any fail.
set -u

PASS=0
FAIL=0

check() {
    local desc="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        FAIL=$((FAIL + 1))
    fi
}

check_file() {
    check "$1" test -f "$2"
}

check_dir() {
    check "$1" test -d "$2"
}

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

echo "── System packages ──"
for pkg in zsh tmux vim python3-pip git virtualenvwrapper curl wget jq bc xclip net-tools; do
    check "package: $pkg" dpkg -s "$pkg"
done

echo "── Shell dotfiles ──"
check_link ".bash_aliases" ~/.bash_aliases
check_link ".vimrc" ~/.vimrc
check_link ".zshrc" ~/.zshrc
check_link ".gitconfig" ~/.gitconfig
check_link ".tmux.conf" ~/.tmux.conf

echo "── Dotfile content (not clobbered by tool installers) ──"
check ".zshrc has our custom prompt" grep -q 'git_prompt_info' ~/.zshrc
check ".zshrc has our plugins" grep -q 'colored-man-pages' ~/.zshrc
check ".zshrc NOT oh-my-zsh template" bash -c '! grep -q "ZSH_THEME=\"robbyrussell\"" ~/.zshrc'
check ".zshrc does NOT have hardcoded node path" bash -c '! grep -q "v24.0.0" ~/.zshrc'
check ".zshrc sources .zshrc.local" grep -q 'zshrc.local' ~/.zshrc
check ".bash_aliases sources .bash_aliases.local" grep -q 'bash_aliases.local' ~/.bash_aliases

echo "── tmux ──"
check_dir "tpm installed" ~/.tmux/plugins/tpm
check_link "copy-to-clipboard.sh" ~/.tmux/copy-to-clipboard.sh
check "copy-to-clipboard.sh executable" test -x ~/.tmux/copy-to-clipboard.sh

echo "── nvm + Node.js ──"
check_dir "nvm installed" ~/.nvm
check "node available" bash -c 'export NVM_DIR="$HOME/.nvm" && [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" && node --version'

echo "── oh-my-zsh ──"
check_dir "oh-my-zsh installed" ~/.oh-my-zsh

echo "── atuin ──"
check_file "atuin installed" ~/.atuin/bin/env

echo "── Claude Code ──"
check "claude CLI installed" bash -c 'export NVM_DIR="$HOME/.nvm" && [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" && command -v claude'

echo "── Default shell ──"
check "zsh is default shell" grep -q "testuser.*/zsh" /etc/passwd

echo "── Claude Code config ──"
check_link "CLAUDE.md" ~/.claude/CLAUDE.md
check_link "hooks.json" ~/.claude/hooks.json
check_link "statusline.sh" ~/.claude/statusline.sh
check "statusline.sh executable" test -x ~/.claude/statusline.sh
check_link "settings.json" ~/.claude/settings.json
check_link "settings.local.json" ~/.claude/settings.local.json

echo "── Claude Code rules ──"
for rule in verification coding-practices git-conventions web-dev error-handling docker; do
    check_link "rule: $rule" ~/.claude/rules/$rule.md
done

echo "── Claude Code skills ──"
# Dynamically check skills that have SKILL.md files in the repo
for skill_dir in /repo/.claude/skills/*/; do
    skill=$(basename "$skill_dir")
    if [ -f "$skill_dir/SKILL.md" ]; then
        check_link "skill: $skill" ~/.claude/skills/$skill/SKILL.md
    fi
done

echo "── Claude Code hookify rules ──"
for hookify in \
    hookify.require-flakiness-investigation.local.md \
    hookify.warn-duplicate-docs.local.md; do
    check_link "hookify: $hookify" ~/.claude/$hookify
done

echo "── Claude Code agents ──"
check_link "agent: unit-test-writer" ~/.claude/agents/unit-test-writer.md

echo "── dotfiles helper ──"
check_link "dotfiles helper" ~/.local/bin/dotfiles

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
