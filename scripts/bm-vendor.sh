#!/bin/bash
# bm-vendor.sh - rebuild the Googlebook "vendor" partition for REAL hardware and write it onto the SSD (and the stick, if plugged in).
# Only the vendor part of `super` and the flags of `vbmeta_a` are written. Nothing else is touched.
# Run:  cd ~/gbos && sudo bash scripts/bm-vendor.sh        (takes ~10 minutes; run it after bm-nvme.sh so the SSD has the partitions)
#
# What it changes compared with Google's original vendor image (stock graphics are kept):
#  1. Adds firmware from this Ubuntu (the files listed in bm.conf): Intel GPU, Wi-Fi, Bluetooth, Ethernet.
#  2. Replaces the parts that need Google's security chip (Trusty/TPM) with software ones.
#  3. Adds the sound setup for the Realtek ALC256 codec and stops services that crash-loop without Google's hardware.
#  4. Switches verification off in vbmeta_a (run bm-sign.sh afterwards if you want verified/locked boot).
set -euo pipefail
GBOS=${GBOS:-$PWD}
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); LIB="$HERE/lib"
[ -f "$GBOS/bm.conf" ] && . "$GBOS/bm.conf"
SERIAL="${1:-${STICK_SERIAL:-none}}"
cd "$GBOS"
[ "$EUID" -eq 0 ] || { echo "Run with sudo:  sudo bash $0"; exit 1; }
[ -n "${SSD_SERIAL:-}" ] || { echo "SSD_SERIAL is not set: run  bash scripts/bm-configure.sh  first (it detects your drives and hardware)"; exit 1; }
for t in mkfs.erofs dump.erofs getfattr setfattr secilc zstd python3 udevadm lsblk xxd readelf mount; do
  command -v $t >/dev/null || { echo "missing tool: $t   (try: sudo apt install erofs-utils attr secilc zstd xxd binutils)"; exit 1; }; done
CF=work/cuttlefish; W=work/bm_tmp; R=work/bm_vendor_root; M=work/bm_mnt
for f in super/vendor_a.img super/system_a.img super/system_ext_a.img super/product_a.img \
         $CF/security/rust_nonsecure_payload.img $CF/security/boot-service.default \
         $CF/security/com.android.hardware.gatekeeper.nonsecure.apex "$LIB/unpack_cf_x86.py"; do
  [ -e "$f" ] || { echo "missing $GBOS/$f"; exit 1; }; done

cleanup() { for m in vendor sysa sysext product; do umount "$M/$m" 2>/dev/null || true; done; }
trap cleanup EXIT
cleanup; rm -rf "$W" "$R"; mkdir -p "$W/km" "$M"/{vendor,sysa,sysext,product}

# ---------------------------------------------------------------- find the stick (USB + serial only)
DEV=""
for d in /sys/block/sd*; do
  [ -e "$d" ] || continue; n=/dev/$(basename "$d")
  p=$(udevadm info --query=property --name="$n")
  if grep -qx "ID_BUS=usb" <<<"$p" && grep -qx "ID_SERIAL_SHORT=$SERIAL" <<<"$p"; then DEV=$n; fi
done
SUPER_DEV=""; VBM_DEV=""
if [ -n "$DEV" ] && [ "$(lsblk -dno TRAN "$DEV")" = usb ]; then
  part_by_name() {  # $1 = GPT partition name -> device node on the stick
    local d n
    for d in /sys/block/$(basename "$DEV")/$(basename "$DEV")*; do
      n=/dev/$(basename "$d")
      if [ "$(udevadm info --query=property --name="$n" | sed -n 's/^ID_PART_ENTRY_NAME=//p')" = "$1" ]; then echo "$n"; return; fi
    done
  }
  SUPER_DEV=$(part_by_name super); VBM_DEV=$(part_by_name vbmeta_a)
  [ -n "$SUPER_DEV" ] && [ -n "$VBM_DEV" ] && echo "Stick: $DEV   super=$SUPER_DEV   vbmeta_a=$VBM_DEV (will also be updated)" || { SUPER_DEV=""; VBM_DEV=""; echo "stick found but has no super/vbmeta_a - ignoring it"; }
else
  echo "USB stick not plugged in - not needed: only the SSD copy (what Android boots) will be written."
fi

echo "== 1. software KeyMint from Cuttlefish"
P=$CF/security/rust_nonsecure_payload.img
if [ -s work/vtmp/km/keymint ] && [ -s work/vtmp/km/libcrypto.so ]; then cp work/vtmp/km/keymint work/vtmp/km/libcrypto.so $W/km/
elif file -b "$P" | grep -qi erofs; then
  dump.erofs --path=/bin/hw/android.hardware.security.keymint-service.nonsecure --cat "$P" > $W/km/keymint
  dump.erofs --path=/lib64/libcrypto.so --cat "$P" > $W/km/libcrypto.so
else
  debugfs -R "dump /bin/hw/android.hardware.security.keymint-service.nonsecure $W/km/keymint" "$P"
  debugfs -R "dump /lib64/libcrypto.so $W/km/libcrypto.so" "$P"
