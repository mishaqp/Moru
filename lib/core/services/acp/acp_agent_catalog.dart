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
    this.contextWindow = 32768,
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

  /// A valid context limit for agents requiring explicit model metadata.
  final int contextWindow;
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
    this.nodeMinor = 0,
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
  final int nodeMinor;
  String get minimumNodeVersion => '$nodeMajor.$nodeMinor.0';

  bool get isCustom => id.startsWith(customPrefix);

  static const String customPrefix = 'custom:';

  /// The command and its settings for [provider].
  AcpLaunch launch(AcpProviderInput provider, {String? configDirectory}) {
    final root = configDirectory ?? acpConfigDir;
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
        final home = '$root/codex';
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
        final path = '$root/opencode.json';
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
      case kimiCodeId:
        final home = '$root/kimi-code';
        return AcpLaunch(
          command: command,
          arguments: arguments,
          environment: {...common, 'KIMI_CODE_HOME': home},
          files: [AcpConfigFile('$home/config.toml', kimiCodeConfig(provider))],
        );
      case deepSeekHarnessId:
        final home = '$root/deepseek-harness';
        final path = '$home/moru.yaml';
        return AcpLaunch(
          command: command,
          arguments: ['--patch', path, ...arguments],
          environment: {...common, 'DSH_HOME': home},
          files: [AcpConfigFile(path, deepSeekHarnessConfig(provider))],
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

  /// A built-in browser interface, available only to the Android client through
  /// the Linux environment's loopback. Unsupported agents have no Web launch.
  AcpLaunch? webLaunch(
    AcpProviderInput provider, {
    required int port,
    String? configDirectory,
  }) {
    if (id != kimiCodeId && id != deepSeekHarnessId && id != openCodeId) {
      return null;
    }
    if (port < 1 || port > 65535) {
      throw ArgumentError.value(port, 'port', 'Must be between 1 and 65535');
    }
    final acp = launch(provider, configDirectory: configDirectory);
    return AcpLaunch(
      command: command,
      arguments: switch (id) {
        deepSeekHarnessId => [
          '--patch',
          acp.files.single.path,
          '--profile',
          'web',
          '--host',
          '127.0.0.1',
          '--port',
          '$port',
          '--no-open',
        ],
        openCodeId => ['web', '--hostname', '127.0.0.1', '--port', '$port'],
        _ => ['web', '--host', '127.0.0.1', '--port', '$port', '--no-open'],
      },
      environment: acp.environment,
      files: acp.files,
    );
  }

  static const String claudeCodeId = 'claude-code';
  static const String codexId = 'codex';
  static const String openCodeId = 'opencode';
  static const String kimiCodeId = 'kimi-code';
  static const String deepSeekHarnessId = 'deepseek-harness';

  static const String _npmInstall =
      'npm install -g --prefix $acpNpmPrefix --no-audit --no-fund';

  /// What coding agents run besides Node, installed by the distribution's
  /// package manager before the agent itself; present packages are kept.
  /// bash runs their commands (Alpine only has BusyBox sh), ripgrep is
  /// their search, git and curl their everyday tools, procps gives ps and
  /// kill. On Alpine (musl), gcompat and glib let the glibc builds some npm
  /// packages ship run at all. The same set OmniBot prepares.
  static const String _agentPackages =
      'moru_packages "bash ca-certificates curl git procps ripgrep gcompat glib" '
      '"bash ca-certificates curl git procps ripgrep" || $_packagesWarning\n';

  /// DeepSeek Harness builds node-pty and koffi (with CMake) from source
  /// where no prebuilt matches, as on Alpine.
  static const String _buildPackages =
      'moru_packages "build-base cmake python3 linux-headers util-linux-dev" '
      '"build-essential cmake python3" || $_packagesWarning\n';

  /// A package source without one of them (Ubuntu without universe) must
  /// not stop the agent's own installation; the log says what happened.
  static const String _packagesWarning =
      "echo 'Moru: some system packages could not be installed' >&2";

  /// `moru_packages ALPINE DEBIAN`: installs whichever listed packages are
  /// missing with apk or apt-get, one at a time so a package the source
  /// lacks does not hold back the rest; fails if any could not be installed.
  /// A distribution with neither package manager is left as is.
  static const String _packagesFunction = r"""
moru_packages() {
  moru_failed=
  if command -v apk >/dev/null 2>&1; then
    for moru_package in $1; do
      apk info -e "$moru_package" >/dev/null 2>&1 ||
        apk --wait 120 add --no-cache "$moru_package" ||
        moru_failed="$moru_failed $moru_package"
    done
  elif command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    moru_updated=
    for moru_package in $2; do
      dpkg-query -W -f='${Status}' "$moru_package" 2>/dev/null | grep -q 'ok installed' && continue
      [ -n "$moru_updated" ] || { apt-get -o DPkg::Lock::Timeout=120 update; moru_updated=1; }
      apt-get -o DPkg::Lock::Timeout=120 install -y --no-install-recommends "$moru_package" ||
        moru_failed="$moru_failed $moru_package"
    done
  fi
  [ -z "$moru_failed" ] || { echo "Moru: not installed:$moru_failed" >&2; return 1; }
}
""";

  static const String _prepare = 'set -e\n$_packagesFunction$_agentPackages';

  /// Node 24 from NodeSource in place of an apt distribution's older
  /// Node. Its package includes npm and ships files that the distribution's
  /// npm and libnode packages own (Ubuntu 22.04's libnode-dev), so those
  /// go first.
  static const String nodeUpgradeScript =
      'set -e\n'
      'command -v apt-get >/dev/null 2>&1 || '
      "{ echo 'Moru: Node.js is too old and there is no apt-get to update it' >&2; exit 1; }\n"
      'export DEBIAN_FRONTEND=noninteractive\n'
      "moru_old=\$(dpkg-query -W -f='\${db:Status-Abbrev} \${Package}\\n' "
      "npm 'libnode*' 2>/dev/null | sed -n 's/^ii *//p')\n"
      'if [ -n "\$moru_old" ]; then '
      'apt-get -o DPkg::Lock::Timeout=120 remove -y \$moru_old; fi\n'
      'apt-get -o DPkg::Lock::Timeout=120 -f install -y\n'
      'apt-get -o DPkg::Lock::Timeout=120 update\n'
      'apt-get -o DPkg::Lock::Timeout=120 install -y --no-install-recommends '
      'ca-certificates curl bash gnupg\n'
      'curl -fsSL https://deb.nodesource.com/setup_24.x -o /tmp/moru-node24-setup.sh\n'
      'bash /tmp/moru-node24-setup.sh\n'
      'apt-get -o DPkg::Lock::Timeout=120 install -y nodejs\n'
      'node --version\n';

  /// Agents offered in the list, in the order shown.
  static const List<AcpAgentSpec> builtIn = [
    AcpAgentSpec(
      id: claudeCodeId,
      name: 'Claude Code',
      command: 'claude-agent-acp',
      installScript:
          '$_prepare$_npmInstall @anthropic-ai/claude-code '
          '@agentclientprotocol/claude-agent-acp\n',
      api: AcpModelApi.anthropic,
      homepage: 'https://docs.anthropic.com/en/docs/claude-code',
    ),
    AcpAgentSpec(
      id: codexId,
      name: 'Codex',
      command: 'codex-acp',
      installScript:
          '$_prepare$_npmInstall @openai/codex '
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
          '$_prepare$_npmInstall opencode-ai\n'
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
    AcpAgentSpec(
      id: kimiCodeId,
      name: 'Kimi Code',
      command: 'kimi',
      arguments: ['acp'],
      installScript: '$_prepare$_npmInstall @moonshot-ai/kimi-code\n',
      api: AcpModelApi.any,
      homepage: 'https://github.com/MoonshotAI/kimi-code',
      nodeMajor: 22,
      nodeMinor: 19,
    ),
    AcpAgentSpec(
      id: deepSeekHarnessId,
      name: 'DeepSeek Harness',
      command: 'dsh',
      arguments: ['--profile', 'acp'],
      installScript: '$_prepare$_buildPackages$_npmInstall @deepseek-ai/dsh\n',
      api: AcpModelApi.any,
      homepage: 'https://github.com/deepseek-ai/deepseek-harness',
      nodeMajor: 22,
      nodeMinor: 19,
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

  static String kimiCodeConfig(AcpProviderInput provider) {
    if (provider.contextWindow <= 0) {
      throw ArgumentError.value(
        provider.contextWindow,
        'contextWindow',
        'Must be positive',
      );
    }
    final type = provider.anthropicProvider
        ? 'anthropic'
        : provider.responsesApi
        ? 'openai_responses'
        : 'openai';
    final baseUrl = provider.anthropicProvider
        ? anthropicBaseUrl(provider)
        : openAiBaseUrl(provider.baseUrl);
    final lines = [
      'default_model = "moru"',
      '',
      '[providers.moru]',
      'type = "$type"',
      'base_url = ${jsonEncode(baseUrl)}',
      'api_key_env = "MORU_AGENT_API_KEY"',
      if (provider.headers.isNotEmpty) ...[
        '',
        '[providers.moru.custom_headers]',
        for (final entry in provider.headers.entries)
          '${jsonEncode(entry.key)} = ${jsonEncode(entry.value)}',
      ],
      '',
      '[models.moru]',
      'provider = "moru"',
      'model = ${jsonEncode(provider.model)}',
      'max_context_size = ${provider.contextWindow}',
      'capabilities = ${jsonEncode(['tool_use', if (provider.imageInput) 'image_in'])}',
    ];
    return '${lines.join('\n')}\n';
  }

  static String deepSeekHarnessConfig(AcpProviderInput provider) {
    final api = provider.anthropicProvider
        ? 'anthropic-messages'
        : provider.responsesApi
        ? 'openai-responses'
        : 'openai-completions';
    final baseUrl = provider.anthropicProvider
        ? anthropicBaseUrl(provider)
        : openAiBaseUrl(provider.baseUrl);
    // JSON is valid YAML, and encoding all values prevents model ids or URLs
    // from becoming additional YAML fields. Credentials stay in the environment.
    return const JsonEncoder.withIndent('  ').convert([
      {
        'id': 'llm-pi-ai',
        'config': {
          'providers': {
            'moru': {
              'apiKeyEnv': 'MORU_AGENT_API_KEY',
              'api': api,
              'baseURL': baseUrl,
              'models': [
                {
                  'id': provider.model,
                  'input': ['text', if (provider.imageInput) 'image'],
                },
              ],
            },
          },
        },
      },
      {
        'id': 'acp',
        'config': {'provider': 'moru', 'model': provider.model},
      },
      {
        'id': 'agent-default-model',
        'config': {'provider': 'moru', 'model': provider.model},
      },
    ]);
  }
}
