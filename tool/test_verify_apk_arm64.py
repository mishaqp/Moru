from pathlib import Path
import struct
import tempfile
import unittest
import zipfile

from verify_apk_arm64 import REQUIRED, inspect_apk


def elf(machine=183, elf_class=2):
    value = bytearray(64)
    value[:4] = b'\x7fELF'
    value[4:7] = bytes([elf_class, 1, 1])
    struct.pack_into('<H', value, 18, machine)
    return bytes(value)


class ApkArm64VerificationTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / 'fixture.apk'

    def make_apk(self, *, additional=None, omit=(), replace=None):
        items = {'AndroidManifest.xml': b'fixture manifest'}
        items.update({f'lib/arm64-v8a/{name}': elf() for name in REQUIRED if name not in omit})
        items.update(additional or {})
        items.update(replace or {})
        with zipfile.ZipFile(self.path, 'w') as apk:
            for name, content in items.items():
                apk.writestr(name, content)

    def test_actual_arm64_libraries_are_accepted(self):
        self.make_apk()
        result = inspect_apk(self.path)
        self.assertEqual(result['abis'], ['arm64-v8a'])
        self.assertEqual(result['native_libraries'], sorted(REQUIRED))
        self.assertEqual(len(result['sha256']), 64)

    def test_extra_abi_is_rejected_even_with_valid_arm64_files(self):
        self.make_apk(additional={'lib/x86_64/libextra.so': elf(machine=62)})
        with self.assertRaisesRegex(ValueError, 'Expected only arm64-v8a'):
            inspect_apk(self.path)

    def test_mislabeled_x86_library_is_rejected(self):
        self.make_apk(replace={'lib/arm64-v8a/libflutter.so': elf(machine=62)})
        with self.assertRaisesRegex(ValueError, 'Not an AArch64'):
            inspect_apk(self.path)

    def test_32bit_library_is_rejected(self):
        self.make_apk(replace={'lib/arm64-v8a/libflutter.so': elf(elf_class=1)})
        with self.assertRaisesRegex(ValueError, 'Not a 64-bit'):
            inspect_apk(self.path)

    def test_missing_proot_is_rejected(self):
        self.make_apk(omit={'libproot_loader.so'})
        with self.assertRaisesRegex(ValueError, 'Missing Android runtime'):
            inspect_apk(self.path)

    def test_empty_apk_is_rejected(self):
        with zipfile.ZipFile(self.path, 'w'):
            pass
        with self.assertRaisesRegex(ValueError, 'Expected only arm64-v8a'):
            inspect_apk(self.path)


if __name__ == '__main__':
    unittest.main()
