#!/bin/bash

# first, force IPv4 address because sometimes you'll get an ipv6 and no ipv4
echo 'Acquire::ForceIPv4 "true";' | sudo tee /etc/apt/apt.conf.d/1000-force-ipv4-transport

sudo apt update
sudo apt install -y zsh tmux vim python3-pip git virtualenvwrapper

# Find and install the latest available Python 3 version
# Add deadsnakes PPA for Ubuntu systems
if grep -q "Ubuntu" /etc/os-release; then
    echo "Adding deadsnakes PPA for Ubuntu to get newer Python versions"
    sudo apt-get install -y software-properties-common
    sudo add-apt-repository -y ppa:deadsnakes/ppa
    sudo apt-get update
fi

# Find the latest python3.x package available from apt.
# The output of search can be like "python3.9 - ...", so we pipe to cut.
LATEST_PYTHON_PKG=$(apt-cache search --names-only '^python3\.[0-9]+$' | cut -d' ' -f1 | sort -V | tail -n 1)

if [ -z "$LATEST_PYTHON_PKG" ]; then
    echo "Could not find any specific python3.x package. Will use the default python3."
    LATEST_PYTHON_PKG="python3"
fi

# For python3 we need python3-venv, for python3.11 we need python3.11-venv
VENV_PKG="${LATEST_PYTHON_PKG}-venv"

echo "Latest available Python package is $LATEST_PYTHON_PKG"
echo "Installing $LATEST_PYTHON_PKG and $VENV_PKG..."
sudo apt-get install -y "$LATEST_PYTHON_PKG" "$VENV_PKG"

echo "Setting $LATEST_PYTHON_PKG as the default python..."
PYTHON_EXECUTABLE="/usr/bin/$LATEST_PYTHON_PKG"
sudo update-alternatives --install /usr/bin/python python "$PYTHON_EXECUTABLE" 1
sudo update-alternatives --set python "$PYTHON_EXECUTABLE"

echo "Default python is now: $(python --version 2>&1)"

wget "https://raw.githubusercontent.com/Marshall-Hallenbeck/dot_files/master/.bash_aliases" -O ~/.bash_aliases
wget "https://raw.githubusercontent.com/Marshall-Hallenbeck/dot_files/master/.vimrc" -O ~/.vimrc
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
wget "https://raw.githubusercontent.com/Marshall-Hallenbeck/dot_files/master/.tmux.conf" -O ~/.tmux.conf
tmux source ~/.tmux.conf
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
wget "https://raw.githubusercontent.com/Marshall-Hallenbeck/dot_files/master/.zshrc" -O ~/.zshrc
curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh
echo "Environment should now be set up!"
