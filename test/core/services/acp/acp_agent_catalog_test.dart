import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/services/acp/acp_agent_catalog.dart';

void main() {
  const deepseek = AcpProviderInput(
    baseUrl: 'https://api.deepseek.com/v1',
    apiKey: 'sk-ds',
    model: 'deepseek-chat',
  );

  test('the catalog lists all installable ACP agents', () {
    expect(AcpAgentSpec.builtIn.map((s) => s.name), [
      'Claude Code',
      'Codex',
      'OpenCode',
      'Kimi Code',
      'DeepSeek Harness',
    ]);
    expect(AcpAgentSpec.byId('codex')?.command, 'codex-acp');
    expect(AcpAgentSpec.byId('nope'), isNull);
    for (final spec in AcpAgentSpec.builtIn) {
      expect(spec.installScript, contains('--prefix $acpNpmPrefix'));
    }
  });

  test('installing Claude Code adds bash on Alpine only when it is '
      'missing', () async {
    final script = AcpAgentSpec.byId('claude-code')!.installScript;
    Future<String> install({required bool hasBash}) async {
      final bin = await Directory.systemTemp.createTemp('moru-install');
      addTearDown(() => bin.delete(recursive: true));
      final log = File('${bin.path}/calls');
      for (final tool in ['apk', 'npm', if (hasBash) 'bash']) {
        final file = File('${bin.path}/$tool')
          ..writeAsStringSync('#!/bin/sh\necho "$tool \$*" >> "${log.path}"\n');
        await Process.run('chmod', ['+x', file.path]);
      }
      final result = await Process.run(
        '/bin/sh',
        ['-c', script],
        environment: {'PATH': bin.path},
        includeParentEnvironment: false,
      );
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      return log.readAsStringSync();
    }

    final alpine = await install(hasBash: false);
    expect(alpine, contains('apk add --no-cache bash'));
    expect(alpine, contains('@anthropic-ai/claude-code'));
    expect(await install(hasBash: true), isNot(contains('apk')));
  }, testOn: 'linux || mac-os');

  test('Kimi Code starts ACP from its installed executable', () {
    final spec = AcpAgentSpec.byId('kimi-code');
    expect(spec, isNotNull);
    final launch = spec!.launch(deepseek);
    expect(launch.command, 'kimi');
    expect(launch.arguments, ['acp']);
    expect(spec.installScript, contains('@moonshot-ai/kimi-code'));
    expect(spec.installScript, isNot(contains('npx')));
    expect(launch.environment['KIMI_CODE_HOME'], '$acpConfigDir/kimi-code');
    expect(launch.environment['MORU_AGENT_API_KEY'], 'sk-ds');
    final config = launch.files.single;
    expect(config.path, '$acpConfigDir/kimi-code/config.toml');
    expect(config.content, contains('default_model = "moru"'));
    expect(config.content, contains('[providers.moru]'));
    expect(config.content, contains('type = "openai"'));
    expect(config.content, contains('api_key_env = "MORU_AGENT_API_KEY"'));
    expect(
      config.content,
      contains('base_url = "https://api.deepseek.com/v1"'),
    );
    expect(config.content, contains('[models.moru]'));
    expect(config.content, contains('provider = "moru"'));
    expect(config.content, contains('model = "deepseek-chat"'));
    expect(config.content, contains('max_context_size = 32768'));
    expect(_tomlArray(config.content, 'capabilities'), ['tool_use']);
    expect(config.content, isNot(contains('sk-ds')));
  });

  test('DeepSeek Harness routes ACP through a key-free provider patch', () {
    final spec = AcpAgentSpec.byId('deepseek-harness');
    expect(spec, isNotNull);
    final launch = spec!.launch(deepseek);
    expect(launch.command, 'dsh');
    expect(spec.installScript, contains('@deepseek-ai/dsh'));
    expect(spec.installScript, isNot(contains('npx')));
    expect(launch.environment['DSH_HOME'], '$acpConfigDir/deepseek-harness');
    expect(launch.environment['MORU_AGENT_API_KEY'], 'sk-ds');
    final config = launch.files.single;
    expect(config.path, '$acpConfigDir/deepseek-harness/moru.yaml');
    expect(launch.arguments, ['--patch', config.path, '--profile', 'acp']);
    final patch = jsonDecode(config.content) as List;
    expect(patch, [
      {
        'id': 'llm-pi-ai',
        'config': {
          'providers': {
            'moru': {
              'apiKeyEnv': 'MORU_AGENT_API_KEY',
              'api': 'openai-completions',
              'baseURL': 'https://api.deepseek.com/v1',
              'models': [
                {
                  'id': 'deepseek-chat',
                  'input': ['text'],
                },
              ],
            },
          },
        },
      },
      {
        'id': 'acp',
        'config': {'provider': 'moru', 'model': 'deepseek-chat'},
      },
      {
        'id': 'agent-default-model',
        'config': {'provider': 'moru', 'model': 'deepseek-chat'},
      },
    ]);
    expect(config.content, isNot(contains('sk-ds')));
  });

  for (final fixture in [
    (
      anthropic: false,
      responses: true,
      kimi: 'openai_responses',
      dsh: 'openai-responses',
      url: 'https://gw.example/v1',
    ),
    (
      anthropic: true,
      responses: false,
      kimi: 'anthropic',
      dsh: 'anthropic-messages',
      url: 'https://gw.example',
    ),
  ]) {
    test(
      'new agents route ${fixture.kimi} with escaped model and image input',
      () {
        const model = 'custom."vision"\\model\nnext';
        final input = AcpProviderInput(
          baseUrl:
              'https://gw.example/v1/${fixture.anthropic ? 'messages' : 'responses'}',
          apiKey: 'secret-never-written',
          model: model,
          anthropicProvider: fixture.anthropic,
          responsesApi: fixture.responses,
          imageInput: true,
        );
        final kimi = AcpAgentSpec.byId('kimi-code');
        final dsh = AcpAgentSpec.byId('deepseek-harness');
        expect(kimi, isNotNull);
        expect(dsh, isNotNull);
        final config = kimi!.launch(input).files.single.content;
        expect(config, contains('type = "${fixture.kimi}"'));
        expect(config, contains('base_url = "${fixture.url}"'));
        expect(config, contains(r'model = "custom.\"vision\"\\model\nnext"'));
        expect(_tomlArray(config, 'capabilities'), ['tool_use', 'image_in']);
        expect(config, isNot(contains(input.apiKey)));
        final patch =
            jsonDecode(dsh!.launch(input).files.single.content) as List;
        final provider =
            (patch[0] as Map)['config']['providers']['moru'] as Map;
        expect(provider['api'], fixture.dsh);
        expect(provider['baseURL'], fixture.url);
        expect(provider['models'], [
          {
            'id': model,
            'input': ['text', 'image'],
          },
        ]);
        expect((patch[1] as Map)['config']['model'], model);
        expect(
          dsh.launch(input).files.single.content,
          isNot(contains(input.apiKey)),
        );
      },
    );
  }

  test(
    'new agents require Node 22.19 while existing agents keep their baseline',
    () {
      for (final id in ['kimi-code', 'deepseek-harness']) {
        final spec = AcpAgentSpec.byId(id)!;
        expect(spec.nodeMajor, 22);
        expect(spec.nodeMinor, 19);
        expect(spec.minimumNodeVersion, '22.19.0');
      }
      final spec = AcpAgentSpec.byId('codex')!;
      expect(spec.nodeMajor, 18);
      expect(spec.nodeMinor, 0);
      expect(spec.minimumNodeVersion, '18.0.0');
    },
  );

  test(
    'each configured agent can isolate its files under a supplied directory',
    () {
      final directory = Directory.systemTemp.createTempSync('acp-config-');
      addTearDown(() => directory.deleteSync(recursive: true));
      for (final fixture in [
        (id: 'codex', variable: 'CODEX_HOME', suffix: '/codex/config.toml'),
        (id: 'opencode', variable: 'OPENCODE_CONFIG', suffix: '/opencode.json'),
        (
          id: 'kimi-code',
          variable: 'KIMI_CODE_HOME',
          suffix: '/kimi-code/config.toml',
        ),
        (
          id: 'deepseek-harness',
          variable: 'DSH_HOME',
          suffix: '/deepseek-harness/moru.yaml',
        ),
      ]) {
        final spec = AcpAgentSpec.byId(fixture.id)!;
        late AcpLaunch launch;
        expect(
          () => launch = spec.launch(deepseek, configDirectory: directory.path),
          returnsNormally,
        );
        expect(launch.files.single.path, '${directory.path}${fixture.suffix}');
        expect(
          launch.environment[fixture.variable],
          startsWith(directory.path),
        );
        expect(launch.files.single.content, isNot(contains('sk-ds')));
        if (fixture.id == 'deepseek-harness') {
          expect(launch.arguments.take(2), [
            '--patch',
            '${directory.path}/deepseek-harness/moru.yaml',
          ]);
        }
      }
    },
  );

  test(
    'Kimi keeps a configured context limit and safely quotes custom headers',
    () {
      final launch = AcpAgentSpec.byId('kimi-code')!.launch(
        const AcpProviderInput(
          baseUrl: 'https://gw.example/v1',
          apiKey: 'secret-never-written',
          model: 'm',
          contextWindow: 65536,
          headers: {'X-Team."quoted"': 'first\nnext\\value'},
        ),
      );
      final config = launch.files.single.content;
      expect(config, contains('max_context_size = 65536'));
      expect(config, contains('[providers.moru.custom_headers]'));
      expect(config, contains(r'"X-Team.\"quoted\"" = "first\nnext\\value"'));
      expect(config, isNot(contains('secret-never-written')));
    },
  );

  test('Kimi rejects a nonpositive explicit model context limit', () {
    for (final contextWindow in [0, -1]) {
      expect(
        () => AcpAgentSpec.byId('kimi-code')!.launch(
          AcpProviderInput(
            baseUrl: 'https://gw.example/v1',
            apiKey: 'k',
            model: 'm',
            contextWindow: contextWindow,
          ),
        ),
        throwsArgumentError,
      );
    }
  });

  for (final fixture in [
    (
      id: 'kimi-code',
      command: 'kimi',
      arguments: ['web', '--host', '127.0.0.1', '--port', '43123', '--no-open'],
    ),
    (
      id: 'opencode',
      command: 'opencode',
      arguments: ['web', '--hostname', '127.0.0.1', '--port', '43123'],
    ),
  ]) {
    test(
      '${fixture.command} Web uses loopback and isolated provider settings',
      () {
        final directory = Directory.systemTemp.createTempSync('acp-web-');
        addTearDown(() => directory.deleteSync(recursive: true));
        final spec = AcpAgentSpec.byId(fixture.id)!;
        AcpLaunch? launch;
        expect(
          () => launch = spec.webLaunch(
            deepseek,
            port: 43123,
            configDirectory: directory.path,
          ),
          returnsNormally,
        );
        expect(launch, isNotNull);
        expect(launch!.command, fixture.command);
        expect(launch!.arguments, fixture.arguments);
        expect(launch!.environment['MORU_AGENT_API_KEY'], 'sk-ds');
        expect(launch!.files.single.path, startsWith(directory.path));
        expect(launch!.arguments.join(' '), isNot(contains('sk-ds')));
        expect(launch!.files.single.content, isNot(contains('sk-ds')));
      },
    );
  }

  test('agents without a built-in Web server return no Web launch', () {
    for (final spec in [
      AcpAgentSpec.byId('claude-code')!,
      AcpAgentSpec.byId('codex')!,
      AcpAgentSpec.custom(id: 'a', name: 'A', command: 'a'),
    ]) {
      AcpLaunch? launch;
      expect(
        () => launch = spec.webLaunch(deepseek, port: 43123),
        returnsNormally,
      );
      expect(launch, isNull);
    }
  });

  test('DeepSeek Web applies its provider patch before the web profile', () {
    final directory = Directory.systemTemp.createTempSync('acp-dsh-web-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final spec = AcpAgentSpec.byId('deepseek-harness')!;
    AcpLaunch? launch;
    expect(
      () => launch = spec.webLaunch(
        deepseek,
        port: 43123,
        configDirectory: directory.path,
      ),
      returnsNormally,
    );
    expect(launch, isNotNull);
    expect(launch!.command, 'dsh');
    expect(launch!.arguments, [
      '--patch',
      '${directory.path}/deepseek-harness/moru.yaml',
      '--profile',
      'web',
      '--host',
      '127.0.0.1',
      '--port',
      '43123',
      '--no-open',
    ]);
    expect(
      launch!.environment['DSH_HOME'],
      '${directory.path}/deepseek-harness',
    );
    expect(launch!.environment['MORU_AGENT_API_KEY'], 'sk-ds');
    final patch = jsonDecode(launch!.files.single.content) as List;
    expect((patch.last as Map)['config'], {
      'provider': 'moru',
      'model': 'deepseek-chat',
    });
    expect(launch!.arguments.join(' '), isNot(contains('sk-ds')));
    expect(launch!.files.single.content, isNot(contains('sk-ds')));
  });

  test('a supported Web launch rejects invalid ports', () {
    final spec = AcpAgentSpec.byId('kimi-code')!;
    for (final port in [0, -1, 65536]) {
      expect(() => spec.webLaunch(deepseek, port: port), throwsArgumentError);
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

List<dynamic> _tomlArray(String config, String key) =>
    jsonDecode(
          config
              .split('\n')
              .singleWhere((line) => line.startsWith('$key = '))
              .substring('$key = '.length),
        )
        as List;
