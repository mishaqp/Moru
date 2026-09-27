part of 'tts_services_page.dart';

Future<void> _showSystemTtsConfig(BuildContext context) async {
  final cs = Theme.of(context).colorScheme;
  final l10n = AppLocalizations.of(context)!;
  final tts = context.read<TtsProvider>();
  double rate = tts.speechRate;
  double pitch = tts.pitch;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: false,
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
                  l10n.ttsServicesPageSystemTtsSettingsTitle,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: AppFontWeights.emphasis,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Engine selector
              FutureBuilder<List<String>>(
                future: tts.listEngines(),
                builder: (context, snap) {
                  final engines = snap.data ?? const <String>[];
                  final cur =
                      tts.engineId ?? (engines.isNotEmpty ? engines.first : '');
                  return _sheetSelectRow(
                    context,
                    label: l10n.ttsServicesPageEngineLabel,
                    value: cur.isEmpty ? l10n.ttsServicesPageAutoLabel : cur,
                    options: engines,
                    onSelected: (picked) async {
                      await tts.setEngineId(picked);
                      (ctx as Element).markNeedsBuild();
                    },
                  );
                },
              ),
              const SizedBox(height: 4),
              // Language selector
              FutureBuilder<List<String>>(
                future: tts.listLanguages(),
                builder: (context, snap) {
                  final langs = snap.data ?? const <String>[];
                  final cur =
                      tts.languageTag ??
                      (langs.contains('zh-CN')
                          ? 'zh-CN'
                          : (langs.contains('en-US')
                                ? 'en-US'
                                : (langs.isNotEmpty ? langs.first : '')));
                  return _sheetSelectRow(
                    context,
                    label: l10n.ttsServicesPageLanguageLabel,
                    value: cur.isEmpty ? l10n.ttsServicesPageAutoLabel : cur,
                    options: langs,
                    onSelected: (picked) async {
                      await tts.setLanguageTag(picked);
                      (ctx as Element).markNeedsBuild();
                    },
                  );
                },
              ),
              const SizedBox(height: 8),
              Text(
                l10n.ttsServicesPageSpeechRateLabel,
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withValues(alpha: 0.7),
                ),
              ),
              Slider(
                value: rate,
                min: 0.1,
                max: 1.0,
                onChanged: (v) {
                  rate = v;
                  // Rebuild this bottom sheet
                  (ctx as Element).markNeedsBuild();
                },
                onChangeEnd: (v) async {
                  await tts.setSpeechRate(v);
                },
              ),
              const SizedBox(height: 4),
              Text(
                l10n.ttsServicesPagePitchLabel,
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withValues(alpha: 0.7),
                ),
              ),
              Slider(
                value: pitch,
                min: 0.5,
                max: 2.0,
                onChanged: (v) {
                  pitch = v;
                  (ctx as Element).markNeedsBuild();
                },
                onChangeEnd: (v) async {
                  await tts.setPitch(v);
                },
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () async {
                    final demo = l10n.ttsServicesPageSettingsSavedMessage;
                    Navigator.of(ctx).maybePop();
                    showAppSnackBar(
                      context,
                      message: demo,
                      type: NotificationType.success,
                    );
                  },
                  icon: Icon(Lucide.Check, size: 16),
                  label: Text(l10n.ttsServicesPageDoneButton),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Widget _sheetSelectRow(
  BuildContext context, {
  required String label,
  required String value,
  required List<String> options,
  required Future<void> Function(String picked) onSelected,
}) {
  return _TactileRow(
    onTap: options.isEmpty
        ? null
        : () async {
            final picked = await showModalBottomSheet<String>(
              context: context,
              backgroundColor: context.overlaySurface,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              builder: (ctx2) {
                return SafeArea(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(ctx2).size.height * 0.6,
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: options.length,
                      separatorBuilder: (c, i) => _sheetDivider(ctx2),
                      itemBuilder: (c, i) => _sheetOption(
                        ctx2,
                        label: options[i],
                        onTap: () => Navigator.of(ctx2).pop(options[i]),
                      ),
                    ),
                  ),
                );
              },
            );
            if (picked != null && picked.isNotEmpty) {
              await onSelected(picked);
            }
          },
    builder: (pressed) {
      final baseColor = Theme.of(
        context,
      ).colorScheme.onSurface.withValues(alpha: 0.9);
      return _AnimatedPressColor(
        pressed: pressed,
        base: baseColor,
        builder: (c) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Expanded(
                  child: Text(label, style: TextStyle(fontSize: 15, color: c)),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                Icon(Lucide.ChevronRight, size: 16, color: c),
              ],
            ),
          );
        },
      );
    },
  );
}

