import 'dart:convert';
import 'dart:io';

import 'package:Kelivo/core/services/mini_apps/mini_app_guide.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_store.dart';
import 'package:Kelivo/features/mini_apps/mini_app_checker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

/// Run on an Android arm64 device with networking disabled:
/// flutter test integration_test/mini_apps/offline_examples_test.dart -d DEVICE
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'every packaged guide example starts in the real Android checker',
    (tester) async {
      expect(
        Platform.isAndroid,
        isTrue,
        reason: 'This is an Android WebView test.',
      );
      await tester.runAsync(() async {
        final temp = await Directory.systemTemp.createTemp(
          'moru-offline-examples-',
        );
        final store = MiniAppStore(
          root: () async => Directory(p.join(temp.path, 'installed')),
        );
        try {
          for (final example in MiniAppGuide.examples) {
            final name = example['id']!;
            final project = await MiniAppGuide.read({'example': name});
            final source = Directory(p.join(temp.path, name));
            for (final file in (project['files'] as Map).entries) {
              final target = File(p.join(source.path, file.key as String));
              await target.parent.create(recursive: true);
              await target.writeAsString(file.value as String);
            }
            final app = (await store.install(source)).app;
            final report = await MiniAppChecker.run(app);
            expect(
              report.loaded,
              isTrue,
              reason: '$name: ${jsonEncode(report.toJson())}',
            );
            expect(report.pageErrors, isEmpty, reason: name);
            expect(report.failedCalls, isEmpty, reason: name);
            expect(
              report.console.where((line) => line.startsWith('error: ')),
              isEmpty,
              reason: name,
            );
            expect(report.visibleContent, greaterThan(0), reason: name);
            expect(
              await store.storageKeys(app.id),
              isEmpty,
              reason: 'Checker must preserve real data.',
            );
            // ignore: avoid_print
            print(
              'MORU_OFFLINE_EXAMPLE:${jsonEncode({'example': name, ...report.toJson()})}',
            );
          }
        } finally {
          store.dispose();
          await temp.delete(recursive: true);
        }
      });
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
