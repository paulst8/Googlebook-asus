#!/bin/bash
# bm-nvme.sh - put Googlebook OS's partitions onto the FREE SPACE of your Ubuntu SSD (the SSD with serial YOUR_SSD_SERIAL).
#
# SAFETY: it only ADDS new partitions inside unallocated space. It never changes, formats, moves or resizes an
# existing partition (Ubuntu, Data, the EFI partition). It saves a backup of the disk's partition table first.
# It refuses to run unless the disk has the serial number you set and is an NVMe disk.
# The USB stick stays as the boot menu (it holds the kernel) until bm-ubuntu-grub.sh; the Android partitions are copied to the SSD.
#
# Run:  DRYRUN=1 sudo bash bm-nvme.sh      (shows the plan, writes nothing)
#       sudo bash bm-nvme.sh               (does it, after you type the serial number)
set -euo pipefail
GBOS=${GBOS:-$PWD}
SERIAL=${SERIAL:-YOUR_SSD_SERIAL}
STICK_SERIAL=${STICK_SERIAL:-YOUR_STICK_SERIAL}
USERDATA_GIB=${USERDATA_GIB:-40}       # wanted size of the Android user-data partition (shrinks automatically if space is short)
MIN_USERDATA_GIB=16
DRYRUN=${DRYRUN:-}
[ "$EUID" -eq 0 ] || { echo "Run with sudo:  sudo bash $0"; exit 1; }
for t in sgdisk parted partx python3 udevadm lsblk blockdev dd; do command -v $t >/dev/null || { echo "missing tool: $t"; exit 1; }; done
for f in lapis.bin gb.raw bm_gpt.py; do [ -e "$GBOS/$f" ] || { echo "missing $GBOS/$f"; exit 1; }; done

# ---------------------------------------------------------------- find the SSD by serial number (names swap between boots)
DEV=""
for d in /sys/block/nvme*n*; do
  [ -e "$d" ] || continue; n=/dev/$(basename "$d")
  [ "$(lsblk -dno SERIAL "$n" | tr -d ' ')" = "$SERIAL" ] && DEV=$n
done
[ -n "$DEV" ] || { echo "No NVMe disk with serial $SERIAL found."; lsblk -d -o NAME,SIZE,TRAN,MODEL,SERIAL; exit 1; }
[ "$(lsblk -dno TRAN "$DEV")" = nvme ] || { echo "$DEV is not NVMe - refusing"; exit 1; }
ROOTSRC=$(findmnt -no SOURCE / || true)
echo "Target SSD: $DEV  (serial $SERIAL)   Ubuntu root is on: $ROOTSRC"
case "$ROOTSRC" in "$DEV"p*) ;; *) echo "WARNING: this SSD does not hold the running Ubuntu - double-check the serial before continuing.";; esac

# ---------------------------------------------------------------- find the USB stick (source of super + vbmeta_a, copied there by bm-usb.sh)
STICK=""
for d in /sys/block/sd*; do
  [ -e "$d" ] || continue; n=/dev/$(basename "$d"); p=$(udevadm info --query=property --name="$n")
  if grep -qx "ID_BUS=usb" <<<"$p" && grep -qx "ID_SERIAL_SHORT=$STICK_SERIAL" <<<"$p"; then STICK=$n; fi
done
[ -n "$STICK" ] || { echo "The Googlebook USB stick ($STICK_SERIAL) must be plugged in - it holds the system image copied by bm-usb.sh."; exit 1; }
echo "USB stick: $STICK"