// Bottom sheet iOS-style option
Widget _sheetOption(
  BuildContext context, {
  required String label,
  required VoidCallback onTap,
}) {
  final cs = Theme.of(context).colorScheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return _TactileRow(
    pressedScale: 1.00,
    haptics: true,
    onTap: onTap,
    builder: (pressed) {
      final base = cs.onSurface;
      final target = pressed
          ? (Color.lerp(base, cs.surface, 0.55) ?? base)
          : base;
      final bgTarget = pressed
          ? (cs.onSurface.withValues(alpha: isDark ? 0.06 : 0.05))
          : Colors.transparent;
      return TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: target),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        builder: (context, color, _) {
          final c = color ?? base;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            color: bgTarget,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(label, style: TextStyle(fontSize: 15, color: c)),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

Widget _sheetDivider(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return Divider(
    height: 1,
    thickness: 0.6,
    indent: 16,
    endIndent: 16,
    color: cs.outlineVariant.withValues(alpha: 0.18),
  );
}

const List<NetworkTtsKind> _networkTtsKinds = [
  NetworkTtsKind.openai,
  NetworkTtsKind.gemini,
  NetworkTtsKind.azure,
  NetworkTtsKind.minimax,
  NetworkTtsKind.qwen,
  NetworkTtsKind.qwenAudio,
  NetworkTtsKind.groq,
  NetworkTtsKind.xai,
  NetworkTtsKind.elevenlabs,
  NetworkTtsKind.mimo,
  NetworkTtsKind.step,
  NetworkTtsKind.fishAudio,
];

String _apiKeyOf(TtsServiceOptions? option) {
  if (option is OpenAiTtsOptions) return option.apiKey;
  if (option is GeminiTtsOptions) return option.apiKey;
  if (option is AzureTtsOptions) return option.apiKey;
  if (option is MiniMaxTtsOptions) return option.apiKey;
  if (option is QwenTtsOptions) return option.apiKey;
  if (option is QwenAudioTtsOptions) return option.apiKey;
  if (option is GroqTtsOptions) return option.apiKey;
  if (option is XaiTtsOptions) return option.apiKey;
  if (option is ElevenLabsTtsOptions) return option.apiKey;
  if (option is MimoTtsOptions) return option.apiKey;
  if (option is StepTtsOptions) return option.apiKey;
  if (option is FishAudioTtsOptions) return option.apiKey;
  return '';
}

String _baseUrlOf(TtsServiceOptions? option) {
  if (option is OpenAiTtsOptions) return option.baseUrl;
  if (option is GeminiTtsOptions) return option.baseUrl;
  if (option is AzureTtsOptions) return option.baseUrl;
  if (option is MiniMaxTtsOptions) return option.baseUrl;
  if (option is QwenTtsOptions) return option.baseUrl;
  if (option is QwenAudioTtsOptions) return option.workspaceId;
  if (option is GroqTtsOptions) return option.baseUrl;
  if (option is XaiTtsOptions) return option.baseUrl;
  if (option is ElevenLabsTtsOptions) return option.baseUrl;
  if (option is MimoTtsOptions) return option.baseUrl;
  if (option is StepTtsOptions) return option.baseUrl;
  if (option is FishAudioTtsOptions) return option.baseUrl;
  return '';
}

String _modelOf(TtsServiceOptions? option) {
  if (option is OpenAiTtsOptions) return option.model;
  if (option is GeminiTtsOptions) return option.model;
  if (option is MiniMaxTtsOptions) return option.model;
  if (option is QwenTtsOptions) return option.model;
  if (option is QwenAudioTtsOptions) return option.model;
  if (option is GroqTtsOptions) return option.model;
  if (option is ElevenLabsTtsOptions) return option.modelId;
  if (option is MimoTtsOptions) return option.model;
  if (option is StepTtsOptions) return option.model;
  if (option is FishAudioTtsOptions) return option.model;
  return '';
}

String _voiceOf(TtsServiceOptions? option) {
  if (option is OpenAiTtsOptions) return option.voice;
  if (option is GeminiTtsOptions) return option.voiceName;
  if (option is AzureTtsOptions) return option.voice;
  if (option is MiniMaxTtsOptions) return option.voiceId;
  if (option is QwenTtsOptions) return option.voice;
  if (option is QwenAudioTtsOptions) return option.voice;
  if (option is GroqTtsOptions) return option.voice;
  if (option is XaiTtsOptions) return option.voiceId;
  if (option is ElevenLabsTtsOptions) return option.voiceId;
  if (option is MimoTtsOptions) return option.voice;
  if (option is StepTtsOptions) return option.voice;
  if (option is FishAudioTtsOptions) return option.referenceId;
  return '';
}

String _defaultBaseUrl(NetworkTtsKind k) {
  switch (k) {
    case NetworkTtsKind.openai:
      return 'https://api.openai.com/v1';
    case NetworkTtsKind.gemini:
      return 'https://generativelanguage.googleapis.com/v1beta';
    case NetworkTtsKind.azure:
      return '';
    case NetworkTtsKind.minimax:
      return 'https://api.minimaxi.com/v1';
    case NetworkTtsKind.qwen:
      return 'https://dashscope.aliyuncs.com/api/v1';
    case NetworkTtsKind.groq:
      return 'https://api.groq.com/openai/v1';
    case NetworkTtsKind.xai:
      return 'https://api.x.ai/v1';
    case NetworkTtsKind.elevenlabs:
      return 'https://api.elevenlabs.io';
    case NetworkTtsKind.mimo:
      return 'https://api.xiaomimimo.com/v1';
    case NetworkTtsKind.qwenAudio:
      return 'wss://dashscope.aliyuncs.com/api-ws/v1/inference';
    case NetworkTtsKind.step:
      return 'https://api.stepfun.com/v1';
    case NetworkTtsKind.fishAudio:
      return 'https://api.fish.audio';
  }
}

String _defaultModel(NetworkTtsKind k) {
  switch (k) {
    case NetworkTtsKind.openai:
      return 'gpt-4o-mini-tts';
    case NetworkTtsKind.gemini:
      return 'gemini-3.1-flash-tts-preview';
    case NetworkTtsKind.azure:
      return '';
    case NetworkTtsKind.minimax:
      return 'speech-2.8-turbo';
    case NetworkTtsKind.qwen:
      return 'qwen3-tts-flash';
    case NetworkTtsKind.groq:
      return 'canopylabs/orpheus-v1-english';
    case NetworkTtsKind.xai:
      return '';
    case NetworkTtsKind.elevenlabs:
      return 'eleven_multilingual_v2';
    case NetworkTtsKind.mimo:
      return 'mimo-v2.5-tts';
    case NetworkTtsKind.qwenAudio:
      return 'qwen-audio-3.0-tts-flash';
    case NetworkTtsKind.step:
      return 'stepaudio-2.5-tts';
    case NetworkTtsKind.fishAudio:
      return 's2.1-pro';
  }
}

String _defaultVoice(NetworkTtsKind k) {
  switch (k) {
    case NetworkTtsKind.openai:
      return 'alloy';
    case NetworkTtsKind.gemini:
      return 'Kore';
    case NetworkTtsKind.azure:
      return 'zh-CN-XiaoxiaoNeural';
    case NetworkTtsKind.minimax:
      return 'female-shaonv';
    case NetworkTtsKind.qwen:
      return 'Cherry';
    case NetworkTtsKind.groq:
      return 'austin';
    case NetworkTtsKind.xai:
      return 'eve';
    case NetworkTtsKind.elevenlabs:
      return '';
    case NetworkTtsKind.mimo:
      return 'mimo_default';
    case NetworkTtsKind.qwenAudio:
      return 'longanhuan_v3.6';
    case NetworkTtsKind.step:
      return 'cixingnansheng';
    case NetworkTtsKind.fishAudio:
      return '';
  }
}

String _voiceLabelFor(NetworkTtsKind k, AppLocalizations l10n) {
  switch (k) {
    case NetworkTtsKind.openai:
      return l10n.ttsServicesFieldVoiceLabel;
    case NetworkTtsKind.gemini:
      return l10n.ttsServicesFieldVoiceLabel; // same label
    case NetworkTtsKind.azure:
      return l10n.ttsServicesFieldVoiceLabel;
    case NetworkTtsKind.minimax:
      return l10n.ttsServicesFieldVoiceIdLabel;
    case NetworkTtsKind.qwen:
      return l10n.ttsServicesFieldVoiceLabel;
    case NetworkTtsKind.groq:
      return l10n.ttsServicesFieldVoiceLabel;
    case NetworkTtsKind.xai:
      return l10n.ttsServicesFieldVoiceIdLabel;
    case NetworkTtsKind.elevenlabs:
      return l10n.ttsServicesFieldVoiceIdLabel;
    case NetworkTtsKind.mimo:
      return l10n.ttsServicesFieldVoiceLabel;
    case NetworkTtsKind.qwenAudio:
      return l10n.ttsServicesFieldVoiceLabel;
    case NetworkTtsKind.step:
      return l10n.ttsServicesFieldVoiceLabel;
    case NetworkTtsKind.fishAudio:
      return l10n.ttsServicesFieldVoiceIdLabel;
  }
}
