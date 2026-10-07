import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/models/spend_limits.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';

import 'support/business_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('spend limits are disabled by default and survive reload', () async {
    final harness = await createBusinessTestHarness();
    final settings = SettingsProvider(harness.preferences);
    addTearDown(settings.dispose);
    await settings.loaded;
    expect(settings.spendLimits.enabled, isFalse);
    final limits = const SpendLimits().patch({
      'chat_usd': 0.5,
      'daily_tokens': 50000,
      'warning_percent': 75,
      'hard_stop': true,
    });
    await settings.setSpendLimits(limits);
    final reloaded = SettingsProvider(harness.preferences);
    addTearDown(reloaded.dispose);
    await reloaded.loaded;
    expect(reloaded.spendLimits.toJson(), limits.toJson());
    final copy = settings.copyWith();
    addTearDown(copy.dispose);
    expect(copy.spendLimits.toJson(), limits.toJson());
    await reloaded.setSpendLimits(const SpendLimits());
    expect(reloaded.spendLimits.enabled, isFalse);
  });
}
