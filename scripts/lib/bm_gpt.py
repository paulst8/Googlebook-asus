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
        if len(h) != 512 or h[:8] != b'EFI PART':
            raise ValueError('no complete 512-byte-sector GPT found in ' + str(path))
        hs, saved = struct.unpack_from('<II', h, 12)
        if not 92 <= hs <= 512:
            raise ValueError('invalid GPT header size')
        if zlib.crc32(h[:16] + b'\0' * 4 + h[20:hs]) != saved:
            raise ValueError('GPT header CRC mismatch')
        first, last = struct.unpack_from('<QQ', h, 40)
        el, n, es, crc = struct.unpack_from('<QIII', h, 72)
        if not (2 <= el < first and 0 < n <= 4096 and es >= 128
                and es % 128 == 0 and n * es <= 16 * 1024 * 1024
                and el * 512 + n * es <= first * 512 and first <= last):
            raise ValueError('invalid GPT entry geometry')
        f.seek(el * 512); ent = f.read(n * es)
        if len(ent) != n * es or zlib.crc32(ent) != crc:
            raise ValueError('GPT partition entry CRC mismatch or truncated table')
    rows = []
    for i in range(n):
        e = ent[i * es:(i + 1) * es]
        if not any(e[:16]):
            continue
        a, b = struct.unpack_from('<QQ', e, 32)
        name = e[56:128].decode('utf-16le').rstrip('\0')
        if not first <= a <= b <= last:
            raise ValueError('partition outside GPT usable range')
        if any(c in name for c in '\0\t\r\n: '):
            raise ValueError('partition name cannot be represented safely in install plan')
        rows.append((i + 1, a, b, str(uuid.UUID(bytes_le=e[0:16])),
                     str(uuid.UUID(bytes_le=e[16:32])), name))
    ordered = sorted(rows, key=lambda r: r[1])
    if any(a[2] >= b[1] for a, b in zip(ordered, ordered[1:])):
        raise ValueError('overlapping GPT partitions')
    if len({r[5] for r in rows}) != len(rows):
        raise ValueError('duplicate partition names')
    return rows

def main():
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

if __name__ == "__main__":
    main()
