# Troubleshooting

## Known issues

<details open>
<summary><strong>Cast My Apps and Continue on do not work</strong></summary>

ADB captures confirm companion-channel attestation failures: certificate provisioning returns HTTP 444 (`Device not registered`), and the Trusty attestation service is unavailable. Nearby authentication and some payload transfers succeed. No working repair for native Cast My Apps or Continue On has been demonstrated on this port. See [verified findings and diagnostics](PHONE-INTEGRATION.md). Re-pairing or reinstalling does not resolve the registration rejection.

</details>

<details>
<summary><strong>Slow boot</strong></summary>

Boot time has not been optimised. The first boot after setup or a data reset takes several minutes because Android builds its app caches. Later boots are faster.

To see where time goes, connect adb to the laptop and run `bash scripts/bm-boottime.sh`. It prints the boot phases, the busiest processes and the lock state. Attach its output to your issue if you ask for help with boot time.

</details>

<details>
<summary><strong>Crash loop of unused security services</strong></summary>

A few services that need Google's security chip keep restarting every few seconds. They do not use noticeable CPU (the setup stops the ones that did). It is harmless but noisy in the logs.

</details>

<details>
<summary><strong>Security chip replaced by software</strong></summary>

Features that need hardware key protection or attestation (some key-protected services) may not work.

</details>

## Boot problems

| Symptom | What to try |
|---|---|
| The Googlebook OS entry is missing from the menu | Hold **Shift** or **Esc** at start to show GRUB. If it is not there, run `sudo bash scripts/bm-ubuntu-grub.sh` again with the stick plugged in |
| Black screen, or a flicker | Use the "kernel messages on screen" entry to see where it stops. Display options are in `scripts/bm-boot.sh` (`EXTRA`) |
| It restarts again and again after switching locked/unlocked | The old data can't be opened in the new state. Run `sudo bash scripts/bm-reset-data.sh` |
| No Wi-Fi | Check `FW_WIFI_BASES` in `bm.conf`, run `bash scripts/bm-wifi-fw.sh`, then rebuild with `sudo bash scripts/bm-vendor.sh` |
| No sound | Check that `bash scripts/bm-configure.sh` found a sound card named `PCH`; see [Hardware](HARDWARE.md) |
| Android won't start at all | Boot Ubuntu and run `bash scripts/bm-check.sh`. Include its output in an issue |

## Getting back to a clean state

| I want to | Run |
|---|---|
| Factory-reset Googlebook OS only | `sudo bash scripts/bm-wipe-userdata.sh` |
| Give Android more space | `sudo bash scripts/bm-grow.sh` (erases its data) |
| Remove the boot entry | See [Undo](SETUP.md#undo) |

## Asking for help

Open a [bug report](../../../issues/new?template=bug_report.yml) and include your `bm.conf` (it contains your drive serial numbers; remove those lines if you don't want to share them), the step that failed, and the last lines of its output.
