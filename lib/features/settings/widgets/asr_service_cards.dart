part of 'asr_services_section.dart';

class _EmptyAsrState extends StatelessWidget {
  const _EmptyAsrState();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final content = Padding(
      padding: EdgeInsets.symmetric(vertical: 22, horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.asrServicesEmptyTitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: cs.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.asrServicesEmptySubtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
    return VoiceServiceMobileCard(children: [content]);
  }
}

class _AsrServiceCard extends StatefulWidget {
  const _AsrServiceCard({
    required this.service,
    required this.selected,
    required this.modelManager,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
  });

  final AsrServiceOptions service;
  final bool selected;
  final SherpaModelManager modelManager;
  final VoidCallback onSelect;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  State<_AsrServiceCard> createState() => _AsrServiceCardState();
}

class _AsrServiceCardState extends State<_AsrServiceCard> {
  @override
  Widget build(BuildContext context) {
    return _buildMobile(context);
  }

  Widget _buildMobile(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final displayName = _serviceDisplayName(l10n, widget.service);
    return VoiceServiceTactileRow(
      onTap: widget.onSelect,
      builder: (pressed) => AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        color: pressed
            ? cs.onSurface.withValues(alpha: 0.05)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          children: [
            _ProviderBadge(kind: widget.service.kind, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      color: cs.onSurface.withValues(alpha: 0.9),
                      fontWeight: AppFontWeights.semibold,
                    ),
                  ),
                  const SizedBox(height: 3),
                  _ServiceSubtitle(
                    service: widget.service,
                    modelManager: widget.modelManager,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            VoiceServiceSmallIconButton(
              icon: Lucide.Settings2,
              tooltip: l10n.asrServicesEditAction,
              onTap: widget.onEdit,
            ),
            const SizedBox(width: 6),
            VoiceServiceSmallIconButton(
              icon: Lucide.Trash2,
              tooltip: l10n.asrServicesDeleteAction,
              onTap: widget.onDelete,
            ),
            const SizedBox(width: 8),
            widget.selected
                ? Icon(
                    Lucide.Check,
                    size: 16,
                    color: cs.onSurface.withValues(alpha: 0.9),
                  )
                : const SizedBox(width: 16),
          ],
        ),
      ),
    );
  }
}

class _ServiceSubtitle extends StatelessWidget {
  const _ServiceSubtitle({required this.service, required this.modelManager});

  final AsrServiceOptions service;
  final SherpaModelManager modelManager;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final style = TextStyle(
      fontSize: 12,
      color: cs.onSurface.withValues(alpha: 0.60),
    );
    if (service case final SherpaOnnxAsrOptions local) {
      final model = SherpaModelCatalog.byId(local.modelId);
      return FutureBuilder<bool>(
        future: local.modelId.isEmpty
            ? Future<bool>.value(false)
            : modelManager.isInstalled(local.modelId),
        builder: (context, snapshot) {
          final status = snapshot.data == true
              ? l10n.asrServicesModelDownloadedLabel
              : l10n.asrServicesModelNotDownloadedLabel;
          final name = model?.name ?? l10n.asrServicesLocalSubtitle;
          return Text(
            '$name · $status',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          );
        },
      );
    }
    return Text(
      _kindSubtitle(l10n, service.kind),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
}

class _ProviderBadge extends StatelessWidget {
  const _ProviderBadge({required this.kind, this.size = 36});

  final AsrServiceKind kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final asset = _kindBrandAsset(kind);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.11),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: asset == null
          ? Icon(_kindIcon(kind), size: size * 0.5, color: cs.primary)
          : asset.endsWith('.svg')
          ? SvgPicture.asset(
              asset,
              width: size * 0.56,
              height: size * 0.56,
              colorFilter: isDark && BrandAssets.assetNeedsDarkInvert(asset)
                  ? ColorFilter.mode(cs.onSurface, BlendMode.srcIn)
                  : null,
            )
          : Image.asset(
              asset,
              width: size * 0.56,
              height: size * 0.56,
              fit: BoxFit.contain,
            ),
    );
  }
}

String? _kindBrandAsset(AsrServiceKind kind) {
  final hint = switch (kind) {
    AsrServiceKind.openAiRealtime => 'OpenAI',
    AsrServiceKind.dashScope => 'Qwen',
    AsrServiceKind.qwenAudio => 'Qwen',
    AsrServiceKind.volcengine => 'Doubao',
    AsrServiceKind.mimo => 'MiMo',
    AsrServiceKind.step => 'Step',
    AsrServiceKind.sherpaOnnx || AsrServiceKind.system => '',
  };
  return hint.isEmpty ? null : BrandAssets.assetForName(hint);
}
