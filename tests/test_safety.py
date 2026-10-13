"""Disk-free regression tests; never open real block devices."""
import hashlib
import importlib.util
import os
from pathlib import Path
import struct
import subprocess
import tempfile
import unittest
import uuid
import zlib

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('bm_gpt', ROOT / 'scripts/lib/bm_gpt.py')
gpt = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gpt)


def image(entries):
    data = bytearray(128 * 128)
    for index, start, end, name in entries:
        off = (index - 1) * 128
        data[off:off+16] = uuid.UUID('0fc63daf-8483-4772-8e79-3d69d8477de4').bytes_le
        data[off+16:off+32] = uuid.uuid4().bytes_le
        struct.pack_into('<QQ', data, off+32, start, end)
        encoded = name.encode('utf-16le')
        data[off+56:off+56+len(encoded)] = encoded
    header = bytearray(512)
    header[:8] = b'EFI PART'
    struct.pack_into('<III', header, 8, 0x10000, 92, 0)
    struct.pack_into('<QQQQ', header, 24, 1, 4095, 34, 4062)
    struct.pack_into('<QIII', header, 72, 2, 128, 128, zlib.crc32(data))
    struct.pack_into('<I', header, 16, zlib.crc32(header[:92]))
    return bytearray(512) + header + data


class GPTTests(unittest.TestCase):
    def read(self, data):
        with tempfile.NamedTemporaryFile() as f:
            f.write(data); f.flush()
            return gpt.read_table(f.name)

    def test_valid(self):
        rows = self.read(image([(1, 34, 100, 'boot_a'), (7, 101, 300, 'userdata')]))
        self.assertEqual([r[0] for r in rows], [1, 7])

    def test_entries_checksum(self):
        data = image([(1, 34, 100, 'boot_a')]); data[1100] ^= 1
        with self.assertRaisesRegex(ValueError, 'entry CRC'):
            self.read(data)

    def test_header_checksum(self):
        data = image([(1, 34, 100, 'boot_a')]); data[550] ^= 1
        with self.assertRaisesRegex(ValueError, 'header CRC'):
            self.read(data)

    def test_truncated(self):
        with self.assertRaisesRegex(ValueError, 'truncated'):
            self.read(image([(1, 34, 100, 'boot_a')])[:-1])

    def test_overlap(self):
        with self.assertRaisesRegex(ValueError, 'overlapping'):
            self.read(image([(1, 34, 100, 'boot_a'), (2, 100, 200, 'userdata')]))

    def test_outside_usable(self):
        with self.assertRaisesRegex(ValueError, 'usable'):
            self.read(image([(1, 20, 100, 'boot_a')]))

    def test_duplicate_names(self):
        with self.assertRaisesRegex(ValueError, 'duplicate'):
            self.read(image([(1, 34, 100, 'boot_a'), (2, 101, 200, 'boot_a')]))

    def test_control_character(self):
        with self.assertRaisesRegex(ValueError, 'safely'):
            self.read(image([(1, 34, 100, 'boot\ta')]))


class TargetTests(unittest.TestCase):
    def shell(self, command, listing='nvme0n1p9 userdata', root='nvme0n1'):
        with tempfile.TemporaryDirectory() as d:
            for name, body in {
                'lsblk': 'case "$*" in *PKNAME*) echo "$TEST_ROOT";; *) printf "%s\\n" "$TEST_LIST";; esac',
                'findmnt': 'echo /dev/nvme0n1p3',
            }.items():
                p = Path(d)/name; p.write_text('#!/bin/bash\n'+body+'\n'); p.chmod(0o755)
            env = dict(os.environ, PATH=d+':'+os.environ['PATH'], TEST_ROOT=root, TEST_LIST=listing)
            return subprocess.run(['bash', '-c', 'source "$1"; '+command, '_', str(ROOT/'scripts/lib/bm-safety.sh')],
                                  env=env, capture_output=True, text=True)

    def test_serial_resolution(self):
        p = self.shell('bm_disk_by_serial UBUNTU', 'nvme7n1 UBUNTU nvme\nnvme0n1 WINDOWS nvme')
        self.assertEqual(p.returncode, 0)
        self.assertEqual(p.stdout.strip(), '/dev/nvme7n1')

    def test_duplicate_serial_refused(self):
        p = self.shell('bm_disk_by_serial UBUNTU', 'nvme7n1 UBUNTU nvme\nnvme0n1 UBUNTU nvme')
        self.assertNotEqual(p.returncode, 0)

    def test_missing_serial_refused(self):
        self.assertNotEqual(self.shell('bm_disk_by_serial UBUNTU', 'nvme0n1 WINDOWS nvme').returncode, 0)

    def test_detect_userdata_not_five(self):
        p = self.shell('bm_partition_number /dev/nvme0n1 userdata')
        self.assertEqual(p.returncode, 0); self.assertEqual(p.stdout.strip(), '9')

    def test_reject_wrong_override(self):
        self.assertNotEqual(self.shell('bm_partition_number /dev/nvme0n1 userdata 5').returncode, 0)

    def test_reject_ambiguous_userdata(self):
        self.assertNotEqual(self.shell('bm_partition_number /dev/nvme0n1 userdata',
                                      'nvme0n1p9 userdata\nnvme0n1p10 userdata').returncode, 0)

    def test_reject_missing_userdata(self):
        self.assertNotEqual(self.shell('bm_partition_number /dev/nvme0n1 userdata', '').returncode, 0)

    def test_reject_windows_disk(self):
        self.assertNotEqual(self.shell('bm_require_ubuntu_disk /dev/nvme1n1').returncode, 0)

    def test_accept_ubuntu_disk(self):
        self.assertEqual(self.shell('bm_require_ubuntu_disk /dev/nvme0n1').returncode, 0)

    def test_reject_indeterminate_root(self):
        self.assertNotEqual(self.shell('bm_require_ubuntu_disk /dev/nvme0n1', root='').returncode, 0)


