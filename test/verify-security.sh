#!/bin/bash
# Verification assertions for security.sh (Docker-safe subset)
# Tests folder structure creation and apt package installation only.
# Exits 0 if all checks pass, 1 if any fail.
set -u

PASS=0
FAIL=0

check() {
    local desc="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        FAIL=$((FAIL + 1))
    fi
}

check_dir() {
    check "$1" test -d "$2"
}

echo "── Pentest folder structure ──"
for dir in \
    ~/pentest/reviews \
    ~/pentest/projects \
    ~/pentest/lists/user_pass \
    ~/pentest/lists/users \
    ~/pentest/lists/passwords \
    ~/pentest/tools/ad_and_windows/coercion \
    ~/pentest/tools/ad_and_windows/av_edr \
    ~/pentest/tools/c2 \
    ~/pentest/tools/cloud \
    ~/pentest/tools/cred_dumping \
    ~/pentest/tools/exploits/cves \
    ~/pentest/tools/forensics \
    ~/pentest/tools/fuzzing \
    ~/pentest/tools/privesc/windows \
    ~/pentest/tools/privesc/linux \
    ~/pentest/tools/recon/osint \
    ~/pentest/tools/recon/scanning \
    ~/pentest/tools/reporting \
    ~/pentest/tools/reversing/windows \
    ~/pentest/tools/reversing/linux \
    ~/pentest/tools/reversing/multi \
    ~/pentest/tools/win_binaries/custom \
    ~/pentest/tools/win_binaries/3rd_party \
    ~/pentest/tools/web/burp; do
    check_dir "dir: ${dir#~/}" "$dir"
done

echo "── Security packages ──"
# Core packages available across Ubuntu, Debian, and Kali
for pkg in libssl-dev build-essential python3 python3-venv htop pipx git libpcap-dev nmap socat; do
    check "package: $pkg" dpkg -s "$pkg"
done

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
