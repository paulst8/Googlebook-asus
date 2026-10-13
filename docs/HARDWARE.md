# Hardware

## What the scripts work out for you

`scripts/bm-configure.sh` looks at **your** laptop and writes `bm.conf`, which every other script reads. It never changes your disks.

| Detected | How | Used for |
|---|---|---|
| SSD and USB stick | You pick from the list; their serial numbers are saved | Every disk script finds its drive by serial number and refuses to touch any other |
| Intel GPU ID | `lspci` | `xe.force_probe=<id>` in the kernel options |
| GPU firmware | Names in your kernel log | Copied into Android's vendor part |
| Wi-Fi, Bluetooth, Ethernet firmware | Names in your kernel log | Copied into Android's vendor part |
| Sound card | `/proc/asound` | Checked against the built-in sound setup |

Anything it can't detect falls back to the test laptop's values, and it tells you.

## What is still specific to the test laptop

| Area | State on other laptops |
|---|---|
| **CPU / GPU** | Needs an **Intel** GPU supported by the `xe` driver. AMD and NVIDIA-only laptops are not supported |
| **Display options** | `scripts/bm-boot.sh` turns off several display features (`xe.enable_psr=0` and others) that caused a flickering screen on the test laptop. They are harmless elsewhere, just slightly less efficient. Change `EXTRA` if you want different ones |
| **Wi-Fi / Bluetooth** | **Intel** chips only. The firmware is copied from your Ubuntu. Realtek, MediaTek and Qualcomm chips are not handled |
| **Sound** | The sound setup assumes an Intel HDA card named `PCH` with an analog codec (the test laptop has a Realtek ALC256). Other Intel HDA laptops will probably work; SoundWire or SOF-only laptops will not |
| **Touchpad, keyboard, battery, USB** | Generic; they worked without changes |
| **Webcam** | The built-in camera worked on the test laptop |
| **NVIDIA GPU** | Present but unused |

> [!NOTE]
> "Probably works" means exactly that: it has not been tried. If you try it, please [report the result](../../../issues/new?template=hardware_report.yml), good or bad.

## If a script can't find your hardware

- Open `bm.conf` and look at the `FW_*` lines. They are plain text; edit them if the detection missed something.
- No firmware detected at all? Run `sudo bash scripts/bm-configure.sh` (the kernel log needs permission to read), or save a kernel log and use `KERNEL_LOG=saved.txt bash scripts/bm-configure.sh`.
- Graphics fail to start: check that `GPU_ID` matches `lspci -nn | grep -iE 'vga|display'` (the part after `8086:`).
