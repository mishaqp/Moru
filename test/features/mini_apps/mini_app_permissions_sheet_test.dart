import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_runtime.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_store.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/features/mini_apps/mini_app_permissions_sheet.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/widgets/ios_switch.dart';

import '../../support/business_test_harness.dart';

void main() {
  late Directory temp;
  late MiniAppStore store;
  late MiniAppRuntime runtime;
  late MiniApp app;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mini-app-grants-ui-');
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
          'device.screen.write',
          'device.root.wifi',
        ],
        'actions': [
          {
            'name': 'wifi',
            'description': 'Change Wi-Fi',
            'inputSchema': {
              'type': 'object',
              'properties': {
                'enabled': {'type': 'boolean'},
              },
              'required': ['enabled'],
              'additionalProperties': false,
            },
            'permissions': ['device.root.wifi'],
            'danger': 'root',
            'executor': {'kind': 'native', 'handler': 'device.root.wifi.set'},
          },
        ],
      }),
    );
    File(
      p.join(source.path, 'screen.json'),
    ).writeAsStringSync(jsonEncode({'version': 1, 'components': []}));
    app = (await store.install(source)).app;
    runtime = MiniAppRuntime(store: store);
  });
  tearDown(() async {
    await runtime.dispose();
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
    await tester.pumpAndSettle();
  }

  Future<void> pumpSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MiniAppPermissionsSheet(
            app: app,
            store: store,
            runtime: runtime,
          ),
        ),
      ),
    );
    await ioUntil(tester, () => find.byType(IosSwitch).evaluate().length == 4);
  }

  testWidgets(
    'opening permissions never grants and each gesture grants or revokes only one capability',
    (tester) async {
      await pumpSheet(tester);
      expect(
        await tester.runAsync(() => runtime.permissions.granted(app.id)),
        isEmpty,
      );
      expect(find.text('Allow AI actions'), findsOneWidget);
      expect(find.text('Root: change Wi-Fi'), findsOneWidget);
      final battery = find.byKey(
        const ValueKey('mini-app-permission-device.battery.read'),
      );
      await tester.tap(battery);
      await ioUntil(
        tester,
        () =>
            tester.widget<IosSwitch>(battery).value &&
            tester.widget<IosSwitch>(battery).onChanged != null,
      );
      expect(await tester.runAsync(() => runtime.permissions.granted(app.id)), {
        'device.battery.read',
      });
      await tester.tap(battery);
      await ioUntil(
        tester,
        () =>
            !tester.widget<IosSwitch>(battery).value &&
            tester.widget<IosSwitch>(battery).onChanged != null,
      );
      expect(
        await tester.runAsync(() => runtime.permissions.granted(app.id)),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      expect(
        await tester.runAsync(() => runtime.permissions.granted(app.id)),
        isEmpty,
      );
    },
  );

  testWidgets('root approval uses the shared service and dismissal denies', (
    tester,
  ) async {
    final approvals = ToolApprovalService();
    final settings = (await tester.runAsync(() async {
      final value = SettingsProvider(createBusinessTestPreferences());
      await value.loaded;
      return value;
    }))!;
    addTearDown(approvals.dispose);
    addTearDown(settings.dispose);
    bool? approved;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: approvals),
          ChangeNotifierProvider.value(value: settings),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async =>
                    approved = await requestMiniAppActionApproval(
                      context,
                      app: app,
                      action: app.actions.single,
                      arguments: {'enabled': false},
                      isActive: () => true,
                      scope: 'ui-test',
                      approvals: approvals,
                    ),
                child: const Text('Run'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Run'));
    await tester.pumpAndSettle();
    expect(approvals.pendingRequests, hasLength(1));
    expect(approvals.pendingRequests.single.toolName, startsWith('ma_'));
    expect(find.text('Confirm app action'), findsOneWidget);
    expect(find.textContaining('uses root'), findsOneWidget);
    expect(find.textContaining('Always'), findsNothing);
    await tester.tap(find.text('Deny'));
    await tester.pumpAndSettle();
    expect(approved, isFalse);
    expect(approvals.pendingRequests, isEmpty);
    approved = null;
    await tester.tap(find.text('Run'));
    await tester.pumpAndSettle();
    expect(approvals.pendingRequests, hasLength(1));
    await tester.runAsync(() => settings.setToolAutoApproveAll(true));
    await tester.pumpAndSettle();
    expect(approved, isTrue);
    expect(approvals.pendingRequests, isEmpty);
    expect(find.text('Confirm app action'), findsNothing);
  });
}
