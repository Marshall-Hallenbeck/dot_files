#!/bin/bash
# setup script for my security tooling, etc

### FOLDER STRUCTURE
# requires a shell that supports brace expansion (zsh, bash, etc)
echo "Creating folder structure"
mkdir -p ~/pentest/{reviews,projects,lists/{user_pass,users,passwords},tools/{ad_and_windows/coercion,av_edr,c2,cloud,cred_dumping,exploits/cves,forensics,fuzzing,privesc/{windows,linux},recon/{osint,scanning},reporting,reversing/{windows,linux,multi},win_binaries/{custom,3rd_party}}}

### DEVELOPMENT
echo "Downloading and installing dev stuff"
echo "Installing dependencies"
apt-get install -y libssl-dev libffi-dev python-dev build-essential

echo "Installing Poetry"
curl -sSL https://install.python-poetry.org | python3 -

echo "Downloading CrackMapExec from Git"
git clone --recursive https://github.com/byt3bl33d3r/CrackMapExec ~/pentest/tools/ad_and_windows/
# go to directory and `poetry install`, then you can `poetry run crackmapexec`

echo "Downloading Impacket from Git"
git clone https://github.com/fortra/impacket.git ~/pentest/tools/ad_and_windows/
# to install the sample scripts/etc, run `python3 -m pip install .`

### TOOLS
echo "Downloading and installing tools"

echo "Installing pipx"
python3 -m pip install pipx
pipx ensurepath

echo "Installing CrackMapExec via pipx"
pipx install crackmapexec

echo "Installing Sliver via install script"
curl https://sliver.sh/install|sudo bash

echo "Making sure nmap, netcat, and socat are installed"
sudo apt install nmap socat netcat-traditional

echo "Installing Kerberos User Package"
sudo apt install krb5-user
