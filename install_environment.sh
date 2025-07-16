#!/bin/bash

# first, force IPv4 address because sometimes you'll get an ipv6 and no ipv4
echo 'Acquire::ForceIPv4 "true";' | sudo tee /etc/apt/apt.conf.d/1000-force-ipv4-transport

sudo apt update
sudo apt install -y zsh tmux vim python3-pip git virtualenvwrapper

# Check if python3 exists but python does not
if command -v python3 &>/dev/null && ! command -v python &>/dev/null; then
    echo "python not found, installing python-is-python3"
    sudo apt install -y python-is-python3
fi

# Check if python is version 3.11, if not, install it and set it as default
if ! python --version 2>&1 | grep -q "Python 3.11"; then
    echo "Python is not version 3.11, installing..."
    # Add deadsnakes PPA for Ubuntu systems
    if grep -q "Ubuntu" /etc/os-release; then
        sudo apt install -y software-properties-common
        sudo add-apt-repository -y ppa:deadsnakes/ppa
    fi
    sudo apt update
    sudo apt install -y python3.11 python3.11-venv
    sudo update-alternatives --install /usr/bin/python python /usr/bin/python3.11 1
    sudo update-alternatives --set python /usr/bin/python3.11
else
    echo "Python 3.11 is already the default."
fi

wget "https://raw.githubusercontent.com/Marshall-Hallenbeck/dot_files/master/.bash_aliases" -O ~/.bash_aliases
wget "https://raw.githubusercontent.com/Marshall-Hallenbeck/dot_files/master/.vimrc" -O ~/.vimrc
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
wget "https://raw.githubusercontent.com/Marshall-Hallenbeck/dot_files/master/.tmux.conf" -O ~/.tmux.conf
tmux source ~/.tmux.conf
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
wget "https://raw.githubusercontent.com/Marshall-Hallenbeck/dot_files/master/.zshrc" -O ~/.zshrc
curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh
echo "Environment should now be set up!"
