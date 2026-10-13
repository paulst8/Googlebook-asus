"""Exercise the diagnostic writer on a regular file; never access disks."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class PhoneCaptureTests(unittest.TestCase):
    def test_padded_slots_and_reader(self):
        with tempfile.TemporaryDirectory() as folder:
            work = Path(folder)
            bin_dir = work / 'bin'
            bin_dir.mkdir()
            for name in ('sleep', 'getprop', 'timeout'):
                tool = bin_dir / name
                tool.write_text('#!/bin/sh\nexit 0\n')
                tool.chmod(0o755)
            # Reject the GNU-only option even though the test host supports it.
            dd = bin_dir / 'dd'
            dd.write_text('#!/bin/sh\ncase "$*" in *fullblock*) exit 99;; esac\nexec /usr/bin/dd "$@"\n')
            dd.chmod(0o755)
            capture = work / 'capture'
            snapshot = work / 'snapshot'
            script = (ROOT / 'scripts/lib/bm-phone-debug.sh').read_text()
            script = script.replace('/data/local/tmp/bm-phone-snapshot.txt', str(snapshot))
            script = script.replace('/dev/block/by-name/gblog', str(capture))
            env = dict(os.environ, PATH=str(bin_dir) + ':' + os.environ['PATH'])
            subprocess.run(['sh', '-c', script], env=env, check=True,
                           capture_output=True, timeout=30)
            self.assertEqual(capture.stat().st_size, 32 * 1048576)
            self.assertFalse(snapshot.exists())
            with capture.open('rb') as stream:
                for slot in range(32):
                    block = stream.read(1048576)
                    self.assertTrue(block.startswith(f'GBOS_PHONE_DEBUG_V1\nsnapshot={slot}\n'.encode()))
                    self.assertIn(b'GBOS_PHONE_SNAPSHOT_END', block)
                    self.assertEqual(block[-1], 0)
            reader = (ROOT / 'scripts/bm-phone-log.sh').read_text().split("<<'PY'\n", 1)[1].rsplit('\nPY', 1)[0]
            result = subprocess.run(['python3', '-c', reader, str(capture)],
                                    check=True, capture_output=True)
            self.assertEqual(result.stdout.count(b'GBOS_PHONE_DEBUG_V1'), 32)
