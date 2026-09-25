import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_semantic_colors.dart';
import '../../chat/widgets/token_display_widget.dart';

/// How full the model's context window is, as a small ring by the send
/// button. Tapping it shows the numbers.
class ContextUsageRing extends StatelessWidget {
  const ContextUsageRing({
    super.key,
    required this.usedTokens,
    required this.windowTokens,
  });

  /// Tokens the next request starts from.
  final int usedTokens;

  /// The model's context window, or null when it is unknown.
  final int? windowTokens;

  /// Fill from 0 to 1, or null when the window is unknown.
  double? get ratio {
    final window = windowTokens;
    if (window == null || window <= 0) return null;
    return usedTokens / window;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final ratio = this.ratio;
    final color = ratio == null
        ? cs.onSurface.withValues(alpha: 0.35)
        : ratio >= 0.85
        ? (ratio >= 1 ? cs.error : context.appColors.warning)
        : cs.primary;
    final used = TokenStatsRow.compact(usedTokens);
    final message = ratio == null
        ? l10n.contextUsageUnknownWindow(used)
        : l10n.contextUsageTooltip(
            used,
            TokenStatsRow.compact(windowTokens!),
            (ratio * 100).round(),
          );
    return Tooltip(
      message: message,
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 4),
      child: Semantics(
        label: message,
        child: SizedBox(
          width: 32,
          height: 32,
          child: Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: (ratio ?? 0).clamp(0.0, 1.0)),
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) => CustomPaint(
                  painter: _RingPainter(
                    progress: value,
                    color: color,
                    trackColor: cs.onSurface.withValues(alpha: 0.12),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
  });

  final double progress;
  final Color color;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 2.5;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = trackColor);
    if (progress <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      paint..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.trackColor != trackColor;
}
