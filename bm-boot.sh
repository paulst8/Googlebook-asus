#!/bin/bash
# bm-boot.sh - put the Googlebook kernel, ramdisk and boot menu on the stick's boot partition (GBOS-ESP).
# Safe to re-run any time (e.g. to change kernel options). Only touches the GBOS-ESP partition.
# Run:  sudo bash bm-boot.sh        Extra kernel options:  sudo EXTRA="nomodeset" bash bm-boot.sh   |   BOOT_FROM=usb sudo -E bash bm-boot.sh
set -euo pipefail
GBOS=${GBOS:-$PWD}
# working display options (verified 2026-10-10: plane-fault flood gone, UI visible). Override with EXTRA="..." (EXTRA="" gives none).
EXTRA=${EXTRA-xe.max_vfs=0 xe.enable_dpt=0 xe.enable_dsb=0 xe.enable_psr=0 xe.enable_fbc=0 xe.enable_dc=0 xe.enable_panel_replay=0 xe.enable_dmc_wl=0 snd_intel_dspcfg.dsp_driver=1}
[ "$EUID" -eq 0 ] || { echo "Run with sudo:  sudo bash $0"; exit 1; }
for f in unpacked/boot_a/kernel unpacked/init_boot_a/ramdisk unpacked/vendor_boot_a/bootconfig \
         unpacked/vendor_boot_a/vendor_ramdisk00 unpacked/vendor_boot_a/vendor_ramdisk01 unpacked/vendor_boot_a/vendor_ramdisk02; do
  [ -f "$GBOS/$f" ] || { echo "missing $GBOS/$f"; exit 1; }; done

# ---- find the boot partition, and make sure it is on a USB disk
ESPDEV=$(blkid -L GBOS-ESP || true); [ -b "${ESPDEV:-}" ] || { echo "No GBOS-ESP partition found - run bm-usb.sh first, with the stick plugged in."; exit 1; }
PK=$(lsblk -no PKNAME "$ESPDEV" | head -1)
[ "$(lsblk -dno TRAN /dev/$PK)" = usb ] || { echo "GBOS-ESP is not on a USB disk - refusing"; exit 1; }

# ---- where does Android live?  Android finds its disk by the PCI path of the controller, so we write that path
#      into the boot settings.  BOOT_FROM=nvme (default, once bm-nvme.sh has run) uses the SSD with serial $NVME_SERIAL;
#      BOOT_FROM=usb uses the stick.
BOOT_FROM=${BOOT_FROM:-nvme}
NVME_SERIAL=${NVME_SERIAL:-YOUR_SSD_SERIAL}
if [ "$BOOT_FROM" = nvme ]; then
  ND=""
  for d in /sys/block/nvme*n*; do
    [ -e "$d" ] || continue; n=$(basename "$d")
    [ "$(lsblk -dno SERIAL /dev/$n | tr -d ' ')" = "$NVME_SERIAL" ] && ND=$n
  done
  if [ -n "$ND" ] && lsblk -lno PARTLABEL /dev/$ND | grep -qx gblog; then
    REAL=$(readlink -f /sys/block/$ND)
    # Android (ueventd) matches boot_devices against ONLY the first two path parts: PCI root + port, e.g. pci0000:00/0000:00:06.2
    BOOTDEV=$(sed -nE 's#^/sys/devices/(pci[^/]+/[^/]+)/.*#\1#p' <<<"$REAL")
    [ -n "$BOOTDEV" ] || { echo "could not work out the SSD controller path from $REAL"; exit 1; }
    echo "Android disk: SSD /dev/$ND (serial $NVME_SERIAL)   controller: $BOOTDEV"
  else
    echo "No Googlebook partitions found on the SSD (serial $NVME_SERIAL) - run bm-nvme.sh first, or use  BOOT_FROM=usb"; exit 1
  fi
else
  REAL=$(readlink -f /sys/block/$PK)
  BOOTDEV=$(sed -nE 's#^/sys/devices/(.*)/usb[0-9]+/.*#\1#p' <<<"$REAL")
  [ -n "$BOOTDEV" ] || { echo "could not work out the USB controller path from $REAL"; exit 1; }
  echo "Android disk: USB stick /dev/$PK   controller: $BOOTDEV   (the stick must stay in the same USB port)"
