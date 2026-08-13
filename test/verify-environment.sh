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
check_link ".conkyrc" ~/.conkyrc
check_link ".tmux.conf" ~/.tmux.conf
check_link ".msf4/config" ~/.msf4/config

echo "── Dotfile content (not clobbered by tool installers) ──"
check ".zshrc has our custom prompt" grep -q 'git_prompt_info' ~/.zshrc
check ".zshrc has our plugins" grep -qF 'plugins=(virtualenv)' ~/.zshrc
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
# shellcheck disable=SC2016
check "node available" bash -c 'export NVM_DIR="$HOME/.nvm" && [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" && node --version'

echo "── oh-my-zsh ──"
check_dir "oh-my-zsh installed" ~/.oh-my-zsh

echo "── atuin ──"
check_file "atuin installed" ~/.atuin/bin/env

echo "── Claude Code ──"
# shellcheck disable=SC2016
check "claude CLI installed" bash -c 'export PATH="$HOME/.local/bin:$PATH"; export NVM_DIR="$HOME/.nvm" && [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" && command -v claude'

echo "── Default shell ──"
check "zsh is default shell" grep -q "testuser.*/zsh" /etc/passwd

echo "── Claude Code config ──"
check_link "CLAUDE.md" ~/.claude/CLAUDE.md
check_link "statusline.sh" ~/.claude/statusline.sh
check "statusline.sh executable" test -x ~/.claude/statusline.sh
check_link "settings.json" ~/.claude/settings.json
check_link "Claude learned insights" ~/.claude/global-learned-insights.md
check_link "Codex learned insights" ~/.codex/global-learned-insights.md
# shellcheck disable=SC2016
check "learned insights share the tracked file" bash -c '
    expected=$(readlink -f "$HOME/.dot_files/.claude/global-learned-insights.md") &&
    [ "$(readlink -f "$HOME/.claude/global-learned-insights.md")" = "$expected" ] &&
    [ "$(readlink -f "$HOME/.codex/global-learned-insights.md")" = "$expected" ]
'

echo "── Claude Code rules ──"
for rule in verification coding-practices git-conventions web-dev error-handling docker; do
    check_link "rule: $rule" ~/.claude/rules/$rule.md
done

echo "── Claude Code skills ──"
# skills/ is deployed as a whole-directory symlink, so individual SKILL.md files
# are real files inside it (not individual symlinks). Verify the dir symlink,
# then that each repo skill resolves through it.
check "skills dir is a symlink" test -L ~/.claude/skills
for skill_dir in /repo/.claude/skills/*/; do
    skill=$(basename "$skill_dir")
    if [ -f "$skill_dir/SKILL.md" ]; then
        check_file "skill: $skill" ~/.claude/skills/"$skill"/SKILL.md
    fi
done

echo "── Claude Code hookify rules ──"
for hookify_file in /repo/.claude/hookify.*.local.md; do
    [ -e "$hookify_file" ] || continue
    hookify=$(basename "$hookify_file")
    check_link "hookify: $hookify" ~/.claude/"$hookify"
done

echo "── Claude Code agents ──"
for agent_file in /repo/.claude/agents/*.md; do
    [ -e "$agent_file" ] || continue
    agent=$(basename "$agent_file" .md)
    check_link "agent: $agent" ~/.claude/agents/"$agent".md
done

echo "── Claude Code commands ──"
for cmd_file in /repo/.claude/commands/*.md; do
    [ -e "$cmd_file" ] || continue
    cmd=$(basename "$cmd_file" .md)
    check_link "command: $cmd" ~/.claude/commands/"$cmd".md
done

echo "── dotfiles helper ──"
check_link "dotfiles helper" ~/.local/bin/dotfiles

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
