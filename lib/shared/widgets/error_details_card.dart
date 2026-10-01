import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../l10n/app_localizations.dart';
import 'ios_tactile.dart';

/// An already-safe failure reason with optional, initially collapsed details.
class ErrorDetailsCard extends StatefulWidget {
  const ErrorDetailsCard({super.key, this.message, this.details});

  final String? message;
  final String? details;

  @override
  State<ErrorDetailsCard> createState() => _ErrorDetailsCardState();
}

class _ErrorDetailsCardState extends State<ErrorDetailsCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final message = widget.message;
    final details = widget.details;
    final hasDetails = details?.trim().isNotEmpty == true;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.2),
        border: Border.all(color: cs.error.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (message?.isNotEmpty == true)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(LucideIcons.circleAlert, size: 18, color: cs.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    message!,
                    style: TextStyle(
                      color: cs.error,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          if (hasDetails) ...[
            if (message?.isNotEmpty == true) const SizedBox(height: 8),
            Semantics(
              button: true,
              expanded: _expanded,
              child: IosCardPress(
                baseColor: Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                padding: const EdgeInsets.symmetric(vertical: 6),
                onTap: () => setState(() => _expanded = !_expanded),
                child: Row(
                  children: [
                    Icon(
                      _expanded
                          ? LucideIcons.chevronUp
                          : LucideIcons.chevronDown,
                      size: 16,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _expanded
                            ? l10n.agentsHideDetails
                            : l10n.agentsShowDetails,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _expanded
                  ? Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: SelectableText(
                        details!,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          fontFamily: 'monospace',
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ],
      ),
    );
  }
}
