import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:Kelivo/core/services/mini_apps/mini_app_bridge.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_reminders.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_store.dart';
import 'package:Kelivo/features/home/services/mini_app_data_tool.dart';

void main() {
  late Directory temp;
  late MiniAppStore store;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mini-apps-2-');
    store = MiniAppStore(
      root: () async => Directory(p.join(temp.path, 'installed')),
    );
    final dir = Directory(p.join(temp.path, 'src'))..createSync();
    File(p.join(dir.path, 'moru-app.json')).writeAsStringSync(
      jsonEncode({
        'id': 'water',
        'name': 'Water',
        'description': 'Tracks water',
        'data': 'log: {"YYYY-MM-DD": [ml, ...]}',
      }),
    );
    File(p.join(dir.path, 'index.html')).writeAsStringSync('<p>x</p>');
    await store.install(dir);
  });
  tearDown(() => temp.delete(recursive: true));

  group('chat tool', () {
    Future<Map<String, dynamic>> run(Map<String, dynamic> args) async =>
        jsonDecode(await MiniAppDataTool(store: store).execute(args))
            as Map<String, dynamic>;

    test('lists apps with their data format and keys', () async {
      await store.storageSet('water', 'goal', 2000, fromApp: true);
      expect(await run({'action': 'list'}), {
        'ok': true,
        'apps': [
          {
            'id': 'water',
            'name': 'Water',
            'description': 'Tracks water',
            'data': 'log: {"YYYY-MM-DD": [ml, ...]}',
            'keys': ['goal'],
          },
        ],
      });
    });

    test('writes, reads and removes data and tells an open app', () async {
      final changes = <String>[];
      final sub = store.changes.listen(
        (c) => changes.add('${c.appId}/${c.key}'),
      );
      addTearDown(sub.cancel);

      expect(
        (await run({
          'action': 'write',
          'app_id': 'water',
          'key': 'log',
          'value': {
            '2026-09-26': [250],
          },
        }))['ok'],
        isTrue,
      );
      expect(await run({'action': 'read', 'app_id': 'water', 'key': 'log'}), {
        'ok': true,
        'key': 'log',
        'value': {
          '2026-09-26': [250],
        },
      });
      expect(await run({'action': 'read', 'app_id': 'water'}), {
        'ok': true,
        'data': {
          'log': {
            '2026-09-26': [250],
          },
        },
      });
      await run({'action': 'remove', 'app_id': 'water', 'key': 'log'});
      await Future<void>.delayed(Duration.zero);
      expect(changes, ['water/log', 'water/log']);
      expect(await store.storageKeys('water'), isEmpty);
    });

    test('the app\'s own writes do not echo back to it', () async {
      final changes = <String>[];
      final sub = store.changes.listen((c) => changes.add(c.key));
      addTearDown(sub.cancel);
      await MiniAppBridge(store: store, appId: 'water').handle(
        jsonEncode({
          'id': 1,
          'method': 'storage.set',
          'args': {'key': 'goal', 'value': 1},
        }),
      );
      await Future<void>.delayed(Duration.zero);
      expect(changes, isEmpty);
    });

    test('mistakes are explained', () async {
      expect(
        (await run({'action': 'read', 'app_id': 'x'}))['error'],
        'not_found',
      );
      expect(
        (await run({
          'action': 'write',
          'app_id': 'water',
          'key': 'k',
        }))['error'],
        'missing_value',
      );
      expect(
        (await run({
          'action': 'write',
          'app_id': 'water',
          'value': 1,
        }))['error'],
        'missing_key',
      );
      expect((await run({'action': 'drop'}))['error'], 'invalid_action');
    });

    test('large data is read key by key', () async {
      await store.storageSet('water', 'big', 'x' * 30000);
      final result = await run({'action': 'read', 'app_id': 'water'});
      expect(result['keys'], ['big']);
      expect(result.containsKey('data'), isFalse);
    });
  });

  group('bridge host', () {
    test('ai.ask goes to the model one request at a time', () async {
      final gate = Completer<String>();
      final calls = <String>[];
      final bridge = MiniAppBridge(
        store: store,
        appId: 'water',
        host: MiniAppHost(
          ask: (prompt, system) {
            calls.add('$system|$prompt');
            return gate.future;
          },
        ),
      );
      String ask(int id) => jsonEncode({
        'id': id,
        'method': 'ai.ask',
        'args': {'prompt': 'plan', 'system': 'coach'},
      });

      final first = bridge.handle(ask(1));
      expect(
        await bridge.handle(ask(2)),
        startsWith('window.__moruReply(2, false, "Wait for'),
      );
      gate.complete('drink more');
      expect(await first, 'window.__moruReply(1, true, "drink more");');
      expect(calls, ['coach|plan']);
    });

    test('without a host capability the call is refused', () async {
      final reply = await MiniAppBridge(store: store, appId: 'water').handle(
        jsonEncode({
          'id': 3,
          'method': 'notify',
          'args': {'title': 'Hi'},
        }),
      );
      expect(
        reply,
        'window.__moruReply(3, false, "This is not available here.");',
      );
    });

    test('notify passes title and body', () async {
      final shown = <String>[];
      final bridge = MiniAppBridge(
        store: store,
        appId: 'water',
        host: MiniAppHost(
          notify: (title, body) async => shown.add('$title|$body'),
        ),
      );
      await bridge.handle(
        jsonEncode({
          'id': 1,
          'method': 'notify',
          'args': {'title': 'Water', 'body': 'Drink'},
        }),
      );
      expect(shown, ['Water|Drink']);
    });
  });

  group('reminders', () {
    late List<String> log;
    late MiniAppReminders reminders;

    setUp(() {
      log = [];
      reminders = MiniAppReminders(
        store: store,
        schedule:
            ({
              required id,
              required appId,
              required title,
              required body,
              required hour,
              required minute,
              weekday,
            }) async => log.add(
              'schedule $id $hour:$minute ${weekday ?? '*'} $title|$body',
            ),
        cancel: (id) async => log.add('cancel $id'),
      );
    });

    test('daily and weekday reminders are scheduled and replaced', () async {
      await reminders.set('water', 'morning', {'time': '8:05'});
      final daily = MiniAppReminders.notificationIds('water', 'morning', {});
      expect(log, ['schedule ${daily.single} 8:5 * Water|']);
      expect(await reminders.list('water'), {
        'morning': {'time': '08:05', 'title': 'Water', 'body': ''},
      });

      log.clear();
      await reminders.set('water', 'morning', {
        'time': '09:30',
        'days': [5, 1, 1],
        'title': 'Пей воду',
        'body': 'Стакан',
      });
      final weekly = MiniAppReminders.notificationIds('water', 'morning', {
        'days': [1, 5],
      });
      expect(log, [
        'cancel ${daily.single}',
        'schedule ${weekly[0]} 9:30 1 Пей воду|Стакан',
        'schedule ${weekly[1]} 9:30 5 Пей воду|Стакан',
      ]);

      log.clear();
      await reminders.remove('water', 'morning');
      expect(log, ['cancel ${weekly[0]}', 'cancel ${weekly[1]}']);
      expect(await reminders.list('water'), isEmpty);
    });

    test('all seven days become one daily reminder', () {
      expect(
        MiniAppReminders.normalize({
          'time': '07:00',
          'days': [1, 2, 3, 4, 5, 6, 7],
        }, fallbackTitle: 'App'),
        {'time': '07:00', 'title': 'App', 'body': ''},
      );
    });

    test('bad reminders are refused', () async {
      Future<String> code(Object? reminder, [String id = 'r']) async {
        try {
          await reminders.set('water', id, reminder);
        } on MiniAppException catch (e) {
          return e.code;
        }
        return 'ok';
      }

      expect(await code({'time': '25:00'}), 'invalid_reminder');
      expect(
        await code({
          'time': '08:00',
          'days': [0],
        }),
        'invalid_reminder',
      );
      expect(await code('08:00'), 'invalid_reminder');
      expect(await code({'time': '08:00'}, 'bad id!'), 'invalid_reminder');
      for (var i = 0; i < MiniAppReminders.maxReminders; i++) {
        expect(await code({'time': '08:00'}, 'r$i'), 'ok');
      }
      expect(await code({'time': '08:00'}, 'one-more'), 'too_many_reminders');
      expect(log.where((l) => l.startsWith('schedule')).length, 20);
    });

    test('deleting the app cancels its reminders', () async {
      store.addDeleteHook(reminders.cancelAll);
      await reminders.set('water', 'a', {'time': '08:00'});
      log.clear();
      await store.delete('water');
      expect(log, [
        'cancel ${MiniAppReminders.notificationIds('water', 'a', {}).single}',
      ]);
    });
  });
}
