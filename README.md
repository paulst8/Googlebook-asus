![Googlebook OS Banner](docs/assets/banner.svg)

# Googlebook OS on Bare-Metal Laptops

**Status**: Experimental

**Platform**: Intel x86_64

**License**: MIT

**Docs**: [docs/SETUP.md](docs/SETUP.md)

Googlebook OS on Bare-Metal Laptops is an open-source hardware enablement suite that boots Googlebook OS natively on standard Intel laptops alongside Linux and Windows, without requiring virtual machines or cloud emulation.

---

## Overview & Key Features

- **Bare-Metal Android 17 Installer**: Boots Android 17 (`lapis` + Cuttlefish x86_64) directly on bare-metal Intel laptop hardware.
- **Multi-Boot Support**: Integrates alongside existing Ubuntu Linux and Microsoft Windows installations without wiping host data.
- **Hardware Enablement**: Configures iGPU graphics acceleration, Wi-Fi, Bluetooth, audio, and touchpad/keyboard input for standard laptops.
- **GRUB2 Integration**: Registers boot entries automatically into Ubuntu GRUB (`/etc/grub.d/40_googlebook`).
- **Android Verified Boot (AVB)**: Provides custom AVB key injection support for locked-boot hardware validation.
-
---

## System Requirements

| Requirement | Specification |
| --- | --- |
| Host OS | Ubuntu 22.04 LTS / 24.04 LTS (or compatible Linux distribution) |
| Unallocated Disk Space | ~32 GB GPT unallocated space for Android partitions |
| UEFI Firmware | UEFI boot enabled, Secure Boot disabled or configured with custom keys |
| Required Host Packages | `git`, `curl`, `fastboot`, `adb`, `gdisk`, `e2fsprogs`, `grub2-common`, `python3` |

---

## Quick Start

### 1. Install Host Dependencies

Prepare the host Linux system with required utilities and tools:

```bash
sudo apt-get update
sudo apt-get install -y git curl android-tools-adb android-tools-fastboot gdisk e2fsprogs grub-common python3
```

### 2. Download Official Images

Download the official Googlebook OS (`lapis` / Cuttlefish x86_64) system image archive:

```bash
mkdir -p ~/googlebook-images
cd ~/googlebook-images
curl -L -O sys-img.zip
```

### 3. Configure and Validate

Validate environment configuration and target disk geometry before flashing:

```bash
python3 scripts/validate_env.py
```

### 4. Partition, Flash, and Build Vendor

Execute the automated partitioner, flash system images, and build vendor driver overlays:

```bash
sudo python3 scripts/partition_disk.py --disk /dev/nvme0n1
sudo python3 scripts/flash_images.py --image-dir ~/googlebook-images
sudo python3 scripts/build_vendor.py
```

### 5. Add GRUB Boot Entry

Install the GRUB dual-boot entry so Googlebook OS appears in the boot menu:

```bash
sudo python3 scripts/install_grub.py
sudo update-grub
```

---

## Script Reference

| Script | Path | Description |
| --- | --- | --- |
| Environment Validator | `scripts/validate_env.py` | Verifies system requirements, kernel version, dependencies, and disk geometry. |
| Disk Partitioner | `scripts/partition_disk.py` | Allocates ~32 GB GPT partitions for system, vendor, userdata, and boot. |
| Image Flasher | `scripts/flash_images.py` | Unpacks and writes Android system and boot images to target partitions. |
| Vendor Builder | `scripts/build_vendor.py` | Compiles hardware modules, kernel parameters, and driver overlays. |
| GRUB Installer | `scripts/install_grub.py` | Generates and registers `/etc/grub.d/40_googlebook` dual-boot configuration. |

---

## Documentation Guide

| Topic | Documentation Link | Description |
| --- | --- | --- |
| Setup & Installation | [docs/SETUP.md](docs/SETUP.md) | Comprehensive step-by-step installation and setup guide. |
| Architecture & Internal Mechanics | [docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md) | Technical overview of Cuttlefish x86_64 HALs and boot pipeline. |
| Hardware Compatibility | [docs/HARDWARE.md](docs/HARDWARE.md) | Hardware matrix, supported GPUs, Wi-Fi chips, and audio codecs. |
| Wi-Fi & Connectivity Repair | [docs/WIFI-REPAIR.md](docs/WIFI-REPAIR.md) | Troubleshooting and driver injection for wireless modules. |
| Phone & Ecosystem Integration | [docs/PHONE-INTEGRATION.md](docs/PHONE-INTEGRATION.md) | Configuring Phone Hub, Nearby Share, and cross-device sync. |
| AVB & Locked Boot Validation | [docs/LOCKED-BOOT.md](docs/LOCKED-BOOT.md) | Instructions for Android Verified Boot key injection and locked boots. |
| General Troubleshooting | [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Solutions to common boot failures, graphics issues, and log collection. |</li></li>
</ul>