fi
[ -s $W/km/keymint ] && [ -s $W/km/libcrypto.so ] || { echo "KeyMint extraction failed"; exit 1; }

echo "== 2. mount the original images read-only and copy vendor (keeps owners + SELinux labels)"
mount -t erofs -o ro,loop super/vendor_a.img "$M/vendor"
mount -t erofs -o ro,loop super/system_a.img "$M/sysa"
mount -t erofs -o ro,loop super/system_ext_a.img "$M/sysext"
mount -t erofs -o ro,loop super/product_a.img "$M/product"
mkdir -p "$R"; cp -a "$M/vendor/." "$R/"
getfattr -n security.selinux "$R/etc/init/hwc3-drm.rc" 2>/dev/null | grep -q selinux \
  || { echo "SELinux labels not preserved - stopping"; exit 1; }
CFG=$(getfattr --only-values -n security.selinux "$R/etc/init/hwc3-drm.rc")
label_of() { getfattr --only-values -n security.selinux "$1"; }
setlabel() { setfattr -n security.selinux -v "$1" "$2"; }

echo "== 3. firmware from this Ubuntu"
FWSRC=/lib/firmware; FWDST="$R/firmware"; FWEXTRA="$GBOS/fw-extra"
FWL=$(label_of "$FWDST/iwlwifi-sc-a0-wh-a0.pnvm" 2>/dev/null || label_of "$FWDST/cs42l43.bin")
FWDL=$(label_of "$FWDST/i915")
addfw() {  # $1 = path relative to /lib/firmware (without .zst); resolves symlinks, decompresses
  local rel="$1" src="" out="$FWDST/$1"
  if [ -e "$FWSRC/$rel.zst" ]; then src="$FWSRC/$rel.zst"; elif [ -e "$FWSRC/$rel" ]; then src="$FWSRC/$rel"; elif [ -e "$FWEXTRA/$rel" ]; then src="$FWEXTRA/$rel"; else return 1; fi
  mkdir -p "$(dirname "$out")"
  local d="$FWDST"; for part in $(dirname "$rel" | tr '/' ' '); do [ "$part" = . ] && continue; d="$d/$part"; setlabel "$FWDL" "$d" ; done
  if [[ "$src" == *.zst ]]; then zstd -dc < "$src" > "$out" 2>/dev/null || true; else cat "$src" > "$out"; fi
  if [ ! -s "$out" ] && [ -s "$FWEXTRA/$rel" ]; then cat "$FWEXTRA/$rel" > "$out"; fi
  [ -s "$out" ] || { echo "  !! EMPTY firmware file, skipped: $rel (from $src)"; rm -f "$out"; return 1; }
  chmod 0644 "$out"; chown 0:0 "$out"; setlabel "$FWL" "$out"; echo "  + $rel"
}
addglob() {  # $1 = directory, remaining = name prefixes; every file starting with a prefix (.zst stripped)
  local dir="$1"; shift; local pre f b
  for pre in "$@"; do
    for f in "$FWSRC/$dir/$pre"*; do
      [ -e "$f" ] || continue; b=$(basename "$f"); b=${b%.zst}; addfw "$dir/$b" || true
    done
  done
}
[ -d "$FWSRC" ] || { echo "$FWSRC missing"; exit 1; }
# which firmware to copy: bm.conf (made by bm-configure.sh from what YOUR Ubuntu actually loads). The defaults are this project's test laptop.
FW_GPU=${FW_GPU:-"i915:adlp_dmc i915:adlp_guc_70 i915:tgl_huc i915:tgl_guc_70"}
FW_BT=${FW_BT:-"ibt-0190-0291"}
FW_ETH=${FW_ETH:-"rtl8168h-2"}
FW_WIFI_BASES=${FW_WIFI_BASES:-"iwlwifi-bz-b0-fm-c0 iwlwifi-gl-c0-fm-c0"}
for e in $FW_GPU; do addglob "${e%%:*}" "${e#*:}"; done
for p in $FW_BT; do addglob intel "$p"; done
for p in $FW_ETH; do addglob rtl_nic "$p"; done
# Wi-Fi: the newest few versions (the driver loads the highest one it understands) + the pnvm file.
for base in $FW_WIFI_BASES; do
  for f in $( (ls "$FWSRC"; ls "$FWEXTRA" 2>/dev/null) | grep -E "^$base(-c?[0-9]+)?\.ucode(\.zst)?$" | sed 's/\.zst$//' | sort -uV | tail -7); do addfw "$f" || true; done
  for f in $( (ls "$FWSRC"; ls "$FWEXTRA" 2>/dev/null) | grep -E "^$base\.pnvm(\.zst)?$" | sed 's/\.zst$//' | sort -u); do addfw "$f" || true; done
  top=$(ls "$FWDST" | grep -E "^$base-c(10[0-3])\.ucode$" | sort -V | tail -1)   # link target = newest file the driver can plausibly take (<= c103)
  if [ -n "$top" ]; then for n in 104 105; do [ -e "$FWDST/$base-c$n.ucode" ] || { ln -s "$top" "$FWDST/$base-c$n.ucode"; setfattr -h -n security.selinux -v "$FWL" "$FWDST/$base-c$n.ucode"; echo "  + $base-c$n.ucode -> $top (symlink, experiment)"; }; done; fi
