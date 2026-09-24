import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../core/models/assistant.dart';
import '../../../core/models/assistant_regex.dart';
import '../../../core/models/preset_message.dart';
import '../../../core/providers/assistant_provider.dart';

/// A chat provider and the models the user added to it.
class AssistantManagerProvider {
  const AssistantManagerProvider({
    required this.key,
    required this.name,
    required this.enabled,
    required this.models,
  });

  final String key;
  final String name;
  final bool enabled;
  final List<String> models;
}

/// An MCP server, skill or workspace an assistant can be pointed at.
class AssistantManagerOption {
  const AssistantManagerOption({
    required this.id,
    required this.name,
    this.description = '',
    this.enabled = true,
  });

  final String id;
  final String name;
  final String description;
  final bool enabled;
}

/// Ids the assistant manager may assign, read from the live providers for
/// each call so every id is checked against current data.
class AssistantManagerCatalog {
  const AssistantManagerCatalog({
    this.providers = const [],
    this.mcpServers = const [],
    this.skills = const [],
    this.workspaces = const [],
    this.localToolIds = const [],
  });

  final List<AssistantManagerProvider> providers;
  final List<AssistantManagerOption> mcpServers;
  final List<AssistantManagerOption> skills;
  final List<AssistantManagerOption> workspaces;
  final List<String> localToolIds;
}

class _ToolFailure implements Exception {
  const _ToolFailure(this.error, this.message);

  final String error;
  final String message;
}

/// The `manage_assistants` local tool: lets the model list, inspect, create,
/// configure, copy, switch and delete the user's assistants.
///
/// Settings use the same keys as [Assistant.toJson]. Avatar images and chat
/// backgrounds are left to the settings page, which picks the files.
class AssistantManagerTool {
  AssistantManagerTool({
    required this.assistants,
    required this.catalog,
    required this.callerAssistantId,
  });

  static const String toolName = 'manage_assistants';

  static const String actionList = 'list';
  static const String actionGet = 'get';
  static const String actionOptions = 'options';
  static const String actionCreate = 'create';
  static const String actionUpdate = 'update';
  static const String actionDuplicate = 'duplicate';
  static const String actionSwitch = 'switch';
  static const String actionDelete = 'delete';

  static const List<String> actions = [
    actionList,
    actionGet,
    actionOptions,
    actionCreate,
    actionUpdate,
    actionDuplicate,
    actionSwitch,
    actionDelete,
  ];

  static const Set<String> _approvalActions = {
    actionCreate,
    actionUpdate,
    actionDuplicate,
    actionDelete,
  };

  /// Settings that `clear` resets to "not set / use the global default".
  static const List<String> clearableSettings = [
    'chatModel',
    'temperature',
    'topP',
    'thinkingBudget',
    'maxTokens',
    'defaultWorkspaceId',
    'skillIds',
    'avatar',
  ];

  static const Map<String, String> _memorySmartAddModes = {
    'batched': 'Extract memories once per reply',
    'perItem': 'Store each memory item separately',
  };

  static const Map<String, String> _memoryWriteScopes = {
    'alwaysGlobal': 'Always write shared memories',
    'alwaysAssistant': 'Always write memories private to this assistant',
    'toolDefaultGlobal': 'Model chooses, shared by default',
    'toolDefaultAssistant': 'Model chooses, private by default',
  };

  final AssistantProvider assistants;
  final AssistantManagerCatalog catalog;

  /// The assistant running the chat that called the tool.
  final String? callerAssistantId;

  static String actionOf(Map<String, dynamic> args) =>
      (args['action'] ?? '').toString().trim().toLowerCase();

  /// Creating, changing, copying and deleting assistants need the user's OK.
  static bool requiresApproval(Map<String, dynamic> args) =>
      _approvalActions.contains(actionOf(args));

