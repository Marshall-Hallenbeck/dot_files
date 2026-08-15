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

# The installer must fail closed when Codex hooks are not trusted. This
# noninteractive test cannot approve hooks through /hooks, so trust only the two
# hook entries copied from this test commit. A hooks.json change must update these
# hashes after review or the integration test will stop at the trust gate.
mkdir -p "$HOME/.codex"
cat > "$HOME/.codex/config.toml" <<EOF
[hooks.state]

[hooks.state."$HOME/.codex/hooks.json:pre_tool_use:0:0"]
trusted_hash = "sha256:09adc401b761208447da5049dc1372aa2063c63b758b0319389e04b3148096be"

[hooks.state."$HOME/.codex/hooks.json:session_start:0:0"]
trusted_hash = "sha256:9c5076fb7df34c41d6c50a42f5eca7cdca7800af79d01c958aeaeea80010a487"
EOF

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
        echo 'set -euo pipefail'
        echo 'sudo apt-get update'
        # Extract folder-structure + package section, up to (not including) the
        # Go block. Marker-based so it survives line-number shifts in security.sh.
        # set -euo pipefail is prepended so the subset runs under the same
        # strictness as the real security.sh (which sets it at the top).
        sed -n '/^### FOLDER STRUCTURE/,/^# Conditionally install Go/p' /repo/security.sh | head -n -1
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
