import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/logging/context_logger.dart';
import 'package:Kelivo/core/services/logging/flutter_logger.dart';
import 'package:Kelivo/core/services/network/request_logger.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/business_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    await RequestLogger.setEnabled(false);
    await ContextLogger.setEnabled(false);
    await FlutterLogger.setEnabled(false);
  });

  test('fresh installs keep request and context logging off', () async {
    final harness = await createBusinessTestHarness();
    final settings = SettingsProvider(harness.preferences);
    addTearDown(settings.dispose);

    final initialRequestLog = settings.requestLogEnabled;
    final initialContextLog = settings.contextLogEnabled;
    await settings.loaded;

    expect(initialRequestLog, isFalse);
    expect(initialContextLog, isFalse);
    expect(settings.requestLogEnabled, isFalse);
    expect(settings.contextLogEnabled, isFalse);
    expect(settings.flutterLogEnabled, isFalse);
    expect(RequestLogger.enabled, isFalse);
    expect(ContextLogger.enabled, isFalse);
    expect(FlutterLogger.enabled, isFalse);
    expect(harness.preferences.getBool('request_log_enabled_v1'), isNull);
    expect(harness.preferences.getBool('context_log_enabled_v1'), isNull);
  });

  for (final enabled in [true, false]) {
    test('saved logging choices remain $enabled after loading', () async {
      final harness = await createBusinessTestHarness(
        initial: {
          'request_log_enabled_v1': enabled,
          'context_log_enabled_v1': enabled,
        },
        localInitial: {'flutter_log_enabled_v1': enabled},
      );
      final settings = SettingsProvider(harness.preferences);
      addTearDown(settings.dispose);
      await settings.loaded;

      expect(settings.requestLogEnabled, enabled);
      expect(settings.contextLogEnabled, enabled);
      expect(settings.flutterLogEnabled, enabled);
      expect(RequestLogger.enabled, enabled);
      expect(ContextLogger.enabled, enabled);
      expect(FlutterLogger.enabled, enabled);
      expect(harness.preferences.getBool('request_log_enabled_v1'), enabled);
      expect(harness.preferences.getBool('context_log_enabled_v1'), enabled);
    });
  }
}
