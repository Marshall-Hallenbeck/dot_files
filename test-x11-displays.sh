#!/bin/bash
echo "=== X11 Display Enumeration ==="
echo ""

displays=$(xauth list 2>/dev/null | awk '{print $1}' | grep -oE ':[0-9]+' | sort -u)

if [ -z "$displays" ]; then
    echo "No X displays found in xauth"
fi

echo "Testing displays..."
echo ""

for display in $displays; do
    if timeout 2 xclip -selection clipboard -display "$display" <<< "test" 2>/dev/null; then
        echo "[OK]     $display"
    else
        echo "[FAILED] $display"
    fi
done
