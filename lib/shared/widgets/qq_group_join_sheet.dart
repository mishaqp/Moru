import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../icons/lucide_adapter.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_font_weights.dart';
import 'custom_bottom_sheet.dart';
import 'ios_tactile.dart';

class _QQGroupEntry {
  const _QQGroupEntry({required this.name, required this.joinUrl});

  final String name;
  final String joinUrl;
}

List<_QQGroupEntry> _groups(AppLocalizations l10n) => <_QQGroupEntry>[
  _QQGroupEntry(
    name: l10n.aboutPageQQGroupOne,
    joinUrl: 'https://qm.qq.com/q/OQaXetKssC',
  ),
  _QQGroupEntry(
    name: l10n.aboutPageQQGroupTwo,
    joinUrl: 'https://qm.qq.com/q/7t6VEqSXhm',
  ),
  _QQGroupEntry(
    name: l10n.aboutPageQQGroupThree,
    joinUrl: 'https://qm.qq.com/q/ebEJBgvDMs',
  ),
];

Future<void> _openJoinUrl(String url) async {
  final uri = Uri.parse(url);
  try {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      await launchUrl(uri, mode: LaunchMode.platformDefault);
    }
  } catch (_) {
    await launchUrl(uri);
  }
}

/// Shows the "join QQ group" picker: a bottom sheet on mobile, a dialog on
/// desktop. Tapping an entry opens its join link directly.
Future<void> showQQGroupJoinSheet({required BuildContext context}) {
  final l10n = AppLocalizations.of(context)!;
  final groups = _groups(l10n);

  return showCustomBottomSheet<void>(
    context: context,
    title: l10n.aboutPageJoinQQGroup,
    closeSemanticLabel: l10n.mcpPageClose,
    partialHeightFactor: 0.50,
    expandedHeightFactor: 0.50,
    builder: (sheetContext, controller) => ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        for (final entry in groups)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _QQGroupRow(
              entry: entry,
              onTap: () {
                Navigator.of(sheetContext).maybePop();
                _openJoinUrl(entry.joinUrl);
              },
            ),
          ),
      ],
    ),
  );
}

class _QQGroupRow extends StatelessWidget {
  const _QQGroupRow({required this.entry, required this.onTap});

  final _QQGroupEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return IosCardPress(
      borderRadius: BorderRadius.circular(12),
      baseColor: isDark
          ? cs.surfaceContainerHighest.withValues(alpha: 0.50)
          : cs.surfaceContainerHighest.withValues(alpha: 0.45),
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Row(
        children: [
          SvgPicture.asset(
            'assets/icons/tencent-qq.svg',
            width: 20,
            height: 20,
            colorFilter: ColorFilter.mode(
              cs.onSurface.withValues(alpha: 0.9),
              BlendMode.srcIn,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              entry.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: AppFontWeights.semibold,
                color: cs.onSurface.withValues(alpha: 0.9),
              ),
            ),
          ),
          Icon(
            Lucide.ChevronRight,
            size: 16,
            color: cs.onSurface.withValues(alpha: 0.6),
          ),
        ],
      ),
    );
  }
}
