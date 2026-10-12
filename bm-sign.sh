#!/bin/bash
# bm-sign.sh - make Android VERIFY its own system partitions with YOUR key (verified boot, "yellow"-style).
# Stage 3 of the verified-boot plan. It:
#   1. reads the vendor partition that bm-vendor.sh wrote to the SSD, adds a dm-verity hash tree to it,
#   2. builds a NEW vbmeta_a (the signed list of partition fingerprints) signed with your key,
#   3. writes both back, and prints the numbers the boot settings need (stage 4).
# Touches ONLY the vendor area inside 'super' and 'vbmeta_a' on the SSD with serial $SSD_SERIAL. It saves the old vbmeta_a first.
# Re-run it after EVERY  sudo bash bm-vendor.sh  (that script switches verification off again).
# Run:    cd ~/gbos && sudo bash bm-sign.sh              Test without writing anything:  DRYRUN=1 bash bm-sign.sh
# Undo:   sudo bash bm-vendor.sh   (rebuilds the vendor and switches verification off again, as before)
set -euo pipefail
GBOS=${GBOS:-$PWD}; cd "$GBOS"
DRYRUN=${DRYRUN:-}
SSD_SERIAL=${SSD_SERIAL:-YOUR_SSD_SERIAL}
AVBTOOL="python3 $GBOS/avb/avbtool.py"
UH=$( [ -n "${SUDO_USER:-}" ] && getent passwd "$SUDO_USER" | cut -d: -f6 || echo "$HOME" )
KEY=${AVB_KEY:-$UH/gbos-avb-key/avb.pem}
[ -z "$DRYRUN" ] && { [ "$EUID" -eq 0 ] || { echo "Run with sudo:  sudo bash $0"; exit 1; }; }
[ -f "$KEY" ] || { echo "Signing key not found: $KEY  (create it first, see the README)"; exit 1; }
[ -f avb/avbtool.py ] || { echo "avb/avbtool.py missing"; exit 1; }
for f in parts/boot_a.img parts/init_boot_a.img parts/vendor_boot_a.img parts/vbmeta_a.img super/system_a.img super/system_ext_a.img super/product_a.img super/system_dlkm_a.img super/vendor_dlkm_a.img; do
  [ -f "$f" ] || { echo "missing $GBOS/$f"; exit 1; }; done
