"""Maintenance guards must fail before touching boot files or disks."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

class MaintenanceTests(unittest.TestCase):
    def test_finalize_dryrun_preserves_all_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            boot = root / 'boot'; boot.mkdir()
            grub = root / 'grub'; grub.mkdir()
            for file in [boot / 'kernel', boot / 'initrd.img', boot / 'initrd-locked.img', boot / 'recovery-backup', grub / '40_googlebook']:
                file.write_text('preserve this')
            before = {str(p): p.read_bytes() for p in root.rglob('*') if p.is_file()}
            env = dict(os.environ, DRYRUN='1', GB_DIR=str(boot), GRUBD_DIR=str(grub))
            subprocess.run(['bash', str(ROOT / 'scripts/bm-finalize.sh')], env=env, check=True, capture_output=True)
            after = {str(p): p.read_bytes() for p in root.rglob('*') if p.is_file()}
            self.assertEqual(before, after)

    def test_boot_experiment_dryrun_requires_explicit_output(self):
        for script in ['bm-verified.sh', 'bm-locked-test.sh']:
            with self.subTest(script=script), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                (root / 'kernel').write_text('kernel')
                (root / 'initrd.img').write_text('ramdisk')
                env = dict(os.environ, DRYRUN='1', GB_DIR=tmp, GBOS=tmp)
                for key in ['VBMETA_IMG', 'OUT_INITRD']:
                    env.pop(key, None)
                result = subprocess.run(['bash', str(ROOT / 'scripts' / script)], env=env, capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('Dry run requires', result.stdout)
                self.assertEqual(sorted(p.name for p in root.iterdir()), ['initrd.img', 'kernel'])