  static Map<String, dynamic> get definition => {
    'type': 'function',
    'function': {
      'name': toolName,
      'description':
          'Create, configure, copy, switch and delete the user\'s assistants '
          'in this app. Call action "options" first to get the valid model, '
          'MCP server, skill, workspace and local tool ids, and "get" to read '
          'an assistant\'s current settings before changing it. "create", '
          '"update", "duplicate" and "delete" ask the user for confirmation. '
          'Changes apply from the next message. Deleting an assistant also '
          'deletes its conversations; the assistant running this chat and '
          'the last remaining assistant cannot be deleted. Avatar images and '
          'chat backgrounds are set by the user in the settings page.',
      'parameters': {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'enum': actions,
            'description':
                'list: all assistants. get: one assistant\'s settings. '
                'options: valid ids and values for settings. create: new '
                'assistant from settings (name required). update: change '
                'settings of assistant_id. duplicate: copy assistant_id, '
                'optionally applying settings to the copy. switch: make '
                'assistant_id the current assistant. delete: remove '
                'assistant_id and its conversations.',
          },
          'assistant_id': {
            'type': 'string',
            'description':
                'Target assistant for get, update, duplicate, switch and '
                'delete. Use the ids returned by "list".',
          },
          'settings': {
            'type': 'object',
            'description':
                'Settings to set. Only include keys you want to change.',
            'properties': _settingsSchema,
          },
          'clear': {
            'type': 'array',
            'items': {'type': 'string', 'enum': clearableSettings},
            'description':
                'Settings to reset to "not set": chatModel and the sampling '
                'values fall back to the global defaults, skillIds back to '
                '"all skills", defaultWorkspaceId and avatar are removed.',
          },
        },
        'required': ['action'],
      },
    },
  };

  static Map<String, dynamic> get _settingsSchema => {
    'name': {'type': 'string', 'description': 'Display name.'},
    'avatar': {
      'type': 'string',
      'description': 'An emoji used as the avatar, for example "🦊".',
    },
    'useAssistantAvatar': {
      'type': 'boolean',
      'description': 'Show the assistant avatar instead of the model icon.',
    },
    'useAssistantName': {
      'type': 'boolean',
      'description': 'Show the assistant name instead of the model name.',
    },
    'chatModelProvider': {
      'type': 'string',
      'description':
          'Provider key from "options". Set together with chatModelId.',
    },
    'chatModelId': {
      'type': 'string',
      'description': 'Model id of that provider from "options".',
    },
    'systemPrompt': {'type': 'string'},
    'messageTemplate': {
      'type': 'string',
      'description':
          'Template for each user message; {{ message }} is replaced by the '
          'text. Default "{{ message }}".',
    },
    'temperature': {'type': 'number', 'minimum': 0, 'maximum': 2},
    'topP': {'type': 'number', 'minimum': 0, 'maximum': 1},
    'maxTokens': {'type': 'integer', 'minimum': 1},
    'thinkingBudget': {
      'type': 'integer',
      'description':
          'Reasoning: 0 off, -1 auto, 1024 low, 16000 medium, 32000 high, '
          '64000 extra high, 128000 max, or another token count.',
    },
    'contextMessageSize': {
      'type': 'integer',
      'minimum': Assistant.minContextMessageSize,
      'maximum': Assistant.maxContextMessageSize,
      'description':
          'Previous messages sent as context when limitContextMessages is '
          'on.',
    },
    'limitContextMessages': {'type': 'boolean'},
    'streamOutput': {'type': 'boolean'},
    'searchEnabled': {'type': 'boolean', 'description': 'Allow web search.'},
    'mcpServerIds': {
      'type': 'array',
      'items': {'type': 'string'},
    },
    'localToolIds': {
      'type': 'array',
      'items': {'type': 'string'},
      'description': 'Local tools, ids from "options".',
    },
    'skillIds': {
      'type': 'array',
      'items': {'type': 'string'},
      'description':
          'Only these skills. Use clear ["skillIds"] to allow all skills.',
    },
    'defaultWorkspaceId': {'type': 'string'},
    'allowConversationSystemPrompt': {'type': 'boolean'},
    'allowConversationPromptInjection': {'type': 'boolean'},
    'enableMemory': {'type': 'boolean'},
    'autoOrganizeMemory': {'type': 'boolean'},
    'memoryOrganizeEveryNTurns': {
      'type': 'integer',
      'minimum': Assistant.minMemoryOrganizeEveryNTurns,
      'maximum': Assistant.maxMemoryOrganizeEveryNTurns,
    },
    'memorySmartAddMode': {
      'type': 'string',
      'enum': _memorySmartAddModes.keys.toList(),
    },
    'memoryWriteScope': {
      'type': 'string',
      'enum': _memoryWriteScopes.keys.toList(),
    },
    'allowPastConversationRecall': {'type': 'boolean'},
    'generateConversationSummary': {'type': 'boolean'},
    'recentChatsSummaryMessageCount': {
      'type': 'integer',
      'enum': Assistant.recentChatsSummaryMessageCountOptions,
    },
    'appendCurrentTimeToUserMessage': {'type': 'boolean'},
    'useIso8601TimeFormat': {'type': 'boolean'},
    'customHeaders': {
      'type': 'array',
      'description': 'Extra HTTP headers for this assistant\'s requests.',
      'items': {
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
          'value': {'type': 'string'},
        },
        'required': ['name', 'value'],
      },
    },
    'customBody': {
      'type': 'array',
      'description':
          'Extra request body fields; value is JSON text or a plain string.',
      'items': {
        'type': 'object',
        'properties': {
          'key': {'type': 'string'},
          'value': {'type': 'string'},
        },
        'required': ['key', 'value'],
      },
    },
    'presetMessages': {
      'type': 'array',
      'description': 'Messages inserted at the start of every conversation.',
      'items': {
        'type': 'object',
        'properties': {
          'role': {
            'type': 'string',
            'enum': ['user', 'assistant'],
          },
          'content': {'type': 'string'},
        },
        'required': ['role', 'content'],
      },
    },
    'regexRules': {
      'type': 'array',
      'description': 'Regex replacements applied to message text.',
      'items': {
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
          'pattern': {'type': 'string'},
          'replacement': {'type': 'string'},
          'scopes': {
            'type': 'array',
            'items': {
              'type': 'string',
              'enum': ['user', 'assistant'],
            },
          },
          'visualOnly': {'type': 'boolean'},
          'replaceOnly': {'type': 'boolean'},
          'enabled': {'type': 'boolean'},
        },
        'required': ['name', 'pattern', 'replacement', 'scopes'],
      },
    },
  };

  Future<String> execute(Map<String, dynamic> args) async {
    try {
      await assistants.loaded;
      final action = actionOf(args);
      final Map<String, dynamic> result;
      switch (action) {
        case actionList:
          result = _list();
        case actionGet:
          result = _get(_target(args));
        case actionOptions:
          result = _options();
        case actionCreate:
          result = await _create(args);
        case actionUpdate:
          result = await _update(args);
        case actionDuplicate:
          result = await _duplicate(args);
        case actionSwitch:
          result = await _switch(args);
        case actionDelete:
          result = await _delete(args);
        default:
          throw _ToolFailure(
            'invalid_action',
            'Unknown action "$action". Use one of: ${actions.join(', ')}.',
          );
      }
      return jsonEncode({'ok': true, ...result});
    } on _ToolFailure catch (e) {
      return jsonEncode({'ok': false, 'error': e.error, 'message': e.message});
    }
  }

  Map<String, dynamic> _list() => {
    'assistants': [for (final a in assistants.assistants) _summary(a)],
  };

  Map<String, dynamic> _summary(Assistant a) => {
    'id': a.id,
    'name': a.name,
    'model': a.chatModelProvider == null || a.chatModelId == null
        ? null
        : {'provider': a.chatModelProvider, 'id': a.chatModelId},
    'current': a.id == assistants.currentAssistantId,
    'runningThisChat': a.id == callerAssistantId,
  };

  Map<String, dynamic> _get(Assistant a) => {
    ..._summary(a),
    'settings': _settingsOf(a),
  };

  Map<String, dynamic> _settingsOf(Assistant a) {
    final json = a.toJson();
    for (final key in const [
      'id',
      'background',
      'useGradientBackground',
      'gradientBackgroundAnimated',
      'gradientBackgroundPhase',
      'gradientBackgroundOffsetX',
      'gradientBackgroundOffsetY',
      'defaultWorkspaceSetup',
      'healthDataTypeIds',
    ]) {
      json.remove(key);
    }
    if (!_isEmojiAvatar(a.avatar)) json.remove('avatar');
    json['presetMessages'] = [
      for (final m in a.presetMessages) {'role': m.role, 'content': m.content},
    ];
    json['regexRules'] = [
      for (final r in a.regexRules)
        {
          'name': r.name,
          'pattern': r.pattern,
          'replacement': r.replacement,
          'scopes': [for (final s in r.scopes) s.name],
          'visualOnly': r.visualOnly,
          'replaceOnly': r.replaceOnly,
          'enabled': r.enabled,
        },
    ];
    return json;
  }

  Map<String, dynamic> _options() => {
    'providers': [
      for (final p in catalog.providers)
        {
          'key': p.key,
          'name': p.name,
          'enabled': p.enabled,
          'models': p.models,
        },
    ],
    'mcpServers': [
      for (final s in catalog.mcpServers)
        {'id': s.id, 'name': s.name, 'enabled': s.enabled},
    ],
    'skills': [
      for (final s in catalog.skills)
        {
          'id': s.id,
          'name': s.name,
          'description': s.description,
          'enabled': s.enabled,
        },
    ],
    'workspaces': [
      for (final w in catalog.workspaces) {'id': w.id, 'name': w.name},
    ],
    'localToolIds': catalog.localToolIds,
    'memorySmartAddMode': _memorySmartAddModes,
    'memoryWriteScope': _memoryWriteScopes,
    'recentChatsSummaryMessageCount':
        Assistant.recentChatsSummaryMessageCountOptions,
  };

  Future<Map<String, dynamic>> _create(Map<String, dynamic> args) async {
    final settings = _settingsArg(args);
    final name = settings['name'];
    if (name is! String || name.trim().isEmpty) {
      throw const _ToolFailure(
        'invalid_settings',
        'settings.name is required to create an assistant.',
      );
    }
    // Validate everything before anything is written.
    final draft = _apply(
      Assistant(id: '', name: name.trim()),
      settings,
      _clearArg(args),
    );
    final id = await assistants.addAssistant(name: draft.name);
    final created = assistants.getById(id)!;
    await assistants.updateAssistant(
      _apply(created, settings, _clearArg(args)),
    );
    return {'created': _get(assistants.getById(id)!)};
  }

  Future<Map<String, dynamic>> _update(Map<String, dynamic> args) async {
    final target = _target(args);
    final settings = _settingsArg(args);
    final clear = _clearArg(args);
    if (settings.isEmpty && clear.isEmpty) {
      throw const _ToolFailure(
        'invalid_settings',
        'Pass settings and/or clear with the changes to make.',
      );
    }
    await assistants.updateAssistant(_apply(target, settings, clear));
    return {'updated': _get(assistants.getById(target.id)!)};
  }

  Future<Map<String, dynamic>> _duplicate(Map<String, dynamic> args) async {
    final source = _target(args);
    final settings = _settingsArg(args);
    final clear = _clearArg(args);
    _apply(source, settings, clear);
    final id = await assistants.duplicateAssistant(source.id);
    if (id == null) {
      throw const _ToolFailure('not_found', 'The assistant no longer exists.');
    }
    if (settings.isNotEmpty || clear.isNotEmpty) {
      await assistants.updateAssistant(
        _apply(assistants.getById(id)!, settings, clear),
      );
    }
    return {'created': _get(assistants.getById(id)!)};
  }

  Future<Map<String, dynamic>> _switch(Map<String, dynamic> args) async {
    final target = _target(args);
    await assistants.setCurrentAssistant(target.id);
    return {
      'current': _summary(target),
      'note':
          'Messages sent from now on use this assistant. Earlier chats keep '
          'their own assistant.',
    };
  }

  Future<Map<String, dynamic>> _delete(Map<String, dynamic> args) async {
    final target = _target(args);
    if (target.id == callerAssistantId) {
      throw const _ToolFailure(
        'not_allowed',
        'The assistant running this chat cannot delete itself. Ask the user '
            'to delete it from the assistant list.',
      );
    }
    if (assistants.assistants.length <= 1) {
      throw const _ToolFailure(
        'not_allowed',
        'The last remaining assistant cannot be deleted.',
      );
    }
    final deleted = await assistants.deleteAssistant(target.id);
    if (!deleted) {
      throw const _ToolFailure('not_found', 'The assistant no longer exists.');
    }
    return {'deleted': target.id};
  }

  Assistant _target(Map<String, dynamic> args) {
    final id = (args['assistant_id'] ?? '').toString().trim();
    if (id.isEmpty) {
      throw const _ToolFailure(
        'missing_assistant_id',
        'assistant_id is required. Call action "list" for ids.',
      );
    }
    final assistant = assistants.getById(id);
    if (assistant == null) {
      throw _ToolFailure(
        'not_found',
        'No assistant with id "$id". Call action "list" for ids.',
      );
    }
    return assistant;
  }

  Map<String, dynamic> _settingsArg(Map<String, dynamic> args) {
    final raw = args['settings'];
    if (raw == null) return const {};
    if (raw is Map) return raw.map((k, v) => MapEntry(k.toString(), v));
    if (raw is String && raw.trim().isNotEmpty) {
      // Some models send nested objects as JSON text.
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return decoded.map((k, v) => MapEntry(k.toString(), v));
        }
      } on FormatException {
        // Reported below.
      }
    }
    throw const _ToolFailure('invalid_settings', 'settings must be an object.');
  }

  Set<String> _clearArg(Map<String, dynamic> args) {
    final raw = args['clear'];
    if (raw == null) return const {};
    if (raw is! List) {
      throw const _ToolFailure(
        'invalid_settings',
        'clear must be a list of setting names.',
      );
    }
    final keys = {for (final k in raw) k.toString()};
    final unknown = keys.difference(clearableSettings.toSet());
    if (unknown.isNotEmpty) {
      throw _ToolFailure(
        'invalid_settings',
        'Cannot clear ${unknown.join(', ')}. Clearable: '
            '${clearableSettings.join(', ')}.',
      );
    }
    return keys;
  }

  /// Returns [base] with [settings] and [clear] applied, or throws a
  /// [_ToolFailure] naming the first invalid value. Never writes anything.
  Assistant _apply(
    Assistant base,
    Map<String, dynamic> settings,
    Set<String> clear,
  ) {
    final allowed = _settingsSchema.keys.toSet();
    final unknown = settings.keys.where((k) => !allowed.contains(k)).toList();
    if (unknown.isNotEmpty) {
      throw _ToolFailure(
        'invalid_settings',
        'Unknown settings: ${unknown.join(', ')}. Allowed: '
            '${allowed.join(', ')}.',
      );
    }
    for (final key in clear) {
      final setKey = key == 'chatModel' ? 'chatModelProvider' : key;
      if (settings.containsKey(setKey) ||
          (key == 'chatModel' && settings.containsKey('chatModelId'))) {
        throw _ToolFailure(
          'invalid_settings',
          '"$key" is both set and cleared.',
        );
      }
    }

    final s = _SettingsReader(settings);
    var next = base.copyWith(
      clearChatModel: clear.contains('chatModel'),
      clearTemperature: clear.contains('temperature'),
      clearTopP: clear.contains('topP'),
      clearThinkingBudget: clear.contains('thinkingBudget'),
      clearMaxTokens: clear.contains('maxTokens'),
      clearDefaultWorkspaceId: clear.contains('defaultWorkspaceId'),
      clearSkillIds: clear.contains('skillIds'),
      clearAvatar: clear.contains('avatar'),
    );

    final name = s.string('name');
    if (name != null && name.trim().isEmpty) {
      throw const _ToolFailure('invalid_settings', 'name cannot be empty.');
    }
    final avatar = s.string('avatar');
    if (avatar != null && !_isEmojiAvatar(avatar)) {
      throw const _ToolFailure(
        'invalid_settings',
        'avatar must be a single emoji. Images are set in the settings page.',
      );
    }

    final hasProvider = settings.containsKey('chatModelProvider');
    final hasModel = settings.containsKey('chatModelId');
    if (hasProvider != hasModel) {
      throw const _ToolFailure(
        'invalid_settings',
        'Set chatModelProvider and chatModelId together.',
      );
    }
    final providerKey = s.string('chatModelProvider');
    final modelId = s.string('chatModelId');
    if (providerKey != null && modelId != null) {
      _checkModel(providerKey, modelId);
    }

    final thinkingBudget = s.integer('thinkingBudget');
    if (thinkingBudget != null && thinkingBudget < -1) {
      throw const _ToolFailure(
        'invalid_settings',
        'thinkingBudget must be -1 (auto), 0 (off) or a token count.',
      );
    }
    final summaryCount = s.integer('recentChatsSummaryMessageCount');
    if (summaryCount != null &&
        !Assistant.recentChatsSummaryMessageCountOptions.contains(
          summaryCount,
        )) {
      throw _ToolFailure(
        'invalid_settings',
        'recentChatsSummaryMessageCount must be one of '
            '${Assistant.recentChatsSummaryMessageCountOptions.join(', ')}.',
      );
    }

    final mcpServerIds = s.stringList('mcpServerIds');
    if (mcpServerIds != null) {
      _checkIds('mcpServerIds', mcpServerIds, {
        for (final o in catalog.mcpServers) o.id,
      });
    }
    final localToolIds = s.stringList('localToolIds');
    if (localToolIds != null) {
      _checkIds('localToolIds', localToolIds, catalog.localToolIds.toSet());
    }
    final skillIds = s.stringList('skillIds');
    if (skillIds != null) {
      _checkIds('skillIds', skillIds, {for (final o in catalog.skills) o.id});
    }
    final workspaceId = s.string('defaultWorkspaceId');
    if (workspaceId != null) {
      _checkIds(
        'defaultWorkspaceId',
        [workspaceId],
        {for (final o in catalog.workspaces) o.id},
      );
    }

    final smartAdd = s.oneOf('memorySmartAddMode', _memorySmartAddModes.keys);
    final writeScope = s.oneOf('memoryWriteScope', _memoryWriteScopes.keys);

    next = next.copyWith(
      name: name?.trim(),
      avatar: avatar?.trim(),
      useAssistantAvatar: s.boolean('useAssistantAvatar'),
      useAssistantName: s.boolean('useAssistantName'),
      chatModelProvider: providerKey,
      chatModelId: modelId,
      systemPrompt: s.string('systemPrompt'),
      messageTemplate: s.string('messageTemplate'),
      temperature: s.number('temperature', min: 0, max: 2),
      topP: s.number('topP', min: 0, max: 1),
      maxTokens: s.integer('maxTokens', min: 1),
      thinkingBudget: thinkingBudget,
      contextMessageSize: s.integer(
        'contextMessageSize',
        min: Assistant.minContextMessageSize,
        max: Assistant.maxContextMessageSize,
      ),
      limitContextMessages: s.boolean('limitContextMessages'),
      streamOutput: s.boolean('streamOutput'),
      searchEnabled: s.boolean('searchEnabled'),
      mcpServerIds: mcpServerIds,
      localToolIds: localToolIds,
      skillIds: skillIds,
      defaultWorkspaceId: workspaceId,
      allowConversationSystemPrompt: s.boolean('allowConversationSystemPrompt'),
      allowConversationPromptInjection: s.boolean(
        'allowConversationPromptInjection',
      ),
      enableMemory: s.boolean('enableMemory'),
      autoOrganizeMemory: s.boolean('autoOrganizeMemory'),
      memoryOrganizeEveryNTurns: s.integer(
        'memoryOrganizeEveryNTurns',
        min: Assistant.minMemoryOrganizeEveryNTurns,
        max: Assistant.maxMemoryOrganizeEveryNTurns,
      ),
      memorySmartAddMode: smartAdd == null
          ? null
          : Assistant.memorySmartAddModeFromString(smartAdd),
      memoryWriteScope: writeScope == null
          ? null
          : Assistant.memoryWriteScopeFromString(writeScope),
      allowPastConversationRecall: s.boolean('allowPastConversationRecall'),
      generateConversationSummary: s.boolean('generateConversationSummary'),
      recentChatsSummaryMessageCount: summaryCount,
      appendCurrentTimeToUserMessage: s.boolean(
        'appendCurrentTimeToUserMessage',
      ),
      useIso8601TimeFormat: s.boolean('useIso8601TimeFormat'),
      customHeaders: s.pairs('customHeaders', 'name'),
      customBody: s.pairs('customBody', 'key'),
      presetMessages: _presetMessages(settings['presetMessages']),
      regexRules: _regexRules(settings['regexRules']),
    );
    return next;
  }

  void _checkModel(String providerKey, String modelId) {
    final provider = catalog.providers
        .where((p) => p.key == providerKey)
        .firstOrNull;
    if (provider == null) {
      throw _ToolFailure(
        'invalid_settings',
        'Unknown provider "$providerKey". Providers: '
            '${catalog.providers.map((p) => p.key).join(', ')}.',
      );
    }
    if (!provider.enabled) {
      throw _ToolFailure(
        'invalid_settings',
        'Provider "$providerKey" is turned off in the app.',
      );
    }
    if (!provider.models.contains(modelId)) {
      throw _ToolFailure(
        'invalid_settings',
        'Provider "$providerKey" has no model "$modelId". Models: '
            '${provider.models.join(', ')}.',
      );
    }
  }

  void _checkIds(String key, List<String> ids, Set<String> valid) {
    final unknown = ids.where((id) => !valid.contains(id)).toList();
    if (unknown.isEmpty) return;
    throw _ToolFailure(
      'invalid_settings',
      '$key has unknown ids: ${unknown.join(', ')}. Call action "options" '
          'for valid ids.',
    );
  }

  List<PresetMessage>? _presetMessages(Object? raw) {
    if (raw == null) return null;
    if (raw is! List) {
      throw const _ToolFailure(
        'invalid_settings',
        'presetMessages must be a list.',
      );
    }
    return [
      for (final item in raw)
        if (item is Map &&
            (item['role'] == 'user' || item['role'] == 'assistant') &&
            item['content'] is String)
          PresetMessage(
            role: item['role'] as String,
            content: item['content'] as String,
          )
        else
          throw const _ToolFailure(
            'invalid_settings',
            'Each preset message needs role "user" or "assistant" and '
                'string content.',
          ),
    ];
  }

  List<AssistantRegex>? _regexRules(Object? raw) {
    if (raw == null) return null;
    if (raw is! List) {
      throw const _ToolFailure(
        'invalid_settings',
        'regexRules must be a list.',
      );
    }
    final rules = <AssistantRegex>[];
    for (final item in raw) {
      if (item is! Map ||
          item['name'] is! String ||
          item['pattern'] is! String ||
          item['replacement'] is! String) {
        throw const _ToolFailure(
          'invalid_settings',
          'Each regex rule needs string name, pattern and replacement.',
        );
      }
      final pattern = item['pattern'] as String;
      try {
        RegExp(pattern);
      } on FormatException catch (e) {
        throw _ToolFailure(
          'invalid_settings',
          'Invalid regex "$pattern": ${e.message}',
        );
      }
      final rawScopes = item['scopes'];
      final scopes = <AssistantRegexScope>[
        if (rawScopes is List)
          for (final scope in rawScopes)
            AssistantRegexScopeX.fromName(scope.toString()) ??
                (throw _ToolFailure(
                  'invalid_settings',
                  'Unknown regex scope "$scope". Use user or assistant.',
                )),
      ];
      if (scopes.isEmpty) {
        throw const _ToolFailure(
          'invalid_settings',
          'Each regex rule needs at least one scope: user or assistant.',
        );
      }
      final visualOnly = item['visualOnly'] == true;
      final replaceOnly = item['replaceOnly'] == true;
      if (visualOnly && replaceOnly) {
        throw const _ToolFailure(
          'invalid_settings',
          'A regex rule cannot be both visualOnly and replaceOnly.',
        );
      }
      rules.add(
        AssistantRegex(
          id: const Uuid().v4(),
          name: item['name'] as String,
          pattern: pattern,
          replacement: item['replacement'] as String,
          scopes: scopes,
          visualOnly: visualOnly,
          replaceOnly: replaceOnly,
          enabled: item['enabled'] != false,
        ),
      );
    }
    return rules;
  }

  /// Emoji avatars are short text; anything path- or URL-like is an image
  /// the settings page manages.
  static bool _isEmojiAvatar(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty || text.runes.length > 8) return false;
    return !RegExp(r'[A-Za-z0-9/\\:.]').hasMatch(text);
  }
}

