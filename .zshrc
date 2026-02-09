# fix PATH for the box I'm on
export PATH=$HOME/bin:/usr/local/bin:$PATH:$HOME/.local/bin

# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Use oh-my-zsh's HIST_STAMPS instead of bash's HISTTIMEFORMAT
HIST_STAMPS="mm/dd/yyyy"

TIMEFMT=$'\n================\nCPU\t%P\nuser\t%*U\nsystem\t%*S\ntotal\t%*E'

# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME="agnoster"

# Auto-correct commands only, not arguments
ENABLE_CORRECTION="true"
setopt nocorrectall; setopt correct

# Display red dots whilst waiting for completion
COMPLETION_WAITING_DOTS="true"

# Plugins - add wisely, as too many plugins slow down shell startup
# Removed: vundle (no Vundle config in .vimrc), sublime (not in use)
plugins=(colored-man-pages colorize cp dircycle encode64 extract history tmux git pip python pyenv virtualenv virtualenvwrapper debian)

source $ZSH/oh-my-zsh.sh

# Custom prompt:
# [09/14/20 2:11:01 EDT] (marshall@host):~ (git-branch)
# -➤
PROMPT='%{$fg[yellow]%}[%D{%m/%f/%y} %D{%L:%M:%S} %D{%Z}] (%{$fg[green]%}%n@%M%{$fg[white]%})%{$fg[yellow]%}:%~ %{$fg[red]%}$(git_prompt_info)%{$reset_color%}
$(virtualenv_prompt_info)-➤ '

# I use .bash_aliases in case zsh isn't installed on the host; naming doesn't really matter
. "$HOME/.bash_aliases"
