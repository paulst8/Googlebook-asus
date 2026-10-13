# Installation & Setup Manual

This document provides a comprehensive, start-to-finish guide to installing and running Googlebook OS natively on bare-metal x86_64 laptops alongside existing installations of Ubuntu and Windows.

## Table of Contents

[Prerequisites & System Requirements](#prerequisites--system-requirements)

[Storage Modes (Single-Drive Internal NVMe vs. Dedicated Secondary Drive)](#storage-modes-single-drive-internal-nvme-vs-dedicated-secondary-drive)

[Preparing Unallocated Space](#preparing-unallocated-space)

[Downloading Build Archives](#downloading-build-archives)

[Step-by-Step Installation Pipeline](#step-by-step-installation-pipeline)

[Step 1: Install Host Packages](#step-1-install-host-packages)

[Step 2: Configure Target Hardware](#step-2-configure-target-hardware)

[Step 3: Validate & Prepare Build Archives](#step-3-validate--prepare-build-archives)

[Step 4: Create GPT Partition Structure](#step-4-create-gpt-partition-structure)

[Step 5: Flash Core Images & Build Custom Vendor Partition](#step-5-flash-core-images--build-custom-vendor-partition)

[Step 6: Register Ubuntu GRUB2 Multi-Boot Entry](#step-6-register-ubuntu-grub2-multi-boot-entry)

[First Boot & System Initialization](#first-boot--system-initialization)

[Reversion & Uninstallation](#reversion--uninstallation)

---

## Prerequisites & System Requirements

Before beginning the installation, ensure your environment meets all hardware and software criteria.

| Requirement | Specification | Notes |
| :--- | :--- | :--- |
| **Host OS** | Ubuntu 22.04 LTS / 24.04 LTS or Debian 12 (x86_64) | Primary host environment for executing build and setup scripts |
| **Disk Space** | ~32 GB Unallocated GPT Space | Unallocated drive space on your primary NVMe drive |
| **Firmware** | UEFI Mode with Secure Boot Disabled | Secure Boot must be turned off in laptop BIOS/UEFI settings |
| **Required Packages** | erofs-utils, attr, secilc, zstd, jq, e2fsprogs, gdisk | Required by flashing and verification scripts |

---

## Storage Modes (Single-Drive Internal NVMe vs. Dedicated Secondary Drive)

Googlebook-asus supports two distinct hardware storage configurations.

### Single-Drive Internal NVMe Mode (Default / Built-In Workspace)

In single-drive internal NVMe mode (configured via NO_USB=1), Googlebook OS lives on dedicated partitions on your primary drive.

Safety: bm-nvme.sh performs non-destructive GPT editing.

Coexistence: Your current OS partitions (EFI System Partition, Windows/Ubuntu root) remain intact.

### Dedicated Secondary Drive Mode

If you prefer to install Googlebook OS onto a dedicated secondary drive, set NO_USB=0 during script execution.

---

## Preparing Unallocated Space

To install Googlebook OS on a single primary drive alongside Windows or Ubuntu, you must create at least 32 GB of unallocated disk space.

### Shrinking Partition under Ubuntu

Open GParted (`sudo apt install gparted && sudo gparted`).

Select your main NVMe drive (`/dev/nvme0n1`).

Right-click your main Linux partition, select Resize/Move.

Reduce the partition size by at least 32768 MB.

Click Apply All Operations.

### Shrinking Partition under Windows

Right-click Start button and select Disk Management.

Right-click your C: drive or main data volume and select Shrink Volume.

Enter 32768 (MB) as the amount of space to shrink.

Click Shrink. Do NOT format or create a new volume in the resulting unallocated space.

---

## Downloading Build Archives

Googlebook OS requires two build archives:

Googlebook OS Base System Image tarball (`googlebook-base-*.tar.zst`)

ASUS Hardware Enablement Overlay tarball (`asus-overlay-*.tar.zst`)

Place both `.tar.zst` files in the root directory of this repository before executing scripts.

---

## Step-by-Step Installation Pipeline

Execute all commands from the root directory of the Googlebook-asus repository.

### Step 1: Install Host Packages

Ensure all essential host dependencies are installed:

```bash
sudo apt update && sudo apt install -y erofs-utils attr secilc zstd jq e2fsprogs gdisk
```

### Step 2: Configure Target Hardware

Run bm-configure.sh to detect hardware devices and write the target configuration:

```bash
sudo ./scripts/bm-configure.sh
```

Output: Validates hardware compatibility and generates target environment parameters.

### Step 3: Validate & Prepare Build Archives

Validate checksums and extract base and overlay archives:

```bash
./scripts/bm-check.sh
./scripts/bm-prepare.sh
```

Output: Validated and extracted base image trees in build/ directory.

### Step 4: Create GPT Partition Structure

Create the native Googlebook OS partitions on the internal NVMe drive:

```bash
sudo ./scripts/bm-nvme.sh
```

Output: Backs up GPT table and creates dedicated system and user data partitions.

### Step 5: Flash Core Images & Build Custom Vendor Partition

Flash images, assemble ASUS device driver payload, and provision Wi-Fi firmware:

```bash
sudo ./scripts/bm-flash.sh
sudo ./scripts/bm-vendor.sh
sudo ./scripts/bm-wifi-fw.sh
```

Output: Writes system images and provisions vendor-specific firmware.

### Step 6: Register Ubuntu GRUB2 Multi-Boot Entry

Add Googlebook OS entry to host GRUB2 menu:

```bash
sudo ./scripts/bm-ubuntu-grub.sh
```

Output: GRUB2 configuration updated with Googlebook OS boot target.

---

## First Boot & System Initialization

Follow these steps after running the installation pipeline:

Reboot your laptop.

At the GRUB menu, select Googlebook OS.

System initializes user space and loads hardware drivers.

---

## Reversion & Uninstallation

To completely remove Googlebook OS and restore your partition table:

```bash
sudo ./scripts/bm-undo.sh
```

Reverts GPT changes and removes multi-boot GRUB entry.
