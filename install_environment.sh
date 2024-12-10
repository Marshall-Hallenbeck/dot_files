#!/bin/bash

# first, force IPv4 address because sometimes you'll get an ipv6 and no ipv4
echo 'Acquire::ForceIPv4 "true";' | sudo tee /etc/apt/apt.conf.d/1000-force-ipv4-transport

sudo apt update
sudo apt install -y zsh tmux vim python3-pip git
wget "https://raw.githubusercontent.com/Marshall-Hallenbeck/dot_files/master/.bash_aliases" -O ~/.bash_aliases
wget "https://raw.githubusercontent.com/Marshall-Hallenbeck/dot_files/master/.vimrc" -O ~/.vimrc
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
wget "https://raw.githubusercontent.com/Marshall-Hallenbeck/dot_files/master/.tmux.conf" -O ~/.tmux.conf
tmux source ~/.tmux.conf
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
wget "https://raw.githubusercontent.com/Marshall-Hallenbeck/dot_files/master/.zshrc" -O ~/.zshrc
echo "Installing virtualenvwrapper via pip3"
pip3 install virtualenvwrapper
echo "Environment should now be set up!"