done
echo "  GPU firmware now in vendor: $(ls "$FWDST/i915" "$FWDST/xe" 2>/dev/null | tr '\n' ' ')"
ls "$FWDST/i915" "$FWDST/xe" 2>/dev/null | grep -q guc || echo "  WARNING: no GPU GuC firmware found - the GPU driver will probably fail (run scripts/bm-configure.sh and check FW_GPU in bm.conf)"

echo "== 4. software replacements for the security chip (same as the VM build)"
install -o 0 -g 2000 -m 0755 $W/km/keymint "$R/bin/hw/android.hardware.security.keymint-service.vm"
setlabel u:object_r:hal_keymint_default_exec:s0 "$R/bin/hw/android.hardware.security.keymint-service.vm"
install -D -o 0 -g 0 -m 0644 $W/km/libcrypto.so "$R/lib64/vm_keymint/libcrypto.so"
setlabel u:object_r:vendor_file:s0 "$R/lib64/vm_keymint"; setlabel u:object_r:vendor_file:s0 "$R/lib64/vm_keymint/libcrypto.so"
put_rc() { tee "$R/etc/init/$1" >/dev/null; chmod 0644 "$R/etc/init/$1"; setlabel "$CFG" "$R/etc/init/$1"; }
put_rc vm-software-keymint.rc <<'RC'
# AOSP software KeyMint: not hardware-backed (this PC has no Trusty/Google security chip).
service vendor.keymint-vm /vendor/bin/hw/android.hardware.security.keymint-service.vm
    class early_hal
    user nobody
    setenv LD_LIBRARY_PATH /vendor/lib64/vm_keymint:/vendor/lib64
RC
rm -f "$R/apex/com.android.hardware.keymint.strongbox.desktop.apex"
replace_keep_label() {  # $1 = source, $2 = vendor path, $3 = mode
  local L; L=$(label_of "$R/$2"); local O; O=$(stat -c %u:%g "$R/$2")
  install -o "${O%:*}" -g "${O#*:}" -m "$3" "$1" "$R/$2"; setlabel "$L" "$R/$2"
}
replace_keep_label $CF/security/boot-service.default bin/hw/android.hardware.boot-service.android-desktop 0755
stub_keep_label() {  # $1 = vendor path, stdin = new content
  local L; L=$(label_of "$R/$1"); tee "$R/$1" >/dev/null; setlabel "$L" "$R/$1"
}
for m in android.hardware.weaver-service.android-desktop android.hardware.gatekeeper-service.trusty \
         android.hardware.security.secretkeeper.trusty; do
  echo '<manifest version="9.0" type="device"/>' | stub_keep_label etc/vintf/manifest/$m.xml
done
echo '# No charge-control hardware: this service crash-looped and loaded init.' | stub_keep_label etc/init/hal_desktop_charge_control_default.rc
echo '# No Weaver hardware.' | stub_keep_label etc/init/android.hardware.weaver-service.android-desktop.rc
echo '# The software Gatekeeper apex (com.android.hardware.gatekeeper.nonsecure) serves this PC.' \
  | stub_keep_label etc/init/android.hardware.gatekeeper-service.trusty.rc
echo '# No Trusty Secretkeeper.' | stub_keep_label etc/init/android.hardware.security.secretkeeper.trusty.desktop.rc
APEXL=$(label_of "$R/apex/com.android.hardware.cas.apex")
install -o 0 -g 0 -m 0644 $CF/security/com.android.hardware.gatekeeper.nonsecure.apex "$R/apex/"
setlabel "$APEXL" "$R/apex/com.android.hardware.gatekeeper.nonsecure.apex"
put_rc bm-absent-hardware.rc <<'RC'
# No TPM-based gscd here: keep it from crash-looping.
on early-init
    stop android.system.desktop.security.gscd
    # trusty_security_vm_launcher aborts (SIGABRT, +crash_dump +flags_health_check) on every start because this property is missing
    setprop desktop.security_vm.vm_image /dev/null
    # init waits 10 s for /dev/tpm0 (system gscutil.rc post-fs) and this PC has none: give it an empty stand-in so the wait ends at once
    symlink /dev/null /dev/tpm0
# These services crash-loop every few seconds on this PC (no protected VM / EC / charge hardware) and keep init (PID 1) at ~100% CPU = the lag.
# Overriding them is blocked (treble boundary) and one early `stop` is undone by later explicit `start`s, so stop them at several points,
# including right when init notices the crashing (that action fires on every crash until they are stopped for good).
on init
    stop apgetty
    stop timberslide
    stop trusty_security_protected_vm_launcher
    stop hal_desktop_charge_control_default
    stop udsattestation
    stop virtualizationservice
on boot
    stop apgetty
    stop timberslide
    stop trusty_security_protected_vm_launcher
    stop hal_desktop_charge_control_default
    stop udsattestation
    stop virtualizationservice
on property:sys.init.updatable_crashing=1
    stop apgetty
    stop timberslide
    stop trusty_security_protected_vm_launcher
    stop hal_desktop_charge_control_default
    stop udsattestation
    stop virtualizationservice