/// Typed, range-checked reads from the model's settings object.
class _SettingsReader {
  _SettingsReader(this._settings);

  final Map<String, dynamic> _settings;

  Never _invalid(String key, String expected) => throw _ToolFailure(
    'invalid_settings',
    '$key must be $expected, got ${jsonEncode(_settings[key])}.',
  );

  String? string(String key) {
    if (!_settings.containsKey(key)) return null;
    final value = _settings[key];
    if (value is String) return value;
    _invalid(key, 'a string');
  }

  bool? boolean(String key) {
    if (!_settings.containsKey(key)) return null;
    final value = _settings[key];
    if (value is bool) return value;
    _invalid(key, 'true or false');
  }

  double? number(String key, {required double min, required double max}) {
    if (!_settings.containsKey(key)) return null;
    final value = _settings[key];
    if (value is num && value.isFinite && value >= min && value <= max) {
      return value.toDouble();
    }
    _invalid(key, 'a number from $min to $max');
  }

  int? integer(String key, {int? min, int? max}) {
    if (!_settings.containsKey(key)) return null;
    final value = _settings[key];
    if (value is num && value == value.roundToDouble()) {
      final n = value.toInt();
      if ((min == null || n >= min) && (max == null || n <= max)) return n;
    }
    final range = [
      if (min != null) 'at least $min',
      if (max != null) 'at most $max',
    ].join(' and ');
    _invalid(key, range.isEmpty ? 'an integer' : 'an integer $range');
  }

