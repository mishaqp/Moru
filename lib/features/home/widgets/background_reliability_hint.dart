import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../core/services/background_reliability.dart';
import '../../../core/services/mobile_background.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/ios_tile_button.dart';
import '../../../shared/widgets/section_card.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../settings/pages/mobile_background_settings_page.dart';

class BackgroundReliabilityHint extends StatefulWidget {
  const BackgroundReliabilityHint({
    super.key,
    this.coordinator,
    this.onOpenSettings,
  });

  final MobileBackgroundCoordinator? coordinator;
  final VoidCallback? onOpenSettings;

  @override
  State<BackgroundReliabilityHint> createState() =>
      _BackgroundReliabilityHintState();
}

class _BackgroundReliabilityHintState extends State<BackgroundReliabilityHint> {
  late final coordinator =
      widget.coordinator ?? MobileBackgroundCoordinator.instance;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    unawaited(coordinator.refreshStatus());
  }

  Future<void> _dismiss() async {
    if (_saving) return;
    final settings = context.read<SettingsProvider>();
    setState(() => _saving = true);
    try {
      await settings.setMobileBackground(
        settings.mobileBackground.copyWith(reliabilityHintDismissed: true),
      );
    } catch (_) {
      if (mounted) {
        showAppSnackBar(
          context,
          message: AppLocalizations.of(
            context,
          )!.modelDetailSheetSaveFailedMessage,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!coordinator.supported) return const SizedBox.shrink();
    final settings = context.watch<SettingsProvider>().mobileBackground;
    return ListenableBuilder(
      listenable: coordinator,
      builder: (context, _) {
        final risk = backgroundReliabilityRisk(
          settings: settings,
          status: coordinator.status,
          hasActiveWork: coordinator.hasActiveWork,
        );
        if (risk == null) return const SizedBox.shrink();
        final l = AppLocalizations.of(context)!;
        final body = switch (risk) {
          BackgroundReliabilityRisk.disabled =>
            l.backgroundReliabilityHintDisabled,
          BackgroundReliabilityRisk.restricted =>
            l.backgroundReliabilityHintRestricted,
          BackgroundReliabilityRisk.standby =>
            l.backgroundReliabilityHintStandby,
          BackgroundReliabilityRisk.manufacturer =>
            l.backgroundReliabilityHintVendor,
          BackgroundReliabilityRisk.interrupted =>
            l.backgroundReliabilityHintInterrupted,
          BackgroundReliabilityRisk.protectionUnavailable =>
            l.backgroundProtectionUnavailable,
        };
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: SectionCard(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 6, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Lucide.Battery, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(l.backgroundReliabilityHintTitle)),
                        IosIconButton(
                          key: const ValueKey(
                            'dismissBackgroundReliabilityHint',
                          ),
                          icon: Lucide.X,
                          minSize: 44,
                          semanticLabel: l.backgroundReliabilityHintDismiss,
                          tooltip: l.backgroundReliabilityHintDismiss,
                          enabled: !_saving,
                          onTap: () => unawaited(_dismiss()),
                        ),
                      ],
                    ),
                    Text(body, style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 10),
                    IosTileButton(
                      label: l.backgroundReliabilityHintSettings,
                      icon: Lucide.Settings,
                      onTap:
                          widget.onOpenSettings ??
                          () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => MobileBackgroundSettingsPage(
                                  coordinator: coordinator,
                                ),
                              ),
                            );
                          },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
