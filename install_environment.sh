#!/usr/bin/env bash
set -euo pipefail

# first, force IPv4 address because sometimes you'll get an ipv6 and no ipv4
echo 'Acquire::ForceIPv4 "true";' | sudo tee /etc/apt/apt.conf.d/1000-force-ipv4-transport

sudo apt update
sudo apt install -y zsh tmux vim python3-pip git virtualenvwrapper

wget "https://raw.githubusercontent.com/Marshall-Hallenbeck/dot_files/main/.bash_aliases" -O ~/.bash_aliases
wget "https://raw.githubusercontent.com/Marshall-Hallenbeck/dot_files/main/.vimrc" -O ~/.vimrc
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
wget "https://raw.githubusercontent.com/Marshall-Hallenbeck/dot_files/main/.tmux.conf" -O ~/.tmux.conf
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
wget "https://raw.githubusercontent.com/Marshall-Hallenbeck/dot_files/main/.zshrc" -O ~/.zshrc
curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh
echo "Environment should now be set up!"
echo "Note: Start a new tmux session and press prefix + I to install tmux plugins"
