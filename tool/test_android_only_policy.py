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

    def test_removed_desktop_packages_do_not_return(self):
        # Upstream Kelivo merges re-add these; the desktop shell that used them
        # is gone, so they only add weight and plugin registrations.
        pubspec = (ROOT / 'pubspec.yaml').read_text()
        for package in ('bitsdojo_window', 'screen_retriever', 'tray_manager',
                        'hotkey_manager', 'reorderable_grid_view', 'system_fonts',
                        'window_manager', 'desktop_drop', 'sherpa_onnx_ios',
                        'sherpa_onnx_linux', 'sherpa_onnx_macos', 'sherpa_onnx_windows'):
            self.assertIsNone(re.search(rf'(?m)^\s+{package}\s*:', pubspec), package)
        tracked = subprocess.run(
            ['git', 'ls-files', '--', 'dependencies/tray_manager',
             'dependencies/flutter-permission-handler', 'lib/core/providers/hotkey_provider.dart'],
            cwd=ROOT, capture_output=True, text=True, check=True,
        ).stdout.split()
        self.assertEqual(tracked, [])

    def test_desktop_dart_code_only_shrinks(self):
        # lib/desktop is gone: its live pieces moved to lib/shared and the
        # features that use them. Any file here is desktop code brought back
        # by a merge: delete it.
        tracked = subprocess.run(
            ['git', 'ls-files', '--', 'lib/desktop'],
            cwd=ROOT, capture_output=True, text=True, check=True,
        ).stdout.split()
        self.assertEqual(tracked, [])

    def test_android_ui_has_no_desktop_flag(self):
        # Width-based Android layouts use isWide; platform-only branches must
        # not return when shared upstream UI is merged.
        problems = []
        for path in [p for folder in ('lib', 'test', 'integration_test')
                     for p in (ROOT / folder).rglob('*.dart')]:
            for number, line in enumerate(path.read_text().splitlines(), 1):
                if 'isDesktop' in line:
                    problems.append(f'{path.relative_to(ROOT)}:{number}')
        self.assertEqual(problems, [], '\n'.join(problems))

    def test_no_non_android_platform_branches(self):
        # These fixtures launch POSIX host processes to verify Android shell,
        # cancellation and STDIO MCP behavior on the Linux CI runner.
        linux_host_fixtures = {
            'test/core/services/acp/acp_agent_manager_test.dart',
            'test/core/services/workspace/workspace_tools_service_test.dart',
            'test/core/services/workspace/generation_cancellation_test.dart',
            'test/core/services/mcp/workspace_stdio_transport_test.dart',
            'test/support/fake_workspace_runtime.dart',
            'test/support/fake_workspace_runtime_test.dart',
        }
        forbidden = re.compile(
            r'Platform\.is(?:MacOS|Windows|Linux|IOS)\b|'
            r'TargetPlatform\.(?:iOS|macOS|windows|linux|fuchsia)\b|'
            r'TargetPlatformVariant\.(?:mobile|desktop|all)\b|'
            r'\b(?:window_manager|desktop_drop)\b')
        problems = []
        for folder in ('lib', 'test', 'integration_test'):
            for path in (ROOT / folder).rglob('*.dart'):
                relative = path.relative_to(ROOT).as_posix()
                for number, line in enumerate(path.read_text().splitlines(), 1):
                    for hit in forbidden.findall(line):
                        if hit == 'Platform.isLinux' and relative in linux_host_fixtures:
                            continue
                        problems.append(f'{relative}:{number}: {hit}')
        self.assertEqual(problems, [], '\n'.join(problems))

    def test_no_apple_native_notification_or_filesystem_code(self):
        forbidden = re.compile(
            r'\b(?:DarwinInitializationSettings|DarwinNotificationDetails|'
            r'_isApple|_fFullFsync|IOSUiSettings)\b|Apple Color Emoji|Segoe UI Emoji')
        problems = []
        for path in (ROOT / 'lib').rglob('*.dart'):
            if forbidden.search(path.read_text()):
                problems.append(path.relative_to(ROOT).as_posix())
        self.assertEqual(problems, [], '\n'.join(problems))

    def test_unused_platform_widgets_do_not_return(self):
        forbidden_by_file = {
            'lib/features/home/services/file_upload_service.dart':
                r'\bonFilesDroppedDesktop\b',
            'lib/features/home/controllers/home_page_controller.dart':
                r'\b(?:onFilesDroppedDesktop|isDragHovering|setDragHovering)\b',
            'lib/core/providers/update_provider.dart':
                r"downloads\['ios'\]",
            'lib/features/chat/widgets/message_export_sheet.dart':
                r'\b(?:_ExportDialog|_BatchExportDialog)\b',
            'lib/features/chat/widgets/image_preview_sheet.dart':
                r'\b_DesktopIconButton\b',
            'lib/features/settings/widgets/voice_service_widgets.dart':
                r'\b(?:desktop|VoiceServiceSelectRow)\b',
        }
        for relative in (
            'lib/features/workspace/widgets/preview/preview_actions.dart',
            'lib/features/workspace/widgets/preview/file_preview.dart',
            'lib/features/workspace/widgets/preview/binary_file_preview.dart',
        ):
            forbidden_by_file[relative] = r'\b(?:revealPreviewFileInFileManager|revealInFileManagerLabel)\b'
        for path in (ROOT / 'lib/features/settings/widgets').glob('asr*.dart'):
            forbidden_by_file[path.relative_to(ROOT).as_posix()] = r'\bdesktop\b|\b_buildDesktop\b'
        for relative, pattern in forbidden_by_file.items():
            with self.subTest(path=relative):
                self.assertNotRegex((ROOT / relative).read_text(), pattern)

    def test_no_desktop_backup_or_oauth_fallback(self):
        # Android uses its native document picker for these backups and its
        # native OAuth browser session, including explicit loopback redirects.
        for relative in (
            'lib/features/backup/pages/backup_page.dart',
            'lib/features/backup/pages/local_snapshots_page.dart',
        ):
            with self.subTest(path=relative):
                self.assertNotRegex((ROOT / relative).read_text(),
                                    r'FilePicker\.platform\.saveFile')
        migration = (ROOT / 'lib/features/migration/hive_to_sqlite_migration_page.dart').read_text()
        self.assertNotRegex(migration, r'\b(?:_createDesktopBackup|FilePicker|_usesMobileBackupFlow)\b')
        oauth = (ROOT / 'lib/core/services/auth/oauth_callback_io.dart').read_text()
        self.assertNotRegex(oauth, r'Platform\.isAndroid|OAuthCallback\? mobileCallback|_callbackPage\(')

    def test_non_android_native_test_sources_do_not_return(self):
        tests = ROOT / 'test/native'
        self.assertEqual([p.name for p in tests.glob('*')
                          if p.name.startswith(('ios_', 'desktop_'))], [])

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
