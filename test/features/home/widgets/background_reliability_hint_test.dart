import 'dart:convert';

import 'package:Kelivo/core/models/mobile_background_settings.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/mobile_background.dart';
import 'package:Kelivo/features/home/widgets/background_reliability_hint.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../../support/business_test_harness.dart';

void main() {
  const channel = MethodChannel('test.background.reliability-hint');
  final calls = <MethodCall>[];
  var status = <String, dynamic>{};
  SettingsProvider? settings;
  MobileBackgroundCoordinator? coordinator;
  BusinessTestHarness? storage;
  var opened = 0;

  setUp(() {
    calls.clear();
    status = {'manufacturer': 'vivo', 'batteryExempt': false};
    opened = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return call.method == 'sync' || call.method == 'getStatus'
              ? status
              : null;
        });
  });

  tearDown(() {
    coordinator?.dispose();
    settings?.dispose();
    coordinator = null;
    settings = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> show(WidgetTester tester, {bool active = true}) async {
    storage = await createBusinessTestHarness(
      initial: {
        'mobile_background_settings_v1': jsonEncode(
          const MobileBackgroundSettings(androidEnabled: true).toJson(),
        ),
      },
    );
    settings = SettingsProvider(storage!.preferences);
    await settings!.loaded;
    coordinator = MobileBackgroundCoordinator(
      platform: TargetPlatform.android,
      channel: channel,
    );
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await coordinator!.configure(settings!.mobileBackground, l10n);
    if (active) {
      await coordinator!.start(
        id: 'live-run',
        conversationId: 'chat',
        title: 'Task',
        scheduled: false,
        cancel: () async {},
      );
    }
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings!,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: BackgroundReliabilityHint(
              coordinator: coordinator,
              onOpenSettings: () => opened++,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('only active work shows OEM advice and settings require a tap', (
    tester,
  ) async {
    await show(tester);
    expect(find.text('Keep this task running'), findsOneWidget);
    expect(find.textContaining('Vivo and Xiaomi'), findsOneWidget);
    expect(opened, 0);
    expect(calls.where((call) => call.method == 'requestPermission'), isEmpty);
    expect(calls.where((call) => call.method == 'openSettings'), isEmpty);
    await tester.tap(find.text('Background settings'));
    expect(opened, 1);
    expect(settings!.mobileBackground.notificationsEnabled, isFalse);
  });

  testWidgets('idle Vivo and ordinary Pixel work do not show a tip', (
    tester,
  ) async {
    await show(tester, active: false);
    expect(find.text('Keep this task running'), findsNothing);
    status = {'manufacturer': 'Google', 'batteryExempt': false};
    await coordinator!.refreshStatus();
    await coordinator!.start(
      id: 'pixel-run',
      conversationId: 'chat',
      title: 'Task',
      scheduled: false,
      cancel: () async {},
    );
    await tester.pumpAndSettle();
    expect(find.text('Keep this task running'), findsNothing);
  });

  testWidgets(
    'dismissal is durable and does not alter saved execution choices',
    (tester) async {
      await show(tester);
      await tester.tap(
        find.byKey(const ValueKey('dismissBackgroundReliabilityHint')),
      );
      Map<String, dynamic>? persisted;
      // The settings use real SQLite; wait for the saved condition, bounded.
      for (var i = 0; i < 100; i++) {
        await tester.runAsync(() async {
          final snapshot = await storage!.repository.readSnapshot();
          final encoded = snapshot.preferences['mobile_background_settings_v1'];
          if (encoded is String) {
            persisted = jsonDecode(encoded) as Map<String, dynamic>;
          }
        });
        await tester.pump();
        if (persisted?['reliabilityHintDismissed'] == true) break;
      }
      expect(persisted?['reliabilityHintDismissed'], isTrue);
      expect(persisted?['androidEnabled'], isTrue);
      expect(persisted?['notificationsEnabled'], isFalse);
      expect(find.text('Keep this task running'), findsNothing);
      final restored = MobileBackgroundSettings.fromJson(persisted!);
      expect(restored.reliabilityHintDismissed, isTrue);
      expect(
        calls.where((call) => call.method == 'requestPermission'),
        isEmpty,
      );
    },
  );
}
