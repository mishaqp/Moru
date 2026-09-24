import 'package:flutter/material.dart';

import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';

/// Token usage of one reply as a single quiet line under it:
/// `↑ 18.4k  ⛁ 18.2k  ↓ 537  ⚡ 259.5 tok/s  ⏱ 2.1 s`.
///
/// Every figure is visible at once, with no popup. Items without data are
/// left out; when the provider only reports a total, that total is shown.
class TokenStatsRow extends StatelessWidget {
  const TokenStatsRow({
    super.key,
    required this.totalTokens,
    this.promptTokens,
    this.completionTokens,
    this.cachedTokens,
    this.durationMs,
  });

  final int totalTokens;
  final int? promptTokens;
  final int? completionTokens;
  final int? cachedTokens;
  final int? durationMs;

  /// 537 → "537", 1234 → "1.2k", 18450 → "18.4k", 1250000 → "1.3M".
  static String compact(int value) {
    if (value < 1000) return '$value';
    if (value < 1000000) {
      final k = value / 1000;
      return '${k < 100 ? _trim(k.toStringAsFixed(1)) : k.round()}k';
    }
    return '${_trim((value / 1000000).toStringAsFixed(1))}M';
  }

  static String _trim(String number) =>
      number.endsWith('.0') ? number.substring(0, number.length - 2) : number;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final color = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.5);
    final prompt = promptTokens ?? 0;
    final cached = cachedTokens ?? 0;
    final completion = completionTokens ?? 0;
    final duration = durationMs ?? 0;

    final items = <(IconData, String)>[];
    final spoken = <String>[];
    if (prompt > 0) {
      items.add((Lucide.ArrowUp, compact(prompt)));
      spoken.add(
        cached > 0
            ? l10n.tokenDetailPromptTokensWithCache(prompt, cached)
            : l10n.tokenDetailPromptTokens(prompt),
      );
      if (cached > 0) items.add((Lucide.Database, compact(cached)));
    }
    if (completion > 0) {
      items.add((Lucide.ArrowDown, compact(completion)));
      spoken.add(l10n.tokenDetailCompletionTokens(completion));
    }
    if (completion > 0 && duration > 0) {
      final speed = l10n.tokenDetailSpeed(
        (completion / (duration / 1000)).toStringAsFixed(1),
      );
      items.add((Lucide.Zap, speed));
      spoken.add(speed);
    }
    if (duration > 0) {
      final seconds = l10n.tokenDetailDuration(
        (duration / 1000).toStringAsFixed(1),
      );
      items.add((Lucide.Timer, seconds));
      spoken.add(seconds);
    }
    if (items.isEmpty) {
      final total = l10n.tokenDetailTotalTokens(totalTokens);
      items.add((Lucide.Hash, compact(totalTokens)));
      spoken.add(total);
    }

    return Semantics(
      label: spoken.join(', '),
      excludeSemantics: true,
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        children: [
          for (final (icon, text) in items)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 12, color: color),
                const SizedBox(width: 3),
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: color,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
