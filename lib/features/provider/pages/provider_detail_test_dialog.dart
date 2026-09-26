part of 'provider_detail_page.dart';

class _ConnectionTestDialog extends StatefulWidget {
  const _ConnectionTestDialog({
    required this.providerKey,
    required this.providerDisplayName,
  });
  final String providerKey;
  final String providerDisplayName;

  @override
  State<_ConnectionTestDialog> createState() => _ConnectionTestDialogState();
}

enum _TestState { idle, loading, success, error }

class _ConnectionTestDialogState extends State<_ConnectionTestDialog> {
  String? _selectedModelId;
  _TestState _state = _TestState.idle;
  String _errorMessage = '';
  bool _useStream = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final title = l10n.providerDetailPageTestConnectionTitle;
    final canTest = _selectedModelId != null && _state != _TestState.loading;
    return Dialog(
      backgroundColor: context.overlaySurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Center(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: AppFontWeights.emphasis,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _buildBody(context, cs, l10n),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.providerDetailPageCancelButton),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: canTest ? _doTest : null,
                    style: TextButton.styleFrom(
                      foregroundColor: canTest
                          ? cs.primary
                          : cs.onSurface.withValues(alpha: 0.4),
                    ),
                    child: Text(l10n.providerDetailPageTestButton),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    ColorScheme cs,
    AppLocalizations l10n,
  ) {
    switch (_state) {
      case _TestState.idle:
        return _buildIdle(context, cs, l10n);
      case _TestState.loading:
        return _buildLoading(context, cs, l10n);
      case _TestState.success:
        return _buildResult(
          context,
          cs,
          l10n,
          success: true,
          message: l10n.providerDetailPageTestSuccessMessage,
        );
      case _TestState.error:
        return _buildResult(
          context,
          cs,
          l10n,
          success: false,
          message: _errorMessage,
        );
    }
  }

  Widget _buildIdle(
    BuildContext context,
    ColorScheme cs,
    AppLocalizations l10n,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (_selectedModelId == null)
          TextButton(
            onPressed: _pickModel,
            child: Text(l10n.providerDetailPageSelectModelButton),
          )
        else
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _BrandAvatar(name: _selectedModelId!, size: 24),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _selectedModelId!,
                  style: TextStyle(fontWeight: AppFontWeights.semibold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 10),
              TextButton(
                onPressed: _pickModel,
                child: Text(l10n.providerDetailPageChangeButton),
              ),
            ],
          ),
        if (_selectedModelId != null) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                l10n.providerDetailPageUseStreamingLabel,
                style: TextStyle(
                  fontSize: 14,
                  color: cs.onSurface.withValues(alpha: 0.9),
                ),
              ),
              const SizedBox(width: 8),
              IosSwitch(
                value: _useStream,
                onChanged: (v) => setState(() => _useStream = v),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildLoading(
    BuildContext context,
    ColorScheme cs,
    AppLocalizations l10n,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (_selectedModelId != null)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _BrandAvatar(name: _selectedModelId!, size: 24),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _selectedModelId!,
                  style: TextStyle(fontWeight: AppFontWeights.semibold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        const SizedBox(height: 16),
        const LinearProgressIndicator(minHeight: 4),
        const SizedBox(height: 12),
        Text(
          l10n.providerDetailPageTestingMessage,
          style: TextStyle(color: cs.onSurface.withValues(alpha: 0.7)),
        ),
      ],
    );
  }

  Widget _buildResult(
    BuildContext context,
    ColorScheme cs,
    AppLocalizations l10n, {
    required bool success,
    required String message,
  }) {
    final color = success ? context.appColors.success : cs.error;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (_selectedModelId != null)
          _TactileRow(
            pressedScale: 0.98,
            haptics: false,
            onTap: _pickModel,
            builder: (_) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    _BrandAvatar(name: _selectedModelId!, size: 24),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _selectedModelId!,
                        style: TextStyle(fontWeight: AppFontWeights.semibold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Lucide.ChevronDown,
                      size: 16,
                      color: cs.onSurface.withValues(alpha: 0.7),
                    ),
                  ],
                ),
              );
            },
          ),
        const SizedBox(height: 14),
        Text(
          message,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: AppFontWeights.semibold,
          ),
        ),
      ],
    );
  }

  Future<void> _pickModel() async {
    final selected = await showModelPickerForTest(
      context,
      widget.providerKey,
      widget.providerDisplayName,
      initialModelId: _selectedModelId,
    );
    if (selected != null) {
      setState(() {
        _selectedModelId = selected;
        _state = _TestState.idle;
        _errorMessage = '';
      });
    }
  }

  Future<void> _doTest() async {
    if (_selectedModelId == null) return;
    setState(() {
      _state = _TestState.loading;
      _errorMessage = '';
    });
    try {
      final cfg = context.read<SettingsProvider>().getProviderConfig(
        widget.providerKey,
        defaultName: widget.providerDisplayName,
      );
      await ProviderManager.testConnection(
        cfg,
        _selectedModelId!,
        useStream: _useStream,
      );
      if (!mounted) return;
      setState(() => _state = _TestState.success);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _TestState.error;
        _errorMessage = e.toString();
      });
    }
  }
}

Future<String?> showModelPickerForTest(
  BuildContext context,
  String providerKey,
  String providerDisplayName, {
  String? initialModelId,
}) async {
  final sel = await showModelSelector(
    context,
    limitProviderKey: providerKey,
    initialProviderKey: initialModelId == null ? null : providerKey,
    initialModelId: initialModelId,
  );
  return sel?.modelId;
}

ModelInfo _applyModelOverride(
  ModelInfo base,
  Map<String, dynamic> ov, {
  bool applyDisplayName = false,
}) {
  try {
    return ModelOverrideResolver.applyModelOverride(
      base,
      ov,
      applyDisplayName: applyDisplayName,
    );
  } catch (e, st) {
    FlutterLogger.log(
      '[ModelOverride] applyModelOverride failed: $e\n$st',
      tag: 'ModelOverride',
    );
    assert(() {
      debugPrint('[ModelOverride] applyModelOverride failed: $e');
      return true;
    }());
    return base;
  }
}

// Using flutter_slidable for reliable swipe actions with confirm + undo.

// Legacy page-based implementations removed in favor of swipeable PageView tabs.