on property:sys.boot_completed=1
    stop apgetty
    stop timberslide
    stop trusty_security_protected_vm_launcher
    stop hal_desktop_charge_control_default
    stop udsattestation
    stop virtualizationservice
RC
tee "$R/etc/vintf/manifest/vm-sharedsecret.xml" >/dev/null <<'XML'
<manifest version="1.0" type="device">
    <hal format="aidl">
        <name>android.hardware.security.sharedsecret</name>
        <fqname>ISharedSecret/default</fqname>
    </hal>
</manifest>
XML
chmod 0644 "$R/etc/vintf/manifest/vm-sharedsecret.xml"
setlabel "$(label_of "$R/etc/vintf/manifest")" "$R/etc/vintf/manifest/vm-sharedsecret.xml"

# Graphics stays stock (ANGLE on Vulkan/ANV, minigbm, hwc3-drm). One safety switch: hwc3-drm rejects display
# planes that lack the new KMS COLOR_PIPELINE property; turning that feature off is harmless if they have it.
sed -i -E '/^vendor\.hwc\.drm\.enable_color_pipeline=/d' "$R/build.prop"
printf '\n# bare metal: do not require KMS COLOR_PIPELINE\nvendor.hwc.drm.enable_color_pipeline=false\n' >> "$R/build.prop"

echo "== 5. logging to the stick (raw partitions gbkmsg + gblog)"
SE="$R/etc/selinux"
printf '\n/dev/block/by-name/gblog u:object_r:gbos_log_device:s0\n/dev/block/by-name/gbkmsg u:object_r:gbos_log_device:s0\n' >> "$SE/vendor_file_contexts"
put_rc bm-log.rc <<'RC'
# Every 4 s: copy the kernel log and the Android log onto the stick's raw log partitions (read later from Ubuntu).
service bm-log /system/bin/sh -c "while :; do /system/bin/dmesg 2>&1 | /system/bin/dd of=/dev/block/by-name/gbkmsg bs=65536 conv=fsync 2>/dev/null; /system/bin/logcat -d -b all -v threadtime -t 40000 2>&1 | /system/bin/dd of=/dev/block/by-name/gblog bs=65536 conv=fsync 2>/dev/null; sleep 4; done"
    user root
    group root shell log readproc system
    seclabel u:r:shell:s0
on init
    start bm-log
RC
# keep the screen on: the default 2-minute screen timeout puts the whole laptop into sleep, and a timer wake does not turn the screen back on
put_rc bm-awake.rc <<'RC'
service bm-awake /system/bin/sh -c "while :; do /system/bin/settings put system screen_off_timeout 2147483647 >/dev/null 2>&1; /system/bin/settings put global stay_on_while_plugged_in 7 >/dev/null 2>&1; /system/bin/svc power stayon true >/dev/null 2>&1; /system/bin/settings put system min_refresh_rate 60.0 >/dev/null 2>&1; /system/bin/settings put system peak_refresh_rate 60.0 >/dev/null 2>&1; sleep 20; done"
    user root
    group root shell system
    seclabel u:r:shell:s0
    disabled
on property:sys.boot_completed=1
    start bm-awake
RC
# diagnostics: what does Android THINK is on screen? screenshots (from SurfaceFlinger) + a SurfaceFlinger dump, written to raw log partitions
put_rc bm-shot.rc <<'RC'
service bm-shot /system/bin/sh -c "sleep 8; i=0; while :; do /system/bin/timeout 8 /system/bin/screencap -p > /data/local/tmp/gb.png 2>/dev/null; n=$$(/system/bin/wc -c < /data/local/tmp/gb.png); if [ $$n -gt 1000 ]; then o=$$((32+(i%15)*2)); ( echo GBSHOT $$(date +%s); /system/bin/cat /data/local/tmp/gb.png ) | /system/bin/dd of=/dev/block/by-name/gbkmsg bs=1M seek=$$o conv=notrunc,fsync 2>/dev/null; i=$$((i+1)); fi; /system/bin/timeout 10 /system/bin/dumpsys SurfaceFlinger 2>&1 | /system/bin/head -c 1000000 | /system/bin/dd of=/dev/block/by-name/gblog bs=1M seek=64 conv=notrunc,fsync 2>/dev/null; sleep 45; done"
    user root
    group root shell system graphics
    seclabel u:r:shell:s0
    disabled
on property:init.svc.surfaceflinger=running
    start bm-shot
