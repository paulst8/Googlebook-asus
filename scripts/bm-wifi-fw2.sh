#!/bin/bash
# bm-wifi-fw2.sh - find OLD Intel BE200 firmware versions (c104, c105) in the git HISTORY of linux-firmware.
# The current tree only has c101-c103 and c106+; Googlebook's driver asks for c105 (accepts c101-c105).
# Run:  cd ~/gbos && bash scripts/bm-wifi-fw2.sh      (needs internet + git in Ubuntu; no sudo; downloads ~100-300 MB of git metadata)
GBOS=${GBOS:-$PWD}; D="$GBOS/fw-extra"; mkdir -p "$D"; T=$(mktemp -d); got=0
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); LIB="$HERE/lib"
[ -f "$GBOS/bm.conf" ] && . "$GBOS/bm.conf"
command -v git >/dev/null || { echo "git is missing:  sudo apt install git"; exit 1; }
for url in https://gitlab.com/kernel-firmware/linux-firmware.git https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git https://github.com/kernel-firmware/linux-firmware.git; do
  echo "cloning (metadata only) from $url ..."
  git clone --filter=blob:none --no-checkout --quiet "$url" "$T/r" 2>/dev/null && break; rm -rf "$T/r"
done
[ -d "$T/r/.git" ] || { echo "could not clone from any site - open an issue and include this output"; exit 1; }
cd "$T/r"
for n in 105 104; do
  for fam in $(for b in ${FW_WIFI_BASES:-"iwlwifi-bz-b0-fm-c0 iwlwifi-gl-c0-fm-c0"}; do echo ${b#iwlwifi-}; done); do
    f="iwlwifi-$fam-c$n.ucode"; ok=0
    for p in "intel/iwlwifi/$f" "$f"; do
      c=$(git log --all --diff-filter=AM --format=%H -n1 -- "$p" 2>/dev/null)
      [ -n "$c" ] || continue
      if git show "$c:$p" > "$D/$f.part" 2>/dev/null && [ "$(wc -c < "$D/$f.part")" -gt 100000 ]; then
        mv "$D/$f.part" "$D/$f"; echo "got $f ($(wc -c < "$D/$f") bytes) from commit ${c:0:10}"; got=$((got+1)); ok=1; break
      fi; rm -f "$D/$f.part"
    done
    [ $ok = 1 ] || echo "no history for $f"
  done
done
echo "$got file(s) saved in $D"
rm -rf "$T"
