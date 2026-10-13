#!/bin/bash
# bm-grow.sh - make Android's userdata partition bigger, using the free space directly after it on the SSD.
# Only changes the userdata partition's END. Ubuntu, Windows data and the ESP are not touched.
# WIPES Android's user data (first-boot setup runs again). Leaves 1 GiB free before the next partition.
set -e
GBOS=${GBOS:-$PWD}; [ -f "$GBOS/bm.conf" ] && . "$GBOS/bm.conf"
[ "$(id -u)" = 0 ] || { echo "run with: sudo bash scripts/bm-grow.sh"; exit 1; }
SERIAL=${SSD_SERIAL:-}; N=${USERDATA_PART:-}
[ -n "$SERIAL" ] || { echo "SSD_SERIAL is not set: run  bash scripts/bm-configure.sh  first"; exit 1; }
DEV=$(lsblk -dn -o NAME,SERIAL | awk -v s="$SERIAL" '$2==s{print "/dev/"$1; exit}')
[ -n "$DEV" ] || { echo "SSD with serial $SERIAL not found"; exit 1; }
source "$(dirname "${BASH_SOURCE[0]}")/lib/bm-safety.sh"
bm_require_ubuntu_disk "$DEV"
[ "$(blockdev --getss "$DEV")" = 512 ] || { echo "Only 512-byte logical sectors supported"; exit 1; }
N=$(bm_partition_number "$DEV" userdata "$N") || exit 1
P="${DEV}p$N"
sgdisk -i $N "$DEV" | grep -q "Partition name: 'userdata'" || { echo "partition $N is not 'userdata' - stopping"; exit 1; }
grep -q "^$P " /proc/mounts && { echo "$P is mounted - stopping"; exit 1; }
START=$(sgdisk -i $N "$DEV" | awk '/First sector/{print $3}')
LAST=$(sgdisk -i $N "$DEV" | awk '/Last sector/{print $3}')
TYPE=$(sgdisk -i $N "$DEV" | awk '/Partition GUID code/{print $4}')
NEXT=$(sgdisk -p "$DEV" | awk -v l="$LAST" '$1 ~ /^[0-9]+$/ && $2+0 > l+0 {print $2}' | sort -n | head -1)
[ -n "$NEXT" ] || NEXT=$(( $(blockdev --getsz "$DEV") - 34 ))
END=$(( (NEXT - 2097152) / 2048 * 2048 - 1 ))
echo "Disk $DEV   userdata now: $(( (LAST-START+1)/2097152 )) GiB   will become: $(( (END-START+1)/2097152 )) GiB"
[ $END -gt $((LAST + 2097152)) ] || { echo "less than 1 GiB to gain - nothing to do"; exit 0; }
B="$PWD/nvme-gpt-backup-before-grow-$(date +%Y%m%d-%H%M%S).bin"
sgdisk -b "$B" "$DEV" >/dev/null && echo "partition table backup: $B"
read -r -p "This ERASES Android's user data and enlarges it. Type YES to continue: " a; [ "$a" = YES ] || { echo cancelled; exit 1; }
sgdisk -d $N -n $N:$START:$END -t $N:$TYPE -c $N:userdata -u $N:R "$DEV" >/dev/null
partx -u "$DEV" 2>/dev/null || partprobe "$DEV" 2>/dev/null || true
udevadm settle; sleep 1
[ -b "$P" ] || { echo "$P did not appear - reboot, then check with lsblk"; exit 1; }
dd if=/dev/zero of="$P" bs=1M count=64 conv=fsync status=none
echo "done: $P is now $(( $(blockdev --getsize64 "$P")/1073741824 )) GiB and empty. Boot Android to set it up again."
