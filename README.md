![Googlebook OS Banner](docs/assets/banner.svg)

# Googlebook OS on Bare-Metal Laptops

**Status:** Experimental · **Platform:** Intel x86_64 · **Project scripts:** MIT

Boot Google's Android 17 Googlebook recovery image on an Intel laptop using
Ubuntu's GRUB. This community port adapts the `lapis` image with AOSP Cuttlefish
components and laptop firmware. It is not an official Google-supported installer.

## Overview & Key Features

- USB-free installation into unallocated space on the **SSD running Ubuntu**.
- Target selection by **disk serial number**, with partition previews and confirmations.
- Vendor adaptations for Intel graphics, Intel wireless and Intel HDA audio.
- Local kernel/ramdisk staging and integration with Ubuntu's existing GRUB.
- Wi-Fi and phone diagnostics; optional experimental custom-key AVB tooling.

Tested on an ASUS TUF F16. Hardware detection does not guarantee compatibility
with another laptop. Native **Cast My Apps / Continue On remain blocked by
attestation** on the tested installation; changing boot properties does not fix
that. See [phone integration](docs/PHONE-INTEGRATION.md).

## System Requirements

| Requirement | Specification |
| --- | --- |
| Host | Ubuntu with working internet; the recent installation used Ubuntu 26.04.1. Other releases are not validated here |
| Hardware | Intel CPU/iGPU, UEFI, Secure Boot disabled; see [hardware limitations](docs/HARDWARE.md) |
| Storage layout | GPT NVMe with 512-byte logical sectors; direct Ubuntu root partition, `/boot` on root, EFI on the same SSD |
| Installation space | Recommend at least **60 GiB contiguous unallocated** on the Ubuntu SSD; the preview calculates the exact requirement |
| Working space | About **80 GiB free inside Ubuntu**, separately from the unallocated installation space |
| USB | Not required for the default installation |

The installer does not resize partitions or install onto a separate Windows SSD.
LVM/LUKS root, separate `/boot`, SATA targets and arbitrary secondary-disk installs
are not supported by this path. Stock OTA updates and a complete Secure Boot chain
are not validated.

## Quick Start

Install Git, then clone into an unused directory:

```bash
sudo apt update && sudo apt install -y git
git clone https://github.com/paulst8/Googlebook-asus.git ~/gbos
cd ~/gbos
```

Continue with the **[complete setup guide](docs/SETUP.md)** for the full dependency
list, both official image downloads and checksums, serial verification, firmware
preparation, build checks and installation commands. Do not skip directly to disk
writes. Existing installations should use [maintenance](docs/SETUP.md#maintenance)
instead of reinstalling.

## Script Reference

| Script | Purpose |
| --- | --- |
| `scripts/bm-configure.sh` | Detect hardware and save local `bm.conf`; use `NO_USB=1` for USB-free setup |
| `scripts/bm-check.sh` | Print settings, dependencies and free-space information |
| `scripts/bm-prepare.sh` | Verify and extract the pinned image archives |
| `scripts/bm-layout.sh` | Inspect the configured Ubuntu SSD by serial |
| `scripts/bm-wifi-fw.sh` | Download Intel firmware before building vendor |
| `scripts/bm-vendor.sh` | Build vendor; `BUILD_ONLY=1` avoids target partition writes |
| `scripts/bm-nvme.sh` | Preview or add partitions and copy Android into the free gap |
| `scripts/bm-boot.sh` | Build boot files; `BOOT_STAGING=1` stages them locally |
| `scripts/bm-ubuntu-grub.sh` | Add Ubuntu GRUB entries; `BOOT_SOURCE=local` uses staged files |

## Documentation Guide

| Topic | Guide |
| --- | --- |
| Installation, downloads, maintenance and removal | [Setup](docs/SETUP.md) |
| Architecture and replaced components | [How it works](docs/HOW-IT-WORKS.md) |
| Hardware assumptions and detection | [Hardware](docs/HARDWARE.md) |
| BE200 firmware workaround and diagnosis | [Wi-Fi repair](docs/WIFI-REPAIR.md) |
| Native phone integration failure and diagnostics | [Phone integration](docs/PHONE-INTEGRATION.md) |
| Experimental AVB signing and reported boot state | [Locked boot](docs/LOCKED-BOOT.md) |
| Common failures | [Troubleshooting](docs/TROUBLESHOOTING.md) |

Google/AOSP images and firmware retain their upstream licenses. Downloads,
configuration, keys and logs are not included in this repository. See
[contributing](CONTRIBUTING.md) and [security](SECURITY.md) before sharing reports.
