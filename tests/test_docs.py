"""Keep copyable setup instructions connected to real repository resources."""
from pathlib import Path
import re
import unittest
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1]
DOCS = list(ROOT.glob('*.md')) + list((ROOT / 'docs').rglob('*.md'))


def anchors(path):
    result = set()
    for title in re.findall(r'^#{1,6}\s+(.+)$', path.read_text(), re.M):
        title = re.sub(r'[^\w\- ]', '', title.lower())
        result.add(title.replace(' ', '-'))
    return result


class DocumentationTests(unittest.TestCase):
    def test_referenced_scripts_exist(self):
        for doc in DOCS:
            for name in re.findall(r'(?<![\w/])(scripts/[\w/.-]+\.(?:sh|py))\b', doc.read_text()):
                with self.subTest(document=doc.name, script=name):
                    self.assertTrue((ROOT / name).is_file(), f'Nonexistent script: {name}')

    def test_local_links_and_anchors_resolve(self):
        for doc in DOCS:
            for target in re.findall(r'\]\(([^)\s]+)\)', doc.read_text()):
                url = urlsplit(target)
                if url.scheme or url.netloc:
                    continue
                path = (doc.parent / unquote(url.path)).resolve() if url.path else doc
                with self.subTest(document=doc.name, link=target):
                    self.assertTrue(path.exists(), f'Broken local link: {target}')
                    if url.fragment and path.suffix == '.md' and path.exists():
                        self.assertIn(unquote(url.fragment), anchors(path))

    def test_documented_checksums_match_unpackers(self):
        setup = (ROOT / 'docs/SETUP.md').read_text()
        for script, width in [('scripts/bm-prepare.sh', 32), ('scripts/lib/unpack_cf_x86.py', 64)]:
            source = (ROOT / script).read_text()
            hashes = re.findall(rf"['\"]([a-f0-9]{{{width}}})['\"]", source)
            self.assertTrue(hashes)
            self.assertIn(hashes[0], setup)


if __name__ == '__main__':
    unittest.main()
