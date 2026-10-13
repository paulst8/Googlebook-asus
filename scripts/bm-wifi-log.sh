#!/bin/bash
# Read only the bounded Wi-Fi diagnostic snapshot on the configured Ubuntu SSD.
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
GBOS=${GBOS:-$(dirname "$HERE")}
source "$GBOS/bm.conf"
source "$HERE/lib/bm-safety.sh"
DEV=$(bm_disk_by_serial "$SSD_SERIAL")
bm_require_ubuntu_disk "$DEV"
N=$(bm_partition_number "$DEV" gbkmsg)
# The logger writes one padded 1 MiB block. No userdata or other SSD is read.
dd if="${DEV}p$N" bs=1M count=1 status=none | tr -d '\000'
