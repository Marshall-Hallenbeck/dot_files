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
# function because awk
function myip()
{
    hostname --all-ip-addresses | awk '{ print $1 }'
}
alias ncv='nc -v'
alias start_bundle='bundle exec rails s' # fuck ruby
alias msfconsole='msfconsole -y /usr/share/metasploit-framework/config/database.yml'
alias fix_encoding='export LC_ALL=en_US.UTF-8; export LANG=en_US.UTF-8' # useful for Ruby BS
# instead of aliasing just getent ahostsv4 I gotta clean up the results
function realping()
{
    getent ahostsv4 $1 | grep STREAM | awk '{ print $1 }'
}
alias rp='realping'
alias get_displays='(cd /tmp/.X11-unix && for x in X*; do echo ":${x#X}"; done)'
alias test_x11='~/projects/dot_files/test-x11-displays.sh'
alias elevator='docker compose down -v && docker compose up'
alias build-elevator='docker compose down -v && docker compose up --build'
alias clean_docker_images='for line in $(sudo docker images -aq); do sudo docker rmi -f $line; done'

#alias q='exit'
