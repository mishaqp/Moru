"""Release metadata gates; APK cryptography is verified separately by apksigner."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from prepare_release import prepare_release


class PrepareReleaseTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.apk_dir = self.root / 'out'
        self.reports = self.root / 'verification' / 'reports'
        self.destination = self.root / 'dist'
        self.apk_dir.mkdir()
        self.reports.mkdir(parents=True)
        (self.root / '.github').mkdir()
        (self.root / 'pubspec.yaml').write_text('version: 0.1.1+2\n')
        self.pin = 'c5db7faec00b149db9406af2a714c963f9e6ad1632905e8237d04104f46182db'
        (self.root / '.github/moru-signing-cert-sha256.txt').write_text(self.pin + '\n')
        self.apk = self.apk_dir / 'Moru-arm64-v8a-release.apk'
        self.apk.write_bytes(b'synthetic APK fixture, not an installable application')
        self.digest = hashlib.sha256(self.apk.read_bytes()).hexdigest()
        (self.reports / 'apk.sha256').write_text(f'{self.digest}  out/{self.apk.name}\n')
        (self.reports / 'signature.txt').write_text(
            f'Verifies\nSigner #1 certificate SHA-256 digest: {self.pin}\n')
        self.badging = (
            "package: name='com.mishaqp.moru' versionCode='2' versionName='0.1.1'\n"
            "application-label:'Moru'\nnative-code: 'arm64-v8a'\n")
        (self.reports / 'badging.txt').write_text(self.badging)
        self.commit = 'a' * 40

    def prepare(self):
        return prepare_release(self.root, self.apk_dir, self.reports.parent,
                               self.destination, self.commit)

    def test_copies_exactly_one_apk_and_records_real_hash_size_and_identity(self):
        result = self.prepare()
        target = self.destination / 'Moru-v0.1.1-arm64-v8a-release.apk'
        self.assertEqual(target.read_bytes(), self.apk.read_bytes())
        self.assertEqual(list(self.destination.glob('*.apk')), [target])
        self.assertEqual(result['sha256'], self.digest)
        self.assertEqual(result['size_bytes'], self.apk.stat().st_size)
        self.assertEqual(result['certificate_sha256'], self.pin)
        self.assertEqual(result['commit'], self.commit)
        self.assertEqual(result['version_code'], 2)
        self.assertEqual(json.loads((self.destination / 'release-metadata.json').read_text()), result)
        self.assertEqual((self.destination / f'{target.name}.sha256').read_text(),
                         f'{self.digest}  {target.name}\n')

    def test_accepts_v2_signer_format_from_the_previous_release(self):
        (self.reports / 'signature.txt').write_text(
            'Verifies\n'
            'Verified using v2 scheme (APK Signature Scheme v2): true\n'
            'Number of signers: 1\n'
            f'V2 Signer: certificate SHA-256 digest: {self.pin}\n')
        self.assertEqual(self.prepare()['certificate_sha256'], self.pin)

    def test_rejects_multiple_signing_certificates(self):
        (self.reports / 'signature.txt').write_text(
            f'Verifies\nSigner #1 certificate SHA-256 digest: {self.pin}\n'
            'Signer #2 certificate SHA-256 digest: ' + 'b' * 64 + '\n')
        with self.assertRaisesRegex(ValueError, 'certificate'):
            self.prepare()

    def test_rejects_modified_apk(self):
        self.apk.write_bytes(b'tampered')
        with self.assertRaisesRegex(ValueError, 'checksum'):
            self.prepare()
        self.assertFalse(self.destination.exists())

    def test_rejects_second_apk(self):
        (self.apk_dir / 'extra.apk').write_bytes(b'extra')
        with self.assertRaisesRegex(ValueError, 'exactly one'):
            self.prepare()

    def test_rejects_wrong_certificate(self):
        (self.reports / 'signature.txt').write_text(
            'Verifies\nSigner #1 certificate SHA-256 digest: ' + 'b' * 64 + '\n')
        with self.assertRaisesRegex(ValueError, 'certificate'):
            self.prepare()

    def test_rejects_wrong_package_version_abi_label_and_debuggable(self):
        for badging in [
            self.badging.replace('com.mishaqp.moru', 'com.psyche.kelivo'),
            self.badging.replace("versionCode='2'", "versionCode='1'"),
            self.badging.replace("versionName='0.1.1'", "versionName='0.1.0'"),
            self.badging.replace("'arm64-v8a'", "'arm64-v8a' 'x86_64'"),
            self.badging.replace("application-label:'Moru'", "application-label:'Kelivo'"),
            self.badging + 'application-debuggable\n',
        ]:
            with self.subTest(badging=badging):
                (self.reports / 'badging.txt').write_text(badging)
                with self.assertRaises(ValueError):
                    self.prepare()
                self.assertFalse(self.destination.exists())

    def test_rejects_ambiguous_reports(self):
        (self.reports.parent / 'badging.txt').write_text(self.badging)
        with self.assertRaisesRegex(ValueError, 'exactly one'):
            self.prepare()

    def test_rejects_invalid_version_and_commit(self):
        (self.root / 'pubspec.yaml').write_text('version: bad\n')
        with self.assertRaises(ValueError):
            self.prepare()
        (self.root / 'pubspec.yaml').write_text('version: 0.1.1+2\n')
        self.commit = 'master'
        with self.assertRaises(ValueError):
            self.prepare()


if __name__ == '__main__':
    unittest.main()
