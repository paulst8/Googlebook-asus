#!/bin/bash
# Read bounded phone diagnostics only from the configured Ubuntu SSD.
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
GBOS=${GBOS:-$(dirname "$HERE")}
source "$GBOS/bm.conf"
source "$HERE/lib/bm-safety.sh"
DEV=$(bm_disk_by_serial "$SSD_SERIAL")
bm_require_ubuntu_disk "$DEV"
N=$(bm_partition_number "$DEV" gblog)
python3 - "${DEV}p$N" <<'PY'
import sys
with open(sys.argv[1], 'rb', buffering=0) as stream:
    boot_id = None
    for slot in range(32):
        block = stream.read(1048576).rstrip(b'\0')
        lines = block.splitlines()
        if len(lines) < 4 or lines[0] != b'GBOS_PHONE_DEBUG_V1':
            if slot == 0:
                sys.exit('No phone diagnostic capture found. The diagnostic build may not have booted, or its logger failed. Check work/phone-debug-build.log and the logger before rebuilding.')
            break
        if slot == 0:
            boot_id = lines[3]
        if lines[1] != f'snapshot={slot}'.encode() or lines[3] != boot_id:
            break  # Ignore remaining slots from an older boot.
        sys.stdout.buffer.write(block + b'\n')
PY
