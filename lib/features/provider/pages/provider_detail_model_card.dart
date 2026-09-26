part of 'provider_detail_page.dart';

class _ModelCard extends StatelessWidget {
  const _ModelCard({
    required this.providerKey,
    required this.modelId,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onSelectionChanged,
    this.detectionResult,
    this.detectionErrorMessage,
    this.isDetecting = false,
    this.isPending = false,
  });
  final String providerKey;
  final String modelId;
  final bool isSelectionMode;
  final bool isSelected;
  final ValueChanged<bool>? onSelectionChanged;
  final bool? detectionResult;
  final String? detectionErrorMessage;
  final bool isDetecting;
  final bool isPending;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final resolved = _resolveBaseAndOverride(context);
    final effective = resolved.ov == null
        ? resolved.base
        : _applyModelOverride(
            resolved.base,
            resolved.ov!,
            applyDisplayName: true,
          );
    String displayName = effective.displayName.trim();
    if (displayName.isEmpty) displayName = modelId;
    final Widget? detectionIndicator = isDetecting
        ? SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
          )
        : isPending
        ? Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: cs.onSurface.withValues(alpha: 0.3),
                width: 2,
              ),
            ),
          )
        : detectionResult != null
        ? MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Tooltip(
              message: detectionResult!
                  ? l10n.providerDetailPageDetectSuccess
                  : (detectionErrorMessage ??
                        l10n.providerDetailPageDetectFailed),
              child: Icon(
                detectionResult! ? Lucide.CheckCircle : Lucide.XCircle,
                size: 16,
                color: detectionResult! ? context.appColors.success : cs.error,
              ),
            ),
          )
        : null;
    return _TactileRow(
      pressedScale: 0.98,
      haptics: false,
      onTap: isSelectionMode
          ? () => onSelectionChanged?.call(!isSelected)
          : () {},
      builder: (pressed) {
        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                if (isSelectionMode) ...[
                  IosCheckbox(
                    value: isSelected,
                    onChanged: (value) => onSelectionChanged?.call(value),
                  ),
                  const SizedBox(width: 12),
                ],
                _BrandAvatar(name: resolved.baseId, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: AppFontWeights.semibold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      ModelTagWrap(model: effective),
                    ],
                  ),
                ),
                if (detectionIndicator != null) ...[
                  const SizedBox(width: 8),
                  detectionIndicator,
                ],
                if (!isSelectionMode) ...[
                  const SizedBox(width: 8),
                  _TactileIconButton(
                    icon: Lucide.Settings2,
                    color: cs.onSurface.withValues(alpha: 0.7),
                    size: 18,
                    semanticLabel: l10n.providerDetailPageEditTooltip,
                    onTap: () async {
                      await showModelDetailSheet(
                        context,
                        providerKey: providerKey,
                        modelId: modelId,
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  ModelInfo _infer(String id) {
    // build a minimal ModelInfo and let registry infer
    return ModelRegistry.infer(ModelInfo(id: id, displayName: id));
  }

  _ResolvedModelOverride _resolveBaseAndOverride(BuildContext context) {
    // Only this model's override rebuilds the card.
    final rawOv = context.select<SettingsProvider, Object?>(
      (s) => s.providerConfigs[providerKey]?.modelOverrides[modelId],
    );
    final Map<String, dynamic>? ov = rawOv is Map
        ? {for (final e in rawOv.entries) e.key.toString(): e.value}
        : null;
    String baseId = modelId;
    if (ov != null) {
      final raw = (ov['apiModelId'] ?? ov['api_model_id'])?.toString().trim();
      if (raw != null && raw.isNotEmpty) baseId = raw;
    }
    final base = _infer(baseId);
    return _ResolvedModelOverride(base: base, ov: ov, baseId: baseId);
  }
}

class _ResolvedModelOverride {
  const _ResolvedModelOverride({
    required this.base,
    required this.ov,
    required this.baseId,
  });

  final ModelInfo base;
  final Map<String, dynamic>? ov;
  final String baseId;
}

class _BrandAvatar extends StatelessWidget {
  const _BrandAvatar({required this.name, this.size = 20});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final asset = BrandAssets.assetForName(name);
    final mono =
        asset != null && isDark && BrandAssets.assetNeedsDarkInvert(asset);
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: cs.primary.withValues(alpha: isDark ? 0.18 : 0.1),
      child: asset == null
          ? Text(
              name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
              style: TextStyle(
                color: cs.primary,
                fontSize: size * 0.5,
                fontWeight: AppFontWeights.emphasis,
              ),
            )
          : (asset.endsWith('.svg')
                ? SvgPicture.asset(
                    asset,
                    width: size * 0.7,
                    height: size * 0.7,
                    colorFilter: mono
                        ? ColorFilter.mode(cs.onSurface, BlendMode.srcIn)
                        : null,
                  )
                : Image.asset(
                    asset,
                    width: size * 0.7,
                    height: size * 0.7,
                    fit: BoxFit.contain,
                    color: mono ? cs.onSurface : null,
                    colorBlendMode: mono ? BlendMode.srcIn : null,
                  )),
    );
  }
}

// Top-level tactile row used by iOS-style lists here