# ---------------------------------------------------------------- the partition plan from the pristine image + the biggest free gap
PLAN=$(mktemp); trap 'rm -f "$PLAN"' EXIT
python3 "$GBOS/bm_gpt.py" plan "$GBOS/lapis.bin" > "$PLAN"
FREEFILE=$(mktemp); parted -m -s "$DEV" unit s print free > "$FREEFILE"
EXIST=$(sgdisk -p "$DEV" | awk '/^ +[0-9]+ /{print $1}' | sort -n | tail -1); EXIST=${EXIST:-0}
SECTS=$(blockdev --getsz "$DEV")
eval "$(PLAN="$PLAN" FREEFILE="$FREEFILE" USERDATA_GIB="$USERDATA_GIB" MIN_USERDATA_GIB="$MIN_USERDATA_GIB" EXIST="$EXIST" python3 - <<'PY'
import os, sys
plan = [l.rstrip('\n').split('\t') for l in open(os.environ['PLAN']) if l.strip()]
rows = [(int(p[0]), int(p[1]), int(p[2]), p[3], p[4], p[5]) for p in plan]
S0 = min(r[1] for r in rows if r[5] != 'userdata')
base_end = max(r[2] for r in rows if r[5] != 'userdata')
base = base_end - S0 + 1
LOG, KLG = 524288, 131072
gaps = []
for l in open(os.environ['FREEFILE']):
    f = l.strip().rstrip(';').split(':')
    if len(f) >= 5 and f[4] == 'free':
        gaps.append((int(f[1][:-1]), int(f[2][:-1])))
if not gaps: print('echo "no free space on the disk"; exit 1'); sys.exit()
gs, ge = max(gaps, key=lambda g: g[1]-g[0])
al = lambda x: (x + 2047) // 2048 * 2048
start = al(gs)
BASE = start + (S0 % 2048)
end_base = BASE + base          # first free sector after the Android system partitions
LOGS = al(end_base); KS = LOGS + LOG; UDS = KS + KLG
avail = (ge - 2048) - UDS + 1   # sectors left for user data (keep a little slack at the end of the gap)
want = int(os.environ['USERDATA_GIB']) * 2097152
mn = int(os.environ['MIN_USERDATA_GIB']) * 2097152
if avail < mn:
    need_gib = (UDS - gs + mn) / 2097152
    print('echo "NOT ENOUGH FREE SPACE: biggest free gap is %.1f GiB, need at least %.1f GiB (system %.1f GiB + logs + %d GiB user data)"; exit 1'
          % ((ge-gs+1)/2097152, need_gib, base/2097152, int(os.environ['MIN_USERDATA_GIB'])))
    sys.exit()
ud = min(want, avail) // 2048 * 2048
print('S0=%d BASE=%d LOGS=%d KS=%d UDS=%d UDN=%d GAPS=%d GAPE=%d BASEN=%d' % (S0, BASE, LOGS, KS, UDS, ud, gs, ge, base))
PY
)"
echo "Free gap on the SSD: sectors $GAPS..$GAPE ($(( (GAPE-GAPS+1)/2097152 )) GiB)"
echo "Android system partitions: $(( BASEN/2097152 )) GiB   user data: $(( UDN/2097152 )) GiB   logs: 320 MiB"
echo "Existing partitions on the SSD (will NOT be touched):"; sgdisk -p "$DEV" | sed -n '/^Number/,$p'

# new partition numbers: after the highest existing one, so no existing entry is ever replaced
NEWBASE=$EXIST
ARGS=(); IDXMAP=""; NEWIDS=""
while IFS=$'\t' read -r idx s e t u name; do
  n=$((NEWBASE + idx))
  if [ "$name" = userdata ]; then
    ARGS+=(-n "$n:$UDS:$((UDS+UDN-1))" -t "$n:$t" -c "$n:userdata" -u "$n:R")
  else
    ns=$((BASE + s - S0)); ne=$((BASE + e - S0))
    ARGS+=(-n "$n:$ns:$ne" -t "$n:$t" -c "$n:$name" -u "$n:R")
  fi
  IDXMAP+="$idx:$n:$name:$s:$e "; NEWIDS+="$n "
done < "$PLAN"
GL=$((NEWBASE + 40)); GK=$((NEWBASE + 41))
ARGS+=(-n "$GL:$LOGS:$((LOGS+524288-1))" -t "$GL:8300" -c "$GL:gblog" -u "$GL:R"
       -n "$GK:$KS:$((KS+131072-1))"   -t "$GK:8300" -c "$GK:gbkmsg" -u "$GK:R")
