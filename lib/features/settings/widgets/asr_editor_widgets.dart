part of 'asr_services_section.dart';

class _EditorSectionHeader extends StatelessWidget {
  const _EditorSectionHeader({required this.text, this.first = false});

  final String text;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(12, first ? 6 : 18, 12, 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: AppFontWeights.semibold,
          color: cs.onSurface.withValues(alpha: 0.8),
        ),
      ),
    );
  }
}

class _ProviderChoiceGrid extends StatelessWidget {
  const _ProviderChoiceGrid({required this.selected, required this.onSelected});

  final AsrServiceKind selected;
  final ValueChanged<AsrServiceKind> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _GroupLabel(text: l10n.asrServicesOnDeviceGroup),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final kind in const [
              AsrServiceKind.system,
              AsrServiceKind.sherpaOnnx,
            ])
              _ProviderChoice(
                kind: kind,
                selected: kind == selected,
                onTap: () => onSelected(kind),
              ),
          ],
        ),
        const SizedBox(height: 16),
        _GroupLabel(text: l10n.asrServicesCloudGroup),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final kind in const [
              AsrServiceKind.openAiRealtime,
              AsrServiceKind.dashScope,
              AsrServiceKind.qwenAudio,
              AsrServiceKind.volcengine,
              AsrServiceKind.mimo,
              AsrServiceKind.step,
            ])
              _ProviderChoice(
                kind: kind,
                selected: kind == selected,
                onTap: () => onSelected(kind),
              ),
          ],
        ),
      ],
    );
  }
}

class _ProviderChoice extends StatelessWidget {
  const _ProviderChoice({
    required this.kind,
    required this.selected,
    required this.onTap,
  });

  final AsrServiceKind kind;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return VoiceServiceTactileRow(
      onTap: onTap,
      builder: (pressed) {
        final base = selected
            ? cs.primary.withValues(alpha: 0.13)
            : cs.onSurface.withValues(alpha: 0.06);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: pressed
                ? Color.alphaBlend(cs.onSurface.withValues(alpha: 0.06), base)
                : base,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? cs.primary.withValues(alpha: 0.5)
                  : cs.outlineVariant.withValues(alpha: 0.22),
              width: 0.8,
            ),
          ),
          child: Text(
            _kindTitle(l10n, kind),
            style: TextStyle(
              fontSize: 14,
              fontWeight: AppFontWeights.semibold,
              color: selected ? cs.primary : cs.onSurface,
            ),
          ),
        );
      },
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: AppFontWeights.semibold,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.66),
      ),
    );
  }
}

class _SystemConfiguration extends StatelessWidget {
  const _SystemConfiguration({
    required this.available,
    required this.checking,
    required this.localeController,
    required this.onCheck,
    required this.desktop,
  });

  final bool? available;
  final bool checking;
  final TextEditingController localeController;
  final VoidCallback onCheck;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;
    final statusText = checking
        ? l10n.asrServicesSystemChecking
        : available == true
        ? l10n.asrServicesSystemAvailable
        : available == false
        ? l10n.asrServicesSystemCheckFailed
        : l10n.asrServicesSystemSubtitle;
    final controlColor = desktop
        ? Colors.transparent
        : (context.appColors.surfaceFill);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: desktop ? 4 : 12,
            vertical: desktop ? 6 : 10,
          ),
          child: Semantics(
            button: true,
            label: statusText,
            child: MouseRegion(
              cursor: checking
                  ? SystemMouseCursors.basic
                  : SystemMouseCursors.click,
              child: GestureDetector(
                key: const ValueKey('asr-system-status'),
                behavior: HitTestBehavior.opaque,
                onTap: checking ? null : onCheck,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: available == false
                        ? cs.error.withValues(alpha: isDark ? 0.10 : 0.06)
                        : controlColor,
                    borderRadius: BorderRadius.circular(desktop ? 10 : 12),
                    border: desktop || available == false
                        ? Border.all(
                            color: available == false
                                ? cs.error.withValues(alpha: 0.42)
                                : cs.onSurface.withValues(alpha: 0.24),
                          )
                        : null,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        checking
                            ? Lucide.Loader
                            : available == true
                            ? Lucide.Check
                            : Lucide.Mic,
                        size: 17,
                        color: available == false
                            ? cs.error
                            : available == true
                            ? cs.primary
                            : cs.onSurface.withValues(alpha: 0.58),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          statusText,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            color: available == false
                                ? cs.error
                                : cs.onSurface.withValues(alpha: 0.70),
                          ),
                        ),
                      ),
                      if (!checking)
                        Icon(
                          Lucide.RefreshCw,
                          size: 16,
                          color: cs.onSurface.withValues(alpha: 0.44),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        _EditorField(
          label: l10n.asrServicesLanguageLabel,
          controller: localeController,
          hint: l10n.asrServicesAutomaticLabel,
          desktop: desktop,
        ),
      ],
    );
  }
}

