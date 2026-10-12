<div align="center">

<img src="docs/assets/banner.svg" alt="Googlebook OS on a regular Intel laptop" width="100%">

# Googlebook OS on a regular laptop

Run Google's **Googlebook OS** (Android 17, the successor to ChromeOS) on an ordinary Intel laptop, next to your existing Ubuntu and Windows.

![Status](https://img.shields.io/badge/status-experimental-orange)
![Platform](https://img.shields.io/badge/platform-Intel%20x86__64-blue)
![Tested on](https://img.shields.io/badge/tested%20on-ASUS%20TUF%20F16-informational)
![License](https://img.shields.io/github/license/paulst8/googlebook-asus)
![Last commit](https://img.shields.io/github/last-commit/paulst8/googlebook-asus)

[Setup guide](docs/SETUP.md) · [Hardware](docs/HARDWARE.md) · [Locked boot](docs/LOCKED-BOOT.md) · [Troubleshooting](docs/TROUBLESHOOTING.md) · [How it works](docs/HOW-IT-WORKS.md)

</div>

> [!WARNING]
> **Unofficial and experimental.** Not affiliated with or endorsed by Google or ASUS. The scripts write to disks. Back up first, read what each script does, and use them at your own risk.
> This repository contains **no Google files**. You download Google's image yourself.

## What works

| Works | Doesn't work (yet) |
|---|---|
| Display, keyboard, touchpad, battery, USB | **Cast My Apps** and **Continue on** with a phone |
| Wi-Fi 7 and Bluetooth (Intel) | The NVIDIA GPU (unused) |
| Sound: speakers, wired and Bluetooth headphones | A full Secure Boot chain |
| Webcam, Linux terminal (Debian) | Fast boot (the first boot takes several minutes) |
| Verified boot with **your own key**, optional | |

Everything above was tested on **one laptop** (ASUS TUF F16, Intel Raptor Lake-P). Other Intel laptops may work; see [Hardware](docs/HARDWARE.md).

## How it works, in one minute

```mermaid
flowchart LR
    A[Google's recovery image] --> B[Put Android on a free area of your SSD]
    B --> C[Rebuild the vendor part for your laptop]
    C --> D[Add one entry to your GRUB menu]
    D --> E[Pick Googlebook OS at startup]
```

Googlebook OS is Android, shipped as a disk image for Google's own hardware. These scripts add Android to unused space on your SSD, swap the parts that need Google's security chip for software ones, add the firmware your laptop needs, and put an entry in your boot menu. Your Ubuntu and Windows are not touched. More in [How it works](docs/HOW-IT-WORKS.md).

## Quick start

You need an Intel laptop with Ubuntu, about 60 GB of unallocated SSD space, a 32 GB+ USB stick, and two downloads. The [full guide](docs/SETUP.md) lists everything; the short version is:

```bash
git clone https://github.com/paulst8/googlebook-asus ~/gbos && cd ~/gbos
bash scripts/bm-configure.sh        # detects YOUR drives and hardware, writes bm.conf
bash scripts/bm-prepare.sh          # unpacks the two downloads
sudo bash scripts/bm-usb.sh         # prepares the stick (erases it)
sudo bash scripts/bm-nvme.sh        # adds Android's partitions to your SSD
bash scripts/bm-wifi-fw.sh          # newer Wi-Fi firmware
sudo bash scripts/bm-vendor.sh      # builds the laptop-specific system part
sudo bash scripts/bm-boot.sh        # kernel and boot settings
sudo bash scripts/bm-ubuntu-grub.sh # adds Googlebook OS to Ubuntu's boot menu
```

Then restart and pick **Googlebook OS**. Do the setup in order and read [docs/SETUP.md](docs/SETUP.md) first: it explains the downloads, what each step asks you to confirm, and how to undo it.

## Documentation

| | |
|---|---|
| [Setup guide](docs/SETUP.md) | Every step from the downloads to the first boot |
| [Hardware](docs/HARDWARE.md) | What the scripts detect, what is laptop-specific, which laptops are known to work |
| [Locked boot](docs/LOCKED-BOOT.md) | Optional: sign the system with your own key and boot as "locked" |
| [Troubleshooting](docs/TROUBLESHOOTING.md) | Known issues, boot time, recovering from a bad boot |
| [How it works](docs/HOW-IT-WORKS.md) | Why the image needs patching and what each script does |

## Does it work on your laptop?

Please tell us, whether it worked or not. Open a [hardware report](../../issues/new?template=hardware_report.yml): it takes a minute and builds the list of laptops that work. Found a bug in a script? Open a [bug report](../../issues/new?template=bug_report.yml). To help, read [CONTRIBUTING.md](CONTRIBUTING.md).

## Credits

- [gbos-vm](https://github.com/skylartaylor/gbos-vm) by Skylar Taylor: the original approach, for Apple Silicon.
- [cros.tech/googlebooks](https://cros.tech/googlebooks/): image and codename directory.
- [lpunpack](https://github.com/unix3dgforce/lpunpack): unpacks Android's `super` partition.
- Android Cuttlefish and AOSP `avbtool`: the software security and graphics parts, and verified-boot signing.

Images are always downloaded directly from Google; nothing from Google or Android's test image is redistributed here. Scripts are released under the [MIT License](LICENSE); `scripts/lib/avbtool.py` is from AOSP (Apache 2.0).
