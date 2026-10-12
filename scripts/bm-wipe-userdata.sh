#!/bin/bash
# bm-wipe-userdata.sh - factory-reset Googlebook OS: erases ITS user data (apps, accounts, settings) so first-boot setup runs again.
# Same method bm-grow.sh used (which booted fine afterwards). Touches only Android's 'userdata' partition on the SSD with
# serial from bm.conf. Ubuntu, Windows, the NTFS Data drive and the other Android partitions are NOT touched.
set -e
GBOS=${GBOS:-$PWD}; [ -f "$GBOS/bm.conf" ] && . "$GBOS/bm.conf"
[ "$(id -u)" = 0 ] || { echo "run with: sudo bash scripts/bm-wipe-userdata.sh"; exit 1; }
SERIAL=${SSD_SERIAL:-}; N=${USERDATA_PART:-5}
[ -n "$SERIAL" ] || { echo "SSD_SERIAL is not set: run  bash scripts/bm-configure.sh  first"; exit 1; }
DEV=$(lsblk -dn -o NAME,SERIAL | awk -v s="$SERIAL" '$2==s{print "/dev/"$1; exit}')
[ -n "$DEV" ] || { echo "SSD with serial $SERIAL not found"; exit 1; }
P="${DEV}p$N"
sgdisk -i $N "$DEV" | grep -q "Partition name: 'userdata'" || { echo "partition $N is not 'userdata' - stopping"; exit 1; }
grep -q "^$P " /proc/mounts && { echo "$P is mounted - stopping"; exit 1; }
echo "Will erase Android's user data on $P ($(( $(blockdev --getsize64 "$P")/1073741824 )) GiB). Nothing else is changed."
read -r -p "Type YES to erase: " a; [ "$a" = YES ] || { echo cancelled; exit 1; }
blkdiscard -f "$P" 2>/dev/null || dd if=/dev/zero of="$P" bs=1M count=256 conv=fsync status=none
dd if=/dev/zero of="$P" bs=1M count=64 conv=fsync status=none
echo "done: user data erased. Boot Googlebook OS - it will set itself up again (first boot is a bit slower)."
