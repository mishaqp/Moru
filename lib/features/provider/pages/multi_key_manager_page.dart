import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../core/providers/model_provider.dart';
import '../../../core/models/api_keys.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../model/widgets/model_select_sheet.dart';
import '../../../shared/widgets/ios_switch.dart';
import '../../../shared/widgets/ios_tile_button.dart';
import '../../../core/services/haptics.dart';
import 'package:Kelivo/theme/app_font_weights.dart';
import 'package:Kelivo/theme/app_semantic_colors.dart';
import 'package:Kelivo/shared/widgets/section_card.dart';
import '../../../core/providers/provider_config_watch.dart';

part 'multi_key_manager_sheets.dart';
part 'multi_key_manager_widgets.dart';

class MultiKeyManagerPage extends StatefulWidget {
  const MultiKeyManagerPage({
    super.key,
    required this.providerKey,
    required this.providerDisplayName,
  });
  final String providerKey;
  final String providerDisplayName;

  @override
  State<MultiKeyManagerPage> createState() => _MultiKeyManagerPageState();
}

class _MultiKeyManagerPageState extends State<MultiKeyManagerPage> {
  String? _detectModelId;
  bool _detecting = false;
  String? _testingKeyId;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final cfg = context.watchProviderConfig(
      widget.providerKey,
      defaultName: widget.providerDisplayName,
    );
    final apiKeys = List<ApiKeyConfig>.from(
      cfg.apiKeys ?? const <ApiKeyConfig>[],
    );
    final total = apiKeys.length;
    final normal = apiKeys.where((k) => k.status == ApiKeyStatus.active).length;
    final errors = apiKeys.where((k) => k.status == ApiKeyStatus.error).length;
    // accuracy metric removed from UI; no longer needed

