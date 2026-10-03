part of 'asr_services_section.dart';

Future<AsrServiceOptions?> _showAsrEditor(
  BuildContext context, {
  required SherpaModelManager modelManager,
  required Future<bool> Function() checkSystemAvailability,
  AsrServiceOptions? initial,
}) {
  final editorKey = GlobalKey<_AsrEditorState>();
  return Navigator.of(context).push<AsrServiceOptions>(
    MaterialPageRoute(
      builder: (pageContext) => Scaffold(
        backgroundColor: Theme.of(pageContext).colorScheme.surface,
        appBar: AppBar(
          leading: VoiceServicePageIconButton(
            icon: Lucide.ArrowLeft,
            tooltip: AppLocalizations.of(pageContext)!.asrServicesCancelAction,
            onTap: () => Navigator.of(pageContext).pop(),
          ),
          title: Text(
            initial == null
                ? AppLocalizations.of(pageContext)!.asrServicesAddTitle
                : AppLocalizations.of(pageContext)!.asrServicesEditTitle,
          ),
          actions: [
            VoiceServicePageIconButton(
              icon: Lucide.Check,
              tooltip: initial == null
                  ? AppLocalizations.of(pageContext)!.asrServicesAddAction
                  : AppLocalizations.of(pageContext)!.asrServicesSaveAction,
              onTap: () => editorKey.currentState?._submit(),
            ),
            const SizedBox(width: 12),
          ],
        ),
        body: _AsrEditor(
          key: editorKey,
          initial: initial,
          modelManager: modelManager,
          checkSystemAvailability: checkSystemAvailability,
          onSubmit: (value) => Navigator.of(pageContext).pop(value),
        ),
      ),
    ),
  );
}

class _AsrEditor extends StatefulWidget {
  const _AsrEditor({
    super.key,
    required this.initial,
    required this.modelManager,
    required this.checkSystemAvailability,
    required this.onSubmit,
  });

  final AsrServiceOptions? initial;
  final SherpaModelManager modelManager;
  final Future<bool> Function() checkSystemAvailability;
  final ValueChanged<AsrServiceOptions> onSubmit;

  @override
  State<_AsrEditor> createState() => _AsrEditorState();
}