class DynamicPartitionTests(unittest.TestCase):
    def read_extent(self, kind=0, source=0):
        spec = importlib.util.spec_from_file_location('unpack', ROOT/'scripts/lib/unpack_cf_x86.py')
        module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
        data = bytearray(16384)
        struct.pack_into('<I', data, 4096, 0x616c4467)
        struct.pack_into('<I', data, 4136, 4096)
        table = bytearray(76)
        table[:8] = b'vendor_a'
        struct.pack_into('<IIII', table, 36, 0, 0, 1, 0)
        struct.pack_into('<QIQI', table, 52, 2048, kind, 4096, source)
        meta = bytearray(128)
        struct.pack_into('<I', meta, 0, 0x414c5030)
        struct.pack_into('<I', meta, 8, 128)
        struct.pack_into('<I', meta, 44, len(table))
        meta[48:80] = hashlib.sha256(table).digest()
        struct.pack_into('<III', meta, 80, 0, 1, 52)
        struct.pack_into('<III', meta, 92, 52, 1, 24)
        data[12288:12416] = meta
        data[12416:12492] = table
        with tempfile.NamedTemporaryFile() as f:
            f.write(data); f.flush()
            return module.super_partitions(f.name, True)

    def test_extent_size_and_offset(self):
        self.assertEqual(self.read_extent()['vendor_a'], (4096*512, 2048*512))

    def test_zero_extent_rejected(self):
        with self.assertRaisesRegex(ValueError, 'unsupported'):
            self.read_extent(kind=1)

    def test_other_source_rejected(self):
        with self.assertRaisesRegex(ValueError, 'unsupported'):
            self.read_extent(source=1)


class ConfigureTests(unittest.TestCase):
    def test_usb_free_config(self):
        with tempfile.TemporaryDirectory() as d:
            log = Path(d)/'kernel.txt'; log.write_text('')
            env = dict(os.environ, GBOS=d, SSD_SERIAL='TESTSSD', NO_USB='1',
                       GPU_ID='a7ab', KERNEL_LOG=str(log), FW_GPU='i915:test',
                       FW_WIFI_BASES='iwlwifi-test', FW_BT='ibt-test', FW_ETH='rtl-test')
            p = subprocess.run(['bash', str(ROOT/'scripts/bm-configure.sh')],
                               env=env, input='', capture_output=True, text=True)
            self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
            config = (Path(d)/'bm.conf').read_text()
            self.assertIn('SSD_SERIAL="TESTSSD"', config)
            self.assertIn('STICK_SERIAL=""', config)


class WifiAliasTests(unittest.TestCase):
    def run_aliases(self, directory, base='iwlwifi-gl-c0-fm-c0'):
        return subprocess.run(['bash', '-c', 'source "$1"; bm_wifi_compat_aliases "$2" "$3"',
                               '_', str(ROOT/'scripts/lib/bm-wifi-compat.sh'), directory, base],
                              capture_output=True, text=True)

    def test_alias_preserves_payload(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d); name = 'iwlwifi-gl-c0-fm-c0'
            (p/(name+'-c103.ucode')).write_bytes(b'test fixture')
            self.assertEqual(self.run_aliases(d).returncode, 0)
            for version in [104, 105]:
                link = p/(name+f'-c{version}.ucode')
                self.assertTrue(link.is_symlink())
                self.assertEqual(link.read_bytes(), b'test fixture')
            self.assertEqual(self.run_aliases(d).returncode, 0)

    def test_official_file_not_overwritten(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d); name = 'iwlwifi-gl-c0-fm-c0'
            (p/(name+'-c103.ucode')).write_bytes(b'103 fixture')
            official = p/(name+'-c105.ucode'); official.write_bytes(b'105 fixture')
            self.assertEqual(self.run_aliases(d).returncode, 0)
            self.assertFalse(official.is_symlink())
            self.assertEqual(official.read_bytes(), b'105 fixture')

    def test_missing_payload_refused(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertNotEqual(self.run_aliases(d).returncode, 0)

    def test_wrong_family_refused(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertNotEqual(self.run_aliases(d, '../../incorrect').returncode, 0)


if __name__ == '__main__':
    unittest.main()
