<p align="center">
  <img src="docs/assets/banner.svg" alt="Googlebook OS on a regular Intel laptop" width="100%">
</p>p>

# Googlebook OS on Bare-Metal Laptops

**Status**: Experimental | **Platform**: Intel x86_64 | **License**: MIT | **Docs**: docs/SETUP.md

---

Googlebook OS on Bare-Metal Laptops is an open-source hardware enablement suite that boots Googlebook OS natively on standard Intel laptops alongside Linux and Windows, without requiring virtual machines or cloud emulation.

---

## Key Capabilities

- **Hybrid Image Pipeline**: Combines Cuttlefish Android x86_64 system images with Asus-specific Linux kernel modules and driver overlays.
- - **Dual Boot Integration**: Registers directly with GRUB2 (`/etc/grub.d/40_googlebook`), allowing seamless switching between Ubuntu, Windows, and Googlebook OS.
  - - **Hardware Acceleration**: Full Intel iGPU (i915/xe) graphics passthrough, Wi-Fi/Bluetooth firmware injection, and audio pipeline support.
    - - **AVB & Security**: Supports custom Android Verified Boot (AVB) key injection for locked-boot hardware validation.
     
      - ---

      ## What Works

      - Intel Graphics Acceleration (Mesa 3D / Vulkan)
      - - Wi-Fi and Bluetooth connectivity
        - - Audio playback and microphone input
          - - Touchpad and keyboard input
            - - Multi-boot via Ubuntu GRUB2
             
              - ---

              ## Quick Start

              1. **Clone the repository**:
              2.    `git clone paulst8/Googlebook-asus`
              3.   `cd Googlebook-asus`
             
              4.   2. **Obtain system images**:
                   3.    Obtain `gbos-base-*.tar.zst` and `gbos-asus-hw-*.tar.zst` and place them in the project root directory (`~/gbos`).
                
                   4.3. **Configure target hardware**:
                      `sudo ./scripts/bm-configure.sh`
                      Run auto-detection for NVMe SSD serial numbers, PCI address mappings, Wi-Fi hardware, and storage mode.

                   4. **Validate and unpack images**:
                   5.    `./scripts/bm-check.sh`
                   6.   `./scripts/bm-prepare.sh`
                
                   7.   5. **Create GPT partitions**:
                        6.    `sudo ./scripts/bm-nvme.sh`
                     
                        7.6. **Flash partitions and build vendor overlays**:
                           `sudo ./scripts/bm-flash.sh`
                           `sudo ./scripts/bm-vendor.sh`
                           `sudo ./scripts/bm-wifi-fw.sh`

                        7. **Register GRUB boot entry**:
                        8.    `sudo ./scripts/bm-ubuntu-grub.sh`
                     
                        9.---

                        ## Script & Tool Reference

                        | Script | Purpose / Exact Role |
                        | :--- | :--- |
                        | `bm-configure.sh` | Analyzes host hardware and generates config.env. |
                        | `bm-check.sh` | Validates downloaded image release archives against SHA256 checksum manifests. |
                        | `bm-prepare.sh` | Extracts raw partition images and kernel modules into build/raw/. |
                        | `bm-nvme.sh` | Backs up primary GPT headers and creates native Android partitions on unallocated SSD space. |
                        | `bm-flash.sh` | Flashes boot, init_boot, and system images to target NVMe GPT partitions. |
                        | `bm-vendor.sh` | Builds custom EROFS vendor image with Cuttlefish overlays and SELinux patches. |
                        | `bm-wifi-fw.sh` | Extracts host Wi-Fi/Bluetooth firmware blobs and injects them into vendor overlays. |
                        | `bm-ubuntu-grub.sh` | Registers /etc/grub.d/40_googlebook boot entry and updates chain. |
                        | `bm-lock-boot.sh` | Configures optional custom AVB signing keys and verified boot chain. |
                        | `bm-phone-Link-fix.sh` | Solves phone link/ADB connectivity and attestation quirks on bare metal. |

                        ---

                        ## Documentation Guide

                        | Document | Focus & Description |
                        | :--- | :--- |
                        | docs/SETUP.md | Comprehensive start-to-finish installation manual and storage mode guide. |
                        | docs/HOW-IT-WORKS.md | In-depth technical architecture of the EROFS pipeline, kernel, and GRUB integration. |
                        | docs/WIFI-REPAIR.md | Guide for extracting and injecting Intel/Realtek host Wi-Fi & Bluetooth firmware binaries. |
                        | docs/PHONE-INTEGRATION.md | Step-by-Step setup for Android Phone Link, ADB debugging, and attestation. |
                        | docs/LOCKED-BOOT.md | Advanced guide to locking the boot pipeline with custom Android Verified Boot (AVB) keys. |
                        | docs/TROUBLESHOOTING.md | Diagnostic workflows, common boot errors, logcat collection, and hardware fixes. |
                        
