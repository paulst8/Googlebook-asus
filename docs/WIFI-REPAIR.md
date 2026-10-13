# Wi-Fi repair investigation — ASUS BE200

The first boot reached setup but showed no Wi-Fi networks. This is not enough to
identify the failing layer without Googlebook's kernel log.

Observed:
- PCI adapter: Intel 8086:272b, subsystem 8086:00f4 (BE200/Gale Peak).
- Googlebook includes iwlwifi, iwlmld, iwlmvm and wireless stack modules for
  `6.18.21-android17-5-ga3bbc4527b7b-ab16320342`.
- The extracted driver's BZ/GL base configuration encodes core105 maximum and
  core101 minimum; firmware request code contains a decrementing fallback path.
  Hardware-specific restrictions and actual initialization still need logs.
- Intel firmware upstream commit `b72356140866169b692ad33a69a0e5b6e596ebd6`
  contains c101/c102/c103/c106/c107 for GL/FM and BZ/FM. Searching the fetched
  branch/tag history found no c105 file under either old or new path for these
  two families. This does not prove that Intel has never made a private build.
- Installed GL c103 and PNVM match Intel upstream byte-for-byte. The c103 internal
  firmware version is `103.1a5cc88d.0`. No genuine c105 payload was located.

[Official Intel firmware tree](https://kernel.googlesource.com/pub/scm/linux/kernel/git/iwlwifi/linux-firmware/+/refs/heads/for-upstream/intel/iwlwifi)

The owner's previous working installation used c104/c105 filename links to c103.
Those links were removed during the earlier review before a real boot test.
That change is a possible regression, not an established diagnosis.

The alias-enabled build subsequently connected to Wi-Fi with validated internet.
This does not establish Wi-Fi 7 operation or support for every BE200 variant.

Repair options:
- Preserve genuine upstream c103 and matching PNVM for GL/FM and BZ/FM; record
  their hashes in ignored `work/wifi-debug/firmware-provenance.json`.
- `WIFI_COMPAT_ALIASES=1` restores the previous filename links explicitly. The
  payload still reports core103. Existing real c104/c105 files are never replaced.
- `WIFI_DEBUG=1` saves a filtered kernel log to the existing gbkmsg partition every
  ten seconds for three minutes. It does not need networking or completed setup.
  No screenshot or full Android logcat capture is enabled.

Apply from the project directory:

```bash
set -o pipefail
sudo WIFI_COMPAT_ALIASES=1 WIFI_DEBUG=1 bash scripts/bm-vendor.sh 2>&1 | tee work/wifi-repair.log
```

This rebuilds vendor and changes its contents and vbmeta flags on the
configured Ubuntu SSD (and the configured installer USB if connected). It does not repartition or erase userdata. Review the
successful full read-back before rebooting.

On the next Googlebook boot, remain at setup for at least three minutes. If Wi-Fi
still fails, return to Ubuntu and extract the saved diagnostic snapshot:

```bash
sudo bash scripts/bm-wifi-log.sh > work/wifi-kernel.log
```

Inspect firmware name, loaded internal version, PNVM status, RF-kill state,
firmware crash messages and interface creation before changing the kernel driver.
A new module must match this Googlebook kernel's configuration, symbol versions
and wireless stack; copying Ubuntu's driver is not a compatible replacement.

Keep `WIFI_COMPAT_ALIASES=1` on subsequent vendor rebuilds when this laptop needs
the workaround, or add `WIFI_COMPAT_ALIASES="1"` to `bm.conf`. Re-running
`bm-configure.sh` regenerates that file; reapply custom options afterward.
If a configured USB installer is connected, the vendor script also updates it;
unplug it for an SSD-only repair.
