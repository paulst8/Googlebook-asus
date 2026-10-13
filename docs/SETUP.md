# Installation & Setup Manual

This is the USB-free path used on the tested ASUS laptop. Run commands in **Ubuntu**,
from the cloned repository. The final installation stays on the SSD running Ubuntu;
a separate Windows SSD is not an installation target. Your phone needs no modification.

## Table of Contents

- [Prerequisites](#prerequisites)
- [1. Install tools and clone](#1-install-tools-and-clone)
- [2. Download the pinned images](#2-download-the-pinned-images)
- [3. Configure and verify disk serials](#3-configure-and-verify-disk-serials)
- [4. Prepare images and firmware](#4-prepare-images-and-firmware)
- [5. Build and preview before writing](#5-build-and-preview-before-writing)
- [6. Install and add the boot menu](#6-install-and-add-the-boot-menu)
- [7. First boot](#7-first-boot)
- [Maintenance](#maintenance)
- [Optional USB installer](#optional-usb-installer)
- [Undo](#undo)

## Prerequisites

- Intel CPU/iGPU supported by this image; read [Hardware](HARDWARE.md). Only the
  ASUS TUF F16 has been tested here. Detection may fall back to that laptop's values.
- Working Ubuntu, internet and sudo access. The recent installation used Ubuntu
  26.04.1; older releases may have incompatible EROFS/SELinux tools.
- UEFI with **Secure Boot disabled**. Custom-key AVB is not UEFI Secure Boot.
  Keep the Windows BitLocker recovery key before changing firmware settings.
- GPT NVMe with **512-byte logical sectors**, direct Ubuntu root partition,
  `/boot` inside root and `/boot/efi` on that same SSD. LVM/LUKS root, separate
  `/boot`, SATA and arbitrary secondary-disk targets are unsupported.
- About **80 GiB free inside Ubuntu** for downloads, unpacking and builds, plus
  preferably **60 GiB contiguous unallocated space** on that SSD. These are two
  different space requirements. The tested layout used about 58.1 GiB with 40 GiB
  userdata. The installer can reduce userdata to 16 GiB; the preview determines
  whether the available gap fits. 32 GB is not a sufficient general recommendation.
- Backups of important data and reliable power during writes.

The scripts do not shrink partitions. Free space *inside* Ubuntu is not unallocated
space. If a gap must be created, use a suitable offline partitioning environment;
you cannot shrink a mounted Ubuntu root partition. Do not resize the Windows SSD.
If this requires live media, prepare it before continuing; USB-free here means the
Googlebook installer itself does not need a stick.

## 1. Install tools and clone

```bash
sudo apt update && sudo apt install -y \
  git python3 unzip curl lz4 erofs-utils e2fsprogs mkbootimg attr binutils \
  cpio xxd zstd secilc gdisk parted rsync dosfstools grub-efi-amd64-bin \
  grub2-common file openssl pciutils util-linux coreutils mokutil
```

If a package is unavailable, fix the package source/version before proceeding.
For optional ADB diagnostics install `adb`; for local code checks install `shellcheck`.

Clone into a new folder (skip this block if you already cloned there):

```bash
git clone https://github.com/paulst8/Googlebook-asus.git ~/gbos
cd ~/gbos
```

All following commands assume this directory. After opening another terminal,
run `cd ~/gbos` again. Existing users with local script edits should review
`git status` before updating; do not reset the working installation checkout.

## 2. Download the pinned images

Both downloads are from Google. Their endpoints responded with ZIP content on
2026-10-14. Download availability can change; checksums are mandatory. Allow about
9 GB of network transfer, in addition to the extracted working space.

**Googlebook lapis recovery, build 16452207 (7.73 GB):**

```bash
curl --fail --location --retry 3 --continue-at - \
  --output lapis-recovery.zip \
  https://dl.google.com/device/recovery/lapis-user/16452207/recovery.zip
printf '%s  %s\n' '38873eac8ff5b060baf229b7bcf7ec05' 'lapis-recovery.zip' | md5sum -c -
```

MD5 is the legacy corruption check, not a cryptographic authenticity signature.

**AOSP Cuttlefish x86_64 userdebug, build 16373615 (1.16 GB):**

```bash
curl --fail --location --retry 3 --continue-at - \
  --output aosp_cf_x86_64_only_phone-img-16373615.zip \
  https://ci.android.com/builds/submitted/16373615/aosp_cf_x86_64_only_phone-userdebug/latest/aosp_cf_x86_64_only_phone-img-16373615.zip
printf '%s  %s\n' '601d55e3197a2a612becc6931f111fd00caac5cbc70e0fa8261fbdb4cb22c695' 'aosp_cf_x86_64_only_phone-img-16373615.zip' | sha256sum -c -
```

If the artifact URL returns HTML or needs browser interaction, open the
[official build page](https://ci.android.com/builds/submitted/16373615/aosp_cf_x86_64_only_phone-userdebug/),
choose **Artifacts**, download that exact ZIP and place it in `~/gbos`. Re-run the
checksum command. Do not proceed unless **both checks say OK**. Do not rename a
newer build to these names; replacing a pinned build requires compatibility testing.
There is no separate ASUS overlay archive to download.

## 3. Configure and verify disk serials

```bash
sudo NO_USB=1 bash scripts/bm-configure.sh
```

Select the SSD that contains Ubuntu by its **serial**, not a remembered NVMe number.
The command detects hardware and writes `bm.conf` (backing up an existing copy).
It does not certify compatibility. `NO_USB=1` skips the USB selection; it does not
select a secondary-disk installation mode. `STICK_SERIAL` must be empty for this path.

Inspect the configuration and read-only disk information:

```bash
cat bm.conf
lsblk -d -o NAME,MODEL,SIZE,TRAN,LOG-SEC,SERIAL
findmnt -nro SOURCE /
findmnt -nro SOURCE /boot/efi
sudo bash scripts/bm-layout.sh
sudo bash scripts/bm-check.sh
```

Match the current root partition's parent disk to `SSD_SERIAL`, and confirm the EFI
partition has that same parent. Device names can change on reboot; the configured
serial is the stable identity. Compare with the drive's physical label or firmware
inventory if available. Stop if the selected serial belongs to Windows, is ambiguous,
or the storage layout differs from the prerequisites.

`bm-check.sh` is an informational report, not a pass/fail gate: resolve every
`MISSING` tool/download and confirm Secure Boot is disabled. Review hardware
fallback warnings and `FW_WIFI_BASES` before building.

## 4. Prepare images and firmware

```bash
bash scripts/bm-prepare.sh &&
bash scripts/bm-wifi-fw.sh
```

Wait for preparation to report **All set**. It creates `parts/`, `unpacked/`,
`super/`, `work/cuttlefish/`, `lapis.bin` and `gb.raw`. It verifies the pinned archives
on the initial extraction. If interrupted, inspect partial outputs before retrying;
the preparation script skips existing outputs and is not a transactional downloader.

Firmware is downloaded to `fw-extra/` before the vendor build. Some unavailable
firmware versions are expected; a successful download does not establish that the
kernel can initialize your adapter. The optional `scripts/bm-wifi-fw2.sh` searches
history and can download several GB; it does not guarantee a genuine core105 exists.

**Tested Intel BE200 workaround only:** the ASUS setup needed genuine core103 with
core104/core105 filename aliases. For that hardware, persist the option before
building so later vendor rebuilds retain working Wi-Fi:

```bash
printf '\nWIFI_COMPAT_ALIASES="1"\n' >> bm.conf
```

This is a workaround, not genuine core105 firmware. Read [Wi-Fi repair](WIFI-REPAIR.md)
for the applicable GL/FM and BZ/FM families. Do not enable it indiscriminately for
other adapters. Re-running configure regenerates `bm.conf`; restore custom options
from its backup afterward.

## 5. Build and preview before writing

```bash
sudo BUILD_ONLY=1 bash scripts/bm-vendor.sh &&
BOOT_STAGING=1 bash scripts/bm-boot.sh &&
sudo DRYRUN=1 bash scripts/bm-nvme.sh
```

This builds local vendor/boot files and previews the partition plan without writing
target partitions. Stop on any build, SELinux, missing-firmware or size error.
Check the preview's serial, existing partitions, free-sector range and userdata size.
The installer refuses an existing Googlebook layout: use maintenance for an already
installed system. Never remove that guard to retry an interrupted installation.

## 6. Install and add the boot menu

Only after the build and preview succeed, run this block. It stops the sequence
on the first error and saves the output. Read and answer serial prompts carefully.

```bash
set -o pipefail
{
  sudo bash scripts/bm-nvme.sh &&
  sudo bash scripts/bm-vendor.sh &&
  sudo BOOT_STAGING=1 bash scripts/bm-boot.sh &&
  sudo BOOT_SOURCE=local bash scripts/bm-ubuntu-grub.sh
} 2>&1 | tee work/install.log
```

- `bm-nvme.sh` adds partitions in the free gap **and copies Android**. There is no
  separate flash step. Keep its `nvme-<serial>-gpt-backup-*.bin` backup privately.
- `bm-vendor.sh` writes the adapted vendor and disables stock vbmeta verification.
  Confirm the write/read-back checks succeed.
- `bm-boot.sh` stages the kernel/ramdisk in `work/boot-stage`.
- `bm-ubuntu-grub.sh` copies them into `/boot/gbos`, writes
  `/etc/grub.d/40_googlebook` and `/etc/default/grub.d/99-googlebook.cfg`, and updates
  Ubuntu GRUB. It does not install a new EFI bootloader. The menu is visible for
  eight seconds; the existing default selection is not deliberately changed.

OS probing is disabled to avoid scanning/mounting other disks. Windows may no longer
be automatically listed in GRUB; use its existing firmware boot entry. No separate
Windows SSD is written by this installation path.

Do not reboot if any step fails. Inspect `work/install.log`; after partition creation,
resume only the diagnosed failed stage. Re-running the entire install block will
stop at the existing-partition guard.

## 7. First boot

Restart manually and choose **Googlebook OS** in Ubuntu GRUB (try Esc/Shift if the
menu is hidden). First boot can take several minutes. Complete setup and test Wi-Fi
reconnect, Bluetooth, sound/microphone, webcam, keyboard/touchpad, brightness, battery,
sleep/wake, shutdown and a second cold boot. Test the Linux terminal separately.

Return to Ubuntu for repairs if needed. [Troubleshooting](TROUBLESHOOTING.md) and
[Wi-Fi repair](WIFI-REPAIR.md) explain the diagnostic paths.

Cast My Apps and Continue On are **not working on the tested port**: account grouping
can succeed while attestation still prevents connection. See [phone integration](PHONE-INTEGRATION.md).
The Pixel can remain stock; this guide does not promise a native pairing bypass.
NVIDIA graphics, stock OTA updates and full Secure Boot are unsupported or unverified.
Do not run the optional locked-boot/finalize scripts as part of ordinary setup.

## Maintenance

Run from the same repository with its existing `bm.conf` and prepared images.
Do not rerun the partition installer for routine changes.

For updated firmware/vendor (retains userdata; persist any required Wi-Fi alias option):

```bash
bash scripts/bm-wifi-fw.sh &&
sudo bash scripts/bm-vendor.sh
```

For changed boot options:

```bash
sudo BOOT_STAGING=1 bash scripts/bm-boot.sh &&
sudo BOOT_SOURCE=local bash scripts/bm-ubuntu-grub.sh
```

A vendor rebuild disables verification; users of the optional
[locked-boot experiment](LOCKED-BOOT.md) must repeat its signing/boot steps. Factory
reset and grow scripts erase Android data and are not routine repair steps.

## Optional USB installer

Skip this section for the default USB-free path. A stick is a temporary boot/install
medium, **not an alternative internal SSD target**. To use it, configure with
`sudo bash scripts/bm-configure.sh` (without `NO_USB=1`) and select its serial too.
Reapply custom `bm.conf` options after regeneration. The stick is completely erased.

After image preparation, for a 32 GB or larger stick:

```bash
sudo USERDATA_GIB=4 bash scripts/bm-usb.sh
```

The default USB userdata size is 48 GiB, which will not fit a 32 GB stick. Keep the
4 GiB override for that size. Follow the same SSD preview/install process; to stage
boot files on the configured USB instead of locally, use:

```bash
sudo bash scripts/bm-boot.sh &&
sudo bash scripts/bm-ubuntu-grub.sh
```

The USB must be plugged in for both commands. Vendor rebuilds also update a
configured USB when present; unplug it for SSD-only maintenance. After copying to
Ubuntu GRUB, the USB is no longer needed to boot the SSD installation.

## Undo

Boot Ubuntu first. There is no automatic undo script.

- Remove the Googlebook GRUB scripts (`40_googlebook`, and optional
  `41_googlebook_verified` / `42_googlebook_locked`) from `/etc/grub.d`, and its
  `/boot/gbos` directory only after confirming they contain nothing else you need.
  Then run `sudo update-grub`.
- Keeping `/etc/default/grub.d/99-googlebook.cfg` preserves disabled OS probing.
  Removing it restores prior timeout/probing behavior and may scan other disks.
- Removing Android partitions requires identifying the same SSD **by serial** and
  reviewing its current layout. Do not use a remembered `/dev/nvme…` number.
- A saved GPT backup replaces the **entire partition map**. It is usable only if no
  unrelated partition changes occurred afterward and its disk identity is verified.
  It does not restore files, GRUB configuration or Android userdata. Otherwise remove
  only the reviewed Googlebook partitions using a partitioning tool.

Never restore a whole-disk GPT backup blindly. Keep Ubuntu and its EFI partition intact.