  String? oneOf(String key, Iterable<String> values) {
    final value = string(key);
    if (value == null || values.contains(value)) return value;
    _invalid(key, 'one of ${values.join(', ')}');
  }

  List<String>? stringList(String key) {
    if (!_settings.containsKey(key)) return null;
    final value = _settings[key];
    if (value is List && value.every((e) => e is String)) {
      return <String>{
        for (final id in value.cast<String>())
          if (id.trim().isNotEmpty) id.trim(),
      }.toList();
    }
    _invalid(key, 'a list of strings');
  }

  /// Header/body pairs stored as `{nameKey: ..., 'value': ...}`.
  List<Map<String, String>>? pairs(String key, String nameKey) {
    if (!_settings.containsKey(key)) return null;
    final value = _settings[key];
    if (value is List) {
      final out = <Map<String, String>>[];
      for (final item in value) {
        if (item is! Map ||
            item[nameKey] is! String ||
            item['value'] is! String) {
          _invalid(key, 'a list of {"$nameKey": ..., "value": ...} objects');
        }
        final name = (item[nameKey] as String).trim();
        if (name.isEmpty) _invalid(key, 'entries with a non-empty $nameKey');
        out.add({nameKey: name, 'value': item['value'] as String});
      }
      return out;
    }
    _invalid(key, 'a list of {"$nameKey": ..., "value": ...} objects');
  }
}
