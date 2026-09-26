part of 'display_settings_page.dart';

class HapticsSettingsPage extends StatelessWidget {
  const HapticsSettingsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final sp = context.read<SettingsProvider>();
    // Rebuild only for the settings this page shows.
    context.select<SettingsProvider, Object>(
      (s) => (
        s.hapticsGlobalEnabled,
        s.hapticsIosSwitch,
        s.hapticsOnCardTap,
        s.hapticsOnDrawer,
        s.hapticsOnGenerate,
        s.hapticsOnListItemTap,
      ),
    );
    return Scaffold(
      appBar: AppBar(
        leading: Tooltip(
          message: l10n.settingsPageBackButton,
          child: _TactileIconButton(
            icon: Lucide.ArrowLeft,
            color: cs.onSurface,
            size: 22,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ),
        title: Text(l10n.displaySettingsPageHapticsSettingsTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          SectionCard(
            children: [
              _iosSwitchRow(
                context,
                icon: Lucide.Vibrate,
                label: l10n.displaySettingsPageHapticsGlobalTitle,
                value: sp.hapticsGlobalEnabled,
                onChanged: (v) =>
                    context.read<SettingsProvider>().setHapticsGlobalEnabled(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.toggleRight,
                label: l10n.displaySettingsPageHapticsIosSwitchTitle,
                value: sp.hapticsIosSwitch,
                onChanged: (v) =>
                    context.read<SettingsProvider>().setHapticsIosSwitch(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.panelRight,
                label: l10n.displaySettingsPageHapticsOnSidebarTitle,
                value: sp.hapticsOnDrawer,
                onChanged: (v) =>
                    context.read<SettingsProvider>().setHapticsOnDrawer(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.ListOrdered,
                label: l10n.displaySettingsPageHapticsOnListItemTapTitle,
                value: sp.hapticsOnListItemTap,
                onChanged: (v) =>
                    context.read<SettingsProvider>().setHapticsOnListItemTap(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.Square,
                label: l10n.displaySettingsPageHapticsOnCardTapTitle,
                value: sp.hapticsOnCardTap,
                onChanged: (v) =>
                    context.read<SettingsProvider>().setHapticsOnCardTap(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.Vibrate,
                label: l10n.displaySettingsPageHapticsOnGenerateTitle,
                value: sp.hapticsOnGenerate,
                onChanged: (v) =>
                    context.read<SettingsProvider>().setHapticsOnGenerate(v),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
