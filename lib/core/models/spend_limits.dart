/// Global, optional budgets. Cached input is included in the token budget once.
class SpendLimits {
  const SpendLimits({
    this.chatUsd,
    this.chatTokens,
    this.dailyUsd,
    this.dailyTokens,
    this.warningPercent = 80,
    this.hardStop = false,
  });

  final double? chatUsd;
  final int? chatTokens;
  final double? dailyUsd;
  final int? dailyTokens;
  final int warningPercent;
  final bool hardStop;

  bool get enabled =>
      chatUsd != null ||
      chatTokens != null ||
      dailyUsd != null ||
      dailyTokens != null;

  Map<String, dynamic> toJson() => {
    'chat_usd': chatUsd,
    'chat_tokens': chatTokens,
    'daily_usd': dailyUsd,
    'daily_tokens': dailyTokens,
    'warning_percent': warningPercent,
    'hard_stop': hardStop,
  };

  factory SpendLimits.fromJson(Map<String, dynamic> json) {
    try {
      return json.isEmpty
          ? const SpendLimits()
          : const SpendLimits().patch(json);
    } on FormatException {
      return const SpendLimits();
    }
  }

  /// Validate the whole edit before changing anything. Null disables a budget.
  SpendLimits patch(Map<String, dynamic> changes) {
    final values = toJson();
    if (changes.isEmpty ||
        changes.keys.any((key) => !values.containsKey(key))) {
      throw const FormatException('Supply only supported limit fields.');
    }
    values.addAll(changes);
    double? dollars(String key) {
      final value = values[key];
      if (value == null) return null;
      if (value is! num || !value.isFinite || value <= 0) {
        throw FormatException('$key must be a positive finite number or null.');
      }
      return value.toDouble();
    }

    int? tokens(String key) {
      final value = values[key];
      if (value == null) return null;
      if (value is! num ||
          !value.isFinite ||
          value <= 0 ||
          value != value.toInt()) {
        throw FormatException('$key must be a positive integer or null.');
      }
      return value.toInt();
    }

    final warning = values['warning_percent'];
    final stop = values['hard_stop'];
    if (warning is! int || warning < 1 || warning > 100) {
      throw const FormatException(
        'warning_percent must be an integer from 1 to 100.',
      );
    }
    if (stop is! bool) {
      throw const FormatException('hard_stop must be a boolean.');
    }
    return SpendLimits(
      chatUsd: dollars('chat_usd'),
      chatTokens: tokens('chat_tokens'),
      dailyUsd: dollars('daily_usd'),
      dailyTokens: tokens('daily_tokens'),
      warningPercent: warning,
      hardStop: stop,
    );
  }
}
