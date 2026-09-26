import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/services/memory/memory_usage_meter.dart';

import '../../../support/business_test_harness.dart';

void main() {
  test(
    'counts calls and estimated tokens and keeps them across restarts',
    () async {
      final preferences = createBusinessTestPreferences();
      var now = DateTime(2026, 9, 26, 10);
      final meter = MemoryUsageMeter(preferences: preferences, now: () => now);
      expect(meter.today, (calls: 0, input: 0, output: 0));

      var notified = 0;
      meter.addListener(() => notified++);
      meter.record(prompt: 'a' * 400, response: 'b' * 40);
      meter.record(prompt: 'c' * 80, response: '');
      expect(meter.today, (calls: 2, input: 120, output: 10));
      expect(notified, 2);

      // The count survives a restart of the app, once the write has landed.
      await pumpEventQueue();
      final reopened = MemoryUsageMeter(
        preferences: preferences,
        now: () => now,
      );
      expect(reopened.today, (calls: 2, input: 120, output: 10));

      // A new day starts from zero.
      now = DateTime(2026, 9, 27, 0, 1);
      expect(reopened.today, (calls: 0, input: 0, output: 0));
      reopened.record(prompt: 'd' * 4, response: 'e' * 4);
      expect(reopened.today, (calls: 1, input: 1, output: 1));
    },
  );

  test('a damaged stored value starts over', () async {
    final preferences = createBusinessTestPreferences();
    await preferences.setString(MemoryUsageMeter.storageKey, '{not json');
    final meter = MemoryUsageMeter(preferences: preferences);
    expect(meter.today, (calls: 0, input: 0, output: 0));
  });
}
