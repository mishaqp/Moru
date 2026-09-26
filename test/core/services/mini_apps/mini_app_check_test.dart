import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:Kelivo/core/services/mini_apps/mini_app_check.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_store.dart';

void main() {
  late Directory temp;
  late MiniAppStore store;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mini-app-check-test-');
    store = MiniAppStore(
      root: () async => Directory(p.join(temp.path, 'installed')),
    );
    final dir = Directory(p.join(temp.path, 'src'))..createSync();
    File(p.join(dir.path, 'moru-app.json')).writeAsStringSync(
      jsonEncode({
        'id': 'water',
        'name': 'Water',
        'permissions': ['calendar'],
      }),
    );
    File(p.join(dir.path, 'index.html')).writeAsStringSync('<p>x</p>');
    await store.install(dir);
    await store.storageSet('water', 'goal', 2000);
  });
  tearDown(() => temp.delete(recursive: true));

  Future<Map<String, dynamic>> call(
    MiniAppSandbox sandbox,
    String method, [
    Map<String, dynamic> args = const {},
  ]) async {
    final script = (await sandbox.bridge.handle(
      jsonEncode({'id': 1, 'method': method, 'args': args}),
    ))!;
    final match = RegExp(
      r'^window\.__moruReply\(1, (true|false), (.*)\);$',
    ).firstMatch(script)!;
    return {'ok': match[1] == 'true', 'value': jsonDecode(match[2]!)};
  }

  test('the sandbox sees the data but never changes the real app', () async {
    final sandbox = await MiniAppSandbox.create(store.byId('water')!);
    expect(await call(sandbox, 'storage.get', {'key': 'goal'}), {
      'ok': true,
      'value': 2000,
    });
    await call(sandbox, 'storage.set', {'key': 'goal', 'value': 1});
    await call(sandbox, 'reminders.set', {
      'id': 'noon',
      'reminder': {'time': '12:00'},
    });
    expect(await call(sandbox, 'storage.get', {'key': 'goal'}), {
      'ok': true,
      'value': 1,
    });
    expect(await store.storageGet('water', 'goal'), 2000);
    expect(await store.readReminders('water'), isEmpty);
    await sandbox.dispose();
    expect(store.byId('water'), isNotNull);
  });

  test(
    'the sandbox answers without the model, notifications or calendar',
    () async {
      final sandbox = await MiniAppSandbox.create(store.byId('water')!);
      addTearDown(sandbox.dispose);
      expect(await call(sandbox, 'ai.ask', {'prompt': 'hi'}), {
        'ok': true,
        'value': MiniAppSandbox.testAnswer,
      });
      expect((await call(sandbox, 'notify', {'title': 't'}))['ok'], isTrue);
      expect(await call(sandbox, 'calendar.list'), {
        'ok': true,
        'value': {'events': []},
      });
    },
  );

  test('page reports and failed calls are collected for the report', () async {
    final sandbox = await MiniAppSandbox.create(store.byId('water')!);
    addTearDown(sandbox.dispose);
    final bridge = sandbox.bridge;
    expect(
      await bridge.handle(
        jsonEncode({
          'method': '__report',
          'args': {'kind': 'error', 'message': 'x is not defined'},
        }),
      ),
      isNull,
    );
    await call(sandbox, 'storage.get', {'key': 5});
    await call(sandbox, 'nope');
    final report = MiniAppCheckReport(
      loaded: true,
      pageErrors: bridge.pageErrors,
      failedCalls: bridge.failedCalls,
      visibleContent: 12,
    );
    expect(report.toJson(), {
      'ok': false,
      'loaded': true,
      'page_errors': ['error: x is not defined'],
      'failed_moru_calls': [
        'storage.get: key must be a string.',
        'nope: Unknown method "nope".',
      ],
    });
  });

  test('a clean run is ok', () {
    expect(const MiniAppCheckReport(loaded: true, visibleContent: 3).toJson(), {
      'ok': true,
      'loaded': true,
    });
    expect(const MiniAppCheckReport(loaded: false).toJson(), {
      'ok': false,
      'loaded': false,
    });
  });
}
