import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/api/tool_call_cancellation.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_device.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_runtime.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_store.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/features/mini_apps/pages/native_mini_app_page.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

import '../../support/business_test_harness.dart';

class _Device extends MiniAppDeviceService {
  _Device() {
    events = StreamController.broadcast(
      onListen: () => watching++,
      onCancel: () => watching--,
    );
  }
  late final StreamController<Map<String, dynamic>> events;
  int watching = 0;
  int reads = 0;
  int writes = 0;
  int finished = 0;
  String result = 'applied';
  bool hold = false;
  ToolCallCancellation? nativeCancellation;
  @override
  Stream<Map<String, dynamic>> get changes => events.stream;
  @override
  Future<Map<String, dynamic>> snapshot() async {
    reads++;
    return {
      'battery': {
        'levelPercent': null,
        'reasons': {'levelPercent': 'unsupported'},
      },
    };
  }

  @override
  Future<Map<String, dynamic>> execute(
    String handler,
    Map<String, dynamic> args,
  ) async {
    writes++;
    nativeCancellation = ToolCallCancellation.current;
    if (hold) await nativeCancellation!.cancelled;
    final state = await snapshot();
    finished++;
    return {'status': result, 'message': 'Native detail', 'state': state};
  }
}

class _FeedbackRuntime extends MiniAppRuntime {
  _FeedbackRuntime(MiniAppStore store, MiniAppDeviceService device)
    : super(store: store, device: device);
  @override
  Future<Map<String, dynamic>> execute(
    String appId,
    String actionName,
    Map<String, dynamic> arguments, {
    required MiniAppInvocation invocation,
  }) async => {
    'status': 'failed',
    'partial': true,
    'steps': [
      {'handler': 'device.audio.dnd.set', 'status': 'unsupported'},
      {'handler': 'device.screen.brightness.set', 'status': 'conflict'},
    ],
    'conflicts': ['screen.brightness'],
  };
}