RC
# diagnostics: performance sampler (CPU use, CPU/GPU frequency, temperatures, memory, busiest processes) -> gblog at 128 MiB
put_etc() { tee "$R/etc/$1" >/dev/null; chmod 0644 "$R/etc/$1"; setlabel "$CFG" "$R/etc/$1"; }
put_etc bm-perf.sh <<'RC'
#!/system/bin/sh
sleep 30
F=/data/local/tmp/perf.txt
rm -f $F
while :; do
  {
    echo "=== $(date +%H:%M:%S) up=$(cut -d' ' -f1 /proc/uptime)"
    head -1 /proc/stat
    cat /proc/loadavg
    echo "cpufreq: $(cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq 2>/dev/null | tr '\n' ' ')"
    echo "gpufreq: $(cat /sys/class/drm/card*/device/tile0/gt0/freq0/cur_freq 2>/dev/null | tr '\n' ' ') act: $(cat /sys/class/drm/card*/device/tile0/gt0/freq0/act_freq 2>/dev/null | tr '\n' ' ')"
    echo "temps: $(for z in /sys/class/thermal/thermal_zone*; do echo -n "$(cat $z/type 2>/dev/null)=$(cat $z/temp 2>/dev/null) "; done)"
    grep -E 'MemFree|MemAvailable|Dirty:|Writeback:|SwapFree' /proc/meminfo | tr '\n' ' '; echo
    grep -E 'pgmajfault|pswpin|pswpout' /proc/vmstat | tr '\n' ' '; echo
    top -b -n 1 -d 1 -m 12 2>&1 | head -20
  } >> $F 2>/dev/null
  tail -c 800000 $F > $F.n && mv $F.n $F
  tail -c 300000 $F | dd of=/dev/block/by-name/gblog bs=1M seek=128 conv=notrunc,fsync 2>/dev/null
  sleep 6
done
RC
put_rc bm-perf.rc <<'RC'
service bm-perf /system/bin/sh /vendor/etc/bm-perf.sh
    user root
    group root shell system
    seclabel u:r:shell:s0
    disabled
on property:sys.boot_completed=1
    start bm-perf
RC
# audio experiment: the legacy HDA driver (what Ubuntu uses for 8086:51ca) is on the module blocklist and snd_soc_avs wins and fails.
# Same pattern as init.fatcat.rc uses for iwlmld (vendor_modprobe domain). Harmless if it fails; result is in the kernel log.
put_rc bm-audio.rc <<'RC'
on init
    exec_background u:r:vendor_modprobe:s0 -- /vendor/bin/modprobe --dirname=/vendor/lib/modules snd_hda_intel
RC
# audio: the Google desktop audio HAL picks /vendor/etc/audio/<card name>/audio_config.xml (USB cards live in for_all_boards/).
# The image only has a config for the original ASUS SoundWire board, so on this PC the audio policy never starts (NO_INIT).
# EXPERIMENT: add configs for this laptop's Realtek ALC256 card ("HDA Intel PCH", id PCH) and the NVIDIA HDMI card ("HDA NVidia").
mk_audio_cfg() {  # $1 = dir name under etc/audio (and for_all_boards), $2 = card id, then stdin = <HiFi> body
  local body; body=$(cat)
  local AL; AL=$(label_of "$R/etc/audio/for_all_boards/Dummy"); local FL; FL=$(label_of "$R/etc/audio/for_all_boards/Dummy/audio_config.xml")
  for d in "$R/etc/audio/$1" "$R/etc/audio/for_all_boards/$1"; do
    mkdir -p "$d"; chmod 0755 "$d"; setfattr -n security.selinux -v "$AL" "$d"
    printf "<?xml version='1.0' encoding='utf-8'?>\n<audio_config>\n\t<SoundCardName>hw:%s</SoundCardName>\n\t<HiFi>\n%s\n\t</HiFi>\n</audio_config>\n" "$2" "$body" > "$d/audio_config.xml"
    printf "<?xml version='1.0' encoding='utf-8'?>\n<mixer enum_mixer_numeric_fallback=\"true\">\n</mixer>\n" > "$d/mixer_paths.xml"
    chmod 0644 "$d/audio_config.xml" "$d/mixer_paths.xml"
    setfattr -n security.selinux -v "$FL" "$d/audio_config.xml"; setfattr -n security.selinux -v "$FL" "$d/mixer_paths.xml"
  done
}
mk_audio_cfg HDA_Intel_PCH PCH <<'XML'
		<Speaker>
			<PlaybackPCM>hw:PCH,0</PlaybackPCM>
		</Speaker>
		<Headphone>
			<PlaybackPCM>hw:PCH,0</PlaybackPCM>
			<JackDev>@JK_HP@</JackDev>
			<JackSwitch>2</JackSwitch>
		</Headphone>
		<InternalMic>
			<CapturePCM>hw:PCH,0</CapturePCM>
			<IntrinsicSensitivity>-2600</IntrinsicSensitivity>
			<RampUpMs>100</RampUpMs>
		</InternalMic>
		<Mic>
			<CapturePCM>hw:PCH,0</CapturePCM>
			<CaptureMixerElem>Capture</CaptureMixerElem>
			<JackDev>@JK_MIC@</JackDev>
		</Mic>
		<HDMI1>
			<PlaybackPCM>hw:PCH,3</PlaybackPCM>
			<JackDev>@JK_H1@</JackDev>
			<PlaybackChannels>2</PlaybackChannels>
		</HDMI1>
		<HDMI2>
			<PlaybackPCM>hw:PCH,7</PlaybackPCM>
			<JackDev>@JK_H2@</JackDev>
			<PlaybackChannels>2</PlaybackChannels>
		</HDMI2>
		<HDMI3>
			<PlaybackPCM>hw:PCH,8</PlaybackPCM>
			<JackDev>@JK_H3@</JackDev>
			<PlaybackChannels>2</PlaybackChannels>
		</HDMI3>
