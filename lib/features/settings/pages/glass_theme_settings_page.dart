import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_settings_rows.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/section_card.dart';

/// Appearance → Glass: the frosted look over a colour backdrop.
class GlassThemeSettingsPage extends StatelessWidget {
  const GlassThemeSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final glass = context.select<SettingsProvider, (bool, GlassFrost, bool)>(
      (s) => (s.glassTheme, s.glassFrost, s.glassEconomy),
    );
    final settings = context.read<SettingsProvider>();
    String frostLabel(GlassFrost frost) => switch (frost) {
      GlassFrost.soft => l10n.glassFrostSoft,
      GlassFrost.medium => l10n.glassFrostMedium,
      GlassFrost.strong => l10n.glassFrostStrong,
    };

    return Scaffold(
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
        title: Text(l10n.glassThemeTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          SectionCard(
            children: [
              IosSwitchRow(
                key: const ValueKey('glassTheme'),
                icon: Lucide.Sparkles,
                label: l10n.glassThemeEnable,
                subtitle: l10n.glassThemeEnableDetail,
                value: glass.$1,
                onChanged: settings.setGlassTheme,
              ),
            ],
          ),
          IosSectionHeader(text: l10n.glassFrostTitle),
          SectionCard(
            children: [
              for (final frost in GlassFrost.values) ...[
                if (frost != GlassFrost.values.first) const IosRowDivider(),
                IosNavRow(
                  key: ValueKey('glassFrost-${frost.name}'),
                  label: frostLabel(frost),
                  trailing: frost == glass.$2
                      ? Icon(Lucide.Check, size: 18, color: cs.primary)
                      : const SizedBox(width: 18),
                  onTap: () => settings.setGlassFrost(frost),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          SectionCard(
            children: [
              IosSwitchRow(
                key: const ValueKey('glassEconomy'),
                icon: Lucide.Battery,
                label: l10n.glassEconomyTitle,
                subtitle: l10n.glassEconomyDetail,
                value: glass.$3,
                onChanged: settings.setGlassEconomy,
              ),
            ],
          ),
          IosSectionFooter(text: l10n.glassThemeFooter),
        ],
      ),
    );
  }
}
