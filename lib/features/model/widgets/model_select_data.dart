part of 'model_select_sheet.dart';

// Data class for compute function
class _ModelProcessingData {
  final Map<String, dynamic> providerConfigs;
  final Set<String> pinnedModels;
  final String currentModelKey;
  final List<String> providersOrder;
  final String? limitProviderKey;
  final bool disableResolverPlatformLogging;

  _ModelProcessingData({
    required this.providerConfigs,
    required this.pinnedModels,
    required this.currentModelKey,
    required this.providersOrder,
    this.limitProviderKey,
    required this.disableResolverPlatformLogging,
  });
}

class _ModelProcessingResult {
  final Map<String, _ProviderGroup> groups;
  final List<_ModelItem> favItems;
  final List<String> orderedKeys;

  _ModelProcessingResult({
    required this.groups,
    required this.favItems,
    required this.orderedKeys,
  });
}

// Lightweight brand asset resolver usable in isolates
String? _assetForNameStatic(String n) {
  return BrandAssets.assetForName(n);
}

List<String> _buildDisplayProvidersOrder(
  SettingsProvider settings,
  Iterable<String> providerKeys,
) {
  final knownKeys = providerKeys.where((e) => e.trim().isNotEmpty);
  final providerGroupMap = <String, String>{};
  for (final key in knownKeys) {
    final groupId = settings.groupIdForProvider(key);
    if (groupId != null) providerGroupMap[key] = groupId;
  }
  return buildProviderKeysInGroupedDisplayOrder(
    providersOrder: settings.providersOrder,
    groups: settings.providerGroups,
    ungroupedIndex: settings.providerUngroupedDisplayIndex,
    providerGroupMap: providerGroupMap,
    knownProviderKeys: providerKeys,
  );
}

// Static function for compute - must be top-level
_ModelProcessingResult _processModelsInBackground(_ModelProcessingData data) {
  if (data.disableResolverPlatformLogging) {
    ModelOverrideResolver.setPlatformLoggingEnabled(false);
    ModelOverrideResolver.setUnknownValueLoggingEnabled(false);
  }
  final providers = data.limitProviderKey == null
      ? data.providerConfigs
      : {
          if (data.providerConfigs.containsKey(data.limitProviderKey))
            data.limitProviderKey!:
                data.providerConfigs[data.limitProviderKey]!,
        };

  // Build data map: providerKey -> (displayName, models)
  final Map<String, _ProviderGroup> groups = {};

  providers.forEach((key, cfg) {
    // Skip disabled providers entirely so they can't be selected
    if (!(cfg['enabled'] as bool)) return;
    final models = cfg['models'] as List<dynamic>? ?? [];
    if (models.isEmpty) return;

    final name = (cfg['name'] as String?) ?? '';
    final overrides =
        (cfg['overrides'] as Map?)?.map((k, v) => MapEntry(k.toString(), v)) ??
        const <String, dynamic>{};
    final list = <_ModelItem>[
      for (final id in models)
        () {
          final String mid = id.toString();
          final rawOv = overrides[mid];
          final Map<String, dynamic>? ov = rawOv is Map
              ? {for (final e in rawOv.entries) e.key.toString(): e.value}
              : null;
          // Use upstream/api model id for inference when available so that
          // brand assets and default capabilities stay accurate even when the
          // logical key is a custom alias.
          String baseId = mid;
          if (ov != null) {
            final raw = (ov['apiModelId'] ?? ov['api_model_id'])
                ?.toString()
                .trim();
            if (raw != null && raw.isNotEmpty) baseId = raw;
          }
          ModelInfo base = ModelRegistry.infer(
            ModelInfo(id: baseId, displayName: baseId),
          );
          if (ov != null) {
            base = ModelOverrideResolver.applyModelOverride(
              base,
              ov,
              applyDisplayName: true,
            );
          }
          return _ModelItem(
            providerKey: key,
            providerName: name.isNotEmpty ? name : key,
            id: mid,
            info: base,
            pinned: data.pinnedModels.contains('$key::$mid'),
            selected: data.currentModelKey == '$key::$mid',
            asset: _assetForNameStatic(baseId),
          );
        }(),
    ];
    groups[key] = _ProviderGroup(
      name: name.isNotEmpty ? name : key,
      items: list,
    );
  });

  // Build favorites group (duplicate items)
  final favItems = <_ModelItem>[];
  for (final k in data.pinnedModels) {
    final parts = k.split('::');
    if (parts.length < 2) continue;
    final pk = parts[0];
    final mid = parts.sublist(1).join('::');
    final g = groups[pk];
    if (g == null) continue;
    final found = g.items.firstWhere(
      (e) => e.id == mid,
      orElse: () => _ModelItem(
        providerKey: pk,
        providerName: g.name,
        id: mid,
        info: ModelRegistry.infer(ModelInfo(id: mid, displayName: mid)),
        pinned: true,
        selected: data.currentModelKey == '$pk::$mid',
      ),
    );
    favItems.add(found.copyWith(pinned: true));
  }

  // Provider sections ordered by ProvidersPage order
  final orderedKeys = <String>[];
  for (final k in data.providersOrder) {
    if (groups.containsKey(k)) orderedKeys.add(k);
  }
  for (final k in groups.keys) {
    if (!orderedKeys.contains(k)) orderedKeys.add(k);
  }

  return _ModelProcessingResult(
    groups: groups,
    favItems: favItems,
    orderedKeys: orderedKeys,
  );
}
