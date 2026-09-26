part of 'multi_key_manager_page.dart';

Future<void> _showKeyStrategySheet(
  BuildContext context, {
  required String providerKey,
  required String providerDisplayName,
}) async {
  final cs = Theme.of(context).colorScheme;
  final l10n = AppLocalizations.of(context)!;
  final settings = context.read<SettingsProvider>();
  final old = settings.getProviderConfig(
    providerKey,
    defaultName: providerDisplayName,
  );
  final current = old.keyManagement?.strategy ?? LoadBalanceStrategy.roundRobin;
  String labelFor(LoadBalanceStrategy s) {
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

  final selected = await showModalBottomSheet<LoadBalanceStrategy>(
    context: context,
    backgroundColor: context.overlaySurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 12),
              // Only show Round Robin and Random for now
              for (final s in <LoadBalanceStrategy>[
                LoadBalanceStrategy.roundRobin,
                LoadBalanceStrategy.random,
              ])
                _TactileRow(
                  pressedScale: 1.00,
                  onTap: () => Navigator.of(ctx).pop(s),
                  builder: (pressed) {
                    final base = cs.onSurface;
                    final target = pressed
                        ? (Color.lerp(base, cs.surface, 0.55) ?? base)
                        : base;
                    return TweenAnimationBuilder<Color?>(
                      tween: ColorTween(end: target),
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      builder: (context, color, _) {
                        final c = color ?? base;
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  labelFor(s),
                                  style: TextStyle(fontSize: 15, color: c),
                                ),
                              ),
                              if (s == current)
                                Icon(Icons.check, color: cs.primary),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
            ],
          ),
        ),
      );
    },
  );
  if (selected != null && selected != current) {
    final km = (old.keyManagement ?? const KeyManagementConfig()).copyWith(
      strategy: selected,
    );
    await settings.setProviderConfig(
      providerKey,
      old.copyWith(keyManagement: km),
    );
  }
}

Future<List<String>?> _showAddKeysSheet(BuildContext context) async {
  final l10n = AppLocalizations.of(context)!;
  final cs = Theme.of(context).colorScheme;
  final inputCtrl = TextEditingController();
  final result = await showModalBottomSheet<List<String>?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.overlaySurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
              SizedBox(
                height: 36,
                child: Stack(
                  children: [
                    Align(
                      alignment: Alignment.center,
                      child: Text(
                        l10n.multiKeyPageAdd,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: AppFontWeights.semibold,
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _TactileIconButton(
                        icon: Lucide.X,
                        color: cs.onSurface,
                        onTap: () => Navigator.of(ctx).maybePop(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: inputCtrl,
                minLines: 3,
                maxLines: 6,
                decoration: InputDecoration(
                  hintText: l10n.multiKeyPageAddHint,
                  filled: true,
                  fillColor: context.appColors.surfaceCard,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: cs.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: cs.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: cs.primary.withValues(alpha: 0.5),
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: IosTileButton(
                  label: l10n.multiKeyPageAdd,
                  icon: Lucide.Plus,
                  backgroundColor: cs.primary,
                  onTap: () =>
                      Navigator.of(ctx).pop(_splitKeys(inputCtrl.text)),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
  return result;
}

Future<ApiKeyConfig?> _showEditKeySheet(
  BuildContext context,
  ApiKeyConfig k,
) async {
  final l10n = AppLocalizations.of(context)!;
  final cs = Theme.of(context).colorScheme;
  final aliasCtrl = TextEditingController(text: k.name ?? '');
  final keyCtrl = TextEditingController(text: k.key);
  final priCtrl = TextEditingController(text: k.priority.toString());
  final updated = await showModalBottomSheet<ApiKeyConfig?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.overlaySurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
              SizedBox(
                height: 36,
                child: Stack(
                  children: [
                    Align(
                      alignment: Alignment.center,
                      child: Text(
                        l10n.multiKeyPageEdit,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: AppFontWeights.semibold,
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _TactileIconButton(
                        icon: Lucide.X,
                        color: cs.onSurface,
                        onTap: () => Navigator.of(ctx).maybePop(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: aliasCtrl,
                decoration: InputDecoration(
                  hintText: l10n.multiKeyPageAlias,
                  filled: true,
                  fillColor: context.appColors.surfaceCard,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: cs.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: cs.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: cs.primary.withValues(alpha: 0.5),
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: keyCtrl,
                decoration: InputDecoration(
                  hintText: l10n.multiKeyPageKey,
                  filled: true,
                  fillColor: context.appColors.surfaceCard,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: cs.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: cs.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: cs.primary.withValues(alpha: 0.5),
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: priCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: l10n.multiKeyPagePriority,
                  filled: true,
                  fillColor: context.appColors.surfaceCard,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: cs.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: cs.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: cs.primary.withValues(alpha: 0.5),
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: IosTileButton(
                  label: l10n.multiKeyPageSave,
                  icon: Lucide.Check,
                  backgroundColor: cs.primary,
                  onTap: () {
                    final p = int.tryParse(priCtrl.text.trim()) ?? k.priority;
                    final clamped = p.clamp(1, 10);
                    Navigator.of(ctx).pop(
                      k.copyWith(
                        name: aliasCtrl.text.trim().isEmpty
                            ? null
                            : aliasCtrl.text.trim(),
                        key: keyCtrl.text.trim(),
                        priority: clamped,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
  return updated;
}

List<String> _splitKeys(String raw) {
  final s = raw.replaceAll(',', ' ').trim();
  return s
      .split(RegExp(r'\s+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
}
