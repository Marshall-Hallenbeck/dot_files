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

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment the following line to disable bi-weekly auto-update checks.
DISABLE_AUTO_UPDATE="true"

# Uncomment the following line to change how often to auto-update (in days).
# export UPDATE_ZSH_DAYS=13

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load?
# Standard plugins can be found in ~/.oh-my-zsh/plugins/*
# Custom plugins may be added to ~/.oh-my-zsh/custom/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(colored-man-pages colorize cp dircycle encode64 extract history sublime tmux vundle git pip python pyenv virtualenv virtualenvwrapper debian)

if [[ ! -n $CURSOR_TRACE_ID ]]; then
    source $ZSH/oh-my-zsh.sh
fi
#source $ZSH/oh-my-zsh.sh

# User configuration
# The prompt is really the only thing I care about other than plugins
# Will look like:
# [09/14/20 2:11:01 EDT] (marshall@host):~
# -➤
# With the terminal entry after the arrow

PROMPT='(%{$fg[green]%}%n@%M%{$fg[white]%})%{$fg[yellow]%}:%~ %{$fg[red]%}$(git_prompt_info)%{$reset_color%}
$(virtualenv_prompt_info)-➤ '
#-➤ '
#PROMPT='%{$fg[yellow]%}[%D{%m/%f/%y} %D{%L:%M:%S} %D{%Z}] '$PROMPT

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='mvim'
# fi

# Compilation flags
# export ARCHFLAGS="-arch x86_64"

# ssh
# export SSH_KEY_PATH="~/.ssh/rsa_id"

# Set personal aliases, overriding those provided by oh-my-zsh libs,
# plugins, and themes. Aliases can be placed here, though oh-my-zsh
# users are encouraged to define aliases within the ZSH_CUSTOM folder.
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"
# I use .bash_aliases in case zsh isn't installed on the host; naming doesn't really matter
. "$HOME/.bash_aliases"

# nvm - NOT loaded on shell start (adds ~1.2s). Use `nvm` manually when needed.
export NVM_DIR="$HOME/.nvm"
#[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
#[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

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

#zprof # uncomment this and the first line for profiling

export CLAUDE_CODE_DISABLE_AUTO_MEMORY=0  # Force on as of 2026/2/9

# for Tabby directory reporting https://github.com/Eugeny/tabby/wiki/Shell-working-directory-reporting
precmd () { echo -n "\x1b]1337;CurrentDir=$(pwd)\x07" }
