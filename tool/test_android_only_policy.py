"""Repository policy tests: Moru ships only Android arm64-v8a.

These source guards complement (not replace) verification of the built APK.
Run with: python3 -m unittest discover -s tool -p 'test_android_only_policy.py' -v
"""
from pathlib import Path
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


class AndroidOnlyPolicyTest(unittest.TestCase):
    def test_non_android_native_projects_are_not_tracked(self):
        # flutter pub get regenerates plugin registrants in these folders, so
        # check what git tracks rather than what exists on disk.
        tracked = subprocess.run(
            ['git', 'ls-files', '--', 'ios', 'macos', 'windows', 'linux', 'web'],
            cwd=ROOT, capture_output=True, text=True, check=True,
        ).stdout.split()
        self.assertEqual(tracked, [])

    def test_on_device_llm_is_not_packaged(self):
        gradle = (ROOT / 'android/app/build.gradle.kts').read_text()
        manifest = (ROOT / 'android/app/src/main/AndroidManifest.xml').read_text()
        application = (ROOT / 'android/app/src/main/kotlin/com/psyche/kelivo/KelivoApplication.kt').read_text()
        self.assertNotIn('litertlm-android', gradle)
        self.assertNotIn('LiteRtPlugin', application)
        self.assertNotIn('libOpenCL.so', manifest)
        self.assertFalse((ROOT / 'android/app/src/main/kotlin/com/psyche/kelivo/litert').exists())

    def test_gradle_has_only_arm64_native_targets(self):
        source = (ROOT / 'android/app/build.gradle.kts').read_text()
        self.assertNotRegex(source, r'armeabi-v7a|x86_64')
        self.assertRegex(source, r'ndk\s*\{\s*abiFilters\.clear\(\)')
        self.assertRegex(source, r'abiFilters\s*\+=\s*listOf\("arm64-v8a"\)')
        required = re.search(r'val requiredProotLibs = listOf\((.*?)\n\)', source, re.S)
        self.assertIsNotNone(required)
        paths = re.findall(r'"([^"]+)"', required.group(1))
        self.assertEqual(len(paths), 4)
        self.assertTrue(all(p.startswith('arm64-v8a/') for p in paths))

    def test_proot_fetches_only_android_arm64(self):
        source = (ROOT / 'tool/fetch_proot.sh').read_text()
        abis = re.search(r'^ABIS=\((.*?)\)', source, re.S | re.M)
        self.assertIsNotNone(abis)
        self.assertEqual(re.findall(r'"([^"]+)"', abis.group(1)), ['aarch64:arm64-v8a'])

    def test_proot_checksums_remain_pinned_for_all_required_arm64_files(self):
        lines = [line.split() for line in (ROOT / 'tool/proot_checksums.txt').read_text().splitlines()
                 if line.strip() and not line.startswith('#')]
        self.assertEqual(len(lines), 4)
        expected = {'libproot_exec.so', 'libproot_loader.so', 'libtalloc.so', 'libandroid-shmem.so'}
        self.assertEqual({Path(parts[1]).name for parts in lines}, expected)
        for digest, path in lines:
            self.assertRegex(digest, r'^[0-9a-f]{64}$')
            self.assertIn('/jniLibs/arm64-v8a/', path)

    def test_no_non_android_or_nightly_workflows(self):
        forbidden = re.compile(
            r'flutter\s+build\s+(?:linux|windows|macos|ios|ipa|web)\b|'
            r'\bbuild_(?:ios|mac|macos|windows|linux)\s*:|'
            r'runs-on:\s*(?:macos|windows)[^\n]*|'
            r'^\s+schedule\s*:', re.M)
        workflows = list((ROOT / '.github/workflows').glob('*.yml')) + list((ROOT / '.github/workflows').glob('*.yaml'))
        self.assertTrue(workflows)
        problems = []
        for path in workflows:
            content = path.read_text()
            hits = forbidden.findall(content)
            if hits:
                problems.append(f'{path.name}: {hits[:4]}')
        self.assertEqual(problems, [], '\n'.join(problems))


if __name__ == '__main__':
    unittest.main()
