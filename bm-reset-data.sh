#!/bin/bash
# bm-reset-data.sh - factory-reset Googlebook OS so it can be set up fresh in a DIFFERENT boot state (e.g. locked <-> unlocked).
# Android ties the encryption keys of your data to the boot state, so after changing it the old data cannot be opened.
# This ERASES Android's user data (apps, accounts, settings, files) AND removes the old data-encryption key from the small
# 'metadata' partition (a backup of that partition is saved first). Touches only Android's partitions on the SSD with serial
# $SSD_SERIAL. Ubuntu, Windows, the Data drive and the other Android partitions are NOT touched.
# Run:  cd ~/gbos && sudo bash bm-reset-data.sh
set -euo pipefail
GBOS=${GBOS:-$PWD}
SERIAL=${SSD_SERIAL:-YOUR_SSD_SERIAL}; N=${USERDATA_PART:-5}
[ "$(id -u)" = 0 ] || { echo "run with: sudo bash bm-reset-data.sh"; exit 1; }
DEV=$(lsblk -dn -o NAME,SERIAL | awk -v s="$SERIAL" '$2==s{print "/dev/"$1; exit}')
[ -n "$DEV" ] || { echo "SSD with serial $SERIAL not found"; exit 1; }
P="${DEV}p$N"
sgdisk -i $N "$DEV" | grep -q "Partition name: 'userdata'" || { echo "partition $N is not 'userdata' - stopping"; exit 1; }
MD=""; for q in $(lsblk -ln -o NAME "$DEV" | tail -n +2); do
  [ "$(udevadm info --query=property --name=/dev/$q | sed -n 's/^ID_PART_ENTRY_NAME=//p')" = metadata ] && MD=/dev/$q; done
[ -n "$MD" ] || { echo "metadata partition not found - stopping"; exit 1; }
for x in "$P" "$MD"; do grep -q "^$x " /proc/mounts && { echo "$x is mounted - stopping"; exit 1; }; done
echo "SSD: $DEV   userdata: $P ($(( $(blockdev --getsize64 "$P")/1073741824 )) GiB)   metadata: $MD"
echo "This ERASES Android's user data and its old encryption key. Ubuntu and Windows are not touched."
read -r -p "Type YES to continue: " a; [ "$a" = YES ] || { echo cancelled; exit 1; }

# 1. metadata: back up, then remove only the old data-encryption key
M=$(mktemp -d); trap 'umount "$M" 2>/dev/null || true; rmdir "$M" 2>/dev/null || true' EXIT
mount -t ext4 "$MD" "$M" || { echo "could not mount $MD - stopping, nothing was erased"; exit 1; }
B="$GBOS/backup-metadata-$(date +%Y%m%d-%H%M%S).tar"; tar -C "$M" -cf "$B" . && echo "metadata backup: $B"
if [ -d "$M/vold/metadata_encryption" ]; then rm -rf "$M/vold/metadata_encryption" && echo "removed old data-encryption key (vold/metadata_encryption)"; else echo "no old data-encryption key found (ok)"; fi
sync; umount "$M"

# 2. userdata: erase (same method as bm-wipe-userdata.sh)
blkdiscard -f "$P" 2>/dev/null || dd if=/dev/zero of="$P" bs=1M count=256 conv=fsync status=none
dd if=/dev/zero of="$P" bs=1M count=64 conv=fsync status=none
sync
echo "done: user data and its key erased. Boot Googlebook OS (the entry you want to use from now on) - it sets itself up again; the first boot is slower."
