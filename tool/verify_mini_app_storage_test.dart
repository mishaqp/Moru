import 'dart:io';

import 'package:Kelivo/core/services/mini_apps/mini_app_browser_storage_script.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Uses an external Chromium/Playwright installation; no runtime dependency
/// or new application target. See verify_mini_app_examples_test.dart.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'browser storage migrates and survives renderer/process restart',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'mini-app-storage-js-',
      );
      try {
        final script = File(p.join(temp.path, 'migration.js'));
        await script.writeAsString(miniAppBrowserStorageScript);
        final result = await Process.run(
          'node',
          ['tool/verify_mini_app_storage.mjs'],
          environment: {'MORU_STORAGE_SCRIPT_PATH': script.path},
        );
        // ignore: avoid_print
        print(result.stdout);
        expect(
          result.exitCode,
          0,
          reason: '${result.stderr}\n${result.stdout}',
        );
      } finally {
        await temp.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