fi
echo "boot partition: $ESPDEV (on the stick)"

# ---- ramdisk: Googlebook's own ramdisks + our boot settings (bootconfig) appended
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
GBOS="$GBOS" BOOTDEV="$BOOTDEV" OUT="$TMP/initrd.img" python3 - <<'PY'
import os, struct
g, out = os.environ['GBOS'], os.environ['OUT']
base = open(f'{g}/unpacked/vendor_boot_a/bootconfig').read().split()
extra = ["androidboot.slot_suffix=_a",
         f"androidboot.boot_devices={os.environ['BOOTDEV']}",
         "androidboot.verifiedbootstate=orange",
         "androidboot.vbmeta.device_state=unlocked",
         "androidboot.force_normal_boot=1"]
c = ("\n".join(base + extra) + "\n").encode(); c += b"\0" * (-len(c) % 4)
bc = c + struct.pack('<II', len(c), sum(c) & 0xffffffff) + b"#BOOTCONFIG\n"
with open(out, 'wb') as o:
    for f in ['vendor_ramdisk00', 'vendor_ramdisk01', 'vendor_ramdisk02']:
        o.write(open(f'{g}/unpacked/vendor_boot_a/{f}', 'rb').read())
    o.write(open(f'{g}/unpacked/init_boot_a/ramdisk', 'rb').read())
    o.write(bc)
PY

# ---- copy to the stick and write the boot menu
M=$(mktemp -d); mount "$ESPDEV" "$M"
mkdir -p "$M/gbos" "$M/boot/grub"
cp "$GBOS/unpacked/boot_a/kernel" "$M/gbos/kernel"
cp "$TMP/initrd.img" "$M/gbos/initrd.img"
CMD="earlycon=efifb keep_bootcon ignore_loglevel loglevel=8 printk.time=1 printk.devkmsg=on log_buf_len=4M root=/dev/ram0 firmware_class.path=/vendor/firmware cgroup_disable=pressure binder.impl=rust ia32_emulation=false vsyscall=none xe.force_probe=a7ab panic=0 bootconfig $EXTRA"
CMDQ="loglevel=3 printk.time=1 log_buf_len=4M root=/dev/ram0 firmware_class.path=/vendor/firmware cgroup_disable=pressure binder.impl=rust ia32_emulation=false vsyscall=none xe.force_probe=a7ab panic=0 bootconfig $EXTRA"
cat > "$M/boot/grub/grub.cfg" <<CFG
set timeout=8
set default=2
set gfxpayload=keep
menuentry "Googlebook OS (bare metal) - kernel messages on screen" {
    search --no-floppy --label GBOS-ESP --set=root
    linux /gbos/kernel $CMD
    initrd /gbos/initrd.img
}
menuentry "Googlebook OS - quiet (faster, no kernel text on screen)" {
    search --no-floppy --label GBOS-ESP --set=root
    linux /gbos/kernel $CMDQ
    initrd /gbos/initrd.img
}
menuentry "Googlebook OS - quiet + audit off (DEFAULT, lag fix)" {
    search --no-floppy --label GBOS-ESP --set=root
    linux /gbos/kernel $CMDQ audit=0
    initrd /gbos/initrd.img
}
menuentry "Googlebook OS - slow motion (readable messages)" {
    search --no-floppy --label GBOS-ESP --set=root
    linux /gbos/kernel $CMD boot_delay=30
    initrd /gbos/initrd.img
}
menuentry "Googlebook OS - no GPU driver (nomodeset)" {
    search --no-floppy --label GBOS-ESP --set=root
    linux /gbos/kernel $CMD nomodeset
    initrd /gbos/initrd.img
}
CFG
sync; ls -l "$M/gbos"; umount "$M"; rmdir "$M"
echo
echo "DONE.  To try it: shut down, plug the stick into the SAME USB port, press Esc (or F8) at the ASUS logo"
echo "and pick the USB stick.  Nothing on your Windows or Ubuntu drives is changed."
