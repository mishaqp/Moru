import 'dart:convert';

/// Where agents installed with npm live in the Linux environment.
const String acpNpmPrefix = '/root/.npm-global';

/// Moru's own settings files for agents, apart from anything the user keeps
/// in the agents' default locations.
const String acpConfigDir = '/root/.config/moru-agents';

/// The kind of model API an agent speaks.
enum AcpModelApi {
  /// Anthropic Messages (Claude Code).
  anthropic,

  /// OpenAI-compatible; the agent is told which variant to use.
  openai,

  /// The agent configures itself; Moru only passes the key and address.
  any,
}

/// The model an agent should use, taken from a Moru provider.
class AcpProviderInput {
  const AcpProviderInput({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.anthropicProvider = false,
    this.responsesApi = false,
    this.imageInput = false,
    this.headers = const {},
  });

  final String baseUrl;
  final String apiKey;

  /// The upstream model id.
  final String model;

  /// The Moru provider is an Anthropic (Claude) one.
  final bool anthropicProvider;

  /// The Moru provider uses OpenAI's Responses API.
  final bool responsesApi;

  /// The selected Moru model accepts images, including model overrides.
  final bool imageInput;
  final Map<String, String> headers;
}

/// A file an agent reads its settings from, written before it starts.
class AcpConfigFile {
  const AcpConfigFile(this.path, this.content);

  final String path;
  final String content;
}

/// How to start an agent for one provider and model.
class AcpLaunch {
  const AcpLaunch({
    required this.command,
    this.arguments = const [],
    this.environment = const {},
    this.files = const [],
  });

  final String command;
  final List<String> arguments;
  final Map<String, String> environment;
  final List<AcpConfigFile> files;
}

/// An agent Moru knows how to install and run.
class AcpAgentSpec {
  const AcpAgentSpec({
    required this.id,
    required this.name,
    required this.command,
    this.arguments = const [],
    required this.installScript,
    required this.api,
    required this.homepage,
    this.nodeMajor = 18,
  });

  final String id;
  final String name;

  /// The ACP entry point, found on `PATH` after installation.
  final String command;
  final List<String> arguments;

  /// Shell script that installs or updates the agent; npm is present.
  final String installScript;
  final AcpModelApi api;
  final String homepage;

  /// The oldest Node.js the agent runs on.
  final int nodeMajor;

  bool get isCustom => id.startsWith(customPrefix);

  static const String customPrefix = 'custom:';

  /// The command and its settings for [provider].
  AcpLaunch launch(AcpProviderInput provider) {
    final common = <String, String>{
      'PATH':
          '$acpNpmPrefix/bin:/usr/local/sbin:/usr/local/bin:'
          '/usr/sbin:/usr/bin:/sbin:/bin',
      // For custom agents and for scripts the agent runs itself.
      'MORU_AGENT_BASE_URL': provider.baseUrl,
      'MORU_AGENT_API_KEY': provider.apiKey,
      'MORU_AGENT_MODEL': provider.model,
    };
    switch (id) {
      case claudeCodeId:
        final headers = provider.headers.entries
            .map((entry) => '${entry.key}: ${entry.value}')
            .join('\n');
        return AcpLaunch(
          command: command,
          arguments: arguments,
          environment: {
            ...common,
            'ANTHROPIC_BASE_URL': anthropicBaseUrl(provider),
            'ANTHROPIC_API_KEY': provider.apiKey,
            'ANTHROPIC_AUTH_TOKEN': provider.apiKey,
            // Without these Claude Code asks for its own Claude models,
            // which another provider rejects.
            'ANTHROPIC_MODEL': provider.model,
            'ANTHROPIC_SMALL_FAST_MODEL': provider.model,
            'ANTHROPIC_DEFAULT_HAIKU_MODEL': provider.model,
            if (headers.isNotEmpty) 'ANTHROPIC_CUSTOM_HEADERS': headers,
            'DISABLE_AUTOUPDATER': '1',
            'DISABLE_TELEMETRY': '1',
            'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC': '1',
            // The Linux environment is Moru's sandbox; Claude Code allows
            // its "bypass permissions" mode as root only when told so.
            'IS_SANDBOX': '1',
          },
        );
      case codexId:
        const home = '$acpConfigDir/codex';
        return AcpLaunch(
          command: command,
          arguments: arguments,
          environment: {
            ...common,
            'CODEX_HOME': home,
            'MORU_CODEX_API_KEY': provider.apiKey,
          },
          files: [AcpConfigFile('$home/config.toml', codexConfig(provider))],
        );
      case openCodeId:
        const path = '$acpConfigDir/opencode.json';
        return AcpLaunch(
          command: command,
          arguments: arguments,
          environment: {
            ...common,
            'OPENCODE_CONFIG': path,
            'OPENCODE_DISABLE_AUTOUPDATE': 'true',
          },
          files: [AcpConfigFile(path, openCodeConfig(provider))],
        );
      default:
        return AcpLaunch(
          command: command,
          arguments: arguments,
          environment: {
            ...common,
            'OPENAI_BASE_URL': openAiBaseUrl(provider.baseUrl),
            'OPENAI_API_KEY': provider.apiKey,
            'OPENAI_MODEL': provider.model,
          },
        );
    }
  }