    return Scaffold(
      appBar: AppBar(
        leading: Tooltip(
          message: l10n.settingsPageBackButton,
          child: _TactileIconButton(
            icon: Lucide.ArrowLeft,
            color: cs.onSurface,
            semanticLabel: l10n.settingsPageBackButton,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ),
        title: Text(l10n.multiKeyPageTitle),
        actions: [
          Tooltip(
            message: l10n.multiKeyPageDeleteErrorsTooltip,
            child: _TactileIconButton(
              icon: Lucide.Trash2,
              color: cs.onSurface,
              semanticLabel: l10n.multiKeyPageDeleteErrorsTooltip,
              onTap: _onDeleteAllErrorKeys,
            ),
          ),
          if (_detecting)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: cs.primary,
                ),
              ),
            )
          else
            Tooltip(
              message: l10n.multiKeyPageDetect,
              child: _TactileIconButton(
                icon: Lucide.HeartPulse,
                color: cs.onSurface,
                semanticLabel: l10n.multiKeyPageDetect,
                onTap: _onDetect,
                onLongPress: _onPickDetectModel,
              ),
            ),
          Tooltip(
            message: l10n.multiKeyPageAdd,
            child: _TactileIconButton(
              icon: Lucide.Plus,
              color: cs.onSurface,
              semanticLabel: l10n.multiKeyPageAdd,
              onTap: _onAddKeys,
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          SectionCard(
            children: [
              _iosRow(
                context,
                label: l10n.multiKeyPageTotal,
                trailing: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text(
                    '$total',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: AppFontWeights.medium,
                    ),
                  ),
                ),
              ),
              _iosRow(
                context,
                label: l10n.multiKeyPageNormal,
                trailing: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text(
                    '$normal',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: AppFontWeights.medium,
                    ),
                  ),
                ),
              ),
              _iosRow(
                context,
                label: l10n.multiKeyPageError,
                trailing: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text(
                    '$errors',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: AppFontWeights.medium,
                    ),
                  ),
                ),
              ),
              _strategyRow(context, cfg),
            ],
          ),
          const SizedBox(height: 12),
          _keysList(context, apiKeys),
        ],
      ),
    );
  }

  String _strategyLabel(BuildContext context, LoadBalanceStrategy s) {
    final l10n = AppLocalizations.of(context)!;
    switch (s) {
      case LoadBalanceStrategy.priority:
        return l10n.multiKeyPageStrategyPriority;
      case LoadBalanceStrategy.leastUsed:
        return l10n.multiKeyPageStrategyLeastUsed;
      case LoadBalanceStrategy.random:
        return l10n.multiKeyPageStrategyRandom;
      case LoadBalanceStrategy.roundRobin:
        return l10n.multiKeyPageStrategyRoundRobin;
    }
  }

  Widget _strategyRow(BuildContext context, ProviderConfig cfg) {
    final cs = Theme.of(context).colorScheme;
    final strategy =
        cfg.keyManagement?.strategy ?? LoadBalanceStrategy.roundRobin;
    return _TactileRow(
      pressedScale: 1.00,
      onTap: () => _showKeyStrategySheet(
        context,
        providerKey: widget.providerKey,
        providerDisplayName: widget.providerDisplayName,
      ),
      builder: (pressed) {
        final base = cs.onSurface;
        final target = pressed
            ? (Color.lerp(base, cs.surface, 0.55) ?? base)
            : base;
        return TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: target),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          builder: (context, color, _) {
            final c = color ?? base;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context)!.multiKeyPageStrategyTitle,
                      style: TextStyle(fontSize: 15, color: c),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _strategyLabel(context, strategy),
                        style: TextStyle(fontSize: 15, color: c),
                      ),
                      const SizedBox(width: 6),
                      Icon(Lucide.ChevronRight, size: 16, color: c),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _keysList(BuildContext context, List<ApiKeyConfig> keys) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    if (keys.isEmpty) {
      return SectionCard(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Center(child: Text(l10n.multiKeyPageNoKeys)),
          ),
        ],
      );
    }

    String mask(String key) {
      if (key.length <= 8) return key;
      return '${key.substring(0, 4)}••••${key.substring(key.length - 4)}';
    }

    Color statusColor(ApiKeyStatus st) {
      switch (st) {
        case ApiKeyStatus.active:
          return context.appColors.success;
        case ApiKeyStatus.disabled:
          return cs.onSurface.withValues(alpha: 0.6);
        case ApiKeyStatus.error:
          return cs.error;
        case ApiKeyStatus.rateLimited:
          return cs.tertiary;
      }
    }

    String statusText(ApiKeyStatus st) {
      switch (st) {
        case ApiKeyStatus.active:
          return l10n.multiKeyPageStatusActive;
        case ApiKeyStatus.disabled:
          return l10n.multiKeyPageStatusDisabled;
        case ApiKeyStatus.error:
          return l10n.multiKeyPageStatusError;
        case ApiKeyStatus.rateLimited:
          return l10n.multiKeyPageStatusRateLimited;
      }
    }

    return SectionCard(
      children: [
        for (int i = 0; i < keys.length; i++)
          _keyRow(
            context,
            keys[i],
            statusColor,
            statusText,
            mask,
            isTesting: _testingKeyId == keys[i].id,
            onTest: () => _onTestSingleKey(keys[i]),
          ),
      ],
    );
  }

  Widget _keyRow(
    BuildContext context,
    ApiKeyConfig k,
    Color Function(ApiKeyStatus) statusColor,
    String Function(ApiKeyStatus) statusText,
    String Function(String) mask, {
    bool isTesting = false,
    VoidCallback? onTest,
  }) {
    final cs = Theme.of(context).colorScheme;
    final name = k.name?.isNotEmpty == true ? k.name! : mask(k.key);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor(k.status).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    statusText(k.status),
                    style: TextStyle(
                      color: statusColor(k.status),
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(fontWeight: AppFontWeights.semibold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IosSwitch(
            value: k.isEnabled,
            onChanged: (v) async {
              await _updateKey(k.copyWith(isEnabled: v));
            },
            width: 46,
            height: 28,
          ),
          const SizedBox(width: 6),
          if (isTesting)
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: cs.primary,
              ),
            )
          else if (onTest != null)
            _TactileIconButton(
              icon: Lucide.HeartPulse,
              color: cs.primary,
              semanticLabel: AppLocalizations.of(context)!.multiKeyPageDetect,
              onTap: onTest,
            ),
          const SizedBox(width: 4),
          _TactileIconButton(
            icon: Lucide.Pencil,
            color: cs.primary,
            semanticLabel: AppLocalizations.of(context)!.multiKeyPageEdit,
            onTap: () async {
              await _editKey(k);
            },
          ),
          const SizedBox(width: 4),
          _TactileIconButton(
            icon: Lucide.Trash2,
            color: cs.error,
            semanticLabel: AppLocalizations.of(context)!.multiKeyPageDelete,
            onTap: () async {
              await _deleteKey(k);
            },
          ),
        ],
      ),
    );
  }

  // iOS-style section container

  // Single row with label-left and custom trailing
  Widget _iosRow(
    BuildContext context, {
    required String label,
    Widget? trailing,
    GestureTapCallback? onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(fontSize: 15))),
          if (trailing != null)
            DefaultTextStyle.merge(
              style: TextStyle(color: cs.onSurface.withValues(alpha: 0.8)),
              child: trailing,
            ),
        ],
      ),
    );
    if (onTap != null) {
      return _TactileScale(onTap: onTap, child: row);
    }
    return row;
  }

  Future<void> _updateKey(ApiKeyConfig updated) async {
    final settings = context.read<SettingsProvider>();
    final old = settings.getProviderConfig(
      widget.providerKey,
      defaultName: widget.providerDisplayName,
    );
    final list = List<ApiKeyConfig>.from(old.apiKeys ?? const <ApiKeyConfig>[]);
    final idx = list.indexWhere((e) => e.id == updated.id);
    if (idx >= 0) {
      list[idx] = updated;
      await settings.setProviderConfig(
        widget.providerKey,
        old.copyWith(apiKeys: list),
      );
    }
  }

  Future<void> _deleteKey(ApiKeyConfig k) async {
    final settings = context.read<SettingsProvider>();
    final old = settings.getProviderConfig(
      widget.providerKey,
      defaultName: widget.providerDisplayName,
    );
    final list = List<ApiKeyConfig>.from(old.apiKeys ?? const <ApiKeyConfig>[]);
    final idx = list.indexWhere((e) => e.id == k.id);
    if (idx < 0) return;
    final removed = list.removeAt(idx);
    await settings.setProviderConfig(
      widget.providerKey,
      old.copyWith(apiKeys: list),
    );
    if (!mounted) return;
    showAppSnackBar(
      context,
      message: AppLocalizations.of(
        context,
      )!.multiKeyPageDeleteSnackbarDeletedOne,
      type: NotificationType.info,
      actionLabel: AppLocalizations.of(context)!.multiKeyPageUndo,
      onAction: () async {
        // Re-insert if user taps undo
        final latest = settings.getProviderConfig(
          widget.providerKey,
          defaultName: widget.providerDisplayName,
        );
        final cur = List<ApiKeyConfig>.from(
          latest.apiKeys ?? const <ApiKeyConfig>[],
        );
        final insertIndex = idx <= cur.length ? idx : cur.length;
        cur.insert(insertIndex, removed);
        await settings.setProviderConfig(
          widget.providerKey,
          latest.copyWith(apiKeys: cur),
        );
        if (!mounted) return;
        showAppSnackBar(
          context,
          message: AppLocalizations.of(context)!.multiKeyPageUndoRestored,
          type: NotificationType.success,
          duration: const Duration(seconds: 2),
        );
      },
    );
  }

  Future<void> _editKey(ApiKeyConfig k) async {
    final settings = context.read<SettingsProvider>();
    final l10n = AppLocalizations.of(context)!;
    final updated = await _showEditKeySheet(context, k);
    if (updated == null) {
      return;
    }
    // Optional: prevent duplicate keys if key changed
    final cfg = settings.getProviderConfig(
      widget.providerKey,
      defaultName: widget.providerDisplayName,
    );
    final list = List<ApiKeyConfig>.from(cfg.apiKeys ?? const <ApiKeyConfig>[]);
    final duplicate = list.any(
      (e) => e.id != k.id && e.key.trim() == updated.key.trim(),
    );
    if (duplicate) {
      if (!mounted) {
        return;
      }
      showAppSnackBar(
        context,
        message: l10n.multiKeyPageDuplicateKeyWarning,
        type: NotificationType.warning,
      );
      return;
    }
    await _updateKey(updated);
  }

  Future<void> _onAddKeys() async {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.read<SettingsProvider>();
    final added = await _showAddKeysSheet(context);
    if (added == null) {
      return;
    }
    final cfg = settings.getProviderConfig(
      widget.providerKey,
      defaultName: widget.providerDisplayName,
    );
    final existing = (cfg.apiKeys ?? const <ApiKeyConfig>[]);
    final existingSet = existing.map((e) => e.key.trim()).toSet();
    final unique = <String>[];
    for (final k in added) {
      if (k.isEmpty) continue;
      if (existingSet.add(k)) unique.add(k);
    }
    if (unique.isEmpty) {
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, message: l10n.multiKeyPageImportedSnackbar(0));
      return;
    }
    final newKeys = [
      ...existing,
      for (final s in unique) ApiKeyConfig.create(s),
    ];
    await settings.setProviderConfig(
      widget.providerKey,
      cfg.copyWith(apiKeys: newKeys, multiKeyEnabled: true),
    );
    if (!mounted) return;
    showAppSnackBar(
      context,
      message: l10n.multiKeyPageImportedSnackbar(unique.length),
      type: NotificationType.success,
    );

    // Auto-detect imported keys
    await _detectOnly(keys: unique);
  }

  Future<void> _onTestSingleKey(ApiKeyConfig key) async {
    if (_detecting || _testingKeyId != null) return;
    final settings = context.read<SettingsProvider>();
    final cfg = settings.getProviderConfig(
      widget.providerKey,
      defaultName: widget.providerDisplayName,
    );
    final models = cfg.models;
    if (_detectModelId == null) {
      if (models.isEmpty) {
        if (!mounted) return;
        showAppSnackBar(
          context,
          message: AppLocalizations.of(context)!.multiKeyPagePleaseAddModel,
          type: NotificationType.warning,
        );
        return;
      }
      _detectModelId = models.first;
    }
    setState(() => _testingKeyId = key.id);
    try {
      final list = List<ApiKeyConfig>.from(
        cfg.apiKeys ?? const <ApiKeyConfig>[],
      );
      final toTest = list.where((e) => e.id == key.id).toList();
      await _testKeysAndSave(list, toTest, _detectModelId!);
    } finally {
      if (mounted) setState(() => _testingKeyId = null);
    }
  }

  Future<void> _onDetect() async {
    if (_detecting) return;
    final settings = context.read<SettingsProvider>();
    final cfg = settings.getProviderConfig(
      widget.providerKey,
      defaultName: widget.providerDisplayName,
    );
    final models = cfg.models;
    if (_detectModelId == null) {
      if (models.isEmpty) {
        if (!mounted) return;
        showAppSnackBar(
          context,
          message: AppLocalizations.of(context)!.multiKeyPagePleaseAddModel,
          type: NotificationType.warning,
        );
        return;
      }
      _detectModelId = models.first;
    }
    setState(() => _detecting = true);
    try {
      await _detectAllForModel(_detectModelId!);
    } finally {
      if (mounted) setState(() => _detecting = false);
    }
  }

  Future<void> _onPickDetectModel() async {
    final sel = await showModelSelector(
      context,
      limitProviderKey: widget.providerKey,
      initialProviderKey: _detectModelId == null ? null : widget.providerKey,
      initialModelId: _detectModelId,
    );
    if (sel != null) {
      setState(() => _detectModelId = sel.modelId);
    }
  }

  Future<void> _onDeleteAllErrorKeys() async {
    final settings = context.read<SettingsProvider>();
    final cfg = settings.getProviderConfig(
      widget.providerKey,
      defaultName: widget.providerDisplayName,
    );
    final keys = List<ApiKeyConfig>.from(cfg.apiKeys ?? const <ApiKeyConfig>[]);
    final errorKeys = keys
        .where((e) => e.status == ApiKeyStatus.error)
        .toList();
    if (errorKeys.isEmpty) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(l10n.multiKeyPageDeleteErrorsConfirmTitle),
          content: Text(l10n.multiKeyPageDeleteErrorsConfirmContent),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.multiKeyPageCancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: TextButton.styleFrom(foregroundColor: cs.error),
              child: Text(l10n.multiKeyPageDelete),
            ),
          ],
        );
      },
    );
    if (ok != true) return;
    final remain = keys.where((e) => e.status != ApiKeyStatus.error).toList();
    await settings.setProviderConfig(
      widget.providerKey,
      cfg.copyWith(apiKeys: remain),
    );
    if (!mounted) return;
    showAppSnackBar(
      context,
      message: AppLocalizations.of(
        context,
      )!.multiKeyPageDeletedErrorsSnackbar(errorKeys.length),
      type: NotificationType.success,
    );
  }

  Future<void> _detectOnly({required List<String> keys}) async {
    final cfg = context.read<SettingsProvider>().getProviderConfig(
      widget.providerKey,
      defaultName: widget.providerDisplayName,
    );
    final models = cfg.models;
    if (_detectModelId == null) {
      if (models.isEmpty) {
        showAppSnackBar(
          context,
          message: AppLocalizations.of(context)!.multiKeyPagePleaseAddModel,
          type: NotificationType.warning,
        );
        return;
      }
      _detectModelId = models.first;
    }
    final list = List<ApiKeyConfig>.from(cfg.apiKeys ?? const <ApiKeyConfig>[]);
    final toTest = list.where((e) => keys.contains(e.key)).toList();
    await _testKeysAndSave(list, toTest, _detectModelId!);
  }

  Future<void> _detectAllForModel(String modelId) async {
    final settings = context.read<SettingsProvider>();
    final cfg = settings.getProviderConfig(
      widget.providerKey,
      defaultName: widget.providerDisplayName,
    );
    final list = List<ApiKeyConfig>.from(cfg.apiKeys ?? const <ApiKeyConfig>[]);
    await _testKeysAndSave(list, list, modelId);
  }

  Future<void> _testKeysAndSave(
    List<ApiKeyConfig> fullList,
    List<ApiKeyConfig> toTest,
    String modelId,
  ) async {
    final settings = context.read<SettingsProvider>();
    final base = settings.getProviderConfig(
      widget.providerKey,
      defaultName: widget.providerDisplayName,
    );
    final out = List<ApiKeyConfig>.from(fullList);
    for (int i = 0; i < toTest.length; i++) {
      final k = toTest[i];
      final ok = await _testSingleKey(base, modelId, k);
      final idx = out.indexWhere((e) => e.id == k.id);
      if (idx >= 0) {
        out[idx] = k.copyWith(
          status: ok ? ApiKeyStatus.active : ApiKeyStatus.error,
          usage: k.usage.copyWith(
            totalRequests: k.usage.totalRequests + 1,
            successfulRequests: k.usage.successfulRequests + (ok ? 1 : 0),
            failedRequests: k.usage.failedRequests + (ok ? 0 : 1),
            consecutiveFailures: ok ? 0 : (k.usage.consecutiveFailures + 1),
            lastUsed: DateTime.now().millisecondsSinceEpoch,
          ),
          lastError: ok ? null : 'Test failed',
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );
      }
      // Small delay between tests for UX
      await Future.delayed(const Duration(milliseconds: 120));
    }
    await settings.setProviderConfig(
      widget.providerKey,
      base.copyWith(apiKeys: out),
    );
  }

  Future<bool> _testSingleKey(
    ProviderConfig baseCfg,
    String modelId,
    ApiKeyConfig key,
  ) async {
    try {
      final cfg2 = baseCfg.copyWith(
        apiKey: key.key,
        multiKeyEnabled: false,
        apiKeys: const [],
      );
      await ProviderManager.testConnection(cfg2, modelId);
      return true;
    } catch (_) {
      return false;
    }
  }
}
