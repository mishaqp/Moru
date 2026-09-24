import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/models/assistant.dart';
import 'package:Kelivo/core/models/assistant_regex.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/features/home/services/assistant_manager_tool.dart';
import 'package:Kelivo/features/home/services/local_tools_service.dart';

import '../../../support/business_test_harness.dart';

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
}
