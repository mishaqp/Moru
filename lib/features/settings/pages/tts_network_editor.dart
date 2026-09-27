part of 'tts_services_page.dart';

Future<TtsServiceOptions?> _showAddNetworkTtsSheet(BuildContext context) =>
    _showNetworkTtsEditorPage(context, null);

Future<TtsServiceOptions?> _showEditNetworkTtsSheet(
  BuildContext context,
  TtsServiceOptions initial,
) => _showNetworkTtsEditorPage(context, initial);

Future<TtsServiceOptions?> _showNetworkTtsEditorPage(
  BuildContext context,
  TtsServiceOptions? initial,
) {
  return Navigator.of(context).push<TtsServiceOptions>(
    MaterialPageRoute(builder: (_) => _NetworkTtsEditorPage(initial: initial)),
  );
}

class _NetworkTtsEditorPage extends StatefulWidget {
  const _NetworkTtsEditorPage({this.initial});

  final TtsServiceOptions? initial;

  @override
  State<_NetworkTtsEditorPage> createState() => _NetworkTtsEditorPageState();
}

class _NetworkTtsEditorPageState extends State<_NetworkTtsEditorPage> {
  final _formKey = GlobalKey<FormState>();
  late NetworkTtsKind _kind;
  late final TextEditingController _nameCtl;
  late final TextEditingController _apiKeyCtl;
  late final TextEditingController _baseCtl;
  late final TextEditingController _modelCtl;
  late final TextEditingController _voiceCtl;
  late final TextEditingController _emotionCtl;
  late final TextEditingController _speedCtl;
  late final TextEditingController _languageTypeCtl;
  late final TextEditingController _languageCtl;
  late final TextEditingController _volumeCtl;
  late final TextEditingController _pitchCtl;
  late final TextEditingController _languageBoostCtl;
  late final TextEditingController _formatCtl;
  late final TextEditingController _sampleRateCtl;
  late final TextEditingController _bitrateCtl;
  late final TextEditingController _channelCtl;
  late final TextEditingController _pronunciationCtl;
  late final TextEditingController _regionCtl;
  late final TextEditingController _instructionCtl;
  late final TextEditingController _outputFormatCtl;
  late final TextEditingController _temperatureCtl;
  late final TextEditingController _topPCtl;
  late final TextEditingController _latencyCtl;
  late bool _subtitleEnable;
  late bool _stream;
  late bool _optimizeTextPreview;

  bool get _isMimoVoiceDesign =>
      _kind == NetworkTtsKind.mimo &&
      _modelCtl.text.trim() == 'mimo-v2.5-tts-voicedesign';

