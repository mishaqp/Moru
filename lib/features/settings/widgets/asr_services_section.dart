import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/asr_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/asr/asr_service_options.dart';
import '../../../core/services/asr/sherpa_model_manager.dart';
import '../../../core/services/asr/system_asr_service.dart';
import '../../../core/services/haptics.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_tile_button.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../theme/app_font_weights.dart';
import '../../../utils/brand_assets.dart';
import 'voice_service_widgets.dart';
import '../utils/sherpa_model_l10n.dart';
import 'package:Kelivo/theme/app_semantic_colors.dart';

part 'asr_editor_widgets.dart';
part 'asr_service_cards.dart';
part 'asr_service_editor.dart';
part 'asr_service_helpers.dart';

/// The speech-recognition half of the Voice Services screen.
///
/// This widget deliberately owns only short-lived discovery/download helpers.
/// The selected provider and provider definitions stay in [SettingsProvider].
class AsrServicesSection extends StatefulWidget {
  const AsrServicesSection({super.key, this.modelManager});

  final SherpaModelManager? modelManager;

  @override
  State<AsrServicesSection> createState() => _AsrServicesSectionState();
}

class _AsrServicesSectionState extends State<AsrServicesSection> {
  late final SherpaModelManager _modelManager;
  late final bool _ownsModelManager;
  late final SystemAsrService _systemAsr;

  @override
  void initState() {
    super.initState();
    _ownsModelManager = widget.modelManager == null;
    _modelManager = widget.modelManager ?? SherpaModelManager();
    _systemAsr = SystemAsrService();
  }

  @override
  void dispose() {
    if (_ownsModelManager) _modelManager.dispose();
    unawaited(_systemAsr.dispose());
    super.dispose();
  }

  Future<void> _addService() async {
    final runtimeAsr = Provider.of<AsrProvider?>(context, listen: false);
    final created = await _showAsrEditor(
      context,
      modelManager: _modelManager,
      checkSystemAvailability:
          runtimeAsr?.checkSystemAvailability ?? _systemAsr.initialize,
    );
    if (!mounted || created == null) return;

    final settings = context.read<SettingsProvider>();
    final updated = List<AsrServiceOptions>.from(settings.asrServices)
      ..add(created);
    await settings.setAsrServices(updated);
    if (settings.selectedAsrServiceId == null) {
      await settings.setSelectedAsrServiceId(created.id);
    }
    if (created is SherpaOnnxAsrOptions) {
      await runtimeAsr?.refreshAvailability(created);
    }
  }

  Future<void> _editService(AsrServiceOptions service) async {
    final runtimeAsr = Provider.of<AsrProvider?>(context, listen: false);
    final edited = await _showAsrEditor(
      context,
      modelManager: _modelManager,
      checkSystemAvailability:
          runtimeAsr?.checkSystemAvailability ?? _systemAsr.initialize,
      initial: service,
    );
    if (!mounted || edited == null) return;

    final settings = context.read<SettingsProvider>();
    final updated = List<AsrServiceOptions>.from(settings.asrServices);
    final index = updated.indexWhere((item) => item.id == service.id);
    if (index < 0) return;
    updated[index] = edited;
    await settings.setAsrServices(updated);
    if (edited is SherpaOnnxAsrOptions) {
      await runtimeAsr?.refreshAvailability(edited);
    }
  }

  Future<void> _deleteService(AsrServiceOptions service) async {
    final settings = context.read<SettingsProvider>();
    final updated = List<AsrServiceOptions>.from(settings.asrServices)
      ..removeWhere((item) => item.id == service.id);
    await settings.setAsrServices(updated);
    if (settings.selectedAsrServiceId == service.id) {
      await settings.setSelectedAsrServiceId(
        updated.isEmpty ? null : updated.first.id,
      );
    }
  }

  Future<void> _reorderServices(int oldIndex, int newIndex) async {
    final settings = context.read<SettingsProvider>();
    final updated = reorderVoiceServiceList(
      settings.asrServices,
      oldIndex,
      newIndex,
    );
    if (identical(updated, settings.asrServices)) return;
    await settings.setAsrServices(updated);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsProvider>();
    final services = settings.asrServices;

    return SliverMainAxisGroup(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.only(top: 0),
          sliver: SliverToBoxAdapter(
            child: VoiceServiceSectionHeader(
              title: l10n.asrServicesSectionTitle,
              addTooltip: l10n.asrServicesAddTooltip,
              onAdd: _addService,
            ),
          ),
        ),
        if (services.isEmpty)
          SliverToBoxAdapter(child: _EmptyAsrState())
        else
          VoiceServiceCardSliver(
            sliver: SliverReorderableList(
              itemCount: services.length,
              onReorderItem: _reorderServices,
              onReorderStart: (_) {
                Tooltip.dismissAllToolTips();
                Haptics.light();
              },
              proxyDecorator: voiceServiceDragProxy,
              itemBuilder: (context, index) {
                final service = services[index];
                return Column(
                  key: ValueKey('asr-service-${service.id}'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ReorderableDelayedDragStartListener(
                      index: index,
                      child: _AsrServiceCard(
                        service: service,
                        selected: settings.selectedAsrServiceId == service.id,
                        modelManager: _modelManager,
                        onSelect: () =>
                            settings.setSelectedAsrServiceId(service.id),
                        onEdit: () => _editService(service),
                        onDelete: () => _deleteService(service),
                      ),
                    ),
                    if (index != services.length - 1)
                      voiceServiceMobileDivider(context),
                  ],
                );
              },
            ),
          ),
      ],
    );
  }
}
