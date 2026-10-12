# Googlebook OS on a normal laptop (ASUS TUF F16)

Running Google's **Googlebook OS** (Android 17, Google's new laptop OS and the successor to ChromeOS) directly on a regular x86 laptop. Tested on an **ASUS TUF F16 (FX607VUR)**.

> **Unofficial and experimental.** Not affiliated with or endorsed by Google or ASUS. This repo contains **no Google files**; you download Google's recovery image yourself. Follow these steps at your own risk and back up first. The scripts write to disks.

## What works

| Works | Not working |
|---|---|
| Display and touchpad/keyboard | **Cast My Apps** and **Continue on** with an Android phone |
| Wi-Fi 7 and Bluetooth (Intel BE200) | Harmless crash loop of unused security services |
| Sound: speakers, wired and Bluetooth headphones | Slow first boot (several minutes) |
| Battery, USB, webcam, Linux terminal (Debian) | The NVIDIA GPU is unused |
| Verified boot with your own key, and a "locked" boot state | Real Secure Boot chain (see [Optional: locked boot](#optional-locked-boot)) |

On Cast My Apps: the phone and laptop find each other, but the encrypted handshake between them never completes. Details are in [Known issues](#known-issues).

## How it works (in plain words)

Googlebook OS is Android. Google ships it as a disk image for its own hardware, so it won't start on another laptop as it is. These scripts make three changes:

1. **Put Android on a spare area of a drive** (new partitions only; existing ones are not touched).
2. **Rebuild the "vendor" part of the image for your laptop.** That adds the Wi-Fi, Bluetooth and graphics firmware your laptop needs, swaps the parts that need Google's security chip for software ones, and adds the sound setup.
3. **Add a boot menu entry** to your existing Linux (GRUB) menu, so Googlebook OS is one choice at startup.

Your Windows and Linux installs stay as they are.

## What you need

- An **Intel laptop** with a recent Intel GPU. This was done on Raptor Lake-P; other CPUs will need their own firmware and possibly different settings.
- **Ubuntu** already installed (to run the scripts and to host the boot menu).
- **About 60 GB of free, unallocated space** on an SSD (not inside an existing partition). Android's system partitions take about 20 GB, and the rest is its data area: 40 GB by default, shrinking to 16 GB if space is short. More is better.
- A **USB stick of 32 GB or more** (it will be erased). It carries the setup files and the first boot menu. Once step 7 has put the boot entry in Ubuntu's menu, you don't need it to boot any more. On a 32 GB stick, run step 2 as `sudo USERDATA_GIB=4 bash bm-usb.sh`.
- Google's **Googlebook OS recovery image** for the ASUS *lapis* device (build 16452207, about 7 GB). Download it yourself from Google, then save it as `lapis-recovery.zip` in the project folder:
  ```
  https://dl.google.com/device/recovery/lapis-user/16452207/recovery.zip
  ```
  Its MD5 should be `38873eac8ff5b060baf229b7bcf7ec05`. The [cros.tech Googlebooks list](https://cros.tech/googlebooks/) shows every model's current build. The zip holds one raw disk image, which you unzip to `lapis.bin` and never modify.
- The Android **Cuttlefish** x86_64 test image, build 16373615 (`aosp_cf_x86_64_only_phone`). Open [this build page](https://ci.android.com/builds/submitted/16373615/aosp_cf_x86_64_only_phone-userdebug/) on ci.android.com, go to its *Artifacts* list and download `aosp_cf_x86_64_only_phone-img-16373615.zip`. The vendor script borrows its software security and graphics parts. If that build has expired, use the closest newer `aosp_cf_x86_64_only_phone-userdebug` build and change the file name in `bm-prepare.sh` to match (untested).
- Comfort typing commands into a terminal, and a few hours.

Before you start:
- **Turn off Secure Boot** in the firmware. If you use BitLocker on Windows, have your recovery key ready; Windows may ask for it once.
- **Back up anything important.** Do not skip this.

## Set up (one time)

Run these in Ubuntu.

**A. Install the tools**
```
sudo apt install git python3 unzip curl lz4 erofs-utils e2fsprogs mkbootimg attr binutils cpio xxd zstd secilc gdisk parted rsync dosfstools grub-efi-amd64-bin file openssl
```

**B. Get the scripts** into a project folder (keep about 80 GB free there while preparing)
```
git clone https://github.com/paulst8/googlebook-asus ~/gbos
cd ~/gbos
```

**C. Put your two downloads in that folder**, named exactly:
`lapis-recovery.zip` and `aosp_cf_x86_64_only_phone-img-16373615.zip` (links are under [What you need](#what-you-need)).

**D. Tell the scripts about your drives.** Find the serial numbers of your SSD and your USB stick:
```
lsblk -d -o NAME,SERIAL,TRAN,MODEL
```
`TRAN` shows `nvme` for the SSD and `usb` for the stick. Then run this, typing your two serials in place of the angle brackets (this puts your serial numbers into every script):
```
sed -i "s|YOUR_SSD_SERIAL|<your SSD serial>|g; s|YOUR_STICK_SERIAL|<your stick serial>|g" bm-*.sh
```

**E. Unpack the downloads** (no sudo, about 10 to 20 minutes)
```
bash bm-prepare.sh
```
It unzips Google's image, splits out the kernel, boot files and system partitions, unpacks the Cuttlefish parts, and makes the working copy. It finishes with "All set". If it lists something missing, fix that first.

## Steps

All commands are run in Ubuntu, from the project folder. The scripts ask you to confirm before anything is erased.

**1. Check your setup (changes nothing)**
```
bash bm-check.sh
```
It lists your drives, the stick, and the tools you still need.

**2. Prepare the stick** (erases the stick; asks you to type its serial first)
```
sudo bash bm-usb.sh
```
It copies Android's partitions onto the stick and sets up a small boot partition. Takes about 10 minutes. On a 32 GB stick: `sudo USERDATA_GIB=4 bash bm-usb.sh`.

**3. Add Android's partitions to your SSD** (adds new partitions only; the stick must stay plugged in)
```
DRYRUN=1 sudo bash bm-nvme.sh     # preview the plan first
sudo bash bm-nvme.sh
```

**4. Get newer Wi-Fi firmware** (Ubuntu's copy is too old for this image)
```
bash bm-wifi-fw.sh
```

**5. Build the laptop-specific vendor image**
```
sudo bash bm-vendor.sh
```
Takes about 10 minutes. This is the step that holds the audio, Wi-Fi and graphics fixes.

**6. Write the kernel and boot settings**
```
sudo bash bm-boot.sh
```

**7. Add Googlebook OS to Ubuntu's boot menu** (stick still plugged in)
```
sudo bash bm-ubuntu-grub.sh
```

**8. Restart.** If Ubuntu's menu is hidden, hold **Shift** or **Esc** while it starts, then pick **Googlebook OS**. The first boot takes several minutes and then runs the normal Android setup. After this you can unplug the stick.

To change the kernel options later, plug the stick back in and run steps 6 and 7 again.

To undo the boot entry: `sudo rm -rf /boot/gbos /etc/grub.d/40_googlebook && sudo update-grub`.

### Useful extras

| Script | What it does |
|---|---|
| `bm-wipe-userdata.sh` | Factory-resets Googlebook OS only |
| `bm-grow.sh` | Makes the Android data partition bigger (erases it) |
| `bm-boottime.sh` | Shows where boot time is spent (needs adb) |
| `bm-reset-data.sh` | Factory reset that also clears the data key (needed when switching between locked and unlocked) |
| `bm-verified.sh` | Optional: verified boot while still reported as unlocked |
| `bm-wifi-fw2.sh` | Fallback: finds older Wi-Fi firmware versions if step 4 isn't enough |

### Optional: locked boot

By default Android is told the bootloader is unlocked. You can instead sign the system with **your own key** and boot it as "locked". Do this after step 8, once everything works, and **unplug the USB stick first** so the scripts only see the SSD.

```
mkdir -p ~/gbos-avb-key && openssl genrsa -out ~/gbos-avb-key/avb.pem 4096 && chmod 600 ~/gbos-avb-key/avb.pem   # your private key: never share or upload it
sudo bash bm-sign.sh          # signs the system partitions with your key
sudo bash bm-locked-test.sh   # adds a "locked" boot entry (needs step 7 done)
sudo bash bm-reset-data.sh    # wipes Android's user data (type YES). Required: its encryption keys depend on the boot state
sudo bash bm-finalize.sh      # tidy the Googlebook entries in the boot menu (does not change your default)
```
Then restart and pick **Googlebook OS** (the locked entry). Android sets itself up again from scratch. Notes:
- Switching between locked and unlocked entries later needs `bm-reset-data.sh` again.
- Re-run `bm-sign.sh` and `bm-locked-test.sh` after every `bm-vendor.sh`.
- This only makes Android check its own system partitions. Nothing checks GRUB or the kernel before it, so it is not full Secure Boot.
- `bm-boottime.sh` (run with adb connected) shows where boot time goes.

## Adapting it to your laptop

The scripts have **my hardware as defaults**: the Wi-Fi/Bluetooth firmware, and the display and audio settings. Before running them:

- Your drive serials are set in step D of [Set up](#set-up-one-time). Each script refuses to touch any drive that doesn't match, which is deliberate.
- **Display:** the kernel options in `bm-boot.sh` (`xe.enable_psr=0` and the others) fix a flickering screen on this GPU. `xe.force_probe=a7ab` is **this laptop's GPU ID**: find yours with `lspci -nn | grep -i vga` (the part after `8086:`) and change it in `bm-boot.sh`. Other GPUs may need different options, and the firmware list in `bm-vendor.sh` is for this GPU generation.
- **Sound** is the part most tied to hardware. The image only ships a sound setup for Google's own laptop. For this one (Realtek ALC256), the vendor script adds a matching config and loads the sound driver early. A different codec will need its own config.

## Why it needs patching

A few things in the stock image don't exist on a normal laptop, which is what `bm-vendor.sh` works around:

- **No Google security chip (TPM).** The image expects hardware to hold encryption keys. Without it the key service crashed four times, which made the system reboot over and over. A software key service from Cuttlefish fixes that.
- **Intel Panther Lake firmware.** The image carries firmware for Google's laptop, not older Intel chips. The script adds the graphics, Wi-Fi and Bluetooth firmware your laptop needs.
- **Sound.** The image's only sound setup is for Google's own laptop's chips, so the script adds one for this laptop's codec and loads the driver early enough.
- **Verified boot** is turned off by default (the bootloader shows as unlocked), so don't use this for banking or other sensitive accounts. The optional locked boot above turns it on with your own key.

## Known issues

- **Cast My Apps / Continue on do not work.** The phone and laptop connect, but the encrypted channel between them never finishes: the phone waits for the laptop's reply and gives up after about 15–20 seconds. Nothing is logged on the laptop to say why, and the Wi-Fi and the phone's side look healthy. Re-pairing did not help. If you find the cause, please open an issue.
- **Google's security chip is replaced by software.** Features that need hardware attestation (some key-protected services) may not work.
- **Boot time is not optimised.** The first boot takes several minutes. `bm-boottime.sh` shows where time goes. A harmless crash loop of unused security services remains.

## Safety notes

- Scripts only add partitions in free space and save a copy of the partition table first (`nvme-gpt-backup-*.bin`). Keep it.
- Read each script's header before running it. They are short, commented, and say exactly what they touch.
- Never run these on a drive you haven't backed up.

## Credits

- [gbos-vm](https://github.com/skylartaylor/gbos-vm) by Skylar Taylor: the original approach, for Apple Silicon.
- [cros.tech/googlebooks](https://cros.tech/googlebooks/): image and codename directory.
- [lpunpack](https://github.com/unix3dgforce/lpunpack): unpacks Android's `super` partition.
- Android Cuttlefish: the software security and graphics parts.

Images are always downloaded directly from Google; nothing from Google or Android's test image is redistributed here.