  static const String claudeCodeId = 'claude-code';
  static const String codexId = 'codex';
  static const String openCodeId = 'opencode';

  static const String _npmInstall =
      'npm install -g --prefix $acpNpmPrefix --no-audit --no-fund';

  /// Agents offered in the list, in the order shown.
  static const List<AcpAgentSpec> builtIn = [
    AcpAgentSpec(
      id: claudeCodeId,
      name: 'Claude Code',
      command: 'claude-agent-acp',
      installScript:
          'set -e\n$_npmInstall @anthropic-ai/claude-code '
          '@agentclientprotocol/claude-agent-acp\n',
      api: AcpModelApi.anthropic,
      homepage: 'https://docs.anthropic.com/en/docs/claude-code',
    ),
    AcpAgentSpec(
      id: codexId,
      name: 'Codex',
      command: 'codex-acp',
      installScript:
          'set -e\n$_npmInstall @openai/codex '
          '@agentclientprotocol/codex-acp\n',
      api: AcpModelApi.openai,
      homepage: 'https://github.com/openai/codex',
    ),
    AcpAgentSpec(
      id: openCodeId,
      name: 'OpenCode',
      command: 'opencode',
      arguments: ['acp'],
      // OpenCode publishes separate binaries for glibc and musl systems;
      // npm picks by CPU only, so the matching one is installed by name.
      installScript:
          'set -e\n$_npmInstall opencode-ai\n'
          'platform=opencode-linux-arm64\n'
          'if [ -f /etc/alpine-release ]; then '
          'platform=opencode-linux-arm64-musl; fi\n'
          "version=\$(node -p \"require('$acpNpmPrefix/lib/node_modules/"
          "opencode-ai/package.json').version\")\n"
          '$_npmInstall --force "\$platform@\$version"\n'
          'binary="$acpNpmPrefix/lib/node_modules/\$platform/bin/opencode"\n'
          '"\$binary" --version >/dev/null\n'
          'ln -sf "\$binary" $acpNpmPrefix/bin/opencode\n',
      api: AcpModelApi.openai,
      homepage: 'https://opencode.ai',
    ),
  ];

  static AcpAgentSpec? byId(String id) {
    for (final spec in builtIn) {
      if (spec.id == id) return spec;
    }
    return null;
  }

  /// An agent the user adds by its command, for anything else speaking ACP.
  factory AcpAgentSpec.custom({
    required String id,
    required String name,
    required String command,
    List<String> arguments = const [],
  }) => AcpAgentSpec(
    id: id.startsWith(customPrefix) ? id : '$customPrefix$id',
    name: name,
    command: command,
    arguments: arguments,
    installScript: '',
    api: AcpModelApi.any,
    homepage: '',
  );