XML
mk_audio_cfg HDA_NVidia NVidia <<'XML'
		<HDMI1>
			<PlaybackPCM>hw:NVidia,3</PlaybackPCM>
			<PlaybackChannels>2</PlaybackChannels>
		</HDMI1>
		<HDMI2>
			<PlaybackPCM>hw:NVidia,7</PlaybackPCM>
			<PlaybackChannels>2</PlaybackChannels>
		</HDMI2>
XML
# audio: the HAL loads the single board dir of the image (sof-soundwire_...), whose config names the nonexistent card hw:sofsoundwire.
# Rewrite it for this laptop's ALC256 card (id PCH); overwriting in place keeps the SELinux labels.
BD="$R/etc/audio/sof-soundwire_cs42l43_cs35l56"
if [ -d "$BD" ]; then
cat > "$BD/audio_config.xml" <<'XML'
<?xml version='1.0' encoding='utf-8'?>
<audio_config>
	<SoundCardName>hw:PCH</SoundCardName>
	<HiFi>
		<Speaker>
			<PlaybackPCM>hw:PCH,0</PlaybackPCM>
		</Speaker>
		<Headphone>
			<PlaybackPCM>hw:PCH,0</PlaybackPCM>
			<JackDev>@JK_HP@</JackDev>
			<JackSwitch>2</JackSwitch>
		</Headphone>
		<InternalMic>
			<CapturePCM>hw:PCH,0</CapturePCM>
			<IntrinsicSensitivity>-2600</IntrinsicSensitivity>
			<RampUpMs>100</RampUpMs>
		</InternalMic>
		<Mic>
			<CapturePCM>hw:PCH,0</CapturePCM>
			<CaptureMixerElem>Capture</CaptureMixerElem>
			<JackDev>@JK_MIC@</JackDev>
		</Mic>
		<HDMI1>
			<PlaybackPCM>hw:PCH,3</PlaybackPCM>
			<JackDev>@JK_H1@</JackDev>
			<PlaybackChannels>2</PlaybackChannels>
		</HDMI1>
		<HDMI2>
			<PlaybackPCM>hw:PCH,7</PlaybackPCM>
			<JackDev>@JK_H2@</JackDev>
			<PlaybackChannels>2</PlaybackChannels>
		</HDMI2>
		<HDMI3>
			<PlaybackPCM>hw:PCH,8</PlaybackPCM>
			<JackDev>@JK_H3@</JackDev>
			<PlaybackChannels>2</PlaybackChannels>
		</HDMI3>
	</HiFi>
</audio_config>
XML
cat > "$BD/mixer_paths.xml" <<'XML'
<?xml version='1.0' encoding='utf-8'?>
<mixer enum_mixer_numeric_fallback="true">
	<ctl name="Master Playback Switch" value="1" />
	<ctl name="Master Playback Volume" value="87" />
	<ctl name="Auto-Mute Mode" value="0" />
	<ctl name="PCM Playback Volume" value="255 255" />
	<path name="Speaker">
		<ctl name="Speaker Playback Switch" value="1 1" />
		<ctl name="Speaker Playback Volume" value="87 87" />
	</path>
	<path name="Headphone">
		<ctl name="Headphone Playback Switch" value="1 1" />
		<ctl name="Headphone Playback Volume" value="60 60" />
	</path>
	<path name="InternalMic">
		<ctl name="Capture Switch" value="1 1" />
		<ctl name="Capture Volume" value="40 40" />
	</path>
	<path name="Mic">
		<ctl name="Capture Switch" value="1 1" />
		<ctl name="Capture Volume" value="40 40" />
	</path>
	<path name="HDMI1" />
	<path name="HDMI2" />
	<path name="HDMI3" />
</mixer>
XML
rm -f "$BD/sound_card_init.xml" "$BD/CS35L56.xml"
fi
# fill in the jack input-device names (what the kernel calls the headphone/mic/HDMI jack events); copy over the file so SELinux labels stay
JK_HP="${JK_HP:-HDA Intel PCH Headphone}"; JK_MIC="${JK_MIC:-HDA Intel PCH Headphone}"
JK_H1="${JK_H1:-HDA Intel PCH HDMI/DP,pcm=3}"; JK_H2="${JK_H2:-HDA Intel PCH HDMI/DP,pcm=7}"; JK_H3="${JK_H3:-HDA Intel PCH HDMI/DP,pcm=8}"
for f in "$R/etc/audio/HDA_Intel_PCH/audio_config.xml" "$R/etc/audio/for_all_boards/HDA_Intel_PCH/audio_config.xml" "$BD/audio_config.xml"; do
  [ -f "$f" ] || continue
  sed -e "s|@JK_HP@|$JK_HP|g" -e "s|@JK_MIC@|$JK_MIC|g" -e "s|@JK_H1@|$JK_H1|g" -e "s|@JK_H2@|$JK_H2|g" -e "s|@JK_H3@|$JK_H3|g" "$f" > "$f.tmp" && cat "$f.tmp" > "$f" && rm -f "$f.tmp"
