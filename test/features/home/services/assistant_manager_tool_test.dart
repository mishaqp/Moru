import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/models/assistant.dart';
import 'package:Kelivo/core/models/assistant_regex.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/features/home/services/assistant_manager_tool.dart';
import 'package:Kelivo/features/home/services/local_tools_service.dart';

import '../../../support/business_test_harness.dart';

const _legacyBackgroundSettings = {
  'background': '/legacy/assistant-background.jpg',
  'useGradientBackground': true,
  'gradientBackgroundAnimated': false,
  'gradientBackgroundPhase': 7.0,
  'gradientBackgroundOffsetX': 0.4,
  'gradientBackgroundOffsetY': -0.6,
};

const _catalog = AssistantManagerCatalog(
  providers: [
    AssistantManagerProvider(
      key: 'openai',
      name: 'OpenAI',
      enabled: true,
      models: ['gpt-5', 'gpt-5-mini'],
    ),
    AssistantManagerProvider(
      key: 'off',
      name: 'Disabled',
      enabled: false,
      models: ['m'],
    ),
  ],
  mcpServers: [AssistantManagerOption(id: 'mcp-1', name: 'Files')],
  skills: [AssistantManagerOption(id: 'skill-1', name: 'Writer')],
  workspaces: [AssistantManagerOption(id: 'ws-1', name: 'Project')],
  agents: [
    AssistantManagerOption(id: 'opencode', name: 'OpenCode'),
    AssistantManagerOption(id: 'claude-code', name: 'Claude Code'),
    AssistantManagerOption(id: 'codex', name: 'Codex'),
    AssistantManagerOption(id: 'custom:mine', name: 'Custom'),
  ],
  localToolIds: [LocalToolNames.timeInfo, LocalToolNames.calculate],
);

Future<Map<String, dynamic>> _run(
  AssistantManagerTool tool,
  Map<String, dynamic> args,
) async {
  return jsonDecode(await tool.execute(args)) as Map<String, dynamic>;
}

