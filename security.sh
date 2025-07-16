#!/usr/bin/env zsh
# shellcheck disable=SC1071
# setup script for my security tooling, etc

### FOLDER STRUCTURE
# requires a shell that supports brace expansion (zsh, bash, etc)
echo "Creating folder structure"
mkdir -p ~/pentest/{reviews,projects,lists/{user_pass,users,passwords},tools/{ad_and_windows/{coercion,av_edr},c2,cloud,cred_dumping,exploits/cves,forensics,fuzzing,privesc/{windows,linux},recon/{osint,scanning},reporting,reversing/{windows,linux,multi},win_binaries/{custom,3rd_party},web/burp}}

### DEVELOPMENT
echo "Downloading and installing dev stuff"
echo "Installing stuff via apt"
sudo apt install -y libssl-dev libffi-dev build-essential python3 python3-venv golang htop pipx git libpcap-dev nmap socat netcat-traditional odat krb5-user cidrgrep 

pipx ensurepath --prepend

echo "Installing uv"
pipx install uv

echo "Adding Golang path to .zshrc"
{
    echo ""
    echo "# Golang paths"
    echo 'export GOROOT=/usr/lib/go'
    echo "export GOPATH=\$HOME/go"
    echo "export PATH=\$GOPATH/bin:\$GOROOT/bin:\$HOME/.local/bin:\$PATH"
} >> ~/.zshrc

echo "Sourcing .zshrc to apply Go paths for this session"
# shellcheck disable=SC1090
source ~/.zshrc

echo "Installing Poetry"
curl -sSL https://install.python-poetry.org | python -

echo "Installing Impacket from Git"
pipx install git+https://github.com/fortra/impacket.git
#git clone https://github.com/fortra/impacket.git ~/pentest/tools/ad_and_windows/impacket
# to install the sample scripts/etc, run `python3 -m pip install .`

### TOOLS
echo "Installing cidrize"
pip install cidrize

echo "Installing NetExec via GitHub"
pipx install git+https://github.com/Pennyw0rth/NetExec
register-python-argcomplete nxc >> ~/.zshrc

echo "Installing smbclientng"
pipx install smbclientng

echo "Installing Sliver via install script"
curl https://sliver.sh/install|sudo bash

echo "Installing BurpSuitePro"
wget "https://portswigger.net/burp/releases/download?product=pro&version=2025.6.3&type=Linux" -O burp_suite_pro.sh
chmod +x burp_suite_pro.sh
./burp_suite_pro.sh

echo "Installing Project Discovery tools"
go install -v github.com/projectdiscovery/pdtm/cmd/pdtm@latest
pdtm -install-all

echo "Installing ffuf"
go install github.com/ffuf/ffuf/v2@latest

# echo "Installing ScareCrow"
# echo "First installing dependencies"
# go get github.com/fatih/color
# go get github.com/yeka/zip
# go get github.com/josephspurrier/goversioninfo
# go get github.com/Binject/debug/pe
# go get github.com/awgh/rawreader

# git clone https://github.com/optiv/ScareCrow.git ~/pentest/tools/av_edr/ScareCrow/
# cd ~/pentest/tools/av_edr/ScareCrow/ || exit
# go build ScareCrow.go
# echo "Installing ScareCrow to /usr/local/bin/"
# sudo cp ScareCrow /usr/local/bin/
