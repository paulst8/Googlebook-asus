<div align="center<div align="center">
    
    <img src="docs/assets/banner.svg" alt="Googlebook OS on a regular Intel laptop" width="100%">
    
    # Googlebook OS on Bare-Metal Laptops
    
    **Status**: Experimental | **Platform**: Intel x86_64 | **License**: MIT | **Docs**: Step-by-Step Guide
    
    </div>
    
    Googlebook OS on Bare-Metal Laptops is an open-source hardware enablement suite that boots Google's Android 17-based Googlebook OS natively on bare-metal x86_64 laptops alongside existing Ubuntu and Windows installations. By combining automated EROFS filesystem reconstruction, hardware-specific driver injection, and native GRUB2 multi-boot integration, this project provides a seamless, high-performance desktop experience without virtual machine overhead.
    
    ---
    
    ## Key Capabilities
    
    - **Hybrid Image Pipeline**: Bridges Google's Android 17 `lapis` base image with Cuttlefish x86_64 hardware enablement modules for native bare-metal performance.
    - **Automated EROFS & SELinux Patching**: Reconstructs read-only EROFS vendor images and dynamically updates SELinux security contexts and filesystem attributes (`attr`, `secilc`).
    - **Host Firmware Injection**: Extracts host Linux Wi-Fi (`iwlwifi`) and Bluetooth firmware directly from the host system into Android vendor overlays.
    - **Non-Destructive GPT Partitioning**: Safely partitions free NVMe disk space while automatically creating a full primary GPT header backup (`gpt_backup_header.bin`) prior to writing partition modifications.
    - **Ubuntu GRUB2 Integration**: Registers a clean, dedicated multi-boot entry inside `/etc/grub.d/40_googlebook` for effortless startup OS selection.
    
    ---
    
    ## System Requirements
    
    | Requirement | Specification | Notes |
    | :--- | :--- | :--- |
    | **Host OS** | Ubuntu 22.04 / 24.04 LTS or Debian 12 (x86_64) | Uses host GRUB2 as the primary boot manager. |
    | **Disk Space** | ~32 GB Unallocated GPT Space | Free space on primary internal NVMe SSD or secondary drive. |
    | **Firmware** | UEFI Mode (Secure Boot Disabled) | Secure Boot must be turned off in BIOS/UEFI settings. |
    | **Required Host Packages** | `erofs-utils attr secilc zstd xxd binutils gdisk curl python3` | Install via `sudo apt update && sudo apt install -y erofs-utils attr secilc zstd xxd binutils gdisk curl python3`. |
    
    ---
    
    ## End-to-End Quick Start
    
    1. **Install host packages & prepare unallocated disk space**:
       Install necessary build tools (`sudo apt install -y erofs-utils attr secilc zstd xxd binutils gdisk curl python3`) and shrink an existing partition via GParted or Windows Disk Management to leave ~32 GB unallocated GPT space.
       2. **Download the two official build archives**:
          Obtain `gbos-base-*.tar.zst` and `gbos-asus-hw-*.tar.zst` and place them in the project root directory (`~/gbos`).
          3. **Configure target hardware with `bm-configure.sh`**:
             Run `sudo ./scripts/bm-configure.sh` to auto-detect NVMe SSD serial numbers, PCI address mappings, Wi-Fi hardware, and storage mode (`NO_USB=1`).
             4. **Validate and unpack images with `bm-check.sh` and `bm-prepare.sh`**:
                Run `./scripts/bm-check.sh` to verify SHA256 integrity, followed by `./scripts/bm-prepare.sh` to unpack base components into `build/raw/`.
                5. **Create Android GPT partitions with `bm-nvme.sh`**:
                   Run `sudo ./scripts/bm-nvme.sh` to back up primary GPT headers and construct native Android GPT partitions on unallocated disk space.
                   6. **Flash partitions and build custom vendor image with `bm-flash.sh`, `bm-vendor.sh`, and `bm-wifi-fw.sh`**:
                      Run `sudo ./scripts/bm-flash.sh`, `sudo ./scripts/bm-vendor.sh`, and `sudo ./scripts/bm-wifi-fw.sh` to flash system binaries, synthesize custom EROFS vendor overlays, and inject host wireless firmware.
                      7. **Register the GRUB boot entry with `bm-ubuntu-grub.sh`**:
                         Run `sudo ./scripts/bm-ubuntu-grub.sh` to register Googlebook OS into GRUB (`/etc/grub.d/40_googlebook`) and update boot configuration.
                         
                         ---
                         
                         ## Script & Tool Reference
                         
                         | Script | Purpose / Exact Role |
                         | :--- | :--- |
                         | `bm-configure.sh` | Analyzes host hardware (NVMe serial, PCI IDs, firmware) and generates `config.env`. |
                         | `bm-check.sh` | Validates downloaded image release archives against SHA256 checksum manifests. |
                         | `bm-prepare.sh` | Extracts raw partition images and kernel modules into `build/raw/`. |
                         | `bm-nvme.sh` | Backs up primary GPT headers and creates native Android partitions on unallocated SSD space. |
                         | `bm-flash.sh` | Flashes boot, init_boot, and system images to target NVMe GPT partitions. |
                         | `bm-vendor.sh` | Builds custom EROFS vendor image with Cuttlefish overlays and SELinux patches. |
                         | `bm-wifi-fw.sh` | Extracts host Wi-Fi/Bluetooth firmware blobs and injects them into vendor overlays. |
                         | `bm-ubuntu-grub.sh` | Registers `/etc/grub.d/40_googlebook` boot entry and updates GRUB menu. |
                         | `bm-lock-boot.sh` | Configures optional custom AVB signing keys and verified boot chain. |
                         | `bm-phone-Link-fix.sh` | Solves phone link/ADB connectivity and attestation quirks on bare metal. |
                         
                         ---
                         
                         ## Documentation Guide
                         
                         | Document | Focus & Description |
                         | :--- | :--- |
                         | [docs/SETUP.md](docs/SETUP.md) | Comprehensive start-to-finish installation manual and storage mode guide. |
                         | [docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md) | In-depth technical architecture of the EROFS pipeline, kernel, and GRUB integration. |
                         | [docs/WIFI-REPAIR.md](docs/WIFI-REPAIR.md) | Guide for extracting and injecting Intel/Realtek host Wi-Fi & Bluetooth firmware binaries. |
                         | [docs/PHONE-INTEGRATION.md](docs/PHONE-INTEGRATION.md) | Step-by-Step setup for Android Phone Link, ADB debugging, and attestation. |
                         | [docs/LOCKED-BOOT.md](docs/LOCKED-BOOT.md) | Advanced guide to locking the boot pipeline with custom Android Verified Boot (AVB) keys. |
                         | [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Diagnostic workflows, common boot errors, logcat collection, and hardware fixes. |
                         Intel laptop, next to your existing Ubuntu and Windows.

![Status](https://img.shields.io/badge/status-experimental-orange)
![Platform](https://img.shields.io/badge/platform-Intel%20x86__64-blue)
![Tested on](https://img.shields.io/badge/tested%20on-ASUS%20TUF%20F16-informational)
![License](https://img.shields.io/badge/license-MIT-green)
![Docs](https://img.shields.io/badge/docs-step--by--step-success)

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

Googlebook OS is Android, shipped as a disk image for Google's own hardware. These scripts add Android to unused space on your SSD, swap the parts that need Google's security chip for software ones, add the firmware your laptop needs, and put an entry in your boot menu. Existing OS partitions are preserved; Ubuntu boot files and GRUB configuration are modified. More in [How it works](docs/HOW-IT-WORKS.md).

## USB-free installation

For installation entirely on the Ubuntu SSD, use the [USB-free guide](docs/USB-FREE.md).
See the [current ASUS review](docs/REVIEW-2026-10-13.md) for fixes and remaining limitations.

## Quick start

You need an Intel laptop with Ubuntu, about 60 GB of unallocated SSD space, a 32 GB+ USB stick, and two downloads. The [full guide](docs/SETUP.md) lists everything; the short version is:

```bash
git clone https://github.com/paulst8/Googlebook-asus ~/gbos && cd ~/gbos
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

### Phone integration limitation

Native **Cast My Apps** and **Continue On** remain unsupported on this installation.
ADB captures show companion attestation failures and a provisioning response of
`Device not registered`, despite successful Nearby transport. The software security
replacements do not recreate a factory-provisioned Googlebook identity.
See [verified findings](docs/PHONE-INTEGRATION.md) and [Wi-Fi repair](docs/WIFI-REPAIR.md).
