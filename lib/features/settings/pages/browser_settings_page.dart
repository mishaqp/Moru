import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../features/home/services/browser_agent_actions.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_switch.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../theme/app_font_weights.dart';

/// One named, collapsible group of `browser_use` actions. The action ids
/// are the single source of truth (`BrowserAgentActions.all`); this only
/// says which group each id belongs to.
class _ActionGroup {
  const _ActionGroup({
    required this.titleBuilder,
    required this.subtitleBuilder,
    required this.actionIds,
  });

  final String Function(AppLocalizations l10n) titleBuilder;
  final String Function(AppLocalizations l10n) subtitleBuilder;
  final List<String> actionIds;
}

final List<_ActionGroup> _groups = [
  _ActionGroup(
    titleBuilder: (l10n) => l10n.browserSettingsGroupNavigation,
    subtitleBuilder: (l10n) => l10n.browserSettingsGroupNavigationDesc,
    actionIds: const ['open', 'back', 'forward', 'reload', 'scroll'],
  ),
  _ActionGroup(
    titleBuilder: (l10n) => l10n.browserSettingsGroupReadPage,
    subtitleBuilder: (l10n) => l10n.browserSettingsGroupReadPageDesc,
    actionIds: const ['observe', 'read', 'wait_for'],
  ),
  _ActionGroup(
    titleBuilder: (l10n) => l10n.browserSettingsGroupInteraction,
    subtitleBuilder: (l10n) => l10n.browserSettingsGroupInteractionDesc,
    actionIds: const ['click', 'type', 'submit', 'press_key'],
  ),
  _ActionGroup(
    titleBuilder: (l10n) => l10n.browserSettingsGroupAdvanced,
    subtitleBuilder: (l10n) => l10n.browserSettingsGroupAdvancedDesc,
    actionIds: const ['eval_js', 'done', 'close'],
  ),
];

/// Per-action `browser_use` toggles, grouped by what the action actually
/// does (navigation / reading / interacting / advanced) rather than by
/// whether it happens to require an approval prompt -- so an action can
/// still be turned off individually instead of only through the
/// all-or-nothing tool trust switch.
class BrowserSettingsPage extends StatelessWidget {
  const BrowserSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsProvider>();
    final ru = Localizations.localeOf(context).languageCode == 'ru';

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
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
            child: Text(
              l10n.browserSettingsIntro,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: cs.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          const SizedBox(height: 4),
          _TrustStateBanner(
            trusted: settings.toolAutoApproveAll,
            label: settings.toolAutoApproveAll
                ? l10n.browserSettingsTrustOn
                : l10n.browserSettingsTrustOff,
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < _groups.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            _ActionGroupCard(
              group: _groups[i],
              settings: settings,
              ru: ru,
              l10n: l10n,
            ),
          ],
        ],
      ),
    );
  }
}

class _TrustStateBanner extends StatelessWidget {
  const _TrustStateBanner({required this.trusted, required this.label});

  final bool trusted;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = trusted ? cs.primary : cs.onSurface.withValues(alpha: 0.55);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: trusted
            ? cs.primary.withValues(alpha: isDark ? 0.16 : 0.08)
            : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(trusted ? Lucide.Shield : Lucide.Lock, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: AppFontWeights.medium,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionGroupCard extends StatelessWidget {
  const _ActionGroupCard({
    required this.group,
    required this.settings,
    required this.ru,
    required this.l10n,
  });

  final _ActionGroup group;
  final SettingsProvider settings;
  final bool ru;
  final AppLocalizations l10n;

  List<BrowserAgentAction> get _actions => group.actionIds
      .map(BrowserAgentActions.byId)
      .whereType<BrowserAgentAction>()
      .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final actions = _actions;
    final enabledCount = actions
        .where((a) => !settings.disabledBrowserActions.contains(a.id))
        .length;

    return Material(
      color: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outline.withValues(alpha: 0.12)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          tilePadding: const EdgeInsets.fromLTRB(14, 2, 10, 2),
          childrenPadding: EdgeInsets.zero,
          title: Text(
            group.titleBuilder(l10n),
            style: TextStyle(
              fontWeight: AppFontWeights.semibold,
              fontSize: 14,
              color: cs.onSurface.withValues(alpha: 0.92),
            ),
          ),
          subtitle: Text(
            group.subtitleBuilder(l10n),
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurface.withValues(alpha: 0.55),
            ),
          ),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: isDark ? 0.18 : 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              l10n.browserSettingsGroupEnabledCount(
                enabledCount,
                actions.length,
              ),
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: AppFontWeights.emphasis,
                color: cs.primary,
              ),
            ),
          ),
          children: [
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0) _divider(context),
              _actionRow(context, actions[i], settings, ru),
            ],
          ],
        ),
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