void main() {
  late AssistantProvider assistants;
  late String mainId;
  late AssistantManagerTool tool;

  setUp(() async {
    assistants = AssistantProvider(
      preferences: createBusinessTestPreferences(),
    );
    await assistants.loaded;
    mainId = await assistants.addAssistant(name: 'Main');
    await assistants.setCurrentAssistant(mainId);
    tool = AssistantManagerTool(
      assistants: assistants,
      catalog: _catalog,
      callerAssistantId: mainId,
    );
  });

  test('updating unrelated settings prunes inherited dead MCP ids', () async {
    await assistants.updateAssistant(
      assistants.getById(mainId)!.copyWith(mcpServerIds: ['mcp-1', 'removed']),
    );
    final result = await _run(tool, {
      'action': 'update',
      'assistant_id': mainId,
      'settings': {'name': 'Renamed'},
    });
    expect(result['ok'], isTrue, reason: '$result');
    expect(assistants.getById(mainId)!.mcpServerIds, ['mcp-1']);
  });

  test('explicitly retaining an old dead MCP id prunes it', () async {
    await assistants.updateAssistant(
      assistants.getById(mainId)!.copyWith(mcpServerIds: ['removed']),
    );
    final result = await _run(tool, {
      'action': 'update',
      'assistant_id': mainId,
      'settings': {
        'mcpServerIds': ['removed'],
      },
    });
    expect(result['ok'], isTrue, reason: '$result');
    expect(assistants.getById(mainId)!.mcpServerIds, isEmpty);
    final invalid = await _run(tool, {
      'action': 'update',
      'assistant_id': mainId,
      'settings': {
        'mcpServerIds': ['new-unknown'],
      },
    });
    expect(invalid['ok'], isFalse);
    expect(invalid['error'], 'invalid_settings');
  });

  test('retaining old dead ids works after provider read filtering', () async {
    await assistants.updateAssistant(
      assistants.getById(mainId)!.copyWith(mcpServerIds: ['mcp-1', 'removed']),
    );
    assistants.bindMcpServers(liveMcpServerIds: () => {'mcp-1'});
    expect(assistants.getById(mainId)!.mcpServerIds, ['mcp-1']);
    final result = await _run(tool, {
      'action': 'update',
      'assistant_id': mainId,
      'settings': {
        'name': 'Renamed',
        'mcpServerIds': ['mcp-1', 'removed'],
      },
    });
    expect(result['ok'], isTrue, reason: '$result');
    expect(assistants.getStoredMcpServerIds(mainId), ['mcp-1']);
  });

  test('only changes need approval', () {
    for (final action in ['create', 'update', 'duplicate', 'delete']) {
      expect(
        LocalToolNames.requiresApprovalFor(LocalToolNames.assistantManager, {
          'action': action,
        }),
        isTrue,
        reason: action,
      );
    }
    for (final action in ['list', 'get', 'options', 'switch']) {
      expect(
        LocalToolNames.requiresApprovalFor(LocalToolNames.assistantManager, {
          'action': action,
        }),
        isFalse,
        reason: action,
      );
    }
  });

  test('the schema documents provider and subscription authentication', () {
    final settings =
        AssistantManagerTool
                .definition['function']['parameters']['properties']['settings']['properties']
            as Map;
    expect(settings['agentAuthMode'], isA<Map>());
    expect(settings['agentAuthMode']['type'], 'string');
    expect(settings['agentAuthMode']['enum'], ['provider', 'subscription']);
  });

  test('retired assistant backgrounds are absent from tool settings', () async {
    await assistants.updateAssistant(
      Assistant.fromJson({
        ...assistants.getById(mainId)!.toJson(),
        ..._legacyBackgroundSettings,
      }),
    );
    final schema =
        AssistantManagerTool
                .definition['function']['parameters']['properties']['settings']['properties']
            as Map;
    final result = await _run(tool, {'action': 'get', 'assistant_id': mainId});
    expect(result['ok'], isTrue, reason: '$result');
    final settings = result['settings'] as Map;
    for (final key in _legacyBackgroundSettings.keys) {
      expect(schema.containsKey(key), isFalse, reason: key);
      expect(settings.containsKey(key), isFalse, reason: key);
      expect(AssistantManagerTool.clearableSettings, isNot(contains(key)));
    }
  });

  test('background changes and resets are rejected atomically', () async {
    await assistants.updateAssistant(
      Assistant.fromJson({
        ...assistants.getById(mainId)!.toJson(),
        ..._legacyBackgroundSettings,
      }),
    );
    final original = assistants.getById(mainId)!.toJson();
    for (final action in ['create', 'update', 'duplicate']) {
      for (final entry in _legacyBackgroundSettings.entries) {
        for (final change in [
          {
            'settings': {'name': 'Rejected change', entry.key: entry.value},
          },
          {
            'settings': {'name': 'Rejected change'},
            'clear': [entry.key],
          },
        ]) {
          final result = await _run(tool, {
            'action': action,
            if (action != 'create') 'assistant_id': mainId,
            ...change,
          });
          expect(result['ok'], isFalse, reason: '$action $change');
          expect(result['error'], 'invalid_settings', reason: '$result');
          expect(assistants.assistants.map((a) => a.id), [mainId]);
          expect(assistants.getById(mainId)!.toJson(), original);
        }
      }
    }
  });

  test(
    'updates and copies preserve stored retired background values',
    () async {
      await assistants.updateAssistant(
        Assistant.fromJson({
          ...assistants.getById(mainId)!.toJson(),
          ..._legacyBackgroundSettings,
        }),
      );
      final updated = await _run(tool, {
        'action': 'update',
        'assistant_id': mainId,
        'settings': {'name': 'Renamed', 'temperature': 0.8},
      });
      expect(updated['ok'], isTrue, reason: '$updated');
      final copied = await _run(tool, {
        'action': 'duplicate',
        'assistant_id': mainId,
        'settings': {'name': 'Copy'},
      });
      expect(copied['ok'], isTrue, reason: '$copied');
      final copyId = copied['created']['id'] as String;
      for (final id in [mainId, copyId]) {
        final json = assistants.getById(id)!.toJson();
        for (final entry in _legacyBackgroundSettings.entries) {
          expect(json[entry.key], entry.value, reason: '$id ${entry.key}');
        }
        expect(json['temperature'], 0.8);
      }
      expect(assistants.getById(mainId)!.name, 'Renamed');
      expect(assistants.getById(copyId)!.name, 'Copy');
    },
  );

  for (final agentId in ['claude-code', 'codex']) {
    test('creates a $agentId assistant using its own account', () async {
      final result = await _run(tool, {
        'action': 'create',
        'settings': {
          'name': 'Subscription',
          'agentId': agentId,
          'agentAuthMode': 'subscription',
        },
      });
      expect(result['ok'], isTrue, reason: '$result');
      final id = result['created']['id'] as String;
      final settings = assistants.getById(id)!.toJson();
      expect(settings['agentId'], agentId);
      expect(settings['agentAuthMode'], 'subscription');
      expect(settings['chatModelProvider'], isNull);
      expect(settings['chatModelId'], isNull);
    });
  }

  test('agent session options are set, validated and cleared', () async {
    final created = await _run(tool, {
      'action': 'create',
      'settings': {
        'name': 'Options',
        'agentId': 'codex',
        'agentConfig': {'model': 'gpt-6-astra', 'reasoning_effort': 'high'},
      },
    });
    expect(created['ok'], isTrue, reason: '$created');
    final id = created['created']['id'] as String;
    expect(assistants.getById(id)!.agentConfig, {
      'model': 'gpt-6-astra',
      'reasoning_effort': 'high',
    });

    for (final invalid in [
      'high',
      {'model': 1},
      {'': 'x'},
      {for (var i = 0; i < 17; i++) 'k$i': 'v'},
    ]) {
      final result = await _run(tool, {
        'action': 'update',
        'assistant_id': id,
        'settings': {'agentConfig': invalid},
      });
      expect(result['ok'], isFalse, reason: '$invalid');
      expect(result['error'], 'invalid_settings');
    }
    expect(assistants.getById(id)!.agentConfig, hasLength(2));

    final cleared = await _run(tool, {
      'action': 'update',
      'assistant_id': id,
      'clear': ['agentConfig'],
    });
    expect(cleared['ok'], isTrue, reason: '$cleared');
    expect(assistants.getById(id)!.agentConfig, isEmpty);
    expect(assistants.getById(id)!.agentId, 'codex');
  });

  test(
    'rejects unsupported or invalid subscription requests atomically',
    () async {
      for (final settings in [
        {'name': 'A', 'agentAuthMode': 'subscription'},
        {'name': 'A', 'agentId': 'opencode', 'agentAuthMode': 'subscription'},
        {
          'name': 'A',
          'agentId': 'custom:mine',
          'agentAuthMode': 'subscription',
        },
        {'name': 'A', 'agentId': 'codex', 'agentAuthMode': 'unknown'},
        {'name': 'A', 'agentId': 'codex', 'agentAuthMode': true},
      ]) {
        final result = await _run(tool, {
          'action': 'create',
          'settings': settings,
        });
        expect(result['ok'], isFalse, reason: '$settings');
        expect(result['error'], 'invalid_settings');
        expect(assistants.assistants.map((a) => a.id), [mainId]);
      }
    },
  );

  test(
    'mode changes and copies preserve provider settings and the source',
    () async {
      await assistants.updateAssistant(
        Assistant.fromJson({
          ...assistants.getById(mainId)!.toJson(),
          'agentId': 'codex',
          'agentAuthMode': 'subscription',
          'chatModelProvider': 'openai',
          'chatModelId': 'gpt-5',
        }),
      );

      final duplicate = await _run(tool, {
        'action': 'duplicate',
        'assistant_id': mainId,
      });
      expect(duplicate['ok'], isTrue, reason: '$duplicate');
      final copyId = duplicate['created']['id'] as String;
      expect(
        assistants.getById(copyId)!.toJson()['agentAuthMode'],
        'subscription',
      );
      final switched = await _run(tool, {
        'action': 'update',
        'assistant_id': copyId,
        'settings': {'agentAuthMode': 'provider'},
      });
      expect(switched['ok'], isTrue, reason: '$switched');
      final copy = assistants.getById(copyId)!;
      expect(copy.toJson()['agentAuthMode'], 'provider');
      expect(copy.agentId, 'codex');
      expect(copy.chatModelProvider, 'openai');
      expect(copy.chatModelId, 'gpt-5');
      expect(
        assistants.getById(mainId)!.toJson()['agentAuthMode'],
        'subscription',
      );
    },
  );

  test(
    'an unsupported agent change or agent removal restores provider mode',
    () async {
      for (final mutation in [
        {
          'settings': {'agentId': 'opencode'},
        },
        {
          'clear': ['agentId'],
        },
      ]) {
        await assistants.updateAssistant(
          Assistant.fromJson({
            ...assistants.getById(mainId)!.toJson(),
            'agentId': 'codex',
            'agentAuthMode': 'subscription',
          }),
        );
        final changed = await _run(tool, {
          'action': 'update',
          'assistant_id': mainId,
          ...mutation,
        });
        expect(changed['ok'], isTrue, reason: '$changed');
        expect(
          assistants.getById(mainId)!.toJson()['agentAuthMode'],
          'provider',
        );
      }
    },
  );

  test(
    'setting subscription while removing or changing an agent is rejected',
    () async {
      await assistants.updateAssistant(
        assistants.getById(mainId)!.copyWith(agentId: 'codex'),
      );
      for (final mutation in [
        {
          'settings': {'agentId': 'opencode', 'agentAuthMode': 'subscription'},
        },
        {
          'settings': {'agentAuthMode': 'subscription'},
          'clear': ['agentId'],
        },
      ]) {
        final changed = await _run(tool, {
          'action': 'update',
          'assistant_id': mainId,
          ...mutation,
        });
        expect(changed['ok'], isFalse, reason: '$changed');
        expect(changed['error'], 'invalid_settings');
        expect(assistants.getById(mainId)!.agentId, 'codex');
      }
    },
  );

  test('creates an assistant with every kind of setting', () async {
    final result = await _run(tool, {
      'action': 'create',
      'settings': {
        'name': '  Translator ',
        'avatar': '🦊',
        'useAssistantAvatar': true,
        'chatModelProvider': 'openai',
        'chatModelId': 'gpt-5-mini',
        'systemPrompt': 'Translate to English.',
        'temperature': 0.3,
        'topP': 0.9,
        'maxTokens': 2048,
        'thinkingBudget': -1,
        'contextMessageSize': 20,
        'limitContextMessages': true,
        'streamOutput': false,
        'searchEnabled': true,
        'mcpServerIds': ['mcp-1', 'mcp-1'],
        'localToolIds': [LocalToolNames.calculate],
        'skillIds': ['skill-1'],
        'defaultWorkspaceId': 'ws-1',
        'enableMemory': true,
        'memoryOrganizeEveryNTurns': 5,
        'memorySmartAddMode': 'perItem',
        'memoryWriteScope': 'alwaysAssistant',
        'recentChatsSummaryMessageCount': 10,
        'customHeaders': [
          {'name': 'X-Test', 'value': '1'},
        ],
        'customBody': [
          {'key': 'seed', 'value': '42'},
        ],
        'presetMessages': [
          {'role': 'user', 'content': 'Hi'},
          {'role': 'assistant', 'content': 'Hello'},
        ],
        'regexRules': [
          {
            'name': 'dash',
            'pattern': r'\s--\s',
            'replacement': ' — ',
            'scopes': ['assistant'],
            'visualOnly': true,
          },
        ],
      },
    });

    expect(result['ok'], isTrue, reason: result.toString());
    final id = (result['created'] as Map)['id'] as String;
    final created = assistants.getById(id)!;
    expect(created.name, 'Translator');
    expect(created.avatar, '🦊');
    expect(created.useAssistantAvatar, isTrue);
    expect(created.chatModelProvider, 'openai');
    expect(created.chatModelId, 'gpt-5-mini');
    expect(created.systemPrompt, 'Translate to English.');
    expect(created.temperature, 0.3);
    expect(created.topP, 0.9);
    expect(created.maxTokens, 2048);
    expect(created.thinkingBudget, -1);
    expect(created.contextMessageSize, 20);
    expect(created.limitContextMessages, isTrue);
    expect(created.streamOutput, isFalse);
    expect(created.searchEnabled, isTrue);
    expect(created.mcpServerIds, ['mcp-1']);
    expect(created.localToolIds, [LocalToolNames.calculate]);
    expect(created.skillIds, ['skill-1']);
    expect(created.defaultWorkspaceId, 'ws-1');
    expect(created.enableMemory, isTrue);
    expect(created.memoryOrganizeEveryNTurns, 5);
    expect(created.memorySmartAddMode, MemorySmartAddMode.perItem);
    expect(created.memoryWriteScope, MemoryWriteScope.alwaysAssistant);
    expect(created.recentChatsSummaryMessageCount, 10);
    expect(created.customHeaders, [
      {'name': 'X-Test', 'value': '1'},
    ]);
    expect(created.customBody, [
      {'key': 'seed', 'value': '42'},
    ]);
    expect(created.presetMessages.map((m) => m.role), ['user', 'assistant']);
    expect(created.regexRules.single.scopes, [AssistantRegexScope.assistant]);
    expect(created.regexRules.single.visualOnly, isTrue);
    // Creating does not switch away from the assistant in use.
    expect(assistants.currentAssistantId, mainId);
  });

  test('rejects invalid settings without creating anything', () async {
    final invalid = <Map<String, dynamic>>[
      {'name': 'A', 'chatModelProvider': 'openai', 'chatModelId': 'nope'},
      {'name': 'A', 'chatModelProvider': 'off', 'chatModelId': 'm'},
      {'name': 'A', 'chatModelProvider': 'openai'},
      {'name': 'A', 'temperature': 3},
      {'name': 'A', 'contextMessageSize': 0},
      {
        'name': 'A',
        'mcpServerIds': ['missing'],
      },
      {
        'name': 'A',
        'localToolIds': [LocalToolNames.phoneControl],
      },
      {'name': 'A', 'memoryWriteScope': 'everywhere'},
      {'name': 'A', 'recentChatsSummaryMessageCount': 7},
      {'name': 'A', 'avatar': '/sdcard/me.png'},
      {'name': 'A', 'unknownKey': true},
      {
        'name': 'A',
        'regexRules': [
          {
            'name': 'bad',
            'pattern': '(',
            'replacement': '',
            'scopes': ['user'],
          },
        ],
      },
      {'name': '   '},
      {'systemPrompt': 'no name'},
    ];
    for (final settings in invalid) {
      final result = await _run(tool, {
        'action': 'create',
        'settings': settings,
      });
      expect(result['ok'], isFalse, reason: settings.toString());
      expect(result['message'], isNotEmpty);
    }
    expect(assistants.assistants.map((a) => a.id), [mainId]);
  });

  test('updates only the given settings and clears others', () async {
    await assistants.updateAssistant(
      assistants
          .getById(mainId)!
          .copyWith(
            temperature: 0.7,
            skillIds: ['skill-1'],
            systemPrompt: 'Old',
            chatModelProvider: 'openai',
            chatModelId: 'gpt-5',
          ),
    );

    final result = await _run(tool, {
      'action': 'update',
      'assistant_id': mainId,
      'settings': jsonEncode({'systemPrompt': 'New', 'topP': 0.5}),
      'clear': ['temperature', 'skillIds', 'chatModel'],
    });

    expect(result['ok'], isTrue, reason: result.toString());
    final updated = assistants.getById(mainId)!;
    expect(updated.systemPrompt, 'New');
    expect(updated.topP, 0.5);
    expect(updated.temperature, isNull);
    expect(updated.skillIds, isNull);
    expect(updated.chatModelProvider, isNull);
    expect(updated.chatModelId, isNull);
    expect(updated.name, 'Main');
  });

  test('refuses an update that sets and clears the same setting', () async {
    final result = await _run(tool, {
      'action': 'update',
      'assistant_id': mainId,
      'settings': {'temperature': 0.2},
      'clear': ['temperature'],
    });
    expect(result['ok'], isFalse);
  });

  test('duplicates with overrides and keeps the source unchanged', () async {
    await assistants.updateAssistant(
      assistants
          .getById(mainId)!
          .copyWith(systemPrompt: 'Be brief.', searchEnabled: true),
    );

    final result = await _run(tool, {
      'action': 'duplicate',
      'assistant_id': mainId,
      'settings': {'name': 'Main (mini)', 'temperature': 0.1},
    });

    expect(result['ok'], isTrue, reason: result.toString());
    final copyId = (result['created'] as Map)['id'] as String;
    final copy = assistants.getById(copyId)!;
    expect(copy.name, 'Main (mini)');
    expect(copy.systemPrompt, 'Be brief.');
    expect(copy.searchEnabled, isTrue);
    expect(copy.temperature, 0.1);
    expect(assistants.getById(mainId)!.temperature, isNull);
  });

  test('switches the current assistant', () async {
    final otherId = await assistants.addAssistant(name: 'Other');
    final result = await _run(tool, {
      'action': 'switch',
      'assistant_id': otherId,
    });
    expect(result['ok'], isTrue);
    expect(assistants.currentAssistantId, otherId);
  });

  test('never deletes the calling or the last assistant', () async {
    var result = await _run(tool, {'action': 'delete', 'assistant_id': mainId});
    expect(result['ok'], isFalse);
    expect(assistants.getById(mainId), isNotNull);

    final otherId = await assistants.addAssistant(name: 'Other');
    result = await _run(tool, {'action': 'delete', 'assistant_id': otherId});
    expect(result['ok'], isTrue, reason: result.toString());
    expect(assistants.getById(otherId), isNull);

    final lone = AssistantManagerTool(
      assistants: assistants,
      catalog: _catalog,
      callerAssistantId: null,
    );
    result = await _run(lone, {'action': 'delete', 'assistant_id': mainId});
    expect(result['ok'], isFalse);
    expect(assistants.getById(mainId), isNotNull);
  });

  test('lists and reads assistants without image paths', () async {
    await assistants.updateAssistant(
      assistants.getById(mainId)!.copyWith(background: '#112233'),
    );
    final list = await _run(tool, {'action': 'list'});
    final entry = (list['assistants'] as List).single as Map;
    expect(entry['id'], mainId);
    expect(entry['current'], isTrue);
    expect(entry['runningThisChat'], isTrue);

    final get = await _run(tool, {'action': 'get', 'assistant_id': mainId});
    final settings = (get['settings'] as Map).cast<String, dynamic>();
    expect(settings['name'], 'Main');
    expect(settings.containsKey('background'), isFalse);
    expect(settings.containsKey('id'), isFalse);

    // Every key "get" returns can be sent back unchanged.
    final roundTrip = await _run(tool, {
      'action': 'update',
      'assistant_id': mainId,
      'settings': settings..removeWhere((_, v) => v == null),
    });
    expect(roundTrip['ok'], isTrue, reason: roundTrip.toString());
  });

  test('options lists the catalog', () async {
    final options = await _run(tool, {'action': 'options'});
    expect((options['providers'] as List).first['models'], [
      'gpt-5',
      'gpt-5-mini',
    ]);
    expect(options['localToolIds'], [
      LocalToolNames.timeInfo,
      LocalToolNames.calculate,
    ]);
  });

  test('reports an unknown assistant or action', () async {
    expect(
      (await _run(tool, {'action': 'get', 'assistant_id': 'x'}))['error'],
      'not_found',
    );
    expect((await _run(tool, {'action': 'fly'}))['error'], 'invalid_action');
  });

  test('an agent is set from the options, checked and cleared', () async {
    final options = await _run(tool, {'action': 'options'});
    expect(options['agents'], [
      {'id': 'opencode', 'name': 'OpenCode', 'installed': true},
      {'id': 'claude-code', 'name': 'Claude Code', 'installed': true},
      {'id': 'codex', 'name': 'Codex', 'installed': true},
      {'id': 'custom:mine', 'name': 'Custom', 'installed': true},
    ]);

    final bad = await _run(tool, {
      'action': 'update',
      'assistant_id': mainId,
      'settings': {'agentId': 'nope'},
    });
    expect(bad['ok'], isFalse);
    expect(assistants.getById(mainId)!.agentId, isNull);

    final set = await _run(tool, {
      'action': 'update',
      'assistant_id': mainId,
      'settings': {'agentId': 'opencode'},
    });
    expect(set['ok'], isTrue, reason: '$set');
    expect(assistants.getById(mainId)!.agentId, 'opencode');
    final got = await _run(tool, {'action': 'get', 'assistant_id': mainId});
    expect(got['settings']['agentId'], 'opencode');

    final cleared = await _run(tool, {
      'action': 'update',
      'assistant_id': mainId,
      'clear': ['agentId'],
    });
    expect(cleared['ok'], isTrue, reason: '$cleared');
    expect(assistants.getById(mainId)!.agentId, isNull);
  });
}
