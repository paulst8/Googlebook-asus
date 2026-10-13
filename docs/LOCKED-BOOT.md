# Locked boot (optional)

By default Android is told that the bootloader is **unlocked** and skips checking its system partitions. This page shows how to sign the system with **your own key** so Android verifies its partitions and boots as **locked**.

> [!IMPORTANT]
> Read [what this does and does not protect](#what-this-does-and-does-not-protect) before you decide it is worth doing.

Do this **after** a normal setup works ([Setup guide](SETUP.md)), and **unplug the USB stick first** so the scripts only see the SSD.

## Steps

```bash
# 1. Make your private signing key. Keep it safe; never share or upload it.
mkdir -p ~/gbos-avb-key
openssl genrsa -out ~/gbos-avb-key/avb.pem 4096
chmod 600 ~/gbos-avb-key/avb.pem

# 2. Sign the system partitions with your key
sudo bash scripts/bm-sign.sh

# 3. Add the "LOCKED" boot entry
sudo bash scripts/bm-locked-test.sh

# 4. Erase Android's data (type YES). Required, see the note below
sudo bash scripts/bm-reset-data.sh

# 5. Tidy the Googlebook entries in the boot menu (does not change your default)
sudo bash scripts/bm-finalize.sh
```

Restart and pick **Googlebook OS**. Android sets itself up from scratch.

> [!NOTE]
> **Why the data reset?** Android ties the encryption keys of your data to the boot state. Data created while the bootloader was reported as unlocked cannot be opened when it is reported as locked, and the other way round. Booting with the wrong data makes Android restart into recovery. So every switch between locked and unlocked needs `bm-reset-data.sh`.

## Check that it worked

With adb connected to the laptop:

```bash
adb shell "getprop | grep -iE 'vbmeta|verity|verifiedboot|flash.locked'"
```

You should see `verifiedbootstate` set to `yellow`, `vbmeta.device_state` set to `locked`, `veritymode` set to `enforcing`, and a `vbmeta.digest`. That digest should match the one printed by `bm-sign.sh`.

## Good to know

- **After every `bm-vendor.sh`** run `bm-sign.sh` and `bm-locked-test.sh` again: `bm-vendor.sh` switches verification off.
- `bm-verified.sh` is a middle step: verified boot while still reported as unlocked. It is mostly for testing.
- The reported state is `yellow` for your custom key. This is supplied by bootconfig; it is not evidence that firmware verified GRUB or the kernel.
- To go back to unlocked: pick the unlocked entry in the "other options" submenu, after `sudo bash scripts/bm-reset-data.sh`.

## Boot states in plain words

| State | Meaning |
|---|---|
| `green` | Locked, and everything was verified with the manufacturer's key |
| `yellow` | Locked, and verified with a **custom** key (your own) |
| `orange` | **Unlocked**: nothing is verified. The default for this project |
| `red` | Verification failed |

## What this does and does not protect

Android now verifies its own system partitions with your key, so a changed system file is detected.

It does **not** protect the steps before Android. Nothing checks GRUB, the kernel or the ramdisk, so the "locked" label is only a label for those. A real chain of trust needs UEFI **Secure Boot** with a kernel you sign yourself, and this project does not do that yet. Treat locked boot as an experiment, not as a security feature, and don't use Googlebook OS for banking or other sensitive accounts.
