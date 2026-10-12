#!/bin/bash
# bm-prepare.sh - first-time preparation: turn the two downloads into the files the other bm-*.sh scripts need.
# Needs NO sudo and changes nothing outside the project folder. Safe to re-run (finished steps are skipped).
#
# Put these in the project folder first:
#   lapis-recovery.zip                              Google's recovery image (see README)
#   aosp_cf_x86_64_only_phone-img-16373615.zip      Android Cuttlefish test image (see README)
# Run:  cd ~/gbos && bash scripts/bm-prepare.sh
# Result: lapis.bin  gb.raw  parts/  unpacked/  super/  work/cuttlefish/  lpunpack.py
set -euo pipefail
GBOS=${GBOS:-$PWD}; cd "$GBOS"
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); LIB="$HERE/lib"
[ -f "$GBOS/bm.conf" ] && . "$GBOS/bm.conf"
ZIP=lapis-recovery.zip; CFZIP=aosp_cf_x86_64_only_phone-img-16373615.zip

# ---- 1. tools
miss=""
for t in python3 unzip curl lz4 dump.erofs mkfs.erofs debugfs unpack_bootimg; do command -v $t >/dev/null || miss="$miss $t"; done
if [ -n "$miss" ]; then
  echo "Missing tools:$miss"
  echo "Install them with:  sudo apt install python3 unzip curl lz4 erofs-utils e2fsprogs mkbootimg attr binutils cpio xxd zstd secilc gdisk parted rsync dosfstools grub-efi-amd64-bin"
  exit 1
fi
for f in "$ZIP" "$CFZIP" "$LIB/bm_gpt.py" "$LIB/unpack_cf_x86.py"; do [ -e "$f" ] || { echo "missing $f - see docs/SETUP.md"; exit 1; }; done

# ---- 2. Google's image: unzip to lapis.bin (never modified afterwards)
if [ ! -s lapis.bin ]; then
  echo "[1/6] unzipping $ZIP"
  unzip -o -q "$ZIP" -d work_unzip_tmp
  mv work_unzip_tmp/*.bin lapis.bin && rmdir work_unzip_tmp
  chmod a-w lapis.bin
else echo "[1/6] lapis.bin already there"; fi

# ---- 3. partition table -> byte offsets
PLAN=$(mktemp); trap 'rm -f "$PLAN"' EXIT
python3 -I "$LIB/bm_gpt.py" plan lapis.bin > "$PLAN"
part() { awk -F'\t' -v n="$1" '$6==n{print $2, $3-$2+1}' "$PLAN"; }   # prints: start_sector sector_count

# ---- 4. boot-related partitions -> parts/ and unpacked/
mkdir -p parts unpacked
for p in boot_a init_boot_a vendor_boot_a vbmeta_a; do
  if [ ! -s parts/$p.img ]; then
    read -r S N < <(part $p); dd if=lapis.bin of=parts/$p.img bs=512 skip="$S" count="$N" status=none
  fi
done
for p in boot_a init_boot_a vendor_boot_a; do
  if [ ! -d unpacked/$p ]; then
    echo "[2/6] unpacking $p"
    unpack_bootimg --boot_img parts/$p.img --out unpacked/$p > unpacked/$p.txt
  fi
done

# ---- 5. the big 'super' partition -> super/*.img (system, vendor, product, ...)
if [ ! -s super/vendor_a.img ]; then
  echo "[3/6] unpacking super (takes a few minutes, needs about 25 GB free)"
  [ -s lpunpack.py ] || curl -fsSL -o lpunpack.py https://raw.githubusercontent.com/unix3dgforce/lpunpack/master/lpunpack.py
  read -r S N < <(part super); dd if=lapis.bin of=super.tmp bs=4M iflag=skip_bytes,count_bytes skip=$((S*512)) count=$((N*512)) status=none
  mkdir -p super; python3 -I lpunpack.py super.tmp super; rm -f super.tmp
else echo "[3/6] super/ already unpacked"; fi

# ---- 6. Cuttlefish parts (software security + graphics) -> work/cuttlefish/
if [ ! -s work/cuttlefish/manifest.json ]; then
  echo "[4/6] unpacking Cuttlefish parts"
  python3 -I "$LIB/unpack_cf_x86.py" "$CFZIP" work/cuttlefish
else echo "[4/6] work/cuttlefish already there"; fi

# ---- 7. working copy of the disk image (sparse, about 19 GB on disk)
if [ ! -s gb.raw ]; then echo "[5/6] making gb.raw"; cp --sparse=always lapis.bin gb.raw; chmod u+w gb.raw
else echo "[5/6] gb.raw already there"; fi

echo "[6/6] checking"
ok=1
for f in unpacked/boot_a/kernel unpacked/init_boot_a/ramdisk unpacked/vendor_boot_a/bootconfig unpacked/vendor_boot_a/vendor_ramdisk02 \
         super/vendor_a.img super/system_a.img super/system_ext_a.img super/product_a.img \
         work/cuttlefish/security/rust_nonsecure_payload.img work/cuttlefish/security/boot-service.default gb.raw; do
  [ -s "$f" ] || { echo "  MISSING $f"; ok=0; }; done
[ $ok = 1 ] && echo "All set. Next: bash scripts/bm-check.sh   (then the steps in the README)" || { echo "Something is missing - see above."; exit 1; }
