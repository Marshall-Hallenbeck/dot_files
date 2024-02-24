# ls stuff
alias ls='ls --color=auto'
alias sl='ls'
alias LS='ls'
alias ll='ls -lahF'

# makes cd up one dir easier
alias ..='cd ..'

# for nuking older logs
alias clean_logs='sudo find /var/log -mindepth 2 -mtime +5 -delete'

# manual clear
alias cls='printf "\033c"'

# for going to my data drive - manually enable this if I have a /data drive
# alias data='cd /data'

# digital ocean stuff
# add this stuff manually, I don't want to unnecessarily expose my DNS names

# fix my ssh_agent cause tmux messes it up I think
# manually add/fix the default ssh keys I use, this depends on the box I'm on
alias start_ssh_agent='ssh-agent zsh
eval $(ssh-agent)
ssh-add ~/.ssh/id_rsa
ssh-add ~/.ssh/main'

# xclip for copying from terminal
alias xclip='xclip -selection c'
alias xclipx='tr -d "\n" | xclip -selection c'

alias curlv='curl -v'
alias exploitdb='cd /usr/share/exploitdb/'
alias listening_ports='sudo netstat -plnt'
alias myip='hostname --all-ip-addresses | awk {"print $1"}'
alias ncv='nc -v'
alias start_bundle='bundle exec rails s' # fuck ruby
alias msfconsole='msfconsole -y /usr/share/metasploit-framework/config/database.yml'