void main() {
  late Directory temp;
  late MiniAppStore store;
  late MiniAppRuntime runtime;
  late MiniApp app;
  late _Device device;
  late SettingsProvider settings;
  late ToolApprovalService approvals;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('native-mini-page-test-');
    store = MiniAppStore(
      root: () async => Directory(p.join(temp.path, 'apps')),
    );
    final source = Directory(p.join(temp.path, 'source'))..createSync();
    File(p.join(source.path, MiniAppStore.manifestFile)).writeAsStringSync(
      jsonEncode({
        'id': 'panel',
        'name': 'Panel',
        'formatVersion': 2,
        'ui': {'engine': 'native'},
        'permissions': [
          'actions.ai',
          'device.battery.read',
          'device.root.wifi',
        ],
        'actions': [
          {
            'name': 'set_enabled',
            'description': 'Set enabled',
            'inputSchema': {
              'type': 'object',
              'properties': {
                'enabled': {'type': 'boolean'},
              },
              'required': ['enabled'],
              'additionalProperties': false,
            },
            'permissions': [],
            'danger': 'write',
            'executor': {
              'kind': 'state',
              'patch': {
                'enabled': {r'$arg': 'enabled'},
              },
            },
          },
          {
            'name': 'root_wifi',
            'description': 'Change Wi-Fi',
            'inputSchema': MiniAppDeviceService.inputSchemaFor(
              'device.root.wifi.set',
            ),
            'permissions': ['device.root.wifi'],
            'danger': 'root',
            'executor': {'kind': 'native', 'handler': 'device.root.wifi.set'},
          },
        ],
      }),
    );
    File(p.join(source.path, 'screen.json')).writeAsStringSync(
      jsonEncode({
        'version': 1,
        'title': {'en': 'Panel', 'ru': 'Панель'},
        'components': [
          {'type': 'value', 'label': 'Enabled', 'bind': 'data.enabled'},
          {
            'type': 'value',
            'label': 'Battery',
            'bind': 'device.battery.levelPercent',
          },
          {
            'type': 'button',
            'label': 'Enable',
            'action': 'set_enabled',
            'args': {'enabled': true},
          },
          {
            'type': 'button',
            'label': 'Root Wi-Fi',
            'action': 'root_wifi',
            'args': {'enabled': true},
          },
        ],
      }),
    );
    app = (await store.install(source)).app;
    await store.storageSet(app.id, 'enabled', false);
    device = _Device();
    runtime = MiniAppRuntime(store: store, device: device);
    settings = SettingsProvider(createBusinessTestPreferences());
    await settings.loaded;
    approvals = ToolApprovalService();
  });
  tearDown(() async {
    await runtime.dispose();
    await device.events.close();
    approvals.dispose();
    settings.dispose();
    store.dispose();
    await temp.delete(recursive: true);
  });

  Future<void> ioUntil(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 200 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
    expect(done(), isTrue);
    await tester.pump();
  }

  Future<void> pump(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
  }) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: approvals),
        ],
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: NativeMiniAppPage(app: app, store: store, runtime: runtime),
        ),
      ),
    );
    await ioUntil(tester, () => find.text('Enable').evaluate().isNotEmpty);
  }

  testWidgets('button and AI state actions update the same visible panel', (
    tester,
  ) async {
    await tester.runAsync(
      () => runtime.permissions.setGranted(app.id, 'actions.ai', true),
    );
    await pump(tester);
    expect(find.text('Off'), findsOneWidget);
    await tester.tap(find.text('Enable'));
    await ioUntil(
      tester,
      () =>
          find.text('On').evaluate().isNotEmpty &&
          tester
                  .widget<OutlinedButton>(
                    find.widgetWithText(OutlinedButton, 'Enable'),
                  )
                  .onPressed !=
              null,
    );
    Map<String, dynamic>? result;
    unawaited(
      runtime
          .execute(
            app.id,
            'set_enabled',
            {'enabled': false},
            invocation: MiniAppInvocation(
              source: MiniAppInvocationSource.chat,
              approve: (_, _, _) async => true,
            ),
          )
          .then((value) => result = value),
    );
    await ioUntil(tester, () => result != null);
    expect(result!['status'], 'applied');
    await ioUntil(tester, () => find.text('Off').evaluate().isNotEmpty);
    expect(device.writes, 0);
  });

  testWidgets(
    'screen title follows Moru locale while installed name stays intact',
    (tester) async {
      await pump(tester, locale: const Locale('ru'));
      expect(find.text('Панель'), findsOneWidget);
      expect(app.name, 'Panel');
      expect(find.byTooltip('Разрешения приложения'), findsOneWidget);
    },
  );

  testWidgets(
    'partial preset and restore conflicts explain each affected setting in Russian',
    (tester) async {
      await tester.runAsync(runtime.dispose);
      runtime = _FeedbackRuntime(store, device);
      await pump(tester, locale: const Locale('ru'));
      await tester.tap(find.text('Enable'));
      await tester.pump();
      expect(
        find.text(
          'Часть изменений не удалось применить. Проверьте разрешения и возможности устройства.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Последующие ручные изменения сохранены. Эти значения не восстановлены.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Не беспокоить: Это устройство не поддерживает эту возможность',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('device.audio.dnd'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('missing grants show a clear error without changing the device', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Root Wi-Fi'));
    await ioUntil(
      tester,
      () => find.text('Permission required').evaluate().isNotEmpty,
    );
    expect(device.writes, 0);
    expect(approvals.pendingRequests, isEmpty);
  });

  testWidgets('root buttons require confirmation and read full trust live', (
    tester,
  ) async {
    await tester.runAsync(
      () => runtime.permissions.setGranted(app.id, 'device.root.wifi', true),
    );
    await pump(tester);
    await tester.tap(find.text('Root Wi-Fi'));
    await ioUntil(tester, () => approvals.hasPending);
    expect(device.writes, 0);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.ensureVisible(find.text('Deny'));
    await tester.tap(find.text('Deny'));
    await ioUntil(
      tester,
      () => find.text('Action denied').evaluate().isNotEmpty,
    );
    expect(device.writes, 0);
    await tester.runAsync(() => settings.setToolAutoApproveAll(true));
    // Native mutations share a process-wide queue. Its real IO must stay in
    // the real zone across separate widget-test clocks.
    await tester.runAsync(() => tester.tap(find.text('Root Wi-Fi')));
    await ioUntil(
      tester,
      () =>
          device.writes == 1 &&
          find.text('Change applied').evaluate().isNotEmpty &&
          tester
                  .widget<OutlinedButton>(
                    find.widgetWithText(OutlinedButton, 'Root Wi-Fi'),
                  )
                  .onPressed !=
              null,
    );
    expect(approvals.pendingRequests, isEmpty);
  });

  testWidgets(
    'subscriptions stop on close and resume reads fresh native state',
    (tester) async {
      await tester.runAsync(
        () =>
            runtime.permissions.setGranted(app.id, 'device.battery.read', true),
      );
      await pump(tester);
      await ioUntil(tester, () => device.watching == 1);
      expect(find.text('Not supported on this device'), findsOneWidget);
      final reads = device.reads;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await ioUntil(tester, () => device.reads > reads);
      await tester.pumpWidget(const SizedBox.shrink());
      await ioUntil(tester, () => device.watching == 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'closing cancels the native request, but an Android consent pause does not',
    (tester) async {
      await tester.runAsync(() async {
        await runtime.permissions.setGranted(app.id, 'device.root.wifi', true);
        await settings.setToolAutoApproveAll(true);
      });
      device.hold = true;
      await pump(tester);
      await tester.runAsync(() => tester.tap(find.text('Root Wi-Fi')));
      await ioUntil(tester, () => device.nativeCancellation != null);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(device.nativeCancellation!.isCancelled(), isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      await ioUntil(tester, () => device.nativeCancellation!.isCancelled());
      await ioUntil(tester, () => device.finished == 1);
      expect(approvals.pendingRequests, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('invalid installed screen shows an explicit load error', (
    tester,
  ) async {
    File(app.entryPath).writeAsStringSync('{broken');
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: NativeMiniAppPage(app: app, store: store, runtime: runtime),
      ),
    );
    await ioUntil(
      tester,
      () => find.text('Could not load this panel.').evaluate().isNotEmpty,
    );
    expect(tester.takeException(), isNull);
    expect(device.writes, 0);
  });

  testWidgets(
    'a retained page cancels on detach and can invoke again after resume',
    (tester) async {
      await tester.runAsync(() async {
        await runtime.permissions.setGranted(app.id, 'device.root.wifi', true);
        await settings.setToolAutoApproveAll(true);
      });
      device.hold = true;
      await pump(tester);
      await tester.runAsync(() => tester.tap(find.text('Root Wi-Fi')));
      await ioUntil(tester, () => device.nativeCancellation != null);
      final cancelled = device.nativeCancellation!;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
      await ioUntil(
        tester,
        () => cancelled.isCancelled() && device.finished == 1,
      );
      device.hold = false;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await ioUntil(
        tester,
        () =>
            tester
                .widget<OutlinedButton>(
                  find.widgetWithText(OutlinedButton, 'Root Wi-Fi'),
                )
                .onPressed !=
            null,
      );
      await tester.runAsync(() => tester.tap(find.text('Root Wi-Fi')));
      await ioUntil(
        tester,
        () =>
            device.finished == 2 &&
            find.text('Change applied').evaluate().isNotEmpty &&
            tester
                    .widget<OutlinedButton>(
                      find.widgetWithText(OutlinedButton, 'Root Wi-Fi'),
                    )
                    .onPressed !=
                null,
      );
      expect(device.nativeCancellation, isNot(same(cancelled)));
      expect(device.nativeCancellation!.isCancelled(), isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