done
# LEAN is ON by default now (LEAN=0 sudo -E bash scripts/bm-vendor.sh keeps the diagnostics): drops the diagnostics (screenshots, SurfaceFlinger dumps, perf sampler, 4-second log dumps) for a faster, quieter system
if [ "${LEAN:-1}" = 1 ]; then
  rm -f "$R/etc/init/bm-shot.rc" "$R/etc/init/bm-perf.rc" "$R/etc/bm-perf.sh" "$R/etc/init/bm-log.rc"
  echo "  LEAN build: diagnostics services removed (no logs will be saved to the log partitions)"
fi
# audio ROOT CAUSE (found with the boot capture): the HAL reads /vendor/etc/data/hal_configs/audio_default.xml, which names the sound card
# "sof-soundwire" (-> card id sofsoundwire, absent on this PC -> "internal card not found" x100 -> audio policy NO_INIT).
# Point it at this laptop's Realtek card (id PCH) and the HDA_Intel_PCH config folder; overwrite in place so SELinux labels stay.
HC="$R/etc/data/hal_configs/audio_default.xml"
if [ -f "$HC" ]; then
  printf '<AudioConfiguration>\n  <soundcard>PCH</soundcard>\n  <audio-config-dir>HDA_Intel_PCH</audio-config-dir>\n</AudioConfiguration>\n' > "$HC"
  echo "  audio: hal_configs/audio_default.xml -> soundcard PCH, dir HDA_Intel_PCH"
fi
# make the HDA_Intel_PCH folder complete: volume curves + the unmuting mixer file from the (already rewritten) board dir
HD="$R/etc/audio/HDA_Intel_PCH"; BD="$R/etc/audio/sof-soundwire_cs42l43_cs35l56"
if [ -d "$HD" ] && [ -f "$BD/volume_curves.xml" ] && [ -f "$BD/mixer_paths.xml" ]; then
  FL2=$(label_of "$R/etc/audio/for_all_boards/Dummy/audio_config.xml")
  cat "$BD/volume_curves.xml" > "$HD/volume_curves.xml"; cat "$BD/mixer_paths.xml" > "$HD/mixer_paths.xml"
  chmod 0644 "$HD/volume_curves.xml" "$HD/mixer_paths.xml"
  setfattr -n security.selinux -v "$FL2" "$HD/volume_curves.xml" "$HD/mixer_paths.xml"
fi
# audio debugging (temporary, AUDIODBG=0 removes it): a small capture of ONLY the audio-related log lines from early boot
# (the abort storm pushes them out of the normal log buffer) -> /data/local/tmp/audio-boot.log (max 600 KB), read it with adb shell cat
if [ "${AUDIODBG:-1}" = 1 ]; then
put_rc bm-audiodbg.rc <<'RC'
service bm-audiodbg /system/bin/sh -c "umask 022; rm -f /data/local/tmp/audio-boot.log /data/local/tmp/audio-snap.txt; mkdir -p /data/local/tmp; (sleep 90; { getprop | grep -iE 'audio|sku|product.device|soundcard|vendor.model'; ls -lZ /dev/snd; ps -A | grep -iE 'dras|audioserver'; } > /data/local/tmp/audio-snap.txt 2>&1) & /system/bin/logcat -b all -v threadtime 2>&1 | /system/bin/grep -aiE 'dras|audio|alsa|soundcard' | /system/bin/grep -avE 'am_cpu|SysAdapter|NO_INIT|createTrack|PartnerConfig|sysui|Fatal signal|crash_dump|AudioTrack|AudioSystem|AudioSvc|AudioProduct' | /system/bin/head -c 600000 > /data/local/tmp/audio-boot.log"
    user root
    group root shell log readproc system
    seclabel u:r:shell:s0
    oneshot
on post-fs-data
    start bm-audiodbg
RC
echo "  AUDIODBG: audio-only boot log capture added (/data/local/tmp/audio-boot.log)"
fi
tee -a "$SE/vendor_sepolicy.cil" >/dev/null <<'CIL'
; bare metal: raw log partitions on the stick + kernel log access for the log writer
(type gbos_log_device)
(roletype object_r gbos_log_device)
(typeattributeset dev_type (gbos_log_device))
(allow shell_202604 gbos_log_device (blk_file (open read write getattr ioctl)))
(allow shell_202604 kmsg_device_202604 (chr_file (open read getattr)))
(allow shell_202604 kernel_202604 (system (syslog_read)))
CIL
# init ignores this CIL while precompiled_sepolicy matches the system hashes, so delete it: init compiles
# the CIL at boot. Ubuntu's secilc is older than Android's, so check on copies with newer policy caps stripped.
VER=$(cat "$SE/plat_sepolicy_vers.txt"); GV=$(cat "$SE/genfs_labels_version.txt")
SP=$W/se; mkdir -p $SP
STRIP='^\(policycap (functionfs_seclabel|memfd_class)\)'
S=$M/sysa/system/etc/selinux; X=$M/sysext/etc/selinux; PR=$M/product/etc/selinux
grep -vE "$STRIP" $S/plat_sepolicy.cil > $SP/plat_sepolicy.cil
grep -vE "$STRIP" "$SE/vendor_sepolicy.cil" > $SP/vendor_sepolicy.cil
secilc -m -M true -G -N -c 30 -o $SP/check.policy -f /dev/null \
  $SP/plat_sepolicy.cil $S/mapping/$VER.cil $S/plat_sepolicy_genfs_$GV.cil \
  $X/system_ext_sepolicy.cil $X/mapping/$VER.cil $PR/product_sepolicy.cil $PR/mapping/$VER.cil \
  "$SE/plat_pub_versioned.cil" $SP/vendor_sepolicy.cil "$R/odm/etc/selinux/odm_sepolicy.cil" \
  || { echo "SELinux CIL check failed - stopping (nothing was written to the stick)"; exit 1; }
