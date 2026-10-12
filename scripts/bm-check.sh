#!/bin/bash
# bm-check.sh - read-only checks before you start. Changes nothing.
# Run:  bash scripts/bm-check.sh      (after  bash scripts/bm-configure.sh )
GBOS=${GBOS:-$PWD}
echo "== Your settings (bm.conf) =="
if [ -f "$GBOS/bm.conf" ]; then grep -v '^#' "$GBOS/bm.conf"; else echo "bm.conf not found - run:  bash scripts/bm-configure.sh"; fi
echo; echo "== Secure Boot (must be off for this to boot) =="; mokutil --sb-state 2>&1
echo; echo "== Disks (name size transport removable model serial) =="
lsblk -d -o NAME,SIZE,TRAN,RM,MODEL,SERIAL
echo; echo "== USB disks and their partitions =="
for d in $(lsblk -dno NAME,TRAN | awk '$2=="usb"{print $1}'); do
  echo "-- /dev/$d"; lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS /dev/$d
done
echo; echo "== Tools (MISSING ones need installing, see docs/SETUP.md) =="
for t in git python3 unzip curl lz4 mkfs.erofs dump.erofs debugfs getfattr setfattr secilc zstd xxd readelf file unpack_bootimg sgdisk parted partx mkfs.vfat grub-install rsync openssl lspci; do
  printf "%-16s %s\n" $t "$(command -v $t || echo MISSING)"
done
echo; echo "== Files from your downloads =="
for f in lapis-recovery.zip aosp_cf_x86_64_only_phone-img-16373615.zip; do [ -s "$GBOS/$f" ] && echo "found    $f" || echo "MISSING  $f"; done
echo; echo "== Free space in this folder =="; df -h "$GBOS" | tail -1
echo; echo "== Free (unallocated) space on your SSD =="
S=$(grep -oP '^SSD_SERIAL="\K[^"]+' "$GBOS/bm.conf" 2>/dev/null)
D=$(lsblk -dn -o NAME,SERIAL | awk -v s="$S" '$2==s{print "/dev/"$1; exit}')
if [ -n "$D" ] && command -v parted >/dev/null; then parted -m -s "$D" unit GiB print free 2>/dev/null | grep ':free;' | sed 's/^/  gap: /'; else echo "  (needs bm.conf and parted; try with sudo)"; fi
