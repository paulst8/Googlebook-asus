#!/bin/bash
# bm-configure.sh - detect YOUR drives and hardware, and save them in bm.conf. Run this once, before anything else.
# Changes nothing on your disks. Needs no sudo, but with sudo it can read the kernel log, which finds more.
#
# What it works out, and why:
#   SSD_SERIAL / STICK_SERIAL  the scripts identify drives by serial number, so they can never touch the wrong one
#   GPU_ID                     your Intel GPU's PCI ID, passed to the Googlebook kernel (xe.force_probe)
#   FW_GPU / FW_WIFI_BASES / FW_BT / FW_ETH
#                              the firmware files your Ubuntu actually loads for GPU, Wi-Fi, Bluetooth and Ethernet.
#                              bm-vendor.sh copies exactly these into Googlebook OS.
# Run:   bash scripts/bm-configure.sh
# Other ways:  SSD_SERIAL=... STICK_SERIAL=... bash scripts/bm-configure.sh     (no questions)
#              KERNEL_LOG=saved-dmesg.txt bash scripts/bm-configure.sh          (read a saved kernel log)
set -uo pipefail
GBOS=${GBOS:-$PWD}
OUT="$GBOS/bm.conf"
ASOUND=${ASOUND:-/proc/asound}
WARN=()
warn() { WARN+=("$1"); }
say() { printf '%s\n' "$*"; }

# ------------------------------------------------------------------ 1. drives
ROOTDISK=""
src=$(findmnt -no SOURCE / 2>/dev/null || true)
[ -n "$src" ] && ROOTDISK=$(lsblk -no PKNAME "$src" 2>/dev/null | head -1)

list_disks() {  # $1 = transport (nvme|usb) -> lines: NAME|SERIAL|SIZE|MODEL
  lsblk -dn -P -o NAME,SERIAL,SIZE,TRAN,MODEL 2>/dev/null | while IFS= read -r l; do
    eval "$l"   # lsblk -P gives NAME="..." SERIAL="..." ... with safe quoting
    [ "${TRAN:-}" = "$1" ] && printf '%s|%s|%s|%s\n' "$NAME" "$(echo "${SERIAL:-}" | tr -d ' ')" "$SIZE" "${MODEL:-}"
  done
}

