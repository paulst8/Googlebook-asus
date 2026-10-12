#!/bin/bash
# bm-wifi-fw.sh - download newer Intel Wi-Fi firmware (for the chip family in bm.conf, c101..c107) that Googlebook's kernel asks for.
# Ubuntu's own linux-firmware is too old for it. Saves into ~/gbos/fw-extra/ ; bm-vendor.sh picks it up from there.
# Run:  cd ~/gbos && bash scripts/bm-wifi-fw.sh        (needs internet in Ubuntu; no sudo)
GBOS=${GBOS:-$PWD}; D="$GBOS/fw-extra"; mkdir -p "$D"
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); LIB="$HERE/lib"
[ -f "$GBOS/bm.conf" ] && . "$GBOS/bm.conf"
G=https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain
L=https://gitlab.com/kernel-firmware/linux-firmware/-/raw/main
H=https://raw.githubusercontent.com/kernel-firmware/linux-firmware/main
# Intel moved the files into intel/iwlwifi/ in the newer tree, so try both layouts on each site
BASES="$G/intel/iwlwifi $G $L/intel/iwlwifi $L $H/intel/iwlwifi $H"
got=0
FW_WIFI_BASES=${FW_WIFI_BASES:-"iwlwifi-bz-b0-fm-c0 iwlwifi-gl-c0-fm-c0"}
for base in $FW_WIFI_BASES; do
for n in 107 106 105 104 103 102 101; do
  f="$base-c$n.ucode"
  for b in $BASES; do
    if curl -fL --max-time 120 -sS -o "$D/$f.part" "$b/$f" 2>/dev/null && [ "$(wc -c < "$D/$f.part")" -gt 100000 ]; then
      mv "$D/$f.part" "$D/$f"; echo "got $f ($(wc -c < "$D/$f") bytes)"; got=$((got+1)); break
    fi; rm -f "$D/$f.part"
  done
done
done
for f in $(for b in $FW_WIFI_BASES; do echo $b.pnvm; done); do
  for b in $BASES; do
    if curl -fL --max-time 120 -sS -o "$D/$f.part" "$b/$f" 2>/dev/null && [ "$(wc -c < "$D/$f.part")" -gt 1000 ]; then mv "$D/$f.part" "$D/$f"; echo "got $f"; break; fi; rm -f "$D/$f.part"
  done
done
echo "$got firmware file(s) saved in $D"
[ "$got" -gt 0 ] || echo "none downloaded: the internet may be blocked, or these versions are not published yet. Open an issue and include this output."
