# Install without a USB stick

This path uses the images stored on the running Ubuntu SSD. It adds Android only
in unallocated space on that SSD, stages the kernel and ramdisk locally, and
adds a GRUB entry. It does not install a new EFI bootloader or write another SSD.

This is an experimental port. Static tests cannot establish that hardware,
Google account setup, updates, or phone integration work after reboot.

## Requirements

- Direct Ubuntu root partition on a 512-byte logical-sector NVMe disk.
- `/boot` on Ubuntu root and `/boot/efi` on the same physical SSD.
- Enough unallocated space for the recovery image's system partitions plus
  at least 16 GiB userdata (40 GiB by default).
- About 80 GiB free inside Ubuntu for downloads and preparation.
- The pinned recovery and Cuttlefish downloads from SETUP.md.

## Configure and prepare (no disk writes)

Run from the repository directory. This obtains the target identity from the
running Ubuntu installation, without selecting the Windows SSD:

```bash
ROOT_SOURCE=$(findmnt -nro SOURCE /)
ROOT_PARENT=$(lsblk -dnro PKNAME "$ROOT_SOURCE")
SSD_SERIAL=$(lsblk -dnro SERIAL "/dev/$ROOT_PARENT" | tr -d ' ') NO_USB=1 bash scripts/bm-configure.sh
bash scripts/bm-prepare.sh
bash scripts/bm-wifi-fw.sh
```

Inspect `bm.conf`; `STICK_SERIAL` should be empty. The recovery checksum and the
Cuttlefish SHA-256 must match. Do not substitute a newer build without retesting.

## Read the target layout by serial

```bash
sudo bash scripts/bm-layout.sh > work/ubuntu-free-space.txt
```

Never use a remembered NVMe device number to select the installation disk.

## Build before partition writes

Once preparation has completed, test the hardware vendor build without writing
Android partitions:

```bash
sudo BUILD_ONLY=1 bash scripts/bm-vendor.sh
BOOT_STAGING=1 bash scripts/bm-boot.sh
```

## Preview the partition plan

```bash
sudo DRYRUN=1 bash scripts/bm-nvme.sh
```

Check the serial and free-sector range. The installer refuses a target other than
the running Ubuntu disk and refuses to add a second Android installation.
Existing NTFS partitions on the Ubuntu disk must also remain intact.

## Install and add the boot entry

Only after reviewing the preview:

```bash
sudo bash scripts/bm-nvme.sh
sudo bash scripts/bm-vendor.sh
sudo BOOT_STAGING=1 bash scripts/bm-boot.sh
sudo BOOT_SOURCE=local bash scripts/bm-ubuntu-grub.sh
```

The disk writers request the target serial. Do not disconnect power during them.
`bm-vendor.sh` changes Android's vendor partition and disables its stock vbmeta
verification. Keep the default unlocked configuration for the first boot.

The last step creates `/etc/default/grub.d/99-googlebook.cfg`, disables OS probing
to avoid mounting other disks, and makes the boot menu visible for eight seconds.
Ubuntu remains the default. Windows might no longer be automatically listed in
GRUB; use its existing firmware boot entry. No Windows partitions are changed.

Reboot manually and choose Googlebook OS. If it fails, choose Ubuntu. Keep the
GPT backup. Never restore a whole-disk GPT backup after unrelated partition
changes: it would replace the current partition map.

## Verify after the first boot

Test account setup, Wi-Fi reconnect, Bluetooth, speaker/headphone/microphone
switching, webcam, keyboard/touchpad, brightness, battery reporting, sleep/wake,
shutdown and a second cold boot. Verify the Linux terminal separately. Phone
Cast My Apps / Continue on, NVIDIA graphics, full Secure Boot, and unattended
system updates are not established by this installation.