class _LocalModelPicker extends StatelessWidget {
  const _LocalModelPicker({
    required this.statuses,
    required this.selectedModelId,
    required this.downloadTokens,
    required this.onDownload,
    required this.onCancelDownload,
    required this.onDelete,
    required this.onUse,
    required this.languageController,
    required this.desktop,
  });

  final Map<String, SherpaModelInstallStatus> statuses;
  final String selectedModelId;
  final Map<String, SherpaDownloadCancellationToken> downloadTokens;
  final ValueChanged<SherpaModelDefinition> onDownload;
  final ValueChanged<SherpaModelDefinition> onCancelDownload;
  final ValueChanged<SherpaModelDefinition> onDelete;
  final ValueChanged<SherpaModelDefinition> onUse;
  final TextEditingController languageController;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final listColor = desktop
        ? Colors.transparent
        : (context.appColors.surfaceFill);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: desktop ? 4 : 12,
            vertical: desktop ? 6 : 10,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.asrServicesChooseModelTitle,
                style: TextStyle(
                  fontSize: desktop ? 12 : 13,
                  fontWeight: desktop
                      ? AppFontWeights.regular
                      : AppFontWeights.semibold,
                  color: cs.onSurface.withValues(alpha: 0.72),
                ),
              ),
              SizedBox(height: desktop ? 6 : 7),
              Container(
                key: const ValueKey('asr-local-model-list'),
                decoration: BoxDecoration(
                  color: listColor,
                  borderRadius: BorderRadius.circular(desktop ? 10 : 12),
                  border: desktop
                      ? Border.all(color: cs.onSurface.withValues(alpha: 0.24))
                      : null,
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (
                      var i = 0;
                      i < SherpaModelCatalog.models.length;
                      i++
                    ) ...[
                      _ModelRow(
                        key: ValueKey(
                          'asr-model-${SherpaModelCatalog.models[i].id}',
                        ),
                        model: SherpaModelCatalog.models[i],
                        status: statuses[SherpaModelCatalog.models[i].id],
                        selected:
                            selectedModelId == SherpaModelCatalog.models[i].id,
                        downloading: downloadTokens.containsKey(
                          SherpaModelCatalog.models[i].id,
                        ),
                        onDownload: () =>
                            onDownload(SherpaModelCatalog.models[i]),
                        onCancelDownload: () =>
                            onCancelDownload(SherpaModelCatalog.models[i]),
                        onDelete: () => onDelete(SherpaModelCatalog.models[i]),
                        onUse: () => onUse(SherpaModelCatalog.models[i]),
                      ),
                      if (i != SherpaModelCatalog.models.length - 1)
                        Divider(
                          height: 0.6,
                          thickness: 0.6,
                          indent: 12,
                          endIndent: 12,
                          color: cs.outlineVariant.withValues(alpha: 0.18),
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        _EditorField(
          label: l10n.asrServicesLanguageLabel,
          controller: languageController,
          hint: l10n.asrServicesAutomaticLabel,
          desktop: desktop,
        ),
      ],
    );
  }
}

class _ModelRow extends StatelessWidget {
  const _ModelRow({
    super.key,
    required this.model,
    required this.status,
    required this.selected,
    required this.downloading,
    required this.onDownload,
    required this.onCancelDownload,
    required this.onDelete,
    required this.onUse,
  });

