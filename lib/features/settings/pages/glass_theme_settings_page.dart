import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_settings_rows.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/section_card.dart';
import '../../../theme/custom_theme.dart';
import '../../../theme/palettes.dart';

/// Appearance → Glass: a one-tap preset for the frosted look. The message
/// style it writes stays editable in Message style; turning it off restores
/// the previous one.
class GlassThemeSettingsPage extends StatelessWidget {
  const GlassThemeSettingsPage({super.key});

  /// The palette accent for the user's bubbles in light and dark mode.
  static (Color, Color) _accents(BuildContext context) {
    final settings = context.read<SettingsProvider>();
    if (settings.useDynamicColor) {
      final current = Theme.of(context).colorScheme.primary;
      return (current, current);
    }
    final custom = settings.selectedCustomTheme;
    final palette =
        settings.themePaletteId == ThemePalettes.customPaletteId &&
            custom != null
        ? buildCustomThemePalette(custom)
        : ThemePalettes.byId(settings.themePaletteId);
    return (palette.light.primary, palette.dark.primary);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final glass = context.select<SettingsProvider, (bool, bool)>(
      (s) => (s.glassTheme, s.glassEconomy),
    );
    final settings = context.read<SettingsProvider>();

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
                onChanged: (on) {
                  final accents = _accents(context);
                  settings.setGlassTheme(
                    on,
                    accentLight: accents.$1,
                    accentDark: accents.$2,
                  );
                },
              ),
              const IosRowDivider(),
              IosSwitchRow(
                key: const ValueKey('glassEconomy'),
                icon: Lucide.Battery,
                label: l10n.glassEconomyTitle,
                subtitle: l10n.glassEconomyDetail,
                value: glass.$2,
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
