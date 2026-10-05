import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:Kelivo/core/services/mini_apps/mini_app_expressions.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_manifest.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_permissions.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_store.dart';
import 'package:Kelivo/features/mini_apps/focus_mini_app.dart';
import 'package:Kelivo/features/mini_apps/mini_app_launcher.dart';
import 'package:Kelivo/features/mini_apps/widgets/native_mini_app_panel.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

void main() {
  late Directory temp;
  late MiniAppStore store;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('focus-example-test-');
    store = MiniAppStore(
      root: () async => Directory(p.join(temp.path, 'apps')),
    );
  });
  tearDown(() async {
    store.dispose();
    await temp.delete(recursive: true);
  });

  Future<MiniApp> installUserCopy(MiniAppStore target, String id) async {
    final source = Directory(p.join(temp.path, 'source-$id'))..createSync();
    File(p.join(source.path, MiniAppStore.manifestFile)).writeAsStringSync(
      jsonEncode({
        'id': id,
        'name': 'My $id',
        'permissions': ['actions.ai'],
      }),
    );
    File(p.join(source.path, 'index.html')).writeAsStringSync('<p>my $id</p>');
    final app = (await target.install(source)).app;
    await target.storageSet(id, 'mine', 42);
    final permissions = MiniAppPermissions(target);
    try {
      await permissions.setGranted(id, 'actions.ai', true);
    } finally {
      permissions.dispose();
    }
    return app;
  }

  test(
    'Focus installs the same canonical data advertised by the spec without grants',
    () async {
      await FocusMiniApp.ensureInstalled(store);
      final app = store.byId(FocusMiniApp.id)!;
      expect(app.uiEngine, MiniAppUiEngine.native);
      expect(app.serverCommand, isNull);
      final screen = jsonDecode(await File(app.entryPath).readAsString());
      expect(screen, FocusMiniApp.screen());
      MiniAppManifest.validateScreen(screen, app.actions);
      final source = FocusMiniApp.manifest(
        lookupAppLocalizations(const Locale('en')),
      );
      expect(
        app.actions.map((action) => action.toJson()).toList(),
        source['actions'],
      );
      final permissions = MiniAppPermissions(store);
      addTearDown(permissions.dispose);
      expect(await permissions.granted(app.id), isEmpty);
      final sequences = app.actions.where(
        (action) => action.executor['kind'] == 'sequence',
      );
      expect(
        sequences.map((action) => action.name),
        containsAll(['start_15', 'start_25', 'start_50', 'stop']),
      );
      for (final minutes in [15, 25, 50]) {
        final start = app.actions.singleWhere(
          (action) => action.name == 'start_$minutes',
        );
        expect((start.executor['steps'] as List).first, {
          'action': 'focus_preset',
          'arguments': {},
          'onFailure': 'continue',
        });
        expect((start.executor['steps'] as List).last['arguments'], {
          'durationMs': minutes * 60000,
        });
      }
      final preset = app.actions.singleWhere(
        (action) => action.name == 'focus_preset',
      );
      for (final name in ['record_start', 'record_stop']) {
        expect(
          app.actions
              .singleWhere((action) => action.name == name)
              .executor['expressions'],
          isTrue,
        );
      }
      expect(preset.executor['steps'], [
        {
          'handler': 'device.screen.brightness.set',
          'args': {'value': 77, 'mode': 'manual'},
        },
        {
          'handler': 'device.audio.volume.set',
          'args': {'stream': 'music', 'value': 0},
        },
        {
          'handler': 'device.audio.dnd.set',
          'args': {'mode': 'none'},
        },
      ]);
    },
  );

  testWidgets(
    'canonical Focus panel remains readable in Russian and invokes declared controls',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final start = tester.binding.clock.now().millisecondsSinceEpoch;
      final calls = <(String, Map<String, dynamic>)>[];
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
              child: SingleChildScrollView(
                child: NativeMiniAppPanel(
                  screen: FocusMiniApp.screen(),
                  state: {
                    'data': {
                      'startedAt': start,
                      'endsAt': start + 1500000,
                      'running': true,
                      'sessionDay': '2026-10-05',
                      'sessionsToday': 2,
                    },
                  },
                  now: tester.binding.clock.now,
                  onAction: (name, arguments) async =>
                      calls.add((name, arguments)),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('0:25:00'), findsOneWidget);
      expect(find.text('Записанные сессии'), findsOneWidget);
      expect(find.text('Сессий за указанную дату'), findsOneWidget);
      final startButton = find.text('Начать на 25 минут');
      await tester.ensureVisible(startButton);
      await tester.tap(startButton);
      final stopButton = find.text('Остановить и восстановить');
      await tester.ensureVisible(stopButton);
      await tester.tap(stopButton);
      expect(calls.map((call) => call.$1), ['start_25', 'stop']);
      expect(calls.every((call) => call.$2.isEmpty), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'start and stop expression data count only running sessions in the current day',
    () {
      final actions =
          FocusMiniApp.manifest(
                lookupAppLocalizations(const Locale('ru')),
              )['actions']
              as List;
      Map<String, dynamic> patch(String name) => Map<String, dynamic>.from(
        actions.singleWhere(
          (action) => action['name'] == name,
        )['executor']['patch'],
      );
      final now = DateTime(2026, 10, 5, 9);
      final yesterday = {
        'sessionDay': '2026-10-04',
        'sessionsToday': 7,
        'running': false,
      };
      final started = MiniAppExpressions.evaluatePatch(
        patch('record_start'),
        arguments: {'durationMs': 1500000},
        data: yesterday,
        now: now,
      );
      expect(started['startedAt'], now.millisecondsSinceEpoch);
      expect(
        started['endsAt'],
        now.add(const Duration(minutes: 25)).millisecondsSinceEpoch,
      );
      expect(started['running'], true);
      expect(started['sessionsToday'], 0);
      final stopped = MiniAppExpressions.evaluatePatch(
        patch('record_stop'),
        arguments: {},
        data: {...yesterday, ...started},
        now: now,
      );
      expect(stopped['sessionsToday'], 1);
      expect(stopped['sessionDay'], '2026-10-05');
      expect(stopped['running'], false);
      expect(stopped['endsAt'], isNull);
      final stoppedAgain = MiniAppExpressions.evaluatePatch(
        patch('record_stop'),
        arguments: {},
        data: {...started, ...stopped},
        now: now,
      );
      expect(stoppedAgain['sessionsToday'], 1);
      final nextDayStop = MiniAppExpressions.evaluatePatch(
        patch('record_stop'),
        arguments: {},
        data: {...started, 'running': true},
        now: now.add(const Duration(days: 1)),
      );
      expect(nextDayStop['sessionsToday'], 1);
      expect(nextDayStop['sessionDay'], '2026-10-06');
    },
  );

  test(
    'example initialization preserves existing Focus and phone packages, data and grants',
    () async {
      final focus = await installUserCopy(store, FocusMiniApp.id);
      final phone = await installUserCopy(store, 'phone-control');
      await MiniAppLauncher.ensureExample(store: store);
      expect(store.byId(FocusMiniApp.id), same(focus));
      expect(store.byId('phone-control'), same(phone));
      final permissions = MiniAppPermissions(store);
      addTearDown(permissions.dispose);
      for (final app in [focus, phone]) {
        expect(await store.storageGet(app.id, 'mine'), 42);
        expect(await permissions.granted(app.id), {'actions.ai'});
        expect(await store.versions(app.id), isEmpty);
        expect(
          await File(app.entryPath).readAsString(),
          contains('<p>my ${app.id}</p>'),
        );
      }
    },
  );

  test(
    'launcher installs both absent examples and concurrent Focus calls share one copy',
    () async {
      await Future.wait([
        MiniAppLauncher.ensureExample(store: store),
        FocusMiniApp.ensureInstalled(store),
      ]);
      expect(
        store.apps.map((app) => app.id),
        containsAll(['focus', 'phone-control']),
      );
      expect(await store.versions(FocusMiniApp.id), isEmpty);
    },
  );

  test(
    'a concurrent user Focus installation wins initializer IO without data or grant loss',
    () async {
      final reached = Completer<void>();
      final release = Completer<void>();
      var calls = 0;
      final target = MiniAppStore(
        root: () async {
          if (++calls == 2) {
            reached.complete();
            await release.future;
          }
          return Directory(p.join(temp.path, 'racing-apps'));
        },
      );
      addTearDown(target.dispose);
      final installing = FocusMiniApp.ensureInstalled(target);
      await reached.future.timeout(const Duration(seconds: 5));
      final custom = await installUserCopy(target, FocusMiniApp.id);
      release.complete();
      await installing;
      expect(target.byId(FocusMiniApp.id), same(custom));
      expect(await target.storageGet(FocusMiniApp.id, 'mine'), 42);
      final permissions = MiniAppPermissions(target);
      addTearDown(permissions.dispose);
      expect(await permissions.granted(FocusMiniApp.id), {'actions.ai'});
      expect(await target.versions(FocusMiniApp.id), isEmpty);
    },
  );
}
