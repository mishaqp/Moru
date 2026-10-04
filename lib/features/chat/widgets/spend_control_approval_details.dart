import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';

/// Human-readable changes on the ordinary approval card.
class SpendControlApprovalDetails extends StatelessWidget {
  const SpendControlApprovalDetails({super.key, required this.arguments});
  final Map<String, dynamic> arguments;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final labels = {
      'chat_usd': l.spendChatUsd,
      'chat_tokens': l.spendChatTokens,
      'daily_usd': l.spendDailyUsd,
      'daily_tokens': l.spendDailyTokens,
      'warning_percent': l.spendWarningThreshold,
      'hard_stop': l.spendHardStop,
    };
    final changes = <String, dynamic>{
      if (arguments['limits'] is Map)
        ...Map<String, dynamic>.from(arguments['limits'] as Map),
      if (arguments['clear'] is List)
        for (final key in arguments['clear'] as List)
          if (key is String && labels.containsKey(key)) key: null,
    };
    String value(String key, Object? value) => value == null
        ? l.spendDisabled
        : value is bool
        ? value
              ? l.skillsEnabled
              : l.spendDisabled
        : key == 'warning_percent'
        ? '$value%'
        : '$value';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (arguments['action'] == 'compact') Text(l.spendCompactNote),
        for (final entry in changes.entries)
          if (labels.containsKey(entry.key))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                '${labels[entry.key]}: ${value(entry.key, entry.value)}',
              ),
            ),
      ],
    );
  }
}
