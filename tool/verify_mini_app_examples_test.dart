import 'dart:convert';
import 'dart:io';

import 'package:Kelivo/core/services/mini_apps/mini_app_bridge.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_guide.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_store.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_web_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// CI/development browser verification, never an additional application target.
/// Install playwright-core outside the repository, then run:
/// MORU_PLAYWRIGHT_CORE=/tmp/browser/node_modules/playwright-core \
/// flutter test tool/verify_mini_app_examples_test.dart
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'real offline examples and shared libraries execute through the HTTP bridge',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'moru-browser-examples-',
      );
      final store = MiniAppStore(
        root: () async => Directory(p.join(temp.path, 'installed')),
      );
      final bridges = <String, MiniAppBridge>{};
      final server = MiniAppWebServer(
        store: store,
        bridgeFor: (app) => bridges.putIfAbsent(
          app.id,
          () => MiniAppBridge(store: store, appId: app.id),
        ),
        pageBootstrap: () => MiniAppBridge.themeScript({
          'dark': false,
          'colors': {'accent': '#1b7b6b', 'on-accent': '#ffffff'},
          'insets': {'top': 8, 'bottom': 12, 'left': 0, 'right': 0},
        }),
      );
      try {
        final appIds = <String, String>{};
        for (final example in MiniAppGuide.examples) {
          final name = example['id']!;
          final project = await MiniAppGuide.read({'example': name});
          final source = Directory(p.join(temp.path, name));
          for (final file in (project['files'] as Map).entries) {
            final target = File(p.join(source.path, file.key as String));
            await target.parent.create(recursive: true);
            await target.writeAsString(file.value as String);
          }
          appIds[name] = (await store.install(source)).app.id;
        }
        await server.start(port: 0, localhostOnly: true);
        final result = await Process.run(
          'node',
          ['tool/verify_mini_app_examples.mjs'],
          environment: {
            'MORU_EXAMPLE_URLS': jsonEncode({
              for (final entry in appIds.entries)
                entry.key:
                    'http://127.0.0.1:${server.port}/app/${entry.value}/index.html',
            }),
            'MORU_DARK_THEME': MiniAppBridge.themeScript({
              'dark': true,
              'colors': {'accent': '#89d8c5', 'on-accent': '#00382d'},
              'insets': {'top': 4, 'bottom': 6, 'left': 0, 'right': 0},
            }),
          },
        );
        // ignore: avoid_print
        print(result.stdout);
        expect(
          result.exitCode,
          0,
          reason: '${result.stderr}\n${result.stdout}',
        );
        for (final entry in bridges.entries) {
          expect(entry.value.pageErrors, isEmpty, reason: entry.key);
          expect(entry.value.failedCalls, isEmpty, reason: entry.key);
        }
      } finally {
        await server.stop();
        store.dispose();
        await temp.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
