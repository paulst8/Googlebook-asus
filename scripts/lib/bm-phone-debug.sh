#!/system/bin/sh
# Android-only, opt-in diagnostic capture. No changes to pairing or security.
# Each slot is padded, so old bytes cannot be mistaken for this snapshot.
snapshot=/data/local/tmp/bm-phone-snapshot.txt
umask 077
trap 'rm -f "$snapshot"' EXIT
slot=0
while [ "$slot" -lt 32 ]; do
    {
        echo GBOS_PHONE_DEBUG_V1
        echo "snapshot=$slot"
        date
        cat /proc/sys/kernel/random/boot_id
        getprop | grep -iE 'init.svc.*(wifi|bluetooth|keymint|keystore|gsc|trusty|attestation|virtualization)|ro.build.(fingerprint|version)|ro.boot.(verifiedbootstate|vbmeta.device_state)|sys.boot_completed'
        timeout 5 dumpsys package com.google.android.gms | grep -E 'versionName=|versionCode=|enabled=|stopped='
        timeout 5 pm list packages | grep -iE 'crossdevice|companion|continuity|nearby|streaming'
        timeout 5 cmd wifi status
        timeout 5 settings get global bluetooth_on
        timeout 5 service list | grep -iE 'companion|wifi|bluetooth|keystore|keymint'
        echo '--- filtered Android log ---'
        timeout 8 logcat -d -b all -v threadtime -t 6000 2>&1 | grep -aiE 'cross.?device|continuity|continue.?on|cast.?my|companion|nearby|d2d|ditto|rambler|streaming|mdns|nsdmanager|p2p|handshake|attest|keymint|keystore|strongbox|ssl|tls|certificate|avc:.*denied|SecurityException|FATAL EXCEPTION'
        echo '--- filtered kernel log ---'
        timeout 5 dmesg 2>&1 | grep -aiE 'iwl|firmware|bluetooth|avc:.*denied' | tail -c 60000
        echo GBOS_PHONE_SNAPSHOT_END
    } 2>&1 | head -c 1048576 > "$snapshot"
    # Android toybox dd has no iflag=fullblock. A regular input file avoids
    # short pipe reads while keeping fixed-size, zero-padded slots.
    dd if="$snapshot" of=/dev/block/by-name/gblog bs=1048576 count=1 seek="$slot" conv=sync,notrunc,fsync || exit 1
    slot=$((slot + 1))
    sleep 30
done
