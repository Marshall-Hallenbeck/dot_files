#zmodload zsh/zprof # uncomment this and the last line (zprof) for profiling
alias q='exit'
export ZSH=$HOME/.oh-my-zsh/
# If you come from bash you might have to change your $PATH.
# fix PATH for the box I'm on, I'm just leaving these defaults since I normally try to keep the same folder structure
# Node via nvm (hardcoded for speed - nvm.sh adds ~1.2s per shell open)
# The install script patches this line with the actual installed version
export PATH=$HOME/.nvm/versions/node/v24.0.0/bin:$HOME/node/bin/:$HOME/bin:/usr/local/bin:$PATH:$HOME/.local/bin:$HOME/.dotnet/

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

plugins=(colored-man-pages colorize cp dircycle encode64 extract history sublime tmux vundle git pip python pyenv virtualenv virtualenvwrapper debian)

source $ZSH/oh-my-zsh.sh

# User configuration
# Will look like:
# [09/14/20 2:11:01 EDT] (marshall@host):~
# -➤
# With the terminal entry after the arrow

PROMPT='(%{$fg[green]%}%n@%M%{$fg[white]%})%{$fg[yellow]%}:%~ %{$fg[red]%}$(git_prompt_info)%{$reset_color%}
$(virtualenv_prompt_info)➜ '

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
node() { nvm use default >/dev/null; unfunction node; node "$@"; }
npm()  { nvm use default >/dev/null; unfunction npm;  npm "$@"; }
npx()  { nvm use default >/dev/null; unfunction npx;  npx "$@"; }
alias loadnvm='[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"'

# Add RVM to PATH for scripting. Make sure this is the last PATH variable change.
export PATH="$PATH:$HOME/.rvm/bin"

zstyle ':completion:*:*:-command-:*:*' ignored-patterns 'strapi' 'npm'

autoload -Uz compinit
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

#zprof # uncomment this and the first line for profiling