rm -f "$SE"/precompiled_sepolicy "$SE"/precompiled_sepolicy.*.sha256
echo "  CIL check passed; precompiled_sepolicy removed"

echo "== 6. rebuild EROFS"
SIZE=$(stat -c %s super/vendor_a.img); NEW=$((SIZE+1))
build() {
  for OPTS in "-zlz4hc,12 -C65536 -Eztailpacking" \
              "-zlz4hc,12 -C262144 -Eztailpacking,fragments" \
              "-zlz4hc,12 -C262144 -Eztailpacking,fragments,dedupe" \
              "-zlzma,9 -C262144 -Eztailpacking,fragments"; do
    rm -f work/vendor_bm.img
    mkfs.erofs $OPTS work/vendor_bm.img "$R" >/dev/null 2>&1 || true
    NEW=$(stat -c %s work/vendor_bm.img); echo "  $OPTS -> $NEW"
    [ "$NEW" -le "$SIZE" ] && return 0
  done; return 1
}
if ! build; then
  echo "  too big - dropping firmware for other chips (Panther Lake Wi-Fi/GPU) and retrying"
  rm -f "$FWDST"/iwlwifi-sc-* "$FWDST"/iwlwifi-wh-* "$FWDST"/i915/xe3lpd* "$FWDST"/i915/xe2lpd* 2>/dev/null || true
  build || { echo "still too big ($NEW > $SIZE) - stopping, nothing was written to the stick"; exit 1; }
fi
truncate -s "$SIZE" work/vendor_bm.img
echo "new vendor $NEW bytes fits partition area $SIZE"

echo "== 7. write the vendor to the SSD (and the stick, if plugged in)"
SSDSUP=""; SSDVBM=""
for d in /sys/block/nvme*n*; do
  [ -e "$d" ] || continue; n=/dev/$(basename "$d")
  [ "$(lsblk -dno SERIAL "$n" | tr -d ' ')" = "$SSD_SERIAL" ] || continue
  for q in "$d"/"$(basename "$d")"p*; do
    pn=$(udevadm info --query=property --name=/dev/$(basename "$q") | sed -n 's/^ID_PART_ENTRY_NAME=//p')
    [ "$pn" = super ] && SSDSUP=/dev/$(basename "$q"); [ "$pn" = vbmeta_a ] && SSDVBM=/dev/$(basename "$q")
  done
done
[ -n "$SSDSUP" ] && [ -n "$SSDVBM" ] || { echo "No Googlebook super/vbmeta_a on the SSD (serial $SSD_SERIAL) - stopping, nothing was written"; exit 1; }
VOFF=$(python3 -I -c 'import sys;sys.path.insert(0,sys.argv[2]);from unpack_cf_x86 import super_partitions as s;print(s(sys.argv[1])["vendor_a"])' "$SSDSUP" "$LIB")
write_vendor() {  # $1 = super dev, $2 = vbmeta dev
  [ "$(dd if="$1" bs=1 skip=$((VOFF+1024)) count=4 status=none | xxd -p)" = "e2e1f5e0" ] || { echo "no EROFS at vendor offset on $1 - skipping it"; return 1; }
  [ "$(dd if="$2" bs=1 count=4 status=none)" = "AVB0" ] || { echo "vbmeta_a on $2 is not AVB - skipping it"; return 1; }
  dd if=work/vendor_bm.img of="$1" bs=4M seek=$VOFF oflag=seek_bytes conv=notrunc,fsync status=none
  printf '\x00\x00\x00\x03' | dd of="$2" bs=1 seek=120 conv=notrunc,fsync status=none
  sync
  cmp -n 67108864 <(dd if="$1" bs=4M skip=$VOFF iflag=skip_bytes,count_bytes count=67108864 status=none) work/vendor_bm.img \
    && echo "  wrote $1 - read-back of the first 64 MiB matches" || { echo "  READ-BACK FAILED on $1"; return 1; }
}
write_vendor "$SSDSUP" "$SSDVBM" || exit 1
if [ -n "$SUPER_DEV" ]; then write_vendor "$SUPER_DEV" "$VBM_DEV" || echo "  (stick copy not updated)"; fi
echo
echo "DONE. Vendor written to the SSD ($SSDSUP) at offset $VOFF; verification disabled in vbmeta_a."
echo "Next: sudo bash scripts/bm-boot.sh (if kernel options changed), then reboot and pick Googlebook OS in the GRUB menu. The stick is not needed."
