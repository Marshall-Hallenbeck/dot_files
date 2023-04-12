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
echo "Making sure nmap, netcat, and socat are installed"
sudo apt install libpcap-dev nmap socat netcat-traditional

echo "Installing odat (Oracle DB testing tool)"
sudo apt install odat

echo "Installing Kerberos User Package"
sudo apt install krb5-user

echo "Installing Golang"
sudo apt install golang

echo "Adding Golang path to .zshrc"
echo 'export GOROOT=/usr/local/go' >> ~/.zshrc
echo 'export GOPATH=$HOME/go' >> ~/.zshrc
echo 'export PATH=$GOPATH/bin:$GOROOT/bin:$HOME/.local/bin:$PATH' >> ~/.zshrc 

echo "Installing pipx"
python3 -m pip install pipx
pipx ensurepath

echo "Installing CrackMapExec via pipx"
pipx install crackmapexec

echo "Installing Sliver via install script"
curl https://sliver.sh/install|sudo bash

echo "Installing Project Discovery tools"
go install -v github.com/projectdiscovery/nuclei/v2/cmd/nuclei@latest
go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest
go install -v github.com/projectdiscovery/httpx/cmd/httpx@latest
go install -v github.com/projectdiscovery/naabu/v2/cmd/naabu@latest
go install -v github.com/projectdiscovery/dnsx/cmd/dnsx@latest
go install -v github.com/projectdiscovery/proxify/cmd/proxify@latest
go install -v github.com/projectdiscovery/notify/cmd/notify@latest

echo "Making sure nuclei engine & templates are up to date"
nuclei -un
nuclei -ut

echo "Installing ffuf"
go install github.com/ffuf/ffuf/v2@latest
