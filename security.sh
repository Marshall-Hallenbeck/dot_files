#!/bin/bash
# setup script for my security tooling, etc

### FOLDER STRUCTURE
# requires a shell that supports brace expansion (zsh, bash, etc)
# can combine these later, but it was easier to create them like this
echo "Creating folder structure"
mkdir -p ~/pentest/reviews
mkdir -p ~/pentest/projects
mkdir -p ~/pentest/lists
mkdir -p ~/pentest/tools
mkdir -p ~/pentest/lists/user_pass
mkdir -p ~/pentest/lists/users
mkdir -p ~/pentest/lists/passwords
mkdir -p ~/pentest/tools/ad_and_windows/coercion
mkdir -p ~/pentest/tools/ad_and_windows/av_edr
mkdir -p ~/pentest/tools/c2/
mkdir -p ~/pentest/tools/cloud/
mkdir -p ~/pentest/tools/cred_dumping/
mkdir -p ~/pentest/tools/exploits/cves/
mkdir -p ~/pentest/tools/forensics/
mkdir -p ~/pentest/tools/fuzzing/
mkdir -p ~/pentest/tools/privesc/windows
mkdir -p ~/pentest/tools/privesc/linux
mkdir -p ~/pentest/tools/recon/osint
mkdir -p ~/pentest/tools/recon/scanning
mkdir -p ~/pentest/tools/reporting/
mkdir -p ~/pentest/tools/reversing/windows
mkdir -p ~/pentest/tools/reversing/linux
mkdir -p ~/pentest/tools/reversing/multi
mkdir -p ~/pentest/tools/win_binaries/custom
mkdir -p ~/pentest/tools/win_binaries/3rd_party

### DEVELOPMENT
echo "Downloading and installing dev stuff"
echo "Installing stuff via apt"
sudo apt install -y libssl-dev libffi-dev build-essential python3 python3-venv golang htop pipx git libpcap-dev nmap socat netcat-traditional odat krb5-user cidrgrep 

echo "Adding Golang path to .zshrc"
echo 'export GOROOT=/usr/lib/go' >> ~/.zshrc
echo 'export GOPATH=$HOME/go' >> ~/.zshrc
echo 'export PATH=$GOPATH/bin:$GOROOT/bin:$HOME/.local/bin:$PATH' >> ~/.zshrc 

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
pipx ensurepath
pipx install git+https://github.com/Pennyw0rth/NetExec
register-python-argcomplete nxc >> ~/.zshrc

echo "Installing smbclientng"
pipx install smbclientng

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

echo "Installing ScareCrow"
echo "First installing dependencies"
go get github.com/fatih/color
go get github.com/yeka/zip
go get github.com/josephspurrier/goversioninfo
go get github.com/Binject/debug/pe
go get github.com/awgh/rawreader

git clone https://github.com/optiv/ScareCrow.git ~/pentest/tools/av_edr/ScareCrow/
cd ~/pentest/tools/av_edr/ScareCrow/ || exit
go build ScareCrow.go
echo "Installing ScareCrow to /usr/local/bin/"
sudo cp ScareCrow /usr/local/bin/
