part of 'asr_services_section.dart';

IconData _kindIcon(AsrServiceKind kind) {
  switch (kind) {
    case AsrServiceKind.system:
      return Lucide.Mic;
    case AsrServiceKind.sherpaOnnx:
      return Lucide.HardDrive;
    case AsrServiceKind.openAiRealtime:
      return Lucide.AudioWaveform;
    case AsrServiceKind.dashScope:
      return Lucide.Network;
    case AsrServiceKind.qwenAudio:
      return Lucide.Network;
    case AsrServiceKind.volcengine:
      return Lucide.AudioWaveform;
    case AsrServiceKind.mimo:
      return Lucide.Globe;
    case AsrServiceKind.step:
      return Lucide.AudioWaveform;
  }
}

String _serviceDisplayName(AppLocalizations l10n, AsrServiceOptions service) {
  final name = service.name.trim();
  return name.isEmpty || _isDefaultServiceName(service.kind, name)
      ? _kindTitle(l10n, service.kind)
      : name;
}

String _editableServiceName(AsrServiceOptions? service) {
  if (service == null) return '';
  final name = service.name.trim();
  return _isDefaultServiceName(service.kind, name) ? '' : name;
}

bool _isDefaultServiceName(AsrServiceKind kind, String name) {
  return switch (kind) {
    AsrServiceKind.sherpaOnnx => const {
      'Sherpa-ONNX',
      'Offline Model',
      '本地离线模型',
      '本機離線模型',
      '本地模型',
      '本機模型',
    }.contains(name),
    AsrServiceKind.system => const {
      'System speech recognition',
      'System Recognition',
      'System',
      '系统语音识别',
      '系統語音辨識',
      '系统',
      '系統',
    }.contains(name),
    AsrServiceKind.openAiRealtime => const {
      'OpenAI Realtime ASR',
      'OpenAI Realtime',
    }.contains(name),
    AsrServiceKind.dashScope => const {
      'DashScope ASR',
      'DashScope Realtime',
      'DashScope 实时识别',
      'DashScope 即時辨識',
      'DashScope',
    }.contains(name),
    AsrServiceKind.qwenAudio => const {
      'Qwen Audio ASR',
      'Qwen Audio',
    }.contains(name),
    AsrServiceKind.volcengine => const {
      'Volcengine ASR',
      'Volcengine Speech Recognition',
      'Volcengine',
      '火山引擎语音识别',
      '火山引擎語音辨識',
      '火山引擎',
    }.contains(name),
    AsrServiceKind.mimo => const {
      'MiMo ASR',
      'MiMo Speech Recognition',
      'MiMo 语音识别',
      'MiMo 語音辨識',
      'MiMo',
    }.contains(name),
    AsrServiceKind.step => const {
      'Step ASR',
      'Step Speech Recognition',
      'Step',
      '阶跃星辰语音识别',
      '階躍星辰語音辨識',
      '阶跃星辰',
      '階躍星辰',
    }.contains(name),
  };
}

String _kindTitle(AppLocalizations l10n, AsrServiceKind kind) {
  switch (kind) {
    case AsrServiceKind.system:
      return l10n.asrServicesSystemTitle;
    case AsrServiceKind.sherpaOnnx:
      return l10n.asrServicesLocalTitle;
    case AsrServiceKind.openAiRealtime:
      return l10n.asrServicesOpenAiTitle;
    case AsrServiceKind.dashScope:
      return l10n.asrServicesDashScopeTitle;
    case AsrServiceKind.qwenAudio:
      return 'Qwen Audio';
    case AsrServiceKind.volcengine:
      return l10n.asrServicesVolcengineTitle;
    case AsrServiceKind.mimo:
      return l10n.asrServicesMimoTitle;
    case AsrServiceKind.step:
      return l10n.asrServicesStepTitle;
  }
}

String _kindSubtitle(AppLocalizations l10n, AsrServiceKind kind) {
  switch (kind) {
    case AsrServiceKind.system:
      return l10n.asrServicesSystemSubtitle;
    case AsrServiceKind.sherpaOnnx:
      return l10n.asrServicesLocalSubtitle;
    case AsrServiceKind.openAiRealtime:
      return l10n.asrServicesOpenAiSubtitle;
    case AsrServiceKind.dashScope:
      return l10n.asrServicesDashScopeSubtitle;
    case AsrServiceKind.qwenAudio:
      return 'Qwen Audio 3.0 ASR (/api-ws/v1/inference)';
    case AsrServiceKind.volcengine:
      return l10n.asrServicesVolcengineSubtitle;
    case AsrServiceKind.mimo:
      return l10n.asrServicesMimoSubtitle;
    case AsrServiceKind.step:
      return l10n.asrServicesStepSubtitle;
  }
}

