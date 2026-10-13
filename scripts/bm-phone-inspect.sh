#!/bin/bash
# Read-only inspection from an ADB host while Googlebook is running.
# Select the Googlebook explicitly, never an attached phone by default.
set -euo pipefail
command -v adb >/dev/null || { echo 'Install adb on the diagnostic host first.' >&2; exit 1; }
: "${ADB_SERIAL:?Set ADB_SERIAL to the connected Googlebook shown by adb devices}"
ADB=(adb -s "$ADB_SERIAL")
[ "$("${ADB[@]}" get-state)" = device ] || exit 1
"${ADB[@]}" shell '
echo "=== Build and foreground user ==="
getprop ro.build.fingerprint
am get-current-user
pm list users
echo "=== Package to UID mapping ==="
pm list packages -U | grep -E "10209|ambient.streaming|google.android.gms|rkpd"
for package in com.google.ambient.streaming com.google.android.gms; do
    echo "=== Package: $package ==="
    dumpsys package "$package"
done
echo "=== Casting app process logs ==="
for pid in $(pidof com.google.ambient.streaming); do
    logcat -d -b main -b system -b crash --pid="$pid" -t 3000
done
echo "=== Related process identities ==="
ps -A | grep -iE "attest|rkpd|keymint|streaming|google.android.gms|trusty"
echo "=== Companion service state ==="
dumpsys companiondevice
'