  bool get _isMimoVoiceClone =>
      _kind == NetworkTtsKind.mimo &&
      _modelCtl.text.trim() == 'mimo-v2.5-tts-voiceclone';

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _kind = initial?.kind ?? NetworkTtsKind.openai;
    _nameCtl = TextEditingController(text: initial?.name ?? '');
    _apiKeyCtl = TextEditingController(text: _apiKeyOf(initial));
    _baseCtl = TextEditingController(text: _baseUrlOf(initial));
    _modelCtl = TextEditingController(text: _modelOf(initial));
    _voiceCtl = TextEditingController(text: _voiceOf(initial));
    _emotionCtl = TextEditingController(
      text: (initial is MiniMaxTtsOptions) ? initial.emotion : '',
    );
    _speedCtl = TextEditingController(
      text: initial is MiniMaxTtsOptions
          ? initial.speed.toString()
          : initial is StepTtsOptions
          ? initial.speed.toString()
          : initial is FishAudioTtsOptions
          ? initial.speed.toString()
          : '1.0',
    );
    _languageTypeCtl = TextEditingController(
      text: (initial is QwenTtsOptions) ? initial.languageType : 'Auto',
    );
    _languageCtl = TextEditingController(
      text: initial is XaiTtsOptions
          ? initial.language
          : initial is AzureTtsOptions
          ? initial.language
          : 'auto',
    );
    _volumeCtl = TextEditingController(
      text: initial is MiniMaxTtsOptions
          ? initial.volume.toString()
          : initial is StepTtsOptions
          ? initial.volume.toString()
          : '1.0',
    );
    _pitchCtl = TextEditingController(
      text: initial is MiniMaxTtsOptions ? initial.pitch.toString() : '0',
    );
    _languageBoostCtl = TextEditingController(
      text: initial is MiniMaxTtsOptions ? initial.languageBoost : '',
    );
    _formatCtl = TextEditingController(
      text: initial is MiniMaxTtsOptions
          ? initial.format
          : initial is QwenAudioTtsOptions
          ? initial.format
          : initial is FishAudioTtsOptions
          ? initial.format
          : 'mp3',
    );
    _sampleRateCtl = TextEditingController(
      text: initial is MiniMaxTtsOptions
          ? initial.sampleRate.toString()
          : initial is QwenAudioTtsOptions
          ? initial.sampleRate.toString()
          : initial is StepTtsOptions
          ? initial.sampleRate.toString()
          : initial is FishAudioTtsOptions
          ? initial.sampleRate.toString()
          : '32000',
    );
    _bitrateCtl = TextEditingController(
      text: initial is MiniMaxTtsOptions
          ? initial.bitrate.toString()
          : '128000',
    );
    _channelCtl = TextEditingController(
      text: initial is MiniMaxTtsOptions ? initial.channel.toString() : '1',
    );
    _pronunciationCtl = TextEditingController(
      text: initial is MiniMaxTtsOptions
          ? initial.pronunciationDictionary.join('\n')
          : '',
    );
    _regionCtl = TextEditingController(
      text: initial is QwenAudioTtsOptions ? initial.region : 'cn-beijing',
    );
    _instructionCtl = TextEditingController(
      text: initial is MimoTtsOptions
          ? initial.instruction
          : initial is StepTtsOptions
          ? initial.instruction
          : '',
    );
    _outputFormatCtl = TextEditingController(
      text: initial is ElevenLabsTtsOptions
          ? initial.outputFormat
          : initial is StepTtsOptions
          ? initial.responseFormat
          : 'mp3_44100_128',
    );
    _temperatureCtl = TextEditingController(
      text: initial is FishAudioTtsOptions
          ? initial.temperature.toString()
          : '0.7',
    );
    _topPCtl = TextEditingController(
      text: initial is FishAudioTtsOptions ? initial.topP.toString() : '0.7',
    );
    _latencyCtl = TextEditingController(
      text: initial is FishAudioTtsOptions ? initial.latency : 'normal',
    );
    _subtitleEnable = initial is MiniMaxTtsOptions
        ? initial.subtitleEnable
        : false;
    _stream = initial is MimoTtsOptions ? initial.stream : true;
    _optimizeTextPreview = initial is MimoTtsOptions
        ? initial.optimizeTextPreview
        : false;
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _apiKeyCtl.dispose();
    _baseCtl.dispose();
    _modelCtl.dispose();
    _voiceCtl.dispose();
    _emotionCtl.dispose();
    _speedCtl.dispose();
    _languageTypeCtl.dispose();
    _languageCtl.dispose();
    _volumeCtl.dispose();
    _pitchCtl.dispose();
    _languageBoostCtl.dispose();
    _formatCtl.dispose();
    _sampleRateCtl.dispose();
    _bitrateCtl.dispose();
    _channelCtl.dispose();
    _pronunciationCtl.dispose();
    _regionCtl.dispose();
    _instructionCtl.dispose();
    _outputFormatCtl.dispose();
    _temperatureCtl.dispose();
    _topPCtl.dispose();
    _latencyCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        leading: Tooltip(
          message: l10n.ttsServicesPageBackButton,
          child: _TactileIconButton(
            icon: Lucide.ArrowLeft,
            color: cs.onSurface,
            size: 22,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ),
        title: Text(
          widget.initial == null
              ? l10n.ttsServicesDialogAddTitle
              : l10n.ttsServicesDialogEditTitle,
        ),
        actions: [
          Tooltip(
            message: widget.initial == null
                ? l10n.ttsServicesDialogAddButton
                : l10n.ttsServicesDialogSaveButton,
            child: _TactileIconButton(
              icon: Lucide.Check,
              color: cs.onSurface,
              size: 22,
              onTap: _submit,
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    _header(
                      context,
                      l10n.ttsServicesDialogProviderType,
                      first: true,
                    ),
                    SectionCard(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                          child: _ProviderKindWrap(
                            value: _kind,
                            onChanged: _changeKind,
                          ),
                        ),
                      ],
                    ),
                    _header(context, l10n.ttsServicesPageTitle),
                    SectionCard(
                      children: [
                        _TtsEditorTextField(
                          label: l10n.ttsServicesFieldNameLabel,
                          controller: _nameCtl,
                          hint: networkTtsKindDisplayName(_kind),
                        ),
                        _TtsEditorTextField(
                          label: l10n.ttsServicesFieldApiKeyLabel,
                          controller: _apiKeyCtl,
                          obscure: true,
                        ),
                        _TtsEditorTextField(
                          label: _kind == NetworkTtsKind.qwenAudio
                              ? l10n.ttsServicesFieldWorkspaceIdLabel
                              : l10n.ttsServicesFieldBaseUrlLabel,
                          controller: _baseCtl,
                          hint: _kind == NetworkTtsKind.qwenAudio
                              ? null
                              : _kind == NetworkTtsKind.azure
                              ? 'https://<region>.tts.speech.microsoft.com'
                              : _defaultBaseUrl(_kind),
                        ),
                        if (_kind != NetworkTtsKind.xai &&
                            _kind != NetworkTtsKind.azure)
                          _TtsEditorTextField(
                            label: l10n.ttsServicesFieldModelLabel,
                            controller: _modelCtl,
                            hint: _defaultModel(_kind),
                            onChanged: _kind == NetworkTtsKind.mimo
                                ? (_) => setState(() {})
                                : null,
                          ),
                        if (!_isMimoVoiceDesign)
                          _TtsEditorTextField(
                            label: _isMimoVoiceClone
                                ? l10n.ttsServicesFieldReferenceAudioLabel
                                : _voiceLabelFor(_kind, l10n),
                            controller: _voiceCtl,
                            hint: _defaultVoice(_kind),
                          ),
                        if (_isMimoVoiceClone)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                            child: SizedBox(
                              width: double.infinity,
                              child: IosTileButton(
                                label: l10n
                                    .ttsServicesFieldChooseReferenceAudioButton,
                                icon: Lucide.FileText,
                                onTap: _pickMimoReferenceAudio,
                              ),
                            ),
                          ),
                        if (_kind == NetworkTtsKind.minimax) ...[
                          _TtsEditorSelectField(
                            label: l10n.ttsServicesFieldEmotionLabel,
                            value: _emotionCtl.text,
                            options: miniMaxEmotionValues,
                            labelFor: (value) => value.isEmpty
                                ? l10n.ttsServicesEmotionAutoLabel
                                : value,
                            onChanged: (value) =>
                                setState(() => _emotionCtl.text = value),
                          ),
                          _TtsEditorTextField(
                            label: l10n.ttsServicesFieldSpeedLabel,
                            controller: _speedCtl,
                            hint: '1.0',
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                          ),
                          _TtsEditorTextField(
                            label: l10n.ttsServicesFieldVolumeLabel,
                            controller: _volumeCtl,
                            hint: '1.0',
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                          ),
                          _TtsEditorTextField(
                            label: l10n.ttsServicesFieldPitchLabel,
                            controller: _pitchCtl,
                            hint: '0',
                            keyboardType: TextInputType.number,
                          ),
                          _TtsEditorTextField(
                            label: l10n.ttsServicesFieldLanguageBoostLabel,
                            controller: _languageBoostCtl,
                            hint: 'auto',
                          ),
                          _TtsEditorSelectField(
                            label: l10n.ttsServicesFieldFormatLabel,
                            value: _formatCtl.text,
                            options: miniMaxAudioFormats,
                            onChanged: (value) =>
                                setState(() => _formatCtl.text = value),
                          ),
                          _TtsEditorSelectField(
                            label: l10n.ttsServicesFieldSampleRateLabel,
                            value: _sampleRateCtl.text,
                            options: miniMaxSampleRates
                                .map((value) => value.toString())
                                .toList(growable: false),
                            onChanged: (value) =>
                                setState(() => _sampleRateCtl.text = value),
                          ),
                          _TtsEditorSelectField(
                            label: l10n.ttsServicesFieldBitrateLabel,
                            value: _bitrateCtl.text,
                            options: miniMaxBitrates
                                .map((value) => value.toString())
                                .toList(growable: false),
                            onChanged: (value) =>
                                setState(() => _bitrateCtl.text = value),
                          ),
                          _TtsEditorSelectField(
                            label: l10n.ttsServicesFieldChannelLabel,
                            value: _channelCtl.text,
                            options: const <String>['1', '2'],
                            onChanged: (value) =>
                                setState(() => _channelCtl.text = value),
                          ),
                          _TtsEditorTextField(
                            label: l10n
                                .ttsServicesFieldPronunciationDictionaryLabel,
                            controller: _pronunciationCtl,
                            maxLines: 3,
                          ),
                        ],
                        if (_kind == NetworkTtsKind.qwen) ...[
                          _TtsEditorTextField(
                            label: l10n.ttsServicesFieldLanguageTypeLabel,
                            controller: _languageTypeCtl,
                            hint: 'Auto',
                          ),
                        ],
                        if (_kind == NetworkTtsKind.xai ||
                            _kind == NetworkTtsKind.azure) ...[
                          _TtsEditorTextField(
                            label: l10n.ttsServicesFieldLanguageLabel,
                            controller: _languageCtl,
                            hint: _kind == NetworkTtsKind.azure
                                ? 'zh-CN'
                                : 'auto',
                          ),
                        ],
                        if (_kind == NetworkTtsKind.elevenlabs) ...[
                          _TtsEditorTextField(
                            label: l10n.ttsServicesFieldOutputFormatLabel,
                            controller: _outputFormatCtl,
                            hint: 'mp3_44100_128',
                          ),
                        ],
                        if (_kind == NetworkTtsKind.mimo) ...[
                          _TtsEditorTextField(
                            label: l10n.ttsServicesFieldInstructionLabel,
                            controller: _instructionCtl,
                            maxLines: 3,
                          ),
                          _TtsEditorSwitchField(
                            label: l10n.ttsServicesFieldStreamingLabel,
                            value: _stream,
                            onChanged: (value) =>
                                setState(() => _stream = value),
                          ),
                          if (_isMimoVoiceDesign)
                            _TtsEditorSwitchField(
                              label:
                                  l10n.ttsServicesFieldOptimizeTextPreviewLabel,
                              value: _optimizeTextPreview,
                              onChanged: (value) =>
                                  setState(() => _optimizeTextPreview = value),
                            ),
                        ],
                        if (_kind == NetworkTtsKind.qwenAudio) ...[
                          _TtsEditorTextField(
                            label: l10n.ttsServicesFieldRegionLabel,
                            controller: _regionCtl,
                            hint: 'cn-beijing',
                          ),
                          _TtsEditorSelectField(
                            label: l10n.ttsServicesFieldFormatLabel,
                            value: _formatCtl.text,
                            options: const <String>['mp3', 'wav', 'pcm'],
                            onChanged: (value) =>
                                setState(() => _formatCtl.text = value),
                          ),
                          _TtsEditorTextField(
                            label: l10n.ttsServicesFieldSampleRateLabel,
                            controller: _sampleRateCtl,
                            keyboardType: TextInputType.number,
                          ),
                        ],
                        if (_kind == NetworkTtsKind.step) ...[
                          _TtsEditorSelectField(
                            label: l10n.ttsServicesFieldOutputFormatLabel,
                            value: _outputFormatCtl.text,
                            options: const <String>['mp3', 'wav', 'pcm'],
                            onChanged: (value) =>
                                setState(() => _outputFormatCtl.text = value),
                          ),
                          _TtsEditorTextField(
                            label: l10n.ttsServicesFieldSpeedLabel,
                            controller: _speedCtl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                          ),
                          _TtsEditorTextField(
                            label: l10n.ttsServicesFieldVolumeLabel,
                            controller: _volumeCtl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                          ),
                          _TtsEditorTextField(
                            label: l10n.ttsServicesFieldSampleRateLabel,
                            controller: _sampleRateCtl,
                            keyboardType: TextInputType.number,
                          ),
                          _TtsEditorTextField(
                            label: l10n.ttsServicesFieldInstructionLabel,
                            controller: _instructionCtl,
                            maxLines: 3,
                          ),
                        ],
                        if (_kind == NetworkTtsKind.fishAudio) ...[
                          _TtsEditorSelectField(
                            label: l10n.ttsServicesFieldFormatLabel,
                            value: _formatCtl.text,
                            options: fishAudioSampleRates.keys.toList(
                              growable: false,
                            ),
                            onChanged: (value) {
                              final allowed = fishAudioSampleRates[value]!;
                              setState(() {
                                _formatCtl.text = value;
                                if (!allowed.contains(
                                  int.tryParse(_sampleRateCtl.text),
                                )) {
                                  _sampleRateCtl.text = allowed.last.toString();
                                }
                              });
                            },
                          ),
                          _TtsEditorTextField(
                            label: l10n.ttsServicesFieldTemperatureLabel,
                            controller: _temperatureCtl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                          ),
                          _TtsEditorTextField(
                            label: l10n.ttsServicesFieldTopPLabel,
                            controller: _topPCtl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                          ),
                          _TtsEditorTextField(
                            label: l10n.ttsServicesFieldSpeedLabel,
                            controller: _speedCtl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                          ),
                          _TtsEditorSelectField(
                            label: l10n.ttsServicesFieldSampleRateLabel,
                            value: _sampleRateCtl.text,
                            options:
                                (fishAudioSampleRates[_formatCtl.text] ??
                                        const <int>[44100])
                                    .map((value) => value.toString())
                                    .toList(growable: false),
                            onChanged: (value) =>
                                setState(() => _sampleRateCtl.text = value),
                          ),
                          _TtsEditorTextField(
                            label: l10n.ttsServicesFieldLatencyLabel,
                            controller: _latencyCtl,
                            hint: 'normal',
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: IosTileButton(
                    label: widget.initial == null
                        ? l10n.ttsServicesDialogAddButton
                        : l10n.ttsServicesDialogSaveButton,
                    icon: Lucide.Check,
                    onTap: _submit,
                    backgroundColor: cs.primary,
                    foregroundColor: cs.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _submit() {
    final l10n = AppLocalizations.of(context)!;
    if (_apiKeyCtl.text.trim().isEmpty) {
      showAppSnackBar(
        context,
        message: l10n.ttsServicesValidationApiKeyRequired,
        type: NotificationType.error,
      );
      return;
    }
    if (_kind == NetworkTtsKind.azure &&
        !isValidAzureTtsEndpoint(_baseCtl.text)) {
      showAppSnackBar(
        context,
        message: l10n.searchServicesAddDialogUrlRequired,
        type: NotificationType.error,
      );
      return;
    }
    if ((_kind == NetworkTtsKind.fishAudio || _isMimoVoiceClone) &&
        _voiceCtl.text.trim().isEmpty) {
      showAppSnackBar(
        context,
        message: l10n.ttsServicesValidationReferenceIdRequired,
        type: NotificationType.error,
      );
      return;
    }
    if (_isMimoVoiceDesign && _instructionCtl.text.trim().isEmpty) {
      showAppSnackBar(
        context,
        message: l10n.ttsServicesValidationInstructionRequired,
        type: NotificationType.error,
      );
      return;
    }
    if (_kind == NetworkTtsKind.fishAudio) {
      final allowed = fishAudioSampleRates[_formatCtl.text] ?? const <int>[];
      final sampleRate = int.tryParse(_sampleRateCtl.text);
      if (!allowed.contains(sampleRate)) {
        showAppSnackBar(
          context,
          message: AppLocalizations.of(context)!
              .ttsServicesValidationSampleRate(
                _formatCtl.text,
                allowed.join(', '),
              ),
          type: NotificationType.error,
        );
        return;
      }
    }
    Navigator.of(context).pop(_buildOptions());
  }

  Future<void> _pickMimoReferenceAudio() async {
    try {
      final dataUri = await pickMimoReferenceAudioDataUri();
      if (dataUri == null || !mounted) return;
      setState(() => _voiceCtl.text = dataUri);
    } catch (error) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: error.toString(),
        type: NotificationType.error,
      );
    }
  }

  void _changeKind(NetworkTtsKind kind) {
    if (_kind == kind) return;
    setState(() => _kind = kind);
    _baseCtl.text = kind == NetworkTtsKind.qwenAudio
        ? ''
        : _defaultBaseUrl(kind);
    _modelCtl.text = _defaultModel(kind);
    _voiceCtl.text = _defaultVoice(kind);
    _languageCtl.text = kind == NetworkTtsKind.azure ? 'zh-CN' : 'auto';
    _emotionCtl.text = '';
    _speedCtl.text = '1.0';
    _volumeCtl.text = '1.0';
    _pitchCtl.text = '0';
    _languageBoostCtl.clear();
    _formatCtl.text = 'mp3';
    _sampleRateCtl.text = switch (kind) {
      NetworkTtsKind.qwenAudio => '22050',
      NetworkTtsKind.step => '24000',
      _ => '32000',
    };
    _bitrateCtl.text = '128000';
    _channelCtl.text = '1';
    _pronunciationCtl.clear();
    _regionCtl.text = 'cn-beijing';
    _instructionCtl.clear();
    _outputFormatCtl.text = switch (kind) {
      NetworkTtsKind.elevenlabs => 'mp3_44100_128',
      _ => 'mp3',
    };
    _temperatureCtl.text = '0.7';
    _topPCtl.text = '0.7';
    _latencyCtl.text = 'normal';
    _subtitleEnable = false;
    _stream = true;
    _optimizeTextPreview = false;
    if (mounted) setState(() {});
  }

  TtsServiceOptions _buildOptions() {
    final initial = widget.initial;
    final name = _nameCtl.text.trim().isEmpty
        ? networkTtsKindDisplayName(_kind)
        : _nameCtl.text.trim();
    final apiKey = _apiKeyCtl.text.trim();
    final base = _baseCtl.text.trim().isEmpty
        ? _defaultBaseUrl(_kind)
        : _baseCtl.text.trim();
    final model = _modelCtl.text.trim().isEmpty
        ? _defaultModel(_kind)
        : _modelCtl.text.trim();
    final rawVoice = _voiceCtl.text.trim();
    final voice = rawVoice.isEmpty ? _defaultVoice(_kind) : rawVoice;
    switch (_kind) {
      case NetworkTtsKind.openai:
        return OpenAiTtsOptions(
          id: initial?.id,
          enabled: true,
          name: name,
          apiKey: apiKey,
          baseUrl: base,
          model: model,
          voice: voice,
        );
      case NetworkTtsKind.gemini:
        return GeminiTtsOptions(
          id: initial?.id,
          enabled: true,
          name: name,
          apiKey: apiKey,
          baseUrl: base,
          model: model,
          voiceName: voice,
        );
      case NetworkTtsKind.azure:
        return AzureTtsOptions(
          id: initial?.id,
          enabled: true,
          name: name,
          apiKey: apiKey,
          baseUrl: base,
          language: _languageCtl.text.trim().isEmpty
              ? 'zh-CN'
              : _languageCtl.text.trim(),
          voice: voice,
        );
      case NetworkTtsKind.minimax:
        return MiniMaxTtsOptions(
          id: initial?.id,
          enabled: true,
          name: name,
          apiKey: apiKey,
          baseUrl: base,
          model: model,
          voiceId: voice,
          emotion: _emotionCtl.text.trim(),
          speed: double.tryParse(_speedCtl.text.trim()) ?? 1.0,
          volume: double.tryParse(_volumeCtl.text.trim()) ?? 1.0,
          pitch: int.tryParse(_pitchCtl.text.trim()) ?? 0,
          languageBoost: _languageBoostCtl.text.trim(),
          format: _formatCtl.text.trim(),
          sampleRate: int.tryParse(_sampleRateCtl.text.trim()) ?? 32000,
          bitrate: int.tryParse(_bitrateCtl.text.trim()) ?? 128000,
          channel: int.tryParse(_channelCtl.text.trim()) ?? 1,
          subtitleEnable: _subtitleEnable,
          pronunciationDictionary: _pronunciationCtl.text
              .split('\n')
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toList(growable: false),
        );
      case NetworkTtsKind.qwen:
        return QwenTtsOptions(
          id: initial?.id,
          enabled: true,
          name: name,
          apiKey: apiKey,
          baseUrl: base,
          model: model,
          voice: voice,
          languageType: _languageTypeCtl.text.trim().isEmpty
              ? 'Auto'
              : _languageTypeCtl.text.trim(),
        );
      case NetworkTtsKind.groq:
        return GroqTtsOptions(
          id: initial?.id,
          enabled: true,
          name: name,
          apiKey: apiKey,
          baseUrl: base,
          model: model,
          voice: voice,
        );
      case NetworkTtsKind.xai:
        return XaiTtsOptions(
          id: initial?.id,
          enabled: true,
          name: name,
          apiKey: apiKey,
          baseUrl: base,
          voiceId: voice,
          language: _languageCtl.text.trim().isEmpty
              ? 'auto'
              : _languageCtl.text.trim(),
        );
      case NetworkTtsKind.elevenlabs:
        return ElevenLabsTtsOptions(
          id: initial?.id,
          enabled: true,
          name: name,
          apiKey: apiKey,
          baseUrl: base,
          modelId: model,
          voiceId: voice,
          outputFormat: _outputFormatCtl.text.trim().isEmpty
              ? 'mp3_44100_128'
              : _outputFormatCtl.text.trim(),
        );
      case NetworkTtsKind.mimo:
        return MimoTtsOptions(
          id: initial?.id,
          enabled: true,
          name: name,
          apiKey: apiKey,
          baseUrl: base,
          model: model,
          voice: model == 'mimo-v2.5-tts-voicedesign' ? '' : voice,
          instruction: _instructionCtl.text.trim(),
          stream: _stream,
          optimizeTextPreview: _optimizeTextPreview,
        );
      case NetworkTtsKind.qwenAudio:
        return QwenAudioTtsOptions(
          id: initial?.id,
          enabled: true,
          name: name,
          apiKey: apiKey,
          workspaceId: base == _defaultBaseUrl(_kind) ? '' : base,
          region: _regionCtl.text.trim().isEmpty
              ? 'cn-beijing'
              : _regionCtl.text.trim(),
          model: model,
          voice: voice,
          format: _formatCtl.text.trim().isEmpty
              ? 'mp3'
              : _formatCtl.text.trim(),
          sampleRate: int.tryParse(_sampleRateCtl.text.trim()) ?? 22050,
        );
      case NetworkTtsKind.step:
        return StepTtsOptions(
          id: initial?.id,
          enabled: true,
          name: name,
          apiKey: apiKey,
          baseUrl: base,
          model: model,
          voice: voice,
          responseFormat:
              _outputFormatCtl.text.trim().isEmpty ||
                  _outputFormatCtl.text.contains('_')
              ? 'mp3'
              : _outputFormatCtl.text.trim(),
          speed: double.tryParse(_speedCtl.text.trim()) ?? 1.0,
          volume: double.tryParse(_volumeCtl.text.trim()) ?? 1.0,
          sampleRate: int.tryParse(_sampleRateCtl.text.trim()) ?? 24000,
          instruction: _instructionCtl.text.trim(),
        );
      case NetworkTtsKind.fishAudio:
        return FishAudioTtsOptions(
          id: initial?.id,
          enabled: true,
          name: name,
          apiKey: apiKey,
          baseUrl: base,
          model: model,
          referenceId: voice,
          format: _formatCtl.text.trim().isEmpty
              ? 'mp3'
              : _formatCtl.text.trim(),
          temperature: double.tryParse(_temperatureCtl.text.trim()) ?? 0.7,
          topP: double.tryParse(_topPCtl.text.trim()) ?? 0.7,
          speed: double.tryParse(_speedCtl.text.trim()) ?? 1.0,
          sampleRate: int.tryParse(_sampleRateCtl.text.trim()) ?? 44100,
          latency: _latencyCtl.text.trim().isEmpty
              ? 'normal'
              : _latencyCtl.text.trim(),
        );
    }
  }
}

class _ProviderKindWrap extends StatelessWidget {
  const _ProviderKindWrap({required this.value, required this.onChanged});

  final NetworkTtsKind value;
  final ValueChanged<NetworkTtsKind> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final kind in _networkTtsKinds)
          _ProviderKindChip(
            kind: kind,
            selected: kind == value,
            onTap: () => onChanged(kind),
          ),
      ],
    );
  }
}

