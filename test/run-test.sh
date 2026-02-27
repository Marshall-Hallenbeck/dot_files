#!/bin/bash
set -euo pipefail

MODE="${1:-environment}"

echo "=== Test mode: $MODE ==="
echo "=== Distro: $(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"') ==="

# Start HTTP server serving the repo files
cd /repo
python3 -m http.server 8765 &
HTTP_PID=$!

# Wait for server readiness
for i in $(seq 1 30); do
    if curl -sf http://127.0.0.1:8765/ >/dev/null 2>&1; then
        echo "HTTP server ready"
        break
    fi
    if [ "$i" = "30" ]; then
        echo "ERROR: HTTP server failed to start" >&2
        exit 1
    fi
    sleep 0.2
done

cd /home/testuser

if [ "$MODE" = "environment" ]; then
    # Create patched copy of install script
    cp /repo/install_environment.sh /tmp/install_environment.sh

    # Patch REPO_BASE to point to local HTTP server
    sed -i 's|^REPO_BASE=.*|REPO_BASE="http://127.0.0.1:8765"|' /tmp/install_environment.sh

    # Strip community skills section if present (npx skills add blocks download 200MB+)
    sed -i '/Community skills/,/Summary/{/Summary/!d}' /tmp/install_environment.sh

    # Filter SKILL_DIRS to only skills that have SKILL.md files in the repo
    AVAILABLE_SKILLS=""
    for skill_dir in /repo/.claude/skills/*/; do
        skill=$(basename "$skill_dir")
        if [ -f "$skill_dir/SKILL.md" ]; then
            AVAILABLE_SKILLS="$AVAILABLE_SKILLS $skill"
        fi
    done
    sed -i "s|^SKILL_DIRS=.*|SKILL_DIRS=\"${AVAILABLE_SKILLS# }\"|" /tmp/install_environment.sh

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

# HTTP server cleanup handled by container exit
echo ""
echo "=== All tests passed ==="
