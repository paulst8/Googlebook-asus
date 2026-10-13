# Cast My Apps and Continue On

## Confirmed attestation failure in later ADB transcripts

The owner's October 13 captures at 23:27–23:33 establish a companion secure-channel
attestation failure, beyond the earlier boot-log timeouts:

- At 23:27:39, CDM_CompanionTransport reports an RKPD HTTP 444 error and
  OUT_OF_KEYS_PERMANENT_ERROR while generating its attestation key.
- At 23:30:14, the provisioning server explicitly responds `Device not registered.`
  The certificate pool contains zero keys. A preceding network request succeeds.
- At 23:32:42, both CDM_SecureChannel and CDM_CompanionTransport contain
  `AttestationVerifier.generateAvfAttestation(AttestationVerifier.java:198)`.
- Nearby separately records successful UKEY2 authentication and payload transfers.
  This establishes working transport in those attempts, not every network feature.
- The Trusty launcher is restarting and IVmAttestation/default is unavailable.

These excerpts confirm an attestation blocker in this installation. They do not
prove why the Trusty launcher crashes or that the guest payload is absent. The
port explicitly sets desktop.security_vm.vm_image to /dev/null and substitutes
software KeyMint; these must be accounted for in any deeper investigation.
Restoring a guest image alone is not a demonstrated solution to server-side
registration. Stock lapis images are not factory firmware for this ASUS TUF.
No working repair for the official phone features has been demonstrated.

The four supplied transcripts overlap substantially; they are not four independent
reproductions. Raw logs are kept outside repository documentation because they
contain device and connection metadata. Do not repeat pairing, wipe user data,
or reinstall partitions to address this confirmed provisioning failure.

## Earlier investigation

The reported pairing timeout is unresolved. Source inspection alone does not
establish that software KeyMint, attestation, or Wi-Fi is the cause. The installer
keeps the Google system/product apps, but replaces hardware security components
and stops several services that crash on this laptop. Do not blindly restart
those services or change verified-boot properties as a phone integration fix.

First check Google's supported setup:

- Compatible Android 17+ phone, same personal Google account on both devices.
- Wi-Fi and Bluetooth enabled, same home network with multicast DNS and no
  client isolation; temporarily test without a VPN.
- Update Google Play services and Cross-device services through Google Play on
  both devices. Complete Cross-device services / Continue activity setup and
  enable Apps and Tasks. Toggle Cross-device services off for ten seconds and
  back on if necessary. Do not erase Google Play services data.

Official references:
[requirements and setup](https://support.google.com/googlebook/answer/16945063?hl=en),
[connection troubleshooting](https://support.google.com/googlebook/answer/18735325?hl=en-AU).
Avoid stock OS OTA installation as a troubleshooting step on this modified port;
preserving its vendor and boot changes through an OTA has not been tested.

## Capture a failed attempt without ADB

From the repository in Ubuntu:

```bash
set -o pipefail
sudo LEAN=1 WIFI_COMPAT_ALIASES=1 WIFI_DEBUG=1 PHONE_DEBUG=1 bash scripts/bm-vendor.sh 2>&1 | tee work/phone-debug-build.log
```

This preserves the Wi-Fi aliases and adds diagnostics; it is not a confirmed
phone integration fix. The existing vendor write confirmation and disk guards
still apply. After a successful build/write, boot Googlebook, unlock it, and
try each phone feature in the first ten minutes. Note the approximate attempt
times. Wait at least 45 seconds after the last failure before rebooting Ubuntu:

```bash
sudo bash scripts/bm-phone-log.sh > work/phone-debug.log
```

The logger takes 32 snapshots separated by 30-second pauses after boot completes,
with time-limited commands. It writes only the first 32 MiB of the existing gblog
partition. The reader selects the configured SSD by serial, checks that it holds
Ubuntu, and excludes stale snapshots from older boots. LEAN=0 is rejected to
avoid other writers corrupting the capture. Logs remain local and may include
network names, device identifiers, and app log metadata; review before publishing.
Some denials may be absent when the boot entry disables audit logging.

Remove phone capture on a later vendor rebuild by omitting PHONE_DEBUG=1. Keep
WIFI_COMPAT_ALIASES=1 while this laptop needs the firmware filename workaround.
Android execution and cross-device behavior still require a real boot test.

## Findings from the October 13 post-update boot

The local capture confirms Google Play services 26.37.37 is active after a new
boot. Its older 26.22.43 factory package also appears in the package dump; that
alone does not establish that two versions are running. Wi-Fi connected in the
preceding capture. The fresh boot still reports a missing
`CdsNotificationListenerService`, a missing Nearby migration component, and RKPD
timeouts (`OUT_OF_KEYS_TRANSIENT_ERROR`) for app IDs 10209 and 1010209. Requests
also wait for `IVmAttestation/default`. None of these messages alone proves the
cause of app casting failure; the failing app IDs need mapping to packages.

For a live, read-only inspection, use `scripts/bm-phone-inspect.sh` on a host
with ADB while Googlebook is running. Set `ADB_SERIAL` explicitly to Googlebook.
The existing Ubuntu installation on this same laptop cannot inspect the running
Googlebook through ADB while Ubuntu is booted. A separate host or the Googlebook
Linux terminal with working ADB connectivity is needed. The report includes
package state, UID mapping and casting-process logs, and may contain personal
device metadata. Do not publish it without reviewing it.
