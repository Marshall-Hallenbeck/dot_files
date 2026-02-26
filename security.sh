#!/usr/bin/env zsh
# shellcheck disable=SC1071
# setup script for my security tooling, etc

### FOLDER STRUCTURE
# requires a shell that supports brace expansion (zsh, bash, etc)
echo "Creating folder structure"
mkdir -p ~/pentest/{reviews,projects,lists/{user_pass,users,passwords},tools/{ad_and_windows/{coercion,av_edr},c2,cloud,cred_dumping,exploits/cves,forensics,fuzzing,privesc/{windows,linux},recon/{osint,scanning},reporting,reversing/{windows,linux,multi},win_binaries/{custom,3rd_party},web/burp}}

### DEVELOPMENT
echo "Installing necessary dependencies"

PACKAGES=(libssl-dev libffi-dev build-essential python3 python3-venv htop pipx git libpcap-dev nmap socat netcat-traditional odat krb5-user cidrgrep)
AVAILABLE_PACKAGES=()
UNAVAILABLE_PACKAGES=()

# Check each package for availability in apt
for pkg in "${PACKAGES[@]}"; do
    if apt-cache show "$pkg" > /dev/null 2>&1; then
        AVAILABLE_PACKAGES+=("$pkg")
    else
        UNAVAILABLE_PACKAGES+=("$pkg")
    fi
done

# Install available packages
if [ ${#AVAILABLE_PACKAGES[@]} -gt 0 ]; then
    echo "Installing available packages..."
    if ! sudo apt install -y "${AVAILABLE_PACKAGES[@]}"; then
        echo "Failed to install dependencies, exiting." >&2
        exit 1
    fi
fi

# Report unavailable packages
if [ ${#UNAVAILABLE_PACKAGES[@]} -gt 0 ]; then
    echo "The following packages were not found and could not be installed:"
    printf -- " - %s\n" "${UNAVAILABLE_PACKAGES[@]}"
fi

# Conditionally install Go based on the OS version
echo "Installing Go..."
if lsb_release -d 2>/dev/null | grep -q "Ubuntu 20.04"; then
    echo "Detected Ubuntu 20.04. Installing Go via Snap..."
    if ! sudo snap install go --classic; then
        echo "Failed to install Go via Snap. Exiting." >&2
        exit 1
    fi
else
    echo "Installing Go via apt..."
    if ! sudo apt install -y golang; then
        echo "Failed to install Go via apt. Please check if 'golang' is available in your repositories."
    fi
fi

pipx ensurepath

echo "Installing uv"
pipx install uv

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

echo "Installing full smbcrawler"
pipx install 'smbcrawler[binary-conversion]'

echo "Installing Sliver via install script"
curl https://sliver.sh/install|sudo bash

echo "Installing BurpSuitePro"
wget "https://portswigger.net/burp/releases/download?product=pro&type=Linux" -O burp_suite_pro.sh # if you dont include version parameter it downloads the newest release
chmod +x burp_suite_pro.sh
./burp_suite_pro.sh

echo "Installing Project Discovery tools"
go get github.com/projectdiscovery/pdtm/cmd/pdtm@latest
pdtm -install-all

#echo "Installing ffuf"
#go get github.com/ffuf/ffuf/v2@latest

#echo "First installing dependencies"
#go get github.com/fatih/color
#go get github.com/yeka/zip
#go get github.com/josephspurrier/goversioninfo
#go get github.com/Binject/debug/pe
#go get github.com/awgh/rawreader

#git clone https://github.com/optiv/ScareCrow.git ~/pentest/tools/av_edr/ScareCrow/
#cd ~/pentest/tools/av_edr/ScareCrow/ || exit
#go build ScareCrow.go
#echo "Installing ScareCrow to /usr/local/bin/"
#sudo cp ScareCrow /usr/local/bin/
