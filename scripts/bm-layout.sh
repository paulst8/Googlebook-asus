#!/bin/bash
# Read-only partition report for the configured Ubuntu SSD, identified by serial.
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
GBOS=${GBOS:-$(dirname "$HERE")}
[ -f "$GBOS/bm.conf" ] || { echo "Run bm-configure.sh first" >&2; exit 1; }
source "$GBOS/bm.conf"
source "$HERE/lib/bm-safety.sh"
DEV=$(bm_disk_by_serial "${SSD_SERIAL:-}")
bm_require_ubuntu_disk "$DEV"
echo "Ubuntu SSD serial: $SSD_SERIAL" >&2
parted -m -s "$DEV" unit s print free
