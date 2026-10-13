# Changelog

All notable changes. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

- Rebuild the fresh-install guide with cloning, complete packages, pinned official download URLs/checksums, serial inspection, USB-free staging and maintenance instructions.
- Add regression checks for documentation links and referenced scripts.

- USB-free installation, serial-bound Ubuntu/EFI checks, GPT validation and full vendor read-back.
- Explicit BE200 firmware compatibility aliases and bounded Android-compatible diagnostics.
- Confirmed companion attestation limitation documented; no native phone-integration fix claimed.
- Maintenance dry runs no longer alter boot files; finalization preserves recovery files.
- Optional boot experiments select vbmeta by configured SSD and reject ambiguous labels.
- Correct setup, Wi-Fi, boot-state and rollback documentation; broaden CI coverage.

## [0.1.0] - 2026-10-12

First public release.

### Added
- `bm-configure.sh`: detects your drives (by serial), GPU ID and the firmware your Ubuntu loads, and saves them in `bm.conf`. Every script reads it, so nothing is hard-coded to one laptop.
- Setup scripts: `bm-prepare`, `bm-usb`, `bm-nvme`, `bm-wifi-fw`, `bm-vendor`, `bm-boot`, `bm-ubuntu-grub`.
- Optional locked boot with your own key: `bm-sign`, `bm-verified`, `bm-locked-test`, `bm-reset-data`.
- `bm-finalize` (tidy boot menu), `bm-boottime` (where boot time goes), `bm-check`.
- Documentation: setup guide, hardware, locked boot, troubleshooting, how it works.

### Works (tested on an ASUS TUF F16 only)
Display, Wi-Fi, Bluetooth, sound (speakers, wired and Bluetooth headphones), webcam, Linux terminal, battery, USB.

### Known issues
Cast My Apps and Continue on do not work; the first boot is slow; no full Secure Boot chain.
