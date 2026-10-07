import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/models/spend_limits.dart';

void main() {
  test('limits start disabled and patches preserve unrelated choices', () {
    const defaults = SpendLimits();
    expect(defaults.enabled, isFalse);
    expect(defaults.warningPercent, 80);
    expect(defaults.hardStop, isFalse);
    final limits = defaults.patch({'chat_usd': 2.5, 'daily_tokens': 10000});
    expect(limits.enabled, isTrue);
    expect(limits.chatUsd, 2.5);
    expect(limits.dailyTokens, 10000);
    expect(limits.patch({'chat_usd': null}).chatUsd, isNull);
    expect(limits.patch({'chat_usd': null}).dailyTokens, 10000);
  });

  test('invalid patches cannot silently enable or discard a limit', () {
    for (final patch in <Map<String, dynamic>>[
      {'chat_usd': -1},
      {'chat_usd': double.nan},
      {'chat_usd': double.infinity},
      {'chat_tokens': 1.2},
      {'daily_tokens': 0},
      {'warning_percent': 0},
      {'warning_percent': 101},
      {'hard_stop': 'true'},
      {'unknown': 1},
      {},
    ]) {
      expect(() => const SpendLimits().patch(patch), throwsFormatException);
    }
    final limits = const SpendLimits().patch({
      'chat_usd': 0.01,
      'chat_tokens': 5,
      'daily_usd': 2,
      'daily_tokens': 20,
      'warning_percent': 90,
      'hard_stop': true,
    });
    expect(SpendLimits.fromJson(limits.toJson()).toJson(), limits.toJson());
    expect(SpendLimits.fromJson({'chat_usd': -1}).enabled, isFalse);
  });
}
