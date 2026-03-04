#!/bin/bash
set -euo pipefail

MODE="${1:-environment}"

echo "=== Test mode: $MODE ==="
echo "=== Distro: $(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"') ==="

# Set up /repo as a local git repository so install script can clone from it
cd /repo
git config --global user.email "test@test.com"
git config --global user.name "Test"
git init
git add -A
git commit -m "test commit"
cd /home/testuser

if [ "$MODE" = "environment" ]; then
    # Create patched copy of install script
    cp /repo/install_environment.sh /tmp/install_environment.sh

    # Patch DOTFILES_REPO to point to local git repo
    sed -i 's|^DOTFILES_REPO=.*|DOTFILES_REPO="/repo"|' /tmp/install_environment.sh

    # Strip community skills section if present (npx skills add blocks download 200MB+)
    sed -i '/Community skills/,/Summary/{/Summary/!d}' /tmp/install_environment.sh

    echo "=== Running install_environment.sh ==="
    bash /tmp/install_environment.sh

    echo ""
    echo "=== Running verification ==="
    bash /repo/test/verify-environment.sh

elif [ "$MODE" = "security" ]; then
    # Extract and run only folder structure + apt package portions of security.sh
    # Skip everything from "Installing Go" onward (interactive tools, systemd, snap)
    {
        echo '#!/bin/bash'
        echo 'sudo apt-get update'
        sed -n '5,39p' /repo/security.sh
    } > /tmp/security_subset.sh
    chmod +x /tmp/security_subset.sh

    echo "=== Running security.sh subset ==="
    bash /tmp/security_subset.sh

    echo ""
    echo "=== Running verification ==="
    bash /repo/test/verify-security.sh

else
    echo "ERROR: Unknown mode '$MODE'. Use 'environment' or 'security'." >&2
    exit 1
fi

echo ""
echo "=== All tests passed ==="
