#!/bin/bash

sudo apt update
sudo apt install zsh tmux vim python3-pip
wget "https://raw.githubusercontent.com/Marshall-Hallenbeck/dot_files/master/.bash_aliases" -O ~/.bash_aliases
wget "https://raw.githubusercontent.com/Marshall-Hallenbeck/dot_files/master/.vimrc" -O ~/.vimrc
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
wget "https://raw.githubusercontent.com/Marshall-Hallenbeck/dot_files/master/.tmux.conf" -O ~/.tmux.conf
tmux source ~/.tmux.conf
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
wget "https://raw.githubusercontent.com/Marshall-Hallenbeck/dot_files/master/.zshrc" -O ~/.zshrc
pip3 install virtualenvwrapper
echo "Environment should now be set up!"