echo "Will create $(wc -l < "$PLAN") Googlebook partitions (numbers $((NEWBASE+1))..) + gblog ($GL) + gbkmsg ($GK) on $DEV"
if [ -n "$DRYRUN" ]; then echo "[dry run] sgdisk -a 1 ${ARGS[*]} $DEV"; echo "[dry run] nothing was written."; exit 0; fi

echo; echo "This ADDS partitions in the free space of $DEV. Existing partitions are not touched."
read -r -p "Type the SSD's serial number ($SERIAL) to continue: " ANS
[ "$ANS" = "$SERIAL" ] || { echo "Not confirmed - nothing changed."; exit 1; }

# ---------------------------------------------------------------- 1. back up the partition table, then add the partitions
BK="$GBOS/nvme-$SERIAL-gpt-backup-$(date +%Y%m%d-%H%M%S).bin"
sgdisk --backup="$BK" "$DEV" >/dev/null; echo "partition table backup saved: $BK"
echo "  (to undo everything:  sudo sgdisk --load-backup=$BK $DEV )"
sgdisk -a 1 "${ARGS[@]}" "$DEV" >/dev/null
# tell the kernel about the NEW partitions only (re-reading the whole table fails while Ubuntu is using this disk)
partx -a --nr $((NEWBASE+1)):$GK "$DEV" 2>/dev/null || partx -a "$DEV" 2>/dev/null || true
udevadm settle; sleep 1
for n in $NEWIDS $GL $GK; do
  [ -b "${DEV}p$n" ] || { echo "partition ${DEV}p$n did not appear - stopping (the backup is $BK)"; exit 1; }
done
sgdisk -p "$DEV" | sed -n '/^Number/,$p'

# ---------------------------------------------------------------- 2. copy the Android partitions
cp_part() {  # $1=source device/file  $2=source start sector  $3=end  $4=destination partition  $5=label
  local len=$(( ($3-$2+1)*512 ))
  [ "$(blockdev --getsize64 "$4")" -ge "$len" ] || { echo "$4 is smaller than the data for $5 - stopping"; exit 1; }
  echo "copying $5 ($((len/1048576)) MiB)"
  dd if="$1" of="$4" bs=4M iflag=skip_bytes,count_bytes skip=$(($2*512)) count=$len conv=fsync status=none
}
for item in $IDXMAP; do
  IFS=: read -r idx n name s e <<<"$item"
  [ "$name" = userdata ] && continue
  case "$name" in
    super|vbmeta_a) SRC="$STICK" ;;                 # copied from the stick (bm-vendor.sh changes them on the SSD afterwards)
    misc)           SRC="$GBOS/gb.raw" ;;           # AOSP boot-control block
    *)              SRC="$GBOS/lapis.bin" ;;
  esac
  cp_part "$SRC" "$s" "$e" "${DEV}p$n" "$name"
done
echo "flushing..."; sync

# ---------------------------------------------------------------- 3. clean user data + logs so Android formats it itself on first boot
for item in $IDXMAP; do
  IFS=: read -r idx n name s e <<<"$item"
  [ "$name" = userdata ] && { dd if=/dev/zero of="${DEV}p$n" bs=1M count=64 conv=fsync status=none; echo "user data area cleaned (${DEV}p$n)"; }
done
dd if=/dev/zero of="${DEV}p$GL" bs=1M count=1 conv=fsync status=none
dd if=/dev/zero of="${DEV}p$GK" bs=1M count=1 conv=fsync status=none
sync

# ---------------------------------------------------------------- 4. check the copies
echo "checking the copied vendor and vbmeta..."
for item in $IDXMAP; do
  IFS=: read -r idx n name s e <<<"$item"
  case "$name" in vbmeta_a)
    [ "$(dd if="${DEV}p$n" bs=1 count=4 status=none)" = AVB0 ] && echo "  vbmeta_a OK" || { echo "  vbmeta_a looks wrong"; exit 1; } ;;
  esac
done
echo
echo "DONE. Android's partitions are on $DEV (serial $SERIAL)."
echo "Next:  sudo bash bm-boot.sh      (points the boot menu on the stick at the SSD)"