OUT=work/sign-out; mkdir -p "$OUT"; rm -f "$OUT"/*
SLOT=$(stat -c %s super/vendor_a.img)      # size of the vendor slot inside super

# ---- 1. get the current vendor image
if [ -z "$DRYRUN" ]; then
  SSDSUP=""; SSDVBM=""
  for d in /sys/block/nvme*n*; do
    [ -e "$d" ] || continue; n=/dev/$(basename "$d")
    [ "$(lsblk -dno SERIAL "$n" | tr -d ' ')" = "$SSD_SERIAL" ] || continue
    for q in "$d"/"$(basename "$d")"p*; do
      pn=$(udevadm info --query=property --name=/dev/$(basename "$q") | sed -n 's/^ID_PART_ENTRY_NAME=//p')
      [ "$pn" = super ] && SSDSUP=/dev/$(basename "$q"); [ "$pn" = vbmeta_a ] && SSDVBM=/dev/$(basename "$q")
    done
  done
  [ -n "$SSDSUP" ] && [ -n "$SSDVBM" ] || { echo "No Googlebook super/vbmeta_a on the SSD (serial $SSD_SERIAL) - nothing was written"; exit 1; }
  VOFF=$(python3 -I -c 'import sys;sys.path.insert(0,sys.argv[2]);from unpack_cf_x86 import super_partitions as s;print(s(sys.argv[1])["vendor_a"])' "$SSDSUP" "$GBOS")
  dd if="$SSDSUP" of="$OUT/vendor.raw" bs=4M iflag=skip_bytes,count_bytes skip=$VOFF count=$SLOT status=none
else
  cp work/vendor_bm.img "$OUT/vendor.raw"; echo "(dry run: using work/vendor_bm.img, nothing will be written to any disk)"
fi
[ "$(dd if="$OUT/vendor.raw" bs=1 skip=1024 count=4 status=none | xxd -p)" = "e2e1f5e0" ] || { echo "vendor image is not EROFS - stopping"; exit 1; }

# ---- 2. cut off the padding (EROFS knows its own size), add the hash tree + footer
python3 -I - "$OUT/vendor.raw" "$OUT/vendor.img" <<'PY'
import struct, sys
src, dst = sys.argv[1:]
f = open(src, 'rb'); f.seek(1024); sb = f.read(128)
size = struct.unpack('<I', sb[36:40])[0] << sb[12]
f.seek(0); open(dst, 'wb').write(f.read(size)); print('  vendor data: %d bytes' % size)
PY
$AVBTOOL add_hashtree_footer --image "$OUT/vendor.img" --partition_size "$SLOT" --partition_name vendor --do_not_generate_fec --hash_algorithm sha256 >/dev/null
[ "$(stat -c %s "$OUT/vendor.img")" -eq "$SLOT" ] || { echo "signed vendor has the wrong size - stopping"; exit 1; }
echo "  vendor now has its hash tree (fits the $SLOT byte slot)"

# ---- 3. new vbmeta_a, signed with your key; same properties and boot-image entries as Google's original
PROPS=$($AVBTOOL info_image --image parts/vbmeta_a.img | sed -n "s/^ *Prop: \(.*\) -> '\(.*\)'\$/--prop\n\1:\2/p")
mapfile -t PARR <<<"$PROPS"
INC=()
for i in parts/boot_a.img parts/init_boot_a.img parts/vendor_boot_a.img super/system_a.img super/system_ext_a.img super/product_a.img super/system_dlkm_a.img super/vendor_dlkm_a.img "$OUT/vendor.img"; do INC+=(--include_descriptors_from_image "$i"); done
$AVBTOOL make_vbmeta_image --output "$OUT/vbmeta_a.img" --key "$KEY" --algorithm SHA256_RSA4096 --rollback_index 1339 --flags 0 "${INC[@]}" "${PARR[@]}" >/dev/null
echo "  new vbmeta_a: $(stat -c %s "$OUT/vbmeta_a.img") bytes, public key sha1: $($AVBTOOL info_image --image "$OUT/vbmeta_a.img" | sed -n 's/^Public key (sha1): *//p')"
$AVBTOOL info_image --image "$OUT/vbmeta_a.img" | grep -E "Partition Name" | tr -s ' ' | tr '\n' ',' ; echo
DIG=$($AVBTOOL calculate_vbmeta_digest --image "$OUT/vbmeta_a.img" --hash_algorithm sha256)
SZ=$(stat -c %s "$OUT/vbmeta_a.img")
{ echo "androidboot.vbmeta.digest=$DIG"; echo "androidboot.vbmeta.size=$SZ"; echo "androidboot.vbmeta.hash_alg=sha256"; echo "androidboot.vbmeta.avb_version=1.0"; } > avb/vbmeta-bootconfig.txt
echo "  boot settings for stage 4 saved in avb/vbmeta-bootconfig.txt"

[ -n "$DRYRUN" ] && { echo "DRY RUN finished - files are in $GBOS/$OUT, nothing was written."; exit 0; }

# ---- 4. write (with a backup of the old vbmeta_a)
B="$GBOS/backup-vbmeta_a-$(date +%Y%m%d-%H%M%S).img"; dd if="$SSDVBM" of="$B" bs=4k status=none; echo "  old vbmeta_a saved: $B"
[ "$(dd if="$SSDVBM" bs=1 count=4 status=none)" = "AVB0" ] || { echo "vbmeta_a on the SSD is not AVB - stopping"; exit 1; }
[ "$(dd if="$SSDSUP" bs=1 skip=$((VOFF+1024)) count=4 status=none | xxd -p)" = "e2e1f5e0" ] || { echo "no EROFS at the vendor offset - stopping"; exit 1; }
dd if="$OUT/vendor.img" of="$SSDSUP" bs=4M seek=$VOFF oflag=seek_bytes conv=notrunc,fsync status=none
dd if="$OUT/vbmeta_a.img" of="$SSDVBM" bs=4k conv=notrunc,fsync status=none
sync
cmp "$OUT/vendor.img" <(dd if="$SSDSUP" bs=4M iflag=skip_bytes,count_bytes skip=$VOFF count=$SLOT status=none) && echo "  vendor read-back OK" || { echo "  VENDOR READ-BACK FAILED"; exit 1; }
cmp -n "$SZ" "$OUT/vbmeta_a.img" "$SSDVBM" && echo "  vbmeta_a read-back OK" || { echo "  VBMETA READ-BACK FAILED"; exit 1; }
echo
echo "DONE. Android partitions are now signed with your key; the boot state is still 'orange' (stage 4 changes that)."
echo "Reboot and check it still starts. If it does not: sudo bash bm-vendor.sh   (restores the old, unverified setup)."
