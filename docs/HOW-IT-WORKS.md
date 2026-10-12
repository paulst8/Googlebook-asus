# How it works

## The idea

Googlebook OS is Android. Google ships it as a disk image for its own hardware, so it won't start on another laptop as it is. This project makes three changes:

1. **Put Android on a spare area of your SSD.** Only new partitions are added; existing ones are not touched.
2. **Rebuild the "vendor" part of the image for your laptop.** This adds the firmware your laptop needs, replaces the parts that need Google's security chip with software ones, and adds the sound setup.
3. **Add a boot menu entry** to your existing GRUB menu, so Googlebook OS is one choice at startup.

Android's kernel and ramdisk are loaded by Ubuntu's GRUB from `/boot/gbos`, together with a few boot settings (which disk Android lives on, GPU options and so on). Android itself is stored on the SSD in its own partitions.

## Why the image needs patching

A few things in the stock image don't exist on a normal laptop. `scripts/bm-vendor.sh` works around them:

- **No Google security chip (TPM).** The image expects hardware to hold encryption keys. Without it the key service crashed repeatedly, which made the system restart over and over. A software key service from Android's Cuttlefish image replaces it.
- **Firmware for the wrong hardware.** The image carries firmware for Google's laptop, not for yours. The script copies the graphics, Wi-Fi, Bluetooth and Ethernet firmware that your Ubuntu loads.
- **Sound.** The image's only sound setup is for Google's own laptop's chips, so the script adds one for Intel HDA sound and loads the driver early enough.
- **Services that crash-loop** without Google's hardware (a protected VM launcher, a charge controller and others) are stopped. Left alone, they kept the system's first process busy and made the whole system lag.
- **Verified boot** is switched off in the vendor part by default (the bootloader is reported as unlocked). See [Locked boot](LOCKED-BOOT.md) for the optional alternative.

## What each script does

| Script | Needs sudo | Writes to | What it does |
|---|---|---|---|
| `bm-configure.sh` | no | `bm.conf` | Detects your drives and hardware |
| `bm-check.sh` | no | nothing | Read-only checks |
| `bm-prepare.sh` | no | project folder | Unpacks the two downloads into the files the other scripts use |
| `bm-usb.sh` | yes | the stick | Copies Android's partitions to the stick, makes a boot partition |
| `bm-nvme.sh` | yes | the SSD | Adds Android's partitions in unallocated space, copies the system into them |
| `bm-wifi-fw.sh`, `bm-wifi-fw2.sh` | no | `fw-extra/` | Download newer Intel Wi-Fi firmware |
| `bm-vendor.sh` | yes | the SSD | Rebuilds the vendor part and writes it |
| `bm-boot.sh` | yes | the stick | Writes kernel, ramdisk and boot settings |
| `bm-ubuntu-grub.sh` | yes | `/boot/gbos`, GRUB | Adds Googlebook OS to Ubuntu's menu |
| `bm-finalize.sh` | yes | GRUB | Tidies the Googlebook menu entries |
| `bm-sign.sh`, `bm-verified.sh`, `bm-locked-test.sh` | yes | the SSD, GRUB | Verified and locked boot |
| `bm-reset-data.sh`, `bm-wipe-userdata.sh`, `bm-grow.sh` | yes | the SSD | Reset or resize Android's data |
| `bm-boottime.sh` | no | nothing | Shows where boot time goes (uses adb) |

Helper code lives in `scripts/lib/`: a partition-table reader (`bm_gpt.py`), the Cuttlefish unpacker (`unpack_cf_x86.py`) and AOSP's `avbtool.py`.

## Safety design

- Disks are identified by **serial number** (from `bm.conf`), never by `/dev/sdX` names, which change between boots.
- Scripts that erase something ask you to type a confirmation first.
- `bm-nvme.sh` only adds partitions in unallocated space and saves your partition table first.
- Every script says in its header what it touches.
