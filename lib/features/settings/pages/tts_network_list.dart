part of 'tts_services_page.dart';

class _MobileNetworkTtsList extends StatefulWidget {
  const _MobileNetworkTtsList({required this.services});

  final List<TtsServiceOptions> services;

  @override
  State<_MobileNetworkTtsList> createState() => _MobileNetworkTtsListState();
}

class _MobileNetworkTtsListState extends State<_MobileNetworkTtsList> {
  final Map<String, bool> _testing = <String, bool>{};
  final Map<String, String?> _errors = <String, String?>{};

  Future<void> _reorder(int oldIndex, int newIndex) async {
    final settings = context.read<SettingsProvider>();
    final updated = reorderVoiceServiceList(
      settings.ttsServices,
      oldIndex,
      newIndex,
    );
    if (identical(updated, settings.ttsServices)) return;
    await settings.setTtsServices(updated);
  }

  Future<void> _test(TtsServiceOptions service) async {
    final id = service.id;
    setState(() {
      _testing[id] = true;
      _errors[id] = null;
    });
    final demo = AppLocalizations.of(context)!.ttsServicesPageTestSpeechText;
    final err = await context.read<TtsProvider>().testNetworkService(
      service,
      demo,
    );
    if (!mounted) return;
    setState(() {
      _testing[id] = false;
      _errors[id] = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    final services = widget.services;
    return SliverReorderableList(
      itemCount: services.length,
      onReorderItem: _reorder,
      onReorderStart: (_) {
        Tooltip.dismissAllToolTips();
        Haptics.light();
      },
      proxyDecorator: voiceServiceDragProxy,
      itemBuilder: (context, index) {
        final service = services[index];
        return Column(
          key: ValueKey('mobile-tts-${service.id}'),
          mainAxisSize: MainAxisSize.min,
          children: [
            ReorderableDelayedDragStartListener(
              index: index,
              child: _NetworkTtsRowMobile(
                service: service,
                index: index,
                testing: _testing[service.id] == true,
                error: _errors[service.id],
                onTest: () => _test(service),
              ),
            ),
            if (index != services.length - 1) _iosDivider(context),
          ],
        );
      },
    );
  }
}

class _NetworkTtsRowMobile extends StatelessWidget {
  const _NetworkTtsRowMobile({
    required this.service,
    required this.index,
    required this.testing,
    required this.error,
    required this.onTest,
  });

  final TtsServiceOptions service;
  final int index;
  final bool testing;
  final String? error;
  final VoidCallback onTest;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final displayName = service.name.trim().isEmpty
        ? networkTtsKindDisplayName(service.kind)
        : service.name.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TactileRow(
          pressedScale: 0.98,
          haptics: false,
          onTap: () async => context
              .read<SettingsProvider>()
              .setSelectedTtsServiceId(service.id),
          builder: (pressed) {
            final base = cs.onSurface.withValues(alpha: 0.9);
            return _AnimatedPressColor(
              pressed: pressed,
              base: base,
              builder: (c) {
                final isDark = Theme.of(context).brightness == Brightness.dark;
                final overlay = pressed
                    ? cs.surface.withValues(alpha: isDark ? 0.06 : 0.05)
                    : Colors.transparent;
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 11,
                  ),
                  child: Row(
                    children: [
                      _AvatarBrandBadge(name: displayName, overlay: overlay),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            color: c,
                            fontWeight: AppFontWeights.semibold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _SmallTactileIcon(
                        icon: Lucide.Settings2,
                        baseColor: c,
                        onTap: () async {
                          final sp = context.read<SettingsProvider>();
                          final updated = await _showEditNetworkTtsSheet(
                            context,
                            service,
                          );
                          if (updated != null) {
                            final list = List<TtsServiceOptions>.from(
                              sp.ttsServices,
                            );
                            list[index] = updated;
                            await sp.setTtsServices(list);
                          }
                        },
                      ),
                      const SizedBox(width: 6),
                      _SmallTactileIcon(
                        icon: testing ? Lucide.Loader : Lucide.Volume2,
                        baseColor: c,
                        onTap: onTest,
                      ),
                      const SizedBox(width: 6),
                      _SmallTactileIcon(
                        icon: Lucide.Trash2,
                        baseColor: c,
                        onTap: () async {
                          final sp = context.read<SettingsProvider>();
                          final list = List<TtsServiceOptions>.from(
                            sp.ttsServices,
                          );
                          list.removeAt(index);
                          await sp.setTtsServices(list);
                        },
                      ),
                      const SizedBox(width: 8),
                      Builder(
                        builder: (_) {
                          final sp2 = context.watch<SettingsProvider>();
                          final sel = sp2.selectedTtsServiceId == service.id;
                          return sel
                              ? Icon(Lucide.Check, size: 16, color: c)
                              : const SizedBox(width: 16);
                        },
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
        if (error != null && error!.isNotEmpty) ...[
          const SizedBox(height: 6),
          _ErrorInlineMobile(message: error!),
        ],
      ],
    );
  }
}

class _ErrorInlineMobile extends StatelessWidget {
  const _ErrorInlineMobile({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final oneLine = message.replaceAll('\n', ' ');
    return Container(
      decoration: BoxDecoration(
        color: cs.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.error.withValues(alpha: 0.3), width: 0.6),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              oneLine,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: cs.error),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => _showMobileErrorDetails(context, message),
            child: Text(l10n.ttsServicesViewDetailsButton),
          ),
        ],
      ),
    );
  }
}

void _showMobileErrorDetails(BuildContext context, String message) {
  final cs = Theme.of(context).colorScheme;
  final l10n = AppLocalizations.of(context)!;
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.overlaySurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurface.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  l10n.ttsServicesDialogErrorTitle,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: AppFontWeights.emphasis,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SelectableText(
                message,
                style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.9),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).maybePop(),
                  child: Text(l10n.ttsServicesCloseButton),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
