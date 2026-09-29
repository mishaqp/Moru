import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/services/acp/acp_agent_catalog.dart';

void main() {
  const deepseek = AcpProviderInput(
    baseUrl: 'https://api.deepseek.com/v1',
    apiKey: 'sk-ds',
    model: 'deepseek-chat',
  );

  test('the catalog lists Claude Code, Codex and OpenCode', () {
    expect(AcpAgentSpec.builtIn.map((s) => s.name), [
      'Claude Code',
      'Codex',
      'OpenCode',
    ]);
    expect(AcpAgentSpec.byId('codex')?.command, 'codex-acp');
    expect(AcpAgentSpec.byId('nope'), isNull);
    for (final spec in AcpAgentSpec.builtIn) {
      expect(spec.installScript, contains('--prefix $acpNpmPrefix'));
    }
  });

  group('Claude Code', () {
    final spec = AcpAgentSpec.byId(AcpAgentSpec.claudeCodeId)!;

    test('takes the key and the model, and finds the Anthropic endpoint of '
        'an OpenAI-style provider', () {
      final launch = spec.launch(deepseek);
      expect(launch.command, 'claude-agent-acp');
      expect(
        launch.environment['ANTHROPIC_BASE_URL'],
        'https://api.deepseek.com/anthropic',
      );
      expect(launch.environment['ANTHROPIC_AUTH_TOKEN'], 'sk-ds');
      expect(launch.environment['ANTHROPIC_MODEL'], 'deepseek-chat');
      expect(launch.environment['ANTHROPIC_SMALL_FAST_MODEL'], 'deepseek-chat');
      expect(launch.environment['PATH'], startsWith('$acpNpmPrefix/bin:'));
      expect(launch.files, isEmpty);
    });

    test('an Anthropic provider keeps its root without /v1', () {
      expect(
        AcpAgentSpec.anthropicBaseUrl(
          const AcpProviderInput(
            baseUrl: 'https://api.anthropic.com/v1/',
            apiKey: 'k',
            model: 'claude-sonnet-4-5',
            anthropicProvider: true,
          ),
        ),
        'https://api.anthropic.com',
      );
    });

    test('custom headers are passed on', () {
      final launch = spec.launch(
        const AcpProviderInput(
          baseUrl: 'https://gw.example/v1',
          apiKey: 'k',
          model: 'm',
          headers: {'X-Team': 'moru'},
        ),
      );
      expect(launch.environment['ANTHROPIC_CUSTOM_HEADERS'], 'X-Team: moru');
    });
  });

  test('Codex gets its own config with the provider and the key by name', () {
    final spec = AcpAgentSpec.byId(AcpAgentSpec.codexId)!;
    final launch = spec.launch(deepseek);
    expect(launch.environment['CODEX_HOME'], '$acpConfigDir/codex');
    expect(launch.environment['MORU_CODEX_API_KEY'], 'sk-ds');
    final config = launch.files.single;
    expect(config.path, '$acpConfigDir/codex/config.toml');
    expect(config.content, contains('model = "deepseek-chat"'));
    expect(
      config.content,
      contains('base_url = "https://api.deepseek.com/v1"'),
    );
    expect(config.content, contains('env_key = "MORU_CODEX_API_KEY"'));
    expect(config.content, contains('wire_api = "chat"'));
    // The key itself never lands in a file.
    expect(config.content, isNot(contains('sk-ds')));

    final responses = AcpAgentSpec.codexConfig(
      const AcpProviderInput(
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'k',
        model: 'gpt-5',
        responsesApi: true,
        headers: {'OpenAI-Organization': 'org'},
      ),
    );
    expect(responses, contains('wire_api = "responses"'));
    expect(responses, contains('"OpenAI-Organization" = "org"'));
  });

  test('OpenCode reads a Moru provider from its own config file', () {
    final spec = AcpAgentSpec.byId(AcpAgentSpec.openCodeId)!;
    final launch = spec.launch(deepseek);
    expect(launch.arguments, ['acp']);
    expect(launch.environment['OPENCODE_CONFIG'], launch.files.single.path);
    final config = jsonDecode(launch.files.single.content) as Map;
    expect(config['model'], 'moru/deepseek-chat');
    final provider = config['provider']['moru'] as Map;
    expect(provider['npm'], '@ai-sdk/openai-compatible');
    expect(provider['options']['baseURL'], 'https://api.deepseek.com/v1');
    expect(provider['options']['apiKey'], '{env:MORU_AGENT_API_KEY}');
    expect((provider['models'] as Map).keys, ['deepseek-chat']);
    expect(launch.files.single.content, isNot(contains('sk-ds')));
  });

  test('OpenCode explicitly configures text-only model modalities', () {
    final config = jsonDecode(AcpAgentSpec.openCodeConfig(deepseek)) as Map;
    expect(config['provider']['moru']['models'], {
      'deepseek-chat': {
        'name': 'deepseek-chat',
        'modalities': {
          'input': ['text'],
          'output': ['text'],
        },
      },
    });
  });

  test(
    'OpenCode configures attachments and image input for a capable model',
    () {
      final config =
          jsonDecode(
                AcpAgentSpec.openCodeConfig(
                  const AcpProviderInput(
                    baseUrl: 'https://api.example.com/v1',
                    apiKey: 'key',
                    model: 'custom-vision',
                    imageInput: true,
                  ),
                ),
              )
              as Map;
      expect(config['provider']['moru']['models'], {
        'custom-vision': {
          'name': 'custom-vision',
          'attachment': true,
          'modalities': {
            'input': ['text', 'image'],
            'output': ['text'],
          },
        },
      });
    },
  );

  test('base URLs lose endpoint paths and gain /v1 only when missing', () {
    expect(
      AcpAgentSpec.openAiBaseUrl('https://api.example.com/v1/chat/completions'),
      'https://api.example.com/v1',
    );
    expect(
      AcpAgentSpec.openAiBaseUrl('https://api.example.com'),
      'https://api.example.com/v1',
    );
    expect(
      AcpAgentSpec.openAiBaseUrl('https://ark.cn-beijing.volces.com/api/v3'),
      'https://ark.cn-beijing.volces.com/api/v3',
    );
    expect(
      AcpAgentSpec.openAiBaseUrl(
        'https://dashscope.aliyuncs.com/compatible-mode/v1',
      ),
      'https://dashscope.aliyuncs.com/compatible-mode/v1',
    );
  });

  test('a custom agent gets the standard OpenAI variables', () {
    final spec = AcpAgentSpec.custom(
      id: 'goose',
      name: 'Goose',
      command: 'goose',
      arguments: const ['acp'],
    );
    expect(spec.id, 'custom:goose');
    expect(spec.isCustom, isTrue);
    final launch = spec.launch(deepseek);
    expect(launch.command, 'goose');
    expect(launch.environment['OPENAI_API_KEY'], 'sk-ds');
    expect(
      launch.environment['OPENAI_BASE_URL'],
      'https://api.deepseek.com/v1',
    );
    expect(launch.environment['MORU_AGENT_MODEL'], 'deepseek-chat');
  });
}
