#!/usr/bin/env python3
"""GPT helper for bm-usb.sh.  Reads only; never writes.
  bm_gpt.py plan   <image>            print the partition table of <image> as TSV: idx start end typeGUID uniqueGUID name
  bm_gpt.py verify <image> <plan.tsv> check <image>'s table contains every row of plan.tsv exactly
  bm_gpt.py last   <image>            print the first free sector after the last partition
"""
import struct, sys, uuid, zlib

def read_table(path):
    with open(path, 'rb') as f:
        f.seek(512); h = f.read(512)
        assert h[:8] == b'EFI PART', 'no GPT found in ' + path
        hs, saved = struct.unpack_from('<II', h, 12)
        assert zlib.crc32(h[:16] + b'\0' * 4 + h[20:hs]) == saved, 'GPT header CRC mismatch'
        el, n, es = struct.unpack_from('<QII', h, 72)
        f.seek(el * 512); ent = f.read(n * es)
    rows = []
    for i in range(n):
        e = ent[i * es:(i + 1) * es]
        if not any(e[:16]):
            continue
        a, b = struct.unpack_from('<QQ', e, 32)
        rows.append((i + 1, a, b, str(uuid.UUID(bytes_le=e[0:16])), str(uuid.UUID(bytes_le=e[16:32])),
                     e[56:128].decode('utf-16le').rstrip('\0')))
    return rows

cmd, path = sys.argv[1], sys.argv[2]
rows = read_table(path)
if cmd == 'plan':
    for r in rows:
        print('\t'.join(str(x) for x in r))
elif cmd == 'last':
    print(max(r[2] for r in rows) + 1)
elif cmd == 'verify':
    have = {r[0]: r for r in rows}
    bad = 0
    for line in open(sys.argv[3]):
        p = line.rstrip('\n').split('\t')
        if len(p) < 6: continue
        i = int(p[0]); r = have.get(i)
        if not r or (r[1], r[2], r[3], r[5]) != (int(p[1]), int(p[2]), p[3], p[5]):
            print('MISMATCH partition', i, p[5], 'want', p[1:3], 'have', r and r[1:3]); bad += 1
    sys.exit(1 if bad else 0)