  /// Claude Code adds `/v1/messages` itself; providers know their Anthropic
  /// endpoint under different roots.
  static String anthropicBaseUrl(AcpProviderInput provider) {
    var url = _stripEndpoint(provider.baseUrl);
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    // Providers with a separate Anthropic-compatible root on the same host.
    const anthropicRoots = {
      'api.deepseek.com': '/anthropic',
      'api.moonshot.ai': '/anthropic',
      'api.moonshot.cn': '/anthropic',
      'open.bigmodel.cn': '/api/anthropic',
      'api.z.ai': '/api/anthropic',
      'api.minimax.io': '/anthropic',
      'api.minimaxi.com': '/anthropic',
      'openrouter.ai': '/api',
    };
    if (!provider.anthropicProvider && anthropicRoots.containsKey(host)) {
      final uri = Uri.parse(url);
      return '${uri.scheme}://${uri.authority}${anthropicRoots[host]}';
    }
    if (url.endsWith('/v1')) url = url.substring(0, url.length - 3);
    return url;
  }

  /// OpenAI-style root ending in `/v1` (or the provider's own version path).
  static String openAiBaseUrl(String baseUrl) {
    final url = _stripEndpoint(baseUrl);
    if (url.isEmpty || RegExp(r'/v\d+[a-z]*$').hasMatch(url)) return url;
    if (url.endsWith('/compatible-mode/v1') || url.endsWith('/openai')) {
      return url;
    }
    return '$url/v1';
  }

  static String _stripEndpoint(String baseUrl) {
    var url = baseUrl.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    for (final suffix in const [
      '/chat/completions',
      '/responses',
      '/messages',
    ]) {
      if (url.toLowerCase().endsWith(suffix)) {
        url = url.substring(0, url.length - suffix.length);
        break;
      }
    }
    return url;
  }

  static String codexConfig(AcpProviderInput provider) {
    String toml(String value) => jsonEncode(value);
    final lines = [
      'model_provider = "moru"',
      'model = ${toml(provider.model)}',
      'disable_response_storage = true',
      '',
      '[model_providers.moru]',
      'name = "Moru"',
      'base_url = ${toml(openAiBaseUrl(provider.baseUrl))}',
      'env_key = "MORU_CODEX_API_KEY"',
      'wire_api = "${provider.responsesApi ? 'responses' : 'chat'}"',
      if (provider.headers.isNotEmpty) ...[
        '',
        '[model_providers.moru.http_headers]',
        for (final entry in provider.headers.entries)
          '${toml(entry.key)} = ${toml(entry.value)}',
      ],
    ];
    return '${lines.join('\n')}\n';
  }

  static String openCodeConfig(AcpProviderInput provider) {
    final npm = provider.anthropicProvider
        ? '@ai-sdk/anthropic'
        : provider.responsesApi
        ? '@ai-sdk/openai'
        : '@ai-sdk/openai-compatible';
    final baseUrl = provider.anthropicProvider
        ? '${anthropicBaseUrl(provider)}/v1'
        : openAiBaseUrl(provider.baseUrl);
    return const JsonEncoder.withIndent('  ').convert({
      r'$schema': 'https://opencode.ai/config.json',
      'model': 'moru/${provider.model}',
      'small_model': 'moru/${provider.model}',
      'enabled_providers': ['moru'],
      'autoupdate': false,
      'share': 'disabled',
      'provider': {
        'moru': {
          'npm': npm,
          'name': 'Moru',
          'options': {
            'baseURL': baseUrl,
            'apiKey': '{env:MORU_AGENT_API_KEY}',
            if (provider.headers.isNotEmpty) 'headers': provider.headers,
          },
          'models': {
            provider.model: {
              'name': provider.model,
              if (provider.imageInput) 'attachment': true,
              'modalities': {
                'input': ['text', if (provider.imageInput) 'image'],
                'output': ['text'],
              },
            },
          },
        },
      },
    });
  }
}