String _apiKeyOf(AsrServiceOptions? options) {
  return switch (options) {
    OpenAiRealtimeAsrOptions value => value.apiKey,
    DashScopeAsrOptions value => value.apiKey,
    QwenAudioAsrOptions value => value.apiKey,
    VolcengineAsrOptions value => value.apiKey,
    MimoAsrOptions value => value.apiKey,
    StepAsrOptions value => value.apiKey,
    _ => '',
  };
}

String _endpointOf(AsrServiceOptions? options) {
  return switch (options) {
    OpenAiRealtimeAsrOptions value => value.websocketUrl,
    DashScopeAsrOptions value => value.websocketUrl,
    QwenAudioAsrOptions value => value.workspaceId,
    VolcengineAsrOptions value => value.websocketUrl,
    MimoAsrOptions value => value.baseUrl,
    StepAsrOptions value => value.baseUrl,
    _ => '',
  };
}

String _modelOf(AsrServiceOptions? options) {
  return switch (options) {
    OpenAiRealtimeAsrOptions value => value.model,
    DashScopeAsrOptions value => value.model,
    QwenAudioAsrOptions value => value.model,
    MimoAsrOptions value => value.model,
    StepAsrOptions value => value.model,
    _ => '',
  };
}

String _resourceIdOf(AsrServiceOptions? options) {
  return switch (options) {
    VolcengineAsrOptions value => value.resourceId,
    _ => '',
  };
}

String _languageOf(AsrServiceOptions? options) {
  return switch (options) {
    SherpaOnnxAsrOptions value => value.language,
    SystemAsrOptions value => value.localeId,
    OpenAiRealtimeAsrOptions value => value.language,
    DashScopeAsrOptions value => value.language,
    VolcengineAsrOptions value => value.language,
    MimoAsrOptions value => value.language,
    StepAsrOptions value => value.language,
    _ => '',
  };
}

String _defaultEndpoint(AsrServiceKind kind) {
  switch (kind) {
    case AsrServiceKind.openAiRealtime:
      return 'wss://api.openai.com/v1/realtime?intent=transcription';
    case AsrServiceKind.dashScope:
      return 'wss://dashscope.aliyuncs.com/api-ws/v1/realtime';
    case AsrServiceKind.qwenAudio:
      return '';
    case AsrServiceKind.volcengine:
      return 'wss://openspeech.bytedance.com/api/v3/sauc/bigmodel';
    case AsrServiceKind.mimo:
      return 'https://api.xiaomimimo.com/v1';
    case AsrServiceKind.step:
      return 'https://api.stepfun.com';
    case AsrServiceKind.sherpaOnnx:
    case AsrServiceKind.system:
      return '';
  }
}

String _defaultModel(AsrServiceKind kind) {
  switch (kind) {
    case AsrServiceKind.openAiRealtime:
      return 'gpt-live-transcribe';
    case AsrServiceKind.dashScope:
      return 'qwen3-asr-flash-realtime';
    case AsrServiceKind.qwenAudio:
      return 'qwen-audio-3.0-asr-flash-streaming';
    case AsrServiceKind.volcengine:
      return '';
    case AsrServiceKind.mimo:
      return 'mimo-v2.5-asr';
    case AsrServiceKind.step:
      return 'stepaudio-2.5-asr';
    case AsrServiceKind.sherpaOnnx:
    case AsrServiceKind.system:
      return '';
  }
}

String _defaultResourceId(AsrServiceKind kind) {
  // Keep Seed-ASR 2.0 default. Compatible: volc.bigasr.sauc.duration (ASR 1.0).
  // Needs real Key verification before changing the app default.
  return kind == AsrServiceKind.volcengine
      ? VolcengineAsrOptions.seedAsrDurationResourceId
      : '';
}

String _valueOrDefault(String value, String fallback) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? fallback : trimmed;
}

String _formatBytes(int bytes) {
  final mb = bytes / (1024 * 1024);
  return '${mb.round()} MB';
}
