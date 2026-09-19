import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../features/home/services/browser_agent_actions.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_switch.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/section_card.dart';
import '../../../theme/app_font_weights.dart';

/// Per-action `browser_use` toggles, so an action can be turned off
/// individually instead of only through the all-or-nothing tool trust switch.
class BrowserSettingsPage extends StatelessWidget {
  const BrowserSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsProvider>();
    final ru = Localizations.localeOf(context).languageCode == 'ru';
    final readActions = BrowserAgentActions.all
        .where((a) => !a.requiresApproval)
        .toList();
    final writeActions = BrowserAgentActions.all
        .where((a) => a.requiresApproval)
        .toList();

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        leading: Tooltip(
          message: l10n.settingsPageBackButton,
          child: IosIconButton(
            icon: Lucide.ArrowLeft,
            color: cs.onSurface,
            size: 22,
            minSize: 44,
            semanticLabel: l10n.settingsPageBackButton,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ),
        title: Text(l10n.settingsPageBrowser),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _groupHeader(
            context,
            ru ? 'Чтение' : 'Read',
            ru
                ? 'Не требуют подтверждения, даже без полного доверия.'
                : 'Never require approval, even without full trust.',
          ),
          SectionCard(
            padding: EdgeInsets.zero,
            children: [
              for (var i = 0; i < readActions.length; i++) ...[
                if (i > 0) _divider(context),
                _actionRow(context, readActions[i], settings, ru),
              ],
            ],
          ),
          const SizedBox(height: 18),
          _groupHeader(
            context,
            ru ? 'Запись' : 'Write',
            ru
                ? 'Требуют подтверждения, пока не включено полное доверие в инструментах.'
                : 'Require approval unless full tool trust is on.',
          ),
          SectionCard(
            padding: EdgeInsets.zero,
            children: [
              for (var i = 0; i < writeActions.length; i++) ...[
                if (i > 0) _divider(context),
                _actionRow(context, writeActions[i], settings, ru),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _groupHeader(BuildContext context, String title, String subtitle) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: AppFontWeights.semibold,
              color: cs.onSurface.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              height: 1.3,
              color: cs.onSurface.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Divider(
      height: 1,
      thickness: 1,
      color: cs.outline.withValues(alpha: 0.12),
    );
  }

  Widget _actionRow(
    BuildContext context,
    BrowserAgentAction action,
    SettingsProvider settings,
    bool ru,
  ) {
    final enabled = !settings.disabledBrowserActions.contains(action.id);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ru ? action.labelRu : action.labelEn,
                  style: TextStyle(fontWeight: AppFontWeights.semibold),
                ),
                const SizedBox(height: 2),
                Text(
                  ru ? action.descriptionRu : action.descriptionEn,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.3,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          IosSwitch(
            value: enabled,
            onChanged: (value) =>
                settings.setBrowserActionEnabled(action.id, value),
          ),
        ],
      ),
    );
  }
}