  final SherpaModelDefinition model;
  final SherpaModelInstallStatus? status;
  final bool selected;
  final bool downloading;
  final VoidCallback onDownload;
  final VoidCallback onCancelDownload;
  final VoidCallback onDelete;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final installed = status?.isInstalled == true;
    final downloadProgress = status?.progress;
    final progress = downloadProgress?.progress;
    final percent = downloadProgress?.displayPercent;
    final statusLabel = downloading
        ? percent == null
              ? l10n.asrServicesModelDownloadingLabel
              : '${l10n.asrServicesModelDownloadingLabel} $percent%'
        : installed
        ? l10n.asrServicesModelDownloadedLabel
        : l10n.asrServicesModelNotDownloadedLabel;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 170),
      curve: Curves.easeOutCubic,
      color: selected
          ? cs.primary.withValues(alpha: 0.065)
          : Colors.transparent,
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  model.localizedName(l10n),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: AppFontWeights.semibold,
                    color: cs.onSurface,
                  ),
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 8),
                Icon(Lucide.Check, size: 17, color: cs.primary),
              ],
            ],
          ),
          const SizedBox(height: 3),
          Text(
            '${_formatBytes(model.downloadBytes)} · $statusLabel',
            style: TextStyle(
              fontSize: 11,
              color: cs.onSurface.withValues(alpha: 0.56),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            model.localizedDescription(l10n),
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: cs.onSurface.withValues(alpha: 0.62),
            ),
          ),
          if (downloading) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: SizedBox(
                key: ValueKey('asr-model-progress-${model.id}'),
                height: 4,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final fraction =
                        progress?.clamp(0.0, 1.0).toDouble() ?? 0.0;
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(color: cs.onSurface.withValues(alpha: 0.08)),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOutCubic,
                            width: constraints.maxWidth * fraction,
                            color: cs.primary,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
          const SizedBox(height: 7),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                if (downloading)
                  _CompactAction(
                    label: l10n.asrServicesCancelAction,
                    icon: Lucide.X,
                    onTap: onCancelDownload,
                  )
                else if (!installed)
                  _CompactAction(
                    label: l10n.asrServicesModelDownloadAction,
                    icon: Lucide.Download,
                    prominent: true,
                    onTap: onDownload,
                  )
                else ...[
                  if (!selected)
                    _CompactAction(
                      label: l10n.asrServicesModelUseAction,
                      icon: Lucide.Check,
                      prominent: true,
                      onTap: onUse,
                    ),
                  _CompactAction(
                    label: l10n.asrServicesModelDeleteAction,
                    icon: Lucide.Trash2,
                    destructive: true,
                    onTap: onDelete,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactAction extends StatefulWidget {
  const _CompactAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.prominent = false,
    this.destructive = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool prominent;
  final bool destructive;

  @override
  State<_CompactAction> createState() => _CompactActionState();
}

class _CompactActionState extends State<_CompactAction> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = widget.destructive
        ? cs.error
        : widget.prominent
        ? cs.primary
        : cs.onSurface.withValues(alpha: 0.72);
    final backgroundAlpha = _pressed
        ? 0.14
        : _hovered
        ? 0.09
        : widget.prominent
        ? 0.07
        : 0.0;
    return Semantics(
      button: true,
      label: widget.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 130),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: backgroundAlpha),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, size: 14, color: color),
                const SizedBox(width: 5),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: AppFontWeights.semibold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EditorField extends StatefulWidget {
  const _EditorField({
    required this.label,
    required this.controller,
    this.hint,
    this.obscure = false,
    this.errorText,
    this.onChanged,
    this.desktop = false,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool obscure;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final bool desktop;

  @override
  State<_EditorField> createState() => _EditorFieldState();
}

class _EditorFieldState extends State<_EditorField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (widget.desktop) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.label,
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: widget.controller,
              obscureText: widget.obscure,
              autocorrect: !widget.obscure,
              enableSuggestions: !widget.obscure,
              onChanged: widget.onChanged,
              decoration: InputDecoration(
                hintText: widget.hint,
                errorText: widget.errorText,
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final fieldBg = context.appColors.surfaceFill;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: AppFontWeights.semibold,
              color: cs.onSurface.withValues(alpha: 0.72),
            ),
          ),
          const SizedBox(height: 7),
          TextField(
            controller: widget.controller,
            obscureText: widget.obscure && _obscured,
            autocorrect: !widget.obscure,
            enableSuggestions: !widget.obscure,
            onChanged: widget.onChanged,
            style: TextStyle(
              fontSize: 15,
              fontWeight: AppFontWeights.medium,
              color: cs.onSurface.withValues(alpha: 0.92),
            ),
            decoration: InputDecoration(
              hintText: widget.hint,
              errorText: widget.errorText,
              isDense: true,
              filled: true,
              fillColor: fieldBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: cs.primary, width: 1),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: cs.error, width: 1),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: cs.error, width: 1),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              suffixIcon: widget.obscure
                  ? _EditorVisibilityButton(
                      icon: _obscured ? Lucide.Eye : Lucide.EyeOff,
                      onTap: () => setState(() => _obscured = !_obscured),
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _EditorVisibilityButton extends StatefulWidget {
  const _EditorVisibilityButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_EditorVisibilityButton> createState() =>
      _EditorVisibilityButtonState();
}

class _EditorVisibilityButtonState extends State<_EditorVisibilityButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface;
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: () {
          Haptics.light();
          widget.onTap();
        },
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(
            widget.icon,
            size: 18,
            color: color.withValues(alpha: _pressed ? 0.55 : 0.72),
          ),
        ),
      ),
    );
  }
}
