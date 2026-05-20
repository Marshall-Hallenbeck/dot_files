#!/bin/bash
set -euo pipefail

MOUNT=${1:?Usage: $0 <mountpoint>}

LV=$(findmnt -no SOURCE "$MOUNT") || { echo "Error: '$MOUNT' is not a mountpoint" >&2; exit 1; }
echo "LV: $LV"
VG=$(sudo lvs --noheadings -o vg_name "$LV" | xargs)
echo "VG: $VG"
PV=$(sudo pvs --noheadings -o pv_name --select "vg_name=$VG" | xargs)
echo "PV: $PV"
DISK=/dev/$(lsblk -dno PKNAME "$PV")
echo "DISK: $DISK"
PARTNUM=$(cat "/sys/class/block/${PV##*/}/partition")
echo "PARTNUM: $PARTNUM"

sudo sh -c "echo 1 > /sys/class/block/${DISK##*/}/device/rescan"

# If our partition is logical, resize the extended container first
PART_TYPE=$(sudo parted -s "$DISK" print | awk -v pn="$PARTNUM" '$1 == pn {print $5}')
if [[ "$PART_TYPE" == "logical" ]]; then
    EXT_PARTNUM=$(sudo parted -s "$DISK" print | awk '$5 == "extended" {print $1}')
    echo "Resizing extended partition $EXT_PARTNUM first"
    sudo parted ---pretend-input-tty "$DISK" resizepart "$EXT_PARTNUM" 100%
fi

sudo parted ---pretend-input-tty "$DISK" resizepart "$PARTNUM" 100%
sudo pvresize "$PV"
sudo lvextend -l +100%FREE -r "$LV"
