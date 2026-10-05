import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_runtime.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_store.dart';
import 'package:Kelivo/features/home/services/mini_app_data_tool.dart';

void main() {
  late Directory temp;
  late Directory source;
  late MiniAppStore store;
  late MiniAppRuntime runtime;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('moru-data-grants-');
    source = Directory('${temp.path}/source')..createSync();
    File('${source.path}/moru-app.json').writeAsStringSync(
      jsonEncode({
        'id': 'counter',
        'name': 'Counter',
        'formatVersion': 2,
        'ui': {'engine': 'native', 'entry': 'screen.json'},
        'permissions': ['actions.ai'],
      }),
    );
    File(
      '${source.path}/screen.json',
    ).writeAsStringSync(jsonEncode({'version': 1, 'components': <Object>[]}));
    store = MiniAppStore(root: () async => Directory('${temp.path}/apps'));
    await store.install(source);
    runtime = MiniAppRuntime(store: store);
  });

  tearDown(() async {
    runtime.dispose();
    store.dispose();
    await temp.delete(recursive: true);
  });

  Future<Map<String, dynamic>> call(
    String action, {
    MiniAppInvocation? invocation,
    Object? value = 5,
  }) async =>
      jsonDecode(
            await MiniAppDataTool(
              store: store,
              runtime: runtime,
              invocation:
                  invocation ??
                  const MiniAppInvocation(source: MiniAppInvocationSource.chat),
            ).execute({
              'action': action,
              'app_id': 'counter',
              'key': 'count',
              'value': value,
            }),
          )
          as Map<String, dynamic>;

  test('AI data mutations require app grants even in full trust', () async {
    await store.storageSet('counter', 'count', 1, fromApp: true);
    for (final source in [
      MiniAppInvocationSource.chat,
      MiniAppInvocationSource.acp,
    ]) {
      for (final action in ['write', 'remove']) {
        final result = await call(
          action,
          invocation: MiniAppInvocation(source: source, fullTrust: () => true),
        );
        expect(result['ok'], false);
        expect(result['error'], 'permission_required');
        expect(await store.storageGet('counter', 'count'), 1);
      }
    }
  });

  test('granted AI write and remove notify open app state', () async {
    await runtime.permissions.setGranted('counter', 'actions.ai', true);
    final changes = <String>[];
    final subscription = store.changes.listen(
      (event) => changes.add(event.appId),
    );
    addTearDown(subscription.cancel);
    expect(await call('write', value: null), {'ok': true, 'written': 'count'});
    expect(await store.storageAll('counter'), {'count': null});
    expect(await call('remove'), {'ok': true, 'removed': 'count'});
    expect(await store.storageAll('counter'), isEmpty);
    await Future<void>.delayed(Duration.zero);
    expect(changes, ['counter', 'counter']);
  });

  for (final invalidation in [
    'grant revoked',
    'owner stopped',
    'app replaced',
  ]) {
    test('queued AI data write fails when $invalidation', () async {
      await runtime.permissions.setGranted('counter', 'actions.ai', true);
      final entered = Completer<void>();
      final release = Completer<void>();
      final blocker = store.updateState('counter', (data) async {
        entered.complete();
        await release.future;
      });
      await entered.future;
      var live = true;
      final write = call(
        'write',
        invocation: MiniAppInvocation(
          source: MiniAppInvocationSource.chat,
          isAllowed: () => live,
        ),
      );
      if (invalidation == 'grant revoked') {
        await runtime.permissions.setGranted('counter', 'actions.ai', false);
      } else if (invalidation == 'owner stopped') {
        live = false;
      } else {
        await store.install(source);
      }
      release.complete();
      await blocker;
      expect((await write)['ok'], false);
      expect(await store.storageAll('counter'), isEmpty);
    });
  }

  test('Wi-Fi cannot use the AI data mutation capability', () async {
    await runtime.permissions.setGranted('counter', 'actions.ai', true);
    final result = await call(
      'write',
      invocation: const MiniAppInvocation(source: MiniAppInvocationSource.wifi),
    );
    expect(result['ok'], false);
    expect(await store.storageAll('counter'), isEmpty);
  });
}