class _AsrEditorState extends State<_AsrEditor> {
  late AsrServiceKind _kind;
  late final TextEditingController _nameController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _endpointController;
  late final TextEditingController _modelController;
  late final TextEditingController _resourceIdController;
  late final TextEditingController _languageController;
  String _localModelId = '';
  bool _apiKeyError = false;
  bool _checkingSystem = false;
  bool? _systemAvailable;
  final Map<String, SherpaModelInstallStatus> _modelStatuses = {};
  final Map<String, SherpaDownloadCancellationToken> _downloadTokens = {};

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _kind = initial?.kind ?? AsrServiceKind.system;
    _nameController = TextEditingController(
      text: _editableServiceName(initial),
    );
    _apiKeyController = TextEditingController(text: _apiKeyOf(initial));
    _endpointController = TextEditingController(text: _endpointOf(initial));
    _modelController = TextEditingController(text: _modelOf(initial));
    _resourceIdController = TextEditingController(text: _resourceIdOf(initial));
    _languageController = TextEditingController(text: _languageOf(initial));
    if (initial case final SherpaOnnxAsrOptions local) {
      _localModelId = local.modelId;
    }
    _refreshModelStatuses();
    if (initial is SystemAsrOptions) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkSystem());
    }
  }

  @override
  void dispose() {
    for (final token in _downloadTokens.values) {
      token.cancel();
    }
    _nameController.dispose();
    _apiKeyController.dispose();
    _endpointController.dispose();
    _modelController.dispose();
    _resourceIdController.dispose();
    _languageController.dispose();
    super.dispose();
  }

  Future<void> _refreshModelStatuses() async {
    final statuses = await widget.modelManager.listStatuses();
    if (!mounted) return;
    setState(() {
      for (final status in statuses) {
        _modelStatuses[status.model.id] = status;
      }
    });
  }

  Future<void> _checkSystem() async {
    if (_checkingSystem) return;
    setState(() => _checkingSystem = true);
    bool available;
    try {
      available = await widget.checkSystemAvailability();
    } catch (_) {
      available = false;
    }
    if (!mounted) return;
    setState(() {
      _checkingSystem = false;
      _systemAvailable = available;
    });
  }

  void _selectKind(AsrServiceKind kind) {
    if (kind == _kind) return;
    Haptics.light();
    setState(() {
      _kind = kind;
      _apiKeyError = false;
      _nameController.clear();
      _apiKeyController.clear();
      _endpointController.text = _defaultEndpoint(kind);
      _modelController.text = _defaultModel(kind);
      _resourceIdController.text = _defaultResourceId(kind);
      _languageController.text =
          kind == AsrServiceKind.mimo || kind == AsrServiceKind.step
          ? 'auto'
          : '';
    });
    if (kind == AsrServiceKind.system) unawaited(_checkSystem());
  }

  Future<void> _downloadModel(SherpaModelDefinition model) async {
    if (_downloadTokens.containsKey(model.id)) return;
    final token = SherpaDownloadCancellationToken();
    _downloadTokens[model.id] = token;
    setState(() {
      _modelStatuses[model.id] = SherpaModelInstallStatus(
        model: model,
        state: SherpaModelInstallState.downloading,
      );
    });
    try {
      await widget.modelManager.download(
        model.id,
        cancellationToken: token,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _modelStatuses[model.id] = SherpaModelInstallStatus(
              model: model,
              state: SherpaModelInstallState.downloading,
              progress: progress,
            );
          });
        },
      );
    } on SherpaDownloadCancelledException {
      // Cancellation is an expected user action.
    } catch (error) {
      if (mounted) {
        showAppSnackBar(
          context,
          message: AppLocalizations.of(
            context,
          )!.asrServicesDownloadFailed(error.toString()),
          type: NotificationType.error,
        );
      }
    } finally {
      _downloadTokens.remove(model.id);
      await _refreshModelStatuses();
    }
  }

  Future<void> _deleteModel(SherpaModelDefinition model) async {
    try {
      await widget.modelManager.delete(model.id);
      if (_localModelId == model.id && mounted) {
        setState(() => _localModelId = '');
      }
      await _refreshModelStatuses();
      if (mounted) {
        final selected = context.read<SettingsProvider>().selectedAsrService;
        if (selected is SherpaOnnxAsrOptions && selected.modelId == model.id) {
          await Provider.of<AsrProvider?>(
            context,
            listen: false,
          )?.refreshAvailability(selected);
        }
      }
    } catch (error) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: AppLocalizations.of(
          context,
        )!.asrServicesDownloadFailed(error.toString()),
        type: NotificationType.error,
      );
    }
  }

  bool get _canSubmit {
    if (_kind == AsrServiceKind.sherpaOnnx) {
      return _localModelId.isNotEmpty &&
          _modelStatuses[_localModelId]?.isInstalled == true;
    }
    if (_kind == AsrServiceKind.system) return _systemAvailable == true;
    return _apiKeyController.text.trim().isNotEmpty;
  }

  Future<void> _submit() async {
    if (_kind != AsrServiceKind.sherpaOnnx &&
        _kind != AsrServiceKind.system &&
        _apiKeyController.text.trim().isEmpty) {
      setState(() => _apiKeyError = true);
      return;
    }
    if (!_canSubmit) return;
    if (_kind == AsrServiceKind.system && _systemAvailable == null) {
      await _checkSystem();
      if (!mounted) return;
    }

    final l10n = AppLocalizations.of(context)!;
    final name = _nameController.text.trim().isEmpty
        ? _kindTitle(l10n, _kind)
        : _nameController.text.trim();
    final id = widget.initial?.id;
    final language = _languageController.text.trim();
    switch (_kind) {
      case AsrServiceKind.sherpaOnnx:
        final directory = await widget.modelManager.modelDirectory(
          _localModelId,
        );
        widget.onSubmit(
          SherpaOnnxAsrOptions(
            id: id,
            name: name,
            modelId: _localModelId,
            modelDirectory: directory.path,
            language: language,
          ),
        );
        return;
      case AsrServiceKind.system:
        widget.onSubmit(
          SystemAsrOptions(id: id, name: name, localeId: language),
        );
        return;
      case AsrServiceKind.openAiRealtime:
        final initial = widget.initial is OpenAiRealtimeAsrOptions
            ? widget.initial as OpenAiRealtimeAsrOptions
            : null;
        widget.onSubmit(
          OpenAiRealtimeAsrOptions(
            id: id,
            name: name,
            apiKey: _apiKeyController.text.trim(),
            websocketUrl: _valueOrDefault(
              _endpointController.text,
              _defaultEndpoint(_kind),
            ),
            model: _valueOrDefault(_modelController.text, _defaultModel(_kind)),
            language: language,
            prompt: initial?.prompt ?? '',
            sampleRate: initial?.sampleRate ?? 24000,
            vadThreshold: initial?.vadThreshold ?? 0,
            prefixPaddingMs: initial?.prefixPaddingMs ?? 300,
            silenceDurationMs: initial?.silenceDurationMs ?? 500,
          ),
        );
        return;
      case AsrServiceKind.dashScope:
        final initial = widget.initial is DashScopeAsrOptions
            ? widget.initial as DashScopeAsrOptions
            : null;
        widget.onSubmit(
          DashScopeAsrOptions(
            id: id,
            name: name,
            apiKey: _apiKeyController.text.trim(),
            websocketUrl: _valueOrDefault(
              _endpointController.text,
              _defaultEndpoint(_kind),
            ),
            model: _valueOrDefault(_modelController.text, _defaultModel(_kind)),
            language: language,
            sampleRate: initial?.sampleRate ?? 16000,
            vadThreshold: initial?.vadThreshold ?? 0,
            silenceDurationMs: initial?.silenceDurationMs ?? 800,
          ),
        );
        return;
      case AsrServiceKind.qwenAudio:
        final initial = widget.initial is QwenAudioAsrOptions
            ? widget.initial as QwenAudioAsrOptions
            : null;
        widget.onSubmit(
          QwenAudioAsrOptions(
            id: id,
            name: name,
            apiKey: _apiKeyController.text.trim(),
            workspaceId: _endpointController.text.trim(),
            region: initial?.region ?? 'cn-beijing',
            model: _valueOrDefault(_modelController.text, _defaultModel(_kind)),
            sampleRate: initial?.sampleRate ?? 16000,
            format: initial?.format ?? 'pcm',
          ),
        );
        return;
      case AsrServiceKind.volcengine:
        widget.onSubmit(
          VolcengineAsrOptions(
            id: id,
            name: name,
            apiKey: _apiKeyController.text.trim(),
            websocketUrl: _valueOrDefault(
              _endpointController.text,
              _defaultEndpoint(_kind),
            ),
            resourceId: _valueOrDefault(
              _resourceIdController.text,
              _defaultResourceId(_kind),
            ),
            language: language,
          ),
        );
        return;
      case AsrServiceKind.mimo:
        final initial = widget.initial is MimoAsrOptions
            ? widget.initial as MimoAsrOptions
            : null;
        widget.onSubmit(
          MimoAsrOptions(
            id: id,
            name: name,
            apiKey: _apiKeyController.text.trim(),
            baseUrl: _valueOrDefault(
              _endpointController.text,
              _defaultEndpoint(_kind),
            ),
            model: _valueOrDefault(_modelController.text, _defaultModel(_kind)),
            language: language.isEmpty ? 'auto' : language,
            sampleRate: initial?.sampleRate ?? 16000,
            segmentDurationSec: initial?.segmentDurationSec ?? 30,
          ),
        );
        return;
      case AsrServiceKind.step:
        final initial = widget.initial is StepAsrOptions
            ? widget.initial as StepAsrOptions
            : null;
        widget.onSubmit(
          StepAsrOptions(
            id: id,
            name: name,
            apiKey: _apiKeyController.text.trim(),
            baseUrl: _valueOrDefault(
              _endpointController.text,
              _defaultEndpoint(_kind),
            ),
            model: _valueOrDefault(_modelController.text, _defaultModel(_kind)),
            language: language.isEmpty ? 'auto' : language,
            sampleRate: initial?.sampleRate ?? 16000,
            segmentDurationSec: initial?.segmentDurationSec ?? 30,
            enableItn: initial?.enableItn ?? true,
            enableTimestamp: initial?.enableTimestamp ?? false,
            hotwords: initial?.hotwords ?? const [],
          ),
        );
        return;
    }
  }

  List<Widget> _configurationWidgets(AppLocalizations l10n) {
    final widgets = <Widget>[
      _EditorField(
        label: l10n.asrServicesNameLabel,
        controller: _nameController,
        hint: _kindTitle(l10n, _kind),
      ),
    ];
    if (_kind == AsrServiceKind.sherpaOnnx) {
      widgets.add(
        _LocalModelPicker(
          statuses: _modelStatuses,
          selectedModelId: _localModelId,
          downloadTokens: _downloadTokens,
          onDownload: _downloadModel,
          onCancelDownload: (model) {
            _downloadTokens[model.id]?.cancel();
            widget.modelManager.cancelDownload(model.id);
          },
          onDelete: _deleteModel,
          onUse: (model) => setState(() => _localModelId = model.id),
          languageController: _languageController,
        ),
      );
      return widgets;
    }
    if (_kind == AsrServiceKind.system) {
      widgets.add(
        _SystemConfiguration(
          available: _systemAvailable,
          checking: _checkingSystem,
          localeController: _languageController,
          onCheck: _checkSystem,
        ),
      );
      return widgets;
    }
    widgets.addAll([
      _EditorField(
        label: l10n.asrServicesApiKeyLabel,
        controller: _apiKeyController,
        obscure: true,
        errorText: _apiKeyError ? l10n.asrServicesApiKeyRequired : null,
        onChanged: (_) {
          if (_apiKeyError && _apiKeyController.text.trim().isNotEmpty) {
            setState(() => _apiKeyError = false);
          } else {
            setState(() {});
          }
        },
      ),
      _EditorField(
        label: l10n.asrServicesEndpointLabel,
        controller: _endpointController,
        hint: _defaultEndpoint(_kind),
      ),
      if (_kind == AsrServiceKind.volcengine)
        _EditorField(
          label: l10n.asrServicesResourceIdLabel,
          controller: _resourceIdController,
          hint: _defaultResourceId(_kind),
        )
      else
        _EditorField(
          label: l10n.asrServicesModelLabel,
          controller: _modelController,
          hint: _defaultModel(_kind),
        ),
      _EditorField(
        label: l10n.asrServicesLanguageLabel,
        controller: _languageController,
        hint: l10n.asrServicesAutomaticLabel,
      ),
    ]);
    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final actionLabel = widget.initial == null
        ? l10n.asrServicesAddAction
        : l10n.asrServicesSaveAction;
    final configuration = _configurationWidgets(l10n);

    return SafeArea(
      top: false,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                _EditorSectionHeader(
                  text: l10n.ttsServicesDialogProviderType,
                  first: true,
                ),
                VoiceServiceMobileCard(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                      child: SizedBox(
                        key: const ValueKey('asr-provider-choice-grid'),
                        width: double.infinity,
                        child: _ProviderChoiceGrid(
                          selected: _kind,
                          onSelected: _selectKind,
                        ),
                      ),
                    ),
                  ],
                ),
                _EditorSectionHeader(text: l10n.asrServicesSectionTitle),
                VoiceServiceMobileCard(children: configuration),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: IosTileButton(
                label: actionLabel,
                icon: Lucide.Check,
                enabled: _canSubmit,
                backgroundColor: cs.primary,
                foregroundColor: cs.primary,
                onTap: _submit,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
