#!/bin/bash
# bm-usb.sh - prepare the USB stick for running Googlebook OS on real hardware.
# *** ERASES THE WHOLE USB STICK. *** It only ever touches the one device whose serial number you pass
# (default serial: YOUR_STICK_SERIAL). It refuses anything that is not a USB disk.
# Run:  sudo bash bm-usb.sh          (add  DRYRUN=1  to only print what it would do)
set -euo pipefail
GBOS=${GBOS:-$PWD}
SERIAL="${1:-YOUR_STICK_SERIAL}"
USERDATA_GIB=${USERDATA_GIB:-48}   # user-data area on the stick; it is only used if you boot from the stick. On a 32 GB stick use USERDATA_GIB=4
DRYRUN=${DRYRUN:-}
TARGET_IMG=${TARGET_IMG:-}          # testing only: a file instead of a real stick

[ "$EUID" -eq 0 ] || { echo "Run with sudo:  sudo bash $0"; exit 1; }
for t in sgdisk wipefs mkfs.vfat grub-install python3 udevadm lsblk blockdev partprobe; do
  command -v $t >/dev/null || { echo "missing tool: $t"; exit 1; }; done
[ -d /usr/lib/grub/x86_64-efi ] || { echo "missing GRUB EFI files:  sudo apt install grub-efi-amd64-bin"; exit 1; }
for f in lapis.bin gb.raw bm_gpt.py; do [ -e "$GBOS/$f" ] || { echo "missing $GBOS/$f"; exit 1; }; done

# ---- find the stick by serial number, and only if it is a USB disk
DEV=""
if [ -n "$TARGET_IMG" ]; then DEV="$TARGET_IMG"; else
  for d in /sys/block/sd*; do
    [ -e "$d" ] || continue; n=/dev/$(basename "$d")
    p=$(udevadm info --query=property --name="$n")
    if grep -qx "ID_BUS=usb" <<<"$p" && grep -qx "ID_SERIAL_SHORT=$SERIAL" <<<"$p"; then DEV=$n; fi
  done
fi
[ -n "$DEV" ] || { echo "No USB disk with serial $SERIAL found. Is the stick plugged in?"; lsblk -d -o NAME,SIZE,TRAN,SERIAL; exit 1; }
if [ -z "$TARGET_IMG" ]; then
  [ "$(lsblk -dno TRAN "$DEV")" = usb ] || { echo "$DEV is not a USB disk - refusing"; exit 1; }
  BYTES=$(blockdev --getsize64 "$DEV")
  [ "$BYTES" -ge 28000000000 ] && [ "$BYTES" -le 520000000000 ] || { echo "$DEV has an unexpected size ($BYTES) - refusing"; exit 1; }
  if lsblk -lno MOUNTPOINTS "$DEV" | grep -Eq '^(/|/boot.*|/home.*)$'; then echo "$DEV holds a system mount - refusing"; exit 1; fi
fi
SECT=$(python3 -c "import os,sys;p=sys.argv[1];print((os.path.getsize(p) if os.path.isfile(p) else int(open('/sys/class/block/'+os.path.basename(p)+'/size').read())*512)//512)" "$DEV")
LASTUSE=$((SECT-34))

echo "Target: $DEV   serial $SERIAL   $((SECT*512/1000000000)) GB"
[ -z "$TARGET_IMG" ] && lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS "$DEV"

# ---- build the partition plan from the pristine Googlebook image
PLAN=$(mktemp); python3 "$GBOS/bm_gpt.py" plan "$GBOS/lapis.bin" > "$PLAN"
LAST=$(python3 "$GBOS/bm_gpt.py" last "$GBOS/lapis.bin")
al() { echo $(( ($1 + 2047) / 2048 * 2048 )); }
ESP_S=$(al "$LAST");               ESP_E=$((ESP_S + 2097152 - 1))     # 1 GiB boot partition
LOG_S=$((ESP_E + 1));              LOG_E=$((LOG_S + 524288 - 1))      # 256 MiB raw log area
KLG_S=$((LOG_E + 1));              KLG_E=$((KLG_S + 131072 - 1))      # 64 MiB raw kernel-log area
UD_S=$((KLG_E + 1));               UD_E=$((UD_S + USERDATA_GIB*2097152 - 1))
[ "$UD_E" -le "$LASTUSE" ] || { echo "stick too small for ${USERDATA_GIB} GiB of user data"; exit 1; }

