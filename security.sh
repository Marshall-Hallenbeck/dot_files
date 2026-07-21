#!/usr/bin/env zsh
# shellcheck disable=SC1071
# setup script for my security tooling, etc

set -euo pipefail

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

# Install available packages (skip already-installed)
for pkg in "${AVAILABLE_PACKAGES[@]}"; do
    dpkg -s "$pkg" &> /dev/null || sudo apt install -y "$pkg"
done

# Report unavailable packages
if [ ${#UNAVAILABLE_PACKAGES[@]} -gt 0 ]; then
    echo "The following packages were not found and could not be installed:"
    printf -- " - %s\n" "${UNAVAILABLE_PACKAGES[@]}"
fi

# Conditionally install Go based on the OS version
if ! command -v go &>/dev/null; then
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
fi

pipx ensurepath

# Capture installed pipx packages once, then guard installs against it. A
# herestring (not a pipe) avoids a SIGPIPE race with grep -q under pipefail, and
# checking the captured list keeps re-runs idempotent under set -euo pipefail.
PIPX_INSTALLED=$(pipx list --short 2>/dev/null || true)
pipx_install_if_missing() {
    local name="$1"; shift
    grep -qi "^$name " <<<"$PIPX_INSTALLED" || pipx install "$@"
}

echo "Installing uv"
command -v uv >/dev/null 2>&1 || pipx install uv

if ! command -v poetry &> /dev/null; then
    echo "Installing Poetry"
    curl -fsSL https://install.python-poetry.org | python3 -
fi

echo "Installing Impacket from Git"
pipx_install_if_missing impacket git+https://github.com/fortra/impacket.git
#git clone https://github.com/fortra/impacket.git ~/pentest/tools/ad_and_windows/impacket
# to install the sample scripts/etc, run `python3 -m pip install .`

### TOOLS
echo "Installing cidrize"
pipx_install_if_missing cidrize cidrize

echo "Installing NetExec via GitHub, uv (editable)"
NETEXEC_DIR="$HOME/pentest/tools/ad_and_windows/NetExec"
[ -d "$NETEXEC_DIR" ] || git clone https://github.com/Pennyw0rth/NetExec "$NETEXEC_DIR"
uv tool install "$NETEXEC_DIR" -e --force
# pipx install git+https://github.com/Pennyw0rth/NetExec

echo "Installing smbclientng"
pipx_install_if_missing smbclientng smbclientng

echo "Installing full smbcrawler"
pipx_install_if_missing smbcrawler 'smbcrawler[binary-conversion]'

if ! command -v sliver &> /dev/null; then
    echo "Installing Sliver via install script"
    # Download to a file (with -f so an HTTP error body is never piped to a root
    # shell), then run — instead of `curl | sudo bash`.
    sliver_installer=$(mktemp)
    curl -fsSL https://sliver.sh/install -o "$sliver_installer"
    sudo bash "$sliver_installer"
    rm -f "$sliver_installer"
fi

if [ ! -d "$HOME/BurpSuitePro" ]; then
    echo "Installing BurpSuitePro"
    wget "https://portswigger.net/burp/releases/download?product=pro&type=Linux" -O ~/burp_suite_pro.sh
    chmod +x ~/burp_suite_pro.sh
    # Run in a subshell (not sourced) so the installer can't leak into or abort
    # this script under set -e.
    bash ~/burp_suite_pro.sh
    rm -f ~/burp_suite_pro.sh
fi

if ! command -v pdtm &> /dev/null; then
    echo "Installing Project Discovery tools"
    go install github.com/projectdiscovery/pdtm/cmd/pdtm@latest
fi
# go installs to $GOPATH/bin (default ~/go/bin), which may not be on PATH — add
# it so pdtm is runnable (otherwise set -e aborts here on a fresh install).
GOPATH_BIN="$(go env GOPATH)/bin"
export PATH="$GOPATH_BIN:$PATH"
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
