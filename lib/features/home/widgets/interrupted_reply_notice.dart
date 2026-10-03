import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_tile_button.dart';

/// Kept outside message content: an interrupted partial remains model history.
class InterruptedReplyNotice extends StatelessWidget {
  const InterruptedReplyNotice({super.key, this.onContinue});

  final VoidCallback? onContinue;

  static double estimateExtent(BuildContext context, double width) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    double height(String text, TextStyle? style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: math.max(80, width - 52));
      final result = painter.height;
      painter.dispose();
      return result;
    }

    return 24 +
        8 +
        6 +
        8 +
        40 +
        height(
          l10n.generationInterrupted,
          theme.textTheme.bodyMedium?.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ) +
        height(
          l10n.chatInterruptedBody,
          theme.textTheme.bodySmall?.copyWith(fontSize: 12),
        );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.generationInterrupted,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.chatInterruptedBody,
            style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
          ),
          const SizedBox(height: 8),
          IosTileButton(
            label: l10n.chatContinueAfterInterruption,
            icon: LucideIcons.arrowRight,
            enabled: onContinue != null,
            onTap: onContinue ?? () {},
          ),
        ],
      ),
    );
  }
}