class _ProviderKindChip extends StatelessWidget {
  const _ProviderKindChip({
    required this.kind,
    required this.selected,
    required this.onTap,
  });

  final NetworkTtsKind kind;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _TactileRow(
      pressedScale: 0.98,
      onTap: onTap,
      builder: (pressed) {
        final bg = selected
            ? cs.primary.withValues(alpha: 0.13)
            : cs.onSurface.withValues(alpha: 0.06);
        final border = selected
            ? cs.primary.withValues(alpha: 0.5)
            : cs.outlineVariant.withValues(alpha: 0.22);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: pressed
                ? Color.alphaBlend(cs.onSurface.withValues(alpha: 0.06), bg)
                : bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border, width: 0.8),
          ),
          child: Text(
            networkTtsKindDisplayName(kind),
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

class _TtsEditorTextField extends StatefulWidget {
  const _TtsEditorTextField({
    required this.label,
    required this.controller,
    this.hint,
    this.obscure = false,
    this.keyboardType,
    this.maxLines = 1,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final int maxLines;
  final ValueChanged<String>? onChanged;

  @override
  State<_TtsEditorTextField> createState() => _TtsEditorTextFieldState();
}

class _TtsEditorTextFieldState extends State<_TtsEditorTextField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
            keyboardType: widget.keyboardType,
            maxLines: widget.obscure ? 1 : widget.maxLines,
            onChanged: widget.onChanged,
            style: TextStyle(
              fontSize: 15,
              fontWeight: AppFontWeights.medium,
              color: cs.onSurface.withValues(alpha: 0.92),
            ),
            decoration: InputDecoration(
              hintText: widget.hint,
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
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              suffixIcon: widget.obscure
                  ? _SmallTactileIcon(
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

class _TtsEditorSelectField extends StatelessWidget {
  const _TtsEditorSelectField({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.labelFor,
  });

  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  final String Function(String value)? labelFor;

  @override
  Widget build(BuildContext context) {
    final values = <String>[if (!options.contains(value)) value, ...options];
    return VoiceServiceMobileSelectRow<String>(
      label: label,
      value: value,
      options: values,
      labelFor: labelFor ?? (option) => option,
      onSelected: onChanged,
    );
  }
}

class _TtsEditorSwitchField extends StatelessWidget {
  const _TtsEditorSwitchField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _TactileRow(
      onTap: () => onChanged(!value),
      builder: (pressed) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: AppFontWeights.medium,
                  color: cs.onSurface.withValues(alpha: pressed ? 0.68 : 0.9),
                ),
              ),
            ),
            const SizedBox(width: 12),
            IosSwitch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}
