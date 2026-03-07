#zmodload zsh/zprof # uncomment this and the last line (zprof) for profiling
alias q='exit'
export ZSH=$HOME/.oh-my-zsh/
# If you come from bash you might have to change your $PATH.
# PATH setup — nvm lazy-load wrappers handle node/npm/npx (see below)
export PATH=$HOME/bin:/usr/local/bin:$PATH:$HOME/.local/bin:$HOME/.dotnet/

# Path to your oh-my-zsh installation.
# Path depends on my username on the box. I can probably make this dynamic but whatever
#export ZSH="$HOME/.oh-my-zsh"

export HISTTIMEFORMAT="%m/%d/%y %T "

TIMEFMT=$'\n================\nCPU\t%P\nuser\t%*U\nsystem\t%*S\ntotal\t%*E'

ENABLE_CORRECTION="true"
COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

plugins=(virtualenv)

# Skip compaudit insecure-directory check — single-user system
ZSH_DISABLE_COMPFIX=true
source $ZSH/oh-my-zsh.sh

# User configuration
# Will look like:
# [09/14/20 2:11:01 EDT] (marshall@host):~
# -➤
# With the terminal entry after the arrow

PROMPT='(%{$fg[green]%}%n@%M%{$fg[white]%})%{$fg[yellow]%}:%~ %{$fg[red]%}$(git_prompt_info)%{$reset_color%}
$(virtualenv_prompt_info)➜  '

#$(virtualenv_prompt_info)-➤ '

export LANG=en_US.UTF-8

# I use .bash_aliases in case zsh isn't installed on the host; naming doesn't really matter
. "$HOME/.bash_aliases"

# nvm - lazy-loaded to avoid ~1.2s shell startup penalty
export NVM_DIR="$HOME/.nvm"
nvm() {
  unfunction nvm node npm npx
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
  nvm "$@"
}
node() { nvm use default >/dev/null; command node "$@"; }
npm()  { nvm use default >/dev/null; command npm "$@"; }
npx()  { nvm use default >/dev/null; command npx "$@"; }
alias loadnvm='[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"'

zstyle ':completion:*:*:-command-:*:*' ignored-patterns 'strapi' 'npm'

zstyle ':completion:*' menu select
fpath+=~/.zfunc

# only autocorrect commands, not arguments; this must be below any zstyle completion lines
setopt nocorrectall; setopt correct;

if [ -f "$HOME/.atuin/bin/env" ]; then
    . "$HOME/.atuin/bin/env"
    eval "$(atuin init zsh)"
fi

export CLAUDE_CODE_DISABLE_AUTO_MEMORY=0  # Force on as of 2026/2/9

# for Tabby directory reporting https://github.com/Eugeny/tabby/wiki/Shell-working-directory-reporting
precmd () { echo -n "\x1b]1337;CurrentDir=$(pwd)\x07" }

# Per-host overrides (not in repo, not symlinked)
[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"

#zprof # uncomment this and the first line for profiling