choose() {  # $1 = label, $2 = transport, $3 = preset serial (may be empty)  -> prints the chosen serial
  local label="$1" tran="$2" preset="$3" rows i=0 pick line n s z m def="" mark
  if [ -n "$preset" ]; then echo "$preset"; return; fi
  mapfile -t rows < <(list_disks "$tran")
  if [ ${#rows[@]} -eq 0 ]; then echo ""; return; fi
  say "" >&2; say "Which is your $label?" >&2
  for line in "${rows[@]}"; do
    i=$((i+1)); IFS='|' read -r n s z m <<<"$line"; mark=""
    [ "$n" = "$ROOTDISK" ] && { mark="   <- Ubuntu is running from this disk"; [ "$tran" = nvme ] && def=$i; }
    printf '  %d) /dev/%s  %s  %s  serial: %s%s\n' "$i" "$n" "$z" "$m" "${s:-(none)}" "$mark" >&2
  done
  [ ${#rows[@]} -eq 1 ] && def=1
  if [ ! -t 0 ]; then echo ""; return; fi
  read -r -p "Number${def:+ [$def]}: " pick >&2
  pick=${pick:-$def}
  [[ "$pick" =~ ^[0-9]+$ ]] && [ "$pick" -ge 1 ] && [ "$pick" -le ${#rows[@]} ] || { echo ""; return; }
  IFS='|' read -r n s z m <<<"${rows[$((pick-1))]}"; echo "$s"
}

say "== Drives =="
if ! command -v lsblk >/dev/null; then say "lsblk is missing (sudo apt install util-linux)"; exit 1; fi
SSD_SERIAL=$(choose "SSD that will hold Googlebook OS (needs free, unallocated space)" nvme "${SSD_SERIAL:-}")
[ -n "$SSD_SERIAL" ] || { say "No SSD chosen. Run this in a terminal, or set SSD_SERIAL=... (find it with: lsblk -d -o NAME,SERIAL,TRAN,MODEL)"; exit 1; }
if [ "${NO_USB:-0}" = 1 ]; then
  STICK_SERIAL=""
  say "USB-free installation selected; all images and boot files stay on the Ubuntu SSD."
else
STICK_SERIAL=$(choose "USB stick (it will be ERASED in a later step)" usb "${STICK_SERIAL:-}")
[ -n "$STICK_SERIAL" ] || { say "No USB stick chosen. Plug it in and run again, or set STICK_SERIAL=..."; exit 1; }
[ "$SSD_SERIAL" != "$STICK_SERIAL" ] || { say "The SSD and the stick have the same serial - something is wrong."; exit 1; }
fi
say "SSD serial:   $SSD_SERIAL"; say "stick serial: $STICK_SERIAL"

# ------------------------------------------------------------------ 2. GPU
say ""; say "== Graphics =="
GPU_ID=${GPU_ID:-}
if [ -z "$GPU_ID" ]; then
  if command -v lspci >/dev/null; then
    GPU_ID=$(lspci -nn 2>/dev/null | grep -Ei 'vga|display controller|3d controller' | grep -oiE '\[8086:[0-9a-f]{4}\]' | head -1 | sed -E 's/\[8086:([0-9a-f]{4})\]/\1/I' | tr 'A-F' 'a-f')
  else warn "lspci is missing (sudo apt install pciutils), so the GPU could not be detected."; fi
fi
if [ -n "$GPU_ID" ]; then say "Intel GPU PCI ID: $GPU_ID"; else warn "No Intel GPU found. Googlebook OS needs an Intel GPU (the Xe/i915 driver); set GPU_ID=... by hand only if you know what you are doing."; fi

# ------------------------------------------------------------------ 3. firmware your Ubuntu loads
say ""; say "== Firmware that your Ubuntu loads =="
LOGF=$(mktemp); trap 'rm -f "$LOGF"' EXIT
if [ -n "${KERNEL_LOG:-}" ] && [ -r "$KERNEL_LOG" ]; then cp "$KERNEL_LOG" "$LOGF"
else { journalctl -k -b 0 --no-pager 2>/dev/null; dmesg 2>/dev/null; } > "$LOGF" || true; fi
if [ ! -s "$LOGF" ]; then warn "The kernel log is not readable. Run  sudo bash scripts/bm-configure.sh  to detect firmware; until then the test laptop's firmware list is used."; fi

DET=$(python3 -I - "$LOGF" <<'PY'
import re, sys
t = open(sys.argv[1], errors='replace').read()
gpu, wifi, bt, eth = [], [], [], []
def add(l, x):
    if x not in l: l.append(x)
for d, n in re.findall(r'\b(i915|xe)/([A-Za-z0-9_.\-]+)\.bin', t):
    n = re.sub(r'_ver[0-9_]+$', '', n)                 # dmc: adlp_dmc_ver2_16 -> adlp_dmc
    n = re.sub(r'(_guc_[0-9]+)(\.[0-9]+)+$', r'\1', n)  # guc: adlp_guc_70.1.1 -> adlp_guc_70
    n = re.sub(r'(_huc)_[0-9.]+$', r'\1', n)             # huc: tgl_huc_7.9.3 -> tgl_huc
    add(gpu, f'{d}:{n}')
for line in t.splitlines():
    if 'iwlwifi' not in line: continue
    for tok in re.findall(r'[A-Za-z0-9][A-Za-z0-9\-]*\.ucode', line):
        b = re.sub(r'-c?[0-9]+$', '', tok[:-6])
        if not b.startswith('iwlwifi-'): b = 'iwlwifi-' + b
        add(wifi, b)
for n in re.findall(r'intel/(ibt-[0-9a-f\-]+)\.(?:sfi|ddc)', t): add(bt, n)
for n in re.findall(r'rtl_nic/([a-z0-9\-]+)\.fw', t): add(eth, n)
print('GPU=' + ' '.join(gpu[:12])); print('WIFI=' + ' '.join(wifi[:4])); print('BT=' + ' '.join(bt[:4])); print('ETH=' + ' '.join(eth[:3]))
PY
)
getv() { sed -n "s/^$1=//p" <<<"$DET"; }
D_GPU=$(getv GPU); D_WIFI=$(getv WIFI); D_BT=$(getv BT); D_ETH=$(getv ETH)
FW_GPU=${FW_GPU:-$D_GPU};            [ -n "$FW_GPU" ]        || { FW_GPU="i915:adlp_dmc i915:adlp_guc_70 i915:tgl_huc i915:tgl_guc_70"; [ -s "$LOGF" ] && warn "No GPU firmware names found in the kernel log; using the test laptop's list. If graphics fail, check FW_GPU in bm.conf."; }
FW_WIFI_BASES=${FW_WIFI_BASES:-$D_WIFI}; [ -n "$FW_WIFI_BASES" ] || { FW_WIFI_BASES="iwlwifi-bz-b0-fm-c0 iwlwifi-gl-c0-fm-c0"; [ -s "$LOGF" ] && warn "No Intel Wi-Fi firmware found in the kernel log; using BE200-family defaults. Non-Intel Wi-Fi chips are not supported."; }
FW_BT=${FW_BT:-$D_BT};               [ -n "$FW_BT" ]         || { FW_BT="ibt-0190-0291"; [ -s "$LOGF" ] && warn "No Intel Bluetooth firmware found in the kernel log; using the test laptop's. Non-Intel Bluetooth chips are not supported."; }
FW_ETH=${FW_ETH:-$D_ETH};            [ -n "$FW_ETH" ]        || FW_ETH="rtl8168h-2"
say "GPU:       $FW_GPU"; say "Wi-Fi:     $FW_WIFI_BASES"; say "Bluetooth: $FW_BT"; say "Ethernet:  $FW_ETH"

# ------------------------------------------------------------------ 4. sound
say ""; say "== Sound =="
CARD=$(grep -E '^ *[0-9]+ \[PCH' "$ASOUND/cards" 2>/dev/null | head -1)
CODEC=$(cat "$ASOUND"/card*/codec#* 2>/dev/null | sed -n 's/^Codec: //p' | head -1)
if [ -n "$CARD" ]; then say "Sound card 'PCH' found${CODEC:+, codec: $CODEC}. The built-in sound setup should fit."
else warn "No Intel HDA sound card named 'PCH' was found (${CODEC:-no codec seen}). The sound setup in bm-vendor.sh is written for that, so Googlebook OS may have no sound on this laptop."; fi

# ------------------------------------------------------------------ 5. write bm.conf
MODEL=$(cat /sys/class/dmi/id/sys_vendor /sys/class/dmi/id/product_name 2>/dev/null | tr '\n' ' ')
[ -f "$OUT" ] && cp "$OUT" "$OUT.bak"
cat > "$OUT" <<CONF
# bm.conf - made by bm-configure.sh on $(date +%F). Safe to edit by hand; run bm-configure.sh again to regenerate.
# Laptop: ${MODEL:-unknown}
SSD_SERIAL="$SSD_SERIAL"
STICK_SERIAL="$STICK_SERIAL"
GPU_ID="$GPU_ID"
FW_GPU="$FW_GPU"
FW_WIFI_BASES="$FW_WIFI_BASES"
FW_BT="$FW_BT"
FW_ETH="$FW_ETH"
CONF
[ -n "${SUDO_USER:-}" ] && chown "$SUDO_USER": "$OUT" "$OUT.bak" 2>/dev/null
say ""; say "Saved $OUT"
if [ ${#WARN[@]} -gt 0 ]; then say ""; say "== Things to know =="; for w in "${WARN[@]}"; do say " - $w"; done; fi
say ""; say "Next: bash scripts/bm-check.sh   (then the steps in docs/SETUP.md)"
