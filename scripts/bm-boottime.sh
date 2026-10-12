#!/bin/bash
# bm-boottime.sh - shows where Googlebook OS spends its boot time. Changes nothing.
# Run it in Ubuntu or in the Googlebook Linux terminal after the system is up, with adb connected to the laptop:
#   adb connect <laptop-ip:port>   (Settings > Developer options > Wireless debugging), then:  bash scripts/bm-boottime.sh
# Include the whole output when you open an issue.
S="adb ${ADB_SERIAL:+-s $ADB_SERIAL}"
$S shell '
echo "== boot milestones (ms since kernel start) =="
logcat -b events -d | grep -E "boot_progress" | sed "s/^.*I boot_progress_/  /"
echo; echo "== init time per stage (s since boot) =="
for p in ro.boottime.init ro.boottime.init.first_stage ro.boottime.init.selinux ro.boottime.init.cold_boot_wait; do echo "  $p=$(getprop $p)"; done
getprop | grep -E "ro.boottime.(zygote|surfaceflinger|servicemanager|bootanim)|sys.boot_completed|dev.bootcomplete" | sed "s/^/  /"
echo; echo "== init CPU / crash loops =="
top -b -n 1 -m 6 | head -14
for s in trusty_security_protected_vm_launcher apgetty timberslide hal_desktop_charge_control_default; do echo "  $s: $(getprop init.svc.$s)"; done
echo; echo "== slowest service starts =="
getprop | grep -E "ro.boottime\." | sed "s/\[ro.boottime.//; s/\]: \[/ /; s/\]//" | sort -k2 -n | tail -12
echo; echo "== locked / verified state =="
getprop | grep -iE "vbmeta.digest|veritymode|verifiedboot|flash.locked|vbmeta.device_state"
'
