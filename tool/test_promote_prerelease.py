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
        (self.root / '.github').mkdir()
        (self.root / '.github/moru-signing-cert-sha256.txt').write_text('C' * 64 + '\n')
        source = self.root / 'pre'
        source.mkdir()
        self.apk = source / 'Moru-v0.1.1-pre.3-arm64-v8a-release.apk'
        self.apk.write_bytes(b'synthetic APK fixture')
        self.destination = self.root / 'dist'

    def promote(self, tag='v0.1.1-pre.3', tested='b' * 40, commit='a' * 40, apk=None):
        return promote(self.root, apk or self.apk, tag, tested, self.destination, commit)

    def test_publishes_the_same_apk_under_the_stable_tag(self):
        result = self.promote()
        target = self.destination / 'Moru-v0.1.1-arm64-v8a-release.apk'
        digest = hashlib.sha256(self.apk.read_bytes()).hexdigest()
        self.assertEqual(target.read_bytes(), self.apk.read_bytes())
        self.assertEqual(result, {
            'tag': 'v0.1.1', 'prerelease': False, 'version': '0.1.1',
            'version_code': 2, 'package': 'com.mishaqp.moru', 'abi': 'arm64-v8a',
            'commit': 'a' * 40, 'filename': target.name, 'sha256': digest,
            'size_bytes': self.apk.stat().st_size, 'certificate_sha256': 'c' * 64,
            'tested_tag': 'v0.1.1-pre.3', 'tested_commit': 'b' * 40,
        })
        self.assertEqual(json.loads((self.destination / 'release-metadata.json').read_text()), result)
        self.assertEqual((self.destination / f'{target.name}.sha256').read_text(),
                         f'{digest}  {target.name}\n')

    def test_rejects_another_version_or_a_stable_source(self):
        for tag in ['v0.1.0-pre.3', 'v0.1.1', 'v0.1.1-pre.0', 'v0.1.1-pre.3x']:
            with self.subTest(tag=tag):
                with self.assertRaises(ValueError):
                    self.promote(tag=tag)
                self.assertFalse(self.destination.exists())

    def test_rejects_an_apk_of_another_pre_release(self):
        other = self.apk.with_name('Moru-v0.1.1-pre.4-arm64-v8a-release.apk')
        other.write_bytes(b'other')
        with self.assertRaisesRegex(ValueError, 'APK'):
            self.promote(apk=other)

    def test_rejects_invalid_commits(self):
        for kwargs in [{'commit': 'master'}, {'tested': 'HEAD'}]:
            with self.subTest(**kwargs):
                with self.assertRaises(ValueError):
                    self.promote(**kwargs)


if __name__ == '__main__':
    unittest.main()
