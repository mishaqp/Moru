import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:Kelivo/core/services/mini_apps/mini_app_servers.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_store.dart';
import 'package:Kelivo/features/mini_apps/mini_app_checker.dart';

void main() {
  late Directory temp;
  late MiniAppStore store;
  late MiniApp app;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mini-app-native-check-');
    store = MiniAppStore(
      root: () async => Directory(p.join(temp.path, 'apps')),
    );
    final source = Directory(p.join(temp.path, 'source'))..createSync();
    File(p.join(source.path, 'moru-app.json')).writeAsStringSync(
      jsonEncode({
        'id': 'native-panel',
        'name': 'Native panel',
        'formatVersion': 2,
        'ui': {'engine': 'native', 'entry': 'screen.json'},
      }),
    );
    File(p.join(source.path, 'screen.json')).writeAsStringSync(
      jsonEncode({
        'version': 1,
        'components': [
          {'type': 'text', 'text': 'Native panel'},
        ],
      }),
    );
    app = (await store.install(source)).app;
  });
  tearDown(() => temp.delete(recursive: true));

  test(
    'native publish check validates JSON without WebView or a Linux runtime',
    () async {
      var runtimeLookups = 0;
      final report = await MiniAppChecker.run(
        app,
        serverEnvironment: MiniAppServerEnvironment(
          runtime: () async {
            runtimeLookups++;
            throw StateError('unexpected Linux startup');
          },
          variables: () async => {},
        ),
      );
      expect(report.ok, isTrue);
      expect(report.loaded, isTrue);
      expect(report.server, isNull);
      expect(report.scheduledJobs, isEmpty);
      expect(runtimeLookups, 0);
    },
  );

  test(
    'a malformed native screen is reported without hidden execution',
    () async {
      await File(app.entryPath).writeAsString('{invalid');
      final report = await MiniAppChecker.run(app);
      expect(report.ok, isFalse);
      expect(report.loaded, isFalse);
      expect(report.failedCalls.single, contains('screen.json'));
    },
  );
}