ARGS=(-a 1); UDIDX=""
while IFS=$'\t' read -r idx s e t u name; do
  if [ "$name" = userdata ]; then UDIDX=$idx; ARGS+=(-n "$idx:$UD_S:$UD_E" -t "$idx:$t" -c "$idx:userdata")
  else ARGS+=(-n "$idx:$s:$e" -t "$idx:$t" -u "$idx:$u" -c "$idx:$name"); fi
done < "$PLAN"
[ -n "$UDIDX" ] || { echo "no userdata partition in plan"; exit 1; }
ARGS+=(-n "32:$ESP_S:$ESP_E" -t 32:EF00 -c 32:GBOS-ESP
       -n "33:$LOG_S:$LOG_E"  -t 33:8300 -c 33:gblog
       -n "34:$KLG_S:$KLG_E"  -t 34:8300 -c 34:gbkmsg)
echo "Plan: $(wc -l < "$PLAN") Googlebook partitions + boot partition (1 GiB) + 2 log areas + ${USERDATA_GIB} GiB user data."
echo "Source data comes from lapis.bin (pristine, read-only) and the boot-control block from gb.raw."
if [ -n "$DRYRUN" ]; then echo "[dry run] sgdisk --zap-all $DEV ; sgdisk ${ARGS[*]} $DEV"; exit 0; fi

echo; echo "THIS WILL ERASE EVERYTHING ON $DEV."
read -r -p "Type the stick's serial number ($SERIAL) to continue: " ANS
[ "$ANS" = "$SERIAL" ] || { echo "Not confirmed - nothing changed."; exit 1; }

# ---- 1. partition
if [ -z "$TARGET_IMG" ]; then
  for m in $(lsblk -lnpo MOUNTPOINT "$DEV" | grep -v '^$' || true); do umount "$m"; done
  wipefs -a "$DEV" >/dev/null
fi
sgdisk --zap-all "$DEV" >/dev/null 2>&1 || true
sgdisk "${ARGS[@]}" "$DEV" >/dev/null
[ -z "$TARGET_IMG" ] && { partprobe "$DEV" || true; udevadm settle; }
python3 "$GBOS/bm_gpt.py" verify "$DEV" <(grep -v -P '\tuserdata$' "$PLAN") && echo "partition table verified"

# ---- 2. copy the Android partitions (same sector positions as the source image)
cp_part() {  # $1=source file  $2=start  $3=end  $4=label
  echo "copying $4 ($((($3-$2+1)/2048)) MiB)"
  dd if="$1" of="$DEV" bs=4M iflag=skip_bytes,count_bytes oflag=seek_bytes \
     skip=$(($2*512)) seek=$(($2*512)) count=$((($3-$2+1)*512)) conv=notrunc status=none
}
while IFS=$'\t' read -r idx s e t u name; do
  [ "$name" = userdata ] && continue
  SRC="$GBOS/lapis.bin"; [ "$name" = misc ] && SRC="$GBOS/gb.raw"   # misc = the working AOSP boot-control block
  cp_part "$SRC" "$s" "$e" "$name"
done < "$PLAN"
echo "flushing to the stick..."; sync

# ---- 3. clean the new areas so Android formats user data itself on first boot
zero() { dd if=/dev/zero of="$DEV" bs=1M oflag=seek_bytes seek=$(($1*512)) count=$2 conv=notrunc status=none; }
zero "$UD_S" 64; zero "$LOG_S" 1; zero "$KLG_S" 1; sync

if [ -n "$TARGET_IMG" ]; then echo "[test mode] stopping before the boot partition (needs a real device)"; sgdisk -p "$DEV"; exit 0; fi

# ---- 4. boot partition + GRUB (UEFI "removable" layout: shows up in the ASUS boot menu as the USB stick)
ESPDEV="${DEV}32"; [ -b "$ESPDEV" ] || { sleep 2; partprobe "$DEV"; udevadm settle; }
[ -b "$ESPDEV" ] || { echo "$ESPDEV did not appear"; exit 1; }
mkfs.vfat -F32 -n GBOS-ESP "$ESPDEV" >/dev/null
M=$(mktemp -d); mount "$ESPDEV" "$M"
grub-install --target=x86_64-efi --efi-directory="$M" --boot-directory="$M/boot" --removable --no-nvram --no-uefi-secure-boot >/dev/null
mkdir -p "$M/gbos"; sync; umount "$M"; rmdir "$M"
echo
echo "DONE. Next:  sudo bash bm-boot.sh   (puts the kernel, ramdisk and boot menu on the stick)"
