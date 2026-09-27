"""Promotion of a tested pre-release to the stable tag, without rebuilding."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from promote_prerelease import promote


class PromotePrereleaseTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'pubspec.yaml').write_text('version: 0.1.1+2\n')
        self.source = self.root / 'pre'
        self.source.mkdir()
        self.apk = self.source / 'Moru-v0.1.1-pre.3-arm64-v8a-release.apk'
        self.apk.write_bytes(b'synthetic APK fixture')
        self.metadata = {
            'tag': 'v0.1.1-pre.3', 'prerelease': True, 'version': '0.1.1',
            'version_code': 2, 'package': 'com.mishaqp.moru', 'abi': 'arm64-v8a',
            'commit': 'b' * 40, 'filename': self.apk.name,
            'sha256': hashlib.sha256(self.apk.read_bytes()).hexdigest(),
            'size_bytes': self.apk.stat().st_size, 'certificate_sha256': 'c' * 64,
        }
        self.write_metadata()
        self.destination = self.root / 'dist'

    def write_metadata(self):
        (self.source / 'release-metadata.json').write_text(json.dumps(self.metadata))

    def promote(self):
        return promote(self.root, self.source, self.destination, 'a' * 40)

    def test_publishes_the_same_apk_under_the_stable_tag(self):
        result = self.promote()
        target = self.destination / 'Moru-v0.1.1-arm64-v8a-release.apk'
        self.assertEqual(target.read_bytes(), self.apk.read_bytes())
        self.assertEqual(result['tag'], 'v0.1.1')
        self.assertFalse(result['prerelease'])
        self.assertEqual(result['commit'], 'a' * 40)
        self.assertEqual(result['tested_commit'], 'b' * 40)
        self.assertEqual(result['tested_tag'], 'v0.1.1-pre.3')
        self.assertEqual(result['sha256'], self.metadata['sha256'])
        self.assertEqual(json.loads((self.destination / 'release-metadata.json').read_text()), result)
        self.assertEqual((self.destination / f'{target.name}.sha256').read_text(),
                         f"{self.metadata['sha256']}  {target.name}\n")

    def test_rejects_modified_apk(self):
        self.apk.write_bytes(b'tampered')
        with self.assertRaisesRegex(ValueError, 'metadata'):
            self.promote()
        self.assertFalse(self.destination.exists())

    def test_rejects_other_version_or_stable_source(self):
        for change in [
            {'version': '0.1.0'},
            {'version_code': 1},
            {'tag': 'v0.1.0-pre.3'},
            {'tag': 'v0.1.1'},
            {'prerelease': False},
        ]:
            with self.subTest(change=change):
                self.metadata.update(change)
                self.write_metadata()
                with self.assertRaises(ValueError):
                    self.promote()
                self.setUp()

    def test_rejects_invalid_commit(self):
        with self.assertRaises(ValueError):
            promote(self.root, self.source, self.destination, 'master')


if __name__ == '__main__':
    unittest.main()
