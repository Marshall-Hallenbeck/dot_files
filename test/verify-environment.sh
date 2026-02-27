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

echo "── System packages ──"
for pkg in zsh tmux vim python3-pip git virtualenvwrapper curl wget jq bc xclip net-tools; do
    check "package: $pkg" dpkg -s "$pkg"
done

echo "── Shell dotfiles ──"
check_file ".bash_aliases" ~/.bash_aliases
check_file ".vimrc" ~/.vimrc
check_file ".zshrc" ~/.zshrc
check_file ".gitconfig" ~/.gitconfig
check_file ".tmux.conf" ~/.tmux.conf

echo "── tmux ──"
check_dir "tpm installed" ~/.tmux/plugins/tpm
check_file "copy-to-clipboard.sh" ~/.tmux/copy-to-clipboard.sh
check "copy-to-clipboard.sh executable" test -x ~/.tmux/copy-to-clipboard.sh

echo "── nvm + Node.js ──"
check_dir "nvm installed" ~/.nvm
check "node available" bash -c 'export NVM_DIR="$HOME/.nvm" && [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" && node --version'

echo "── oh-my-zsh ──"
check_dir "oh-my-zsh installed" ~/.oh-my-zsh

echo "── atuin ──"
check_file "atuin installed" ~/.atuin/bin/env

echo "── Default shell ──"
check "zsh is default shell" grep -q "testuser.*/zsh" /etc/passwd

echo "── Claude Code config ──"
check_file "CLAUDE.md" ~/.claude/CLAUDE.md
check_file "hooks.json" ~/.claude/hooks.json
check_file "statusline.sh" ~/.claude/statusline.sh
check "statusline.sh executable" test -x ~/.claude/statusline.sh
check_file "settings.json" ~/.claude/settings.json
check_file "settings.local.json" ~/.claude/settings.local.json

echo "── Claude Code rules ──"
for rule in verification coding-practices git-conventions web-dev error-handling; do
    check_file "rule: $rule" ~/.claude/rules/$rule.md
done

echo "── Claude Code skills ──"
# Dynamically check skills that have SKILL.md files in the repo
for skill_dir in /repo/.claude/skills/*/; do
    skill=$(basename "$skill_dir")
    if [ -f "$skill_dir/SKILL.md" ]; then
        check_file "skill: $skill" ~/.claude/skills/$skill/SKILL.md
    fi
done

echo "── Claude Code hookify rules ──"
for hookify in \
    hookify.require-flakiness-investigation.local.md \
    hookify.warn-duplicate-docs.local.md; do
    check_file "hookify: $hookify" ~/.claude/$hookify
done

echo "── Claude Code agents ──"
check_file "agent: unit-test-writer" ~/.claude/agents/unit-test-writer.md

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
