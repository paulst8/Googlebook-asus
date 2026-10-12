#!/bin/bash
# Read-only checks for the bare-metal Googlebook OS port. Changes nothing.
echo "== Secure Boot =="; mokutil --sb-state 2>&1
echo; echo "== Disks (name size transport removable model) =="
lsblk -d -o NAME,SIZE,TRAN,RM,MODEL,SERIAL
echo; echo "== USB stick partitions =="
for d in $(lsblk -dno NAME,TRAN | awk '$2=="usb"{print $1}'); do
  echo "-- /dev/$d"; lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS /dev/$d
  udevadm info -q path -n /dev/$d
done
echo; echo "== Tools =="
for t in sgdisk parted mkfs.vfat mkfs.ext4 grub-install rsync lz4 python3 openssl; do
  printf "%-12s %s\n" $t "$(command -v $t || echo MISSING)"
done
echo; echo "== Host firmware we may need to copy =="
ls /lib/firmware/i915 2>/dev/null | grep -Ei 'adlp|tgl_huc|adlp_guc' | head
ls /lib/firmware/xe 2>/dev/null | head
ls /lib/firmware/ 2>/dev/null | grep -E 'iwlwifi-(gl|bz)' | head
ls /lib/firmware/intel 2>/dev/null | grep -E 'ibt-0190|ibt-0291' | head
echo; echo "== Free space on this disk =="; df -h . | tail -1
