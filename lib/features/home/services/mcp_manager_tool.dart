import 'dart:convert';

import '../../../core/models/assistant.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/mcp_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/mcp/mcp_config_import.dart';
import '../../../core/services/mcp/mcp_secrets.dart';
import '../../../core/services/mcp/mcp_tool_privacy.dart';
import 'tool_approval_service.dart';

/// Opt-in MCP configuration through the normal approval service. Only the
/// provider starts servers; installing packages is a separate workspace shell.
class McpManagerTool {
  McpManagerTool({
    required this.provider,
    this.approvals,
    this.autoApproveAll = false,
    this.checkAllowed,
    this.defaultWorkspaceId,
    this.assistants,
    this.chat,
    this.currentAssistantId,
  });

  static const toolName = 'manage_mcp';
  static const actions = [
    'list',
    'get',
    'add',
    'update',
    'enable',
    'disable',
    'remove',
    'test',
    'select',
    'unselect',
    'set_tool',
    'refresh',
    'reconnect',
    'import',
    'set_timeout',
  ];
  final McpProvider provider;
  final ToolApprovalService? approvals;
  final bool autoApproveAll;
  final void Function()? checkAllowed;
  final String? defaultWorkspaceId;
  final AssistantProvider? assistants;
  final ChatService? chat;
  final String? currentAssistantId;
  static const _availabilityNotice =
      'New tools become available from the next message once this server is connected and selected for the assistant.';

  static String actionOf(Map<String, dynamic> args) =>
      (args['action'] ?? '').toString().trim().toLowerCase();
  static bool requiresApproval(Map<String, dynamic> args) =>
      actions.contains(actionOf(args)) &&
      !const {'list', 'get', 'test'}.contains(actionOf(args));

  static Map<String, dynamic> get definition => {
    'type': 'function',
    'function': {
      'name': toolName,
      'description':
          'Manage MCP servers, assistant selection and tool settings using live ids from list. select/unselect target assistant_id or this chat\'s assistant; add/enable/import select it automatically. update changes only supplied config fields. workspaceId binds STDIO /workspace to chat files; add/import default to the chat workspace, explicit null unbinds. Selected tools become available from the next message. Full trust skips confirmations; other mutations require consent. Ordinary env/headers are visible. Never supply or request secrets in chat: use empty secret env/header values or {{NAME}} in args/URL for the user\'s private input card, also in full trust; this server\'s saved secrets are reused by name. import takes Claude Desktop mcpServers JSON. set_timeout changes the global MCP request timeout. Install packages separately through workspace shell; this tool has no installer.',
      'parameters': {
        'type': 'object',
        'additionalProperties': false,
        'properties': {
          'action': {'type': 'string', 'enum': actions},
          'server_id': {
            'type': 'string',
            'description':
                'Live id from list; omitted for list/add/import/set_timeout.',
          },
          'assistant_id': {
            'type': 'string',
            'description':
                'select/unselect: live assistant id; defaults to this chat.',
          },
          'tool_name': {
            'type': 'string',
            'description':
                'set_tool: tool name or safe alias from this server\'s get/list.',
          },
          'enabled': {
            'type': 'boolean',
            'description': 'set_tool: enable/disable the individual tool.',
          },
          'needs_approval': {
            'type': 'boolean',
            'description': 'set_tool: require confirmation outside full trust.',
          },
          'timeout_seconds': {
            'type': 'integer',
            'minimum': 1,
            'maximum': 86400,
          },
          'json': {
            'type': 'string',
            'maxLength': 65536,
            'description':
                'import: JSON object with mcpServers; never include literal secrets.',
          },
          'name': {
            'type': 'string',
            'maxLength': 128,
            'description': 'Required for add; optional new name for update.',
          },
          'config': {
            'type': 'object',
            'additionalProperties': false,
            'properties': {
              'type': {
                'type': 'string',
                'enum': ['stdio', 'http', 'sse'],
              },
              'command': {
                'type': 'string',
                'description': 'STDIO executable, not an installation command.',
              },
              'args': {
                'type': 'array',
                'maxItems': 64,
                'items': {'type': 'string'},
                'description':
                    'STDIO arguments; use {{NAME}} for private values.',
              },
              'url': {
                'type': 'string',
                'description':
                    'HTTP/SSE endpoint; use {{NAME}} for private URL parts.',
              },
              'env': {
                'type': 'object',
                'additionalProperties': {'type': 'string', 'maxLength': 2048},
                'description':
                    'Ordinary values are allowed; use empty strings for secret names/values so the user can enter them privately.',
              },
              'headers': {
                'type': 'object',
                'additionalProperties': {'type': 'string', 'maxLength': 2048},
                'description':
                    'Ordinary values are allowed; use empty strings for secrets. User includes Bearer/Basic privately when needed.',
              },
              'cwd': {
                'type': ['string', 'null'],
              },
              'workspaceId': {
                'type': ['string', 'null'],
                'description':
                    'Optional live workspace id from manage_assistants options. Null unbinds it.',
              },
              'disabled': {'type': 'boolean'},
            },
          },
        },
        'required': ['action'],
      },
    },
  };

  static Map<String, dynamic> serverSummary(
    McpServerConfig server,
    McpProvider provider,
  ) {
    final secrets = McpSecrets(server);
    final privacy = McpToolPrivacy(provider);
    String publicText(String value) => privacy.text(secrets.text(value));
    String? publicValue(String? value) =>
        value == null ? null : publicText(value);
    Map<String, Object?> names(
      Map<String, String> values, {
      bool private = false,
    }) => {
      for (final entry in values.entries)
        publicText(entry.key): {
          'value_set': entry.value.isNotEmpty,
          if (!private &&
              !McpSecrets.isSecret(entry.key, entry.value) &&
              !privacy.containsCredential(entry.value))
            'value': privacy.text(secrets.redactor.text(entry.value)),
        },
    };
    return {
      'id': server.id,
      'name': publicText(server.name),
      'type': server.transport.name,
      'enabled': server.enabled,
      'status': provider.statusFor(server.id).name,
      'error': publicValue(provider.errorFor(server.id)),
      'request_timeout_seconds': provider.requestTimeoutSeconds,
      if (server.transport == McpTransportType.stdio) ...{
        'command': publicText(server.command ?? ''),
        'args': server.args.map(publicText).toList(),
        'env': names(server.env),
        'cwd': publicValue(server.workingDirectory),
        'workspaceId': server.workspaceId,
        'environment_available': provider.supportsStdio,
      } else if (server.transport != McpTransportType.inmemory) ...{
        'url': publicText(server.url),
        'headers': names(server.headers),
        'authorization_set': server.oauth?.accessToken.isNotEmpty == true,
      },
      'secrets': names(server.managedSecrets, private: true),
      'tool_count': server.tools.length,
      'tools': [
        for (final tool in server.tools)
          {
            'name': privacy.toolNameForModel(server, tool.name),
            'description': publicValue(tool.description),
            'enabled':
                server.enabled &&
                provider.isConnected(server.id) &&
                tool.enabled,
            'configured_enabled': tool.enabled,
            'needs_approval': tool.needsApproval,
          },
      ],
    };
  }

  Future<String> execute(
    Map<String, dynamic> args, {
    required String toolCallId,
    String? conversationId,
  }) async {
    try {
      checkAllowed?.call();
      await provider.loaded;
      final action = actionOf(args);
      if (!actions.contains(action) ||
          jsonEncode(args).length > (action == 'import' ? 65536 : 16384) ||
          args.keys.any(
            (k) => !const {
              'action',
              'server_id',
              'name',
              'config',
              'assistant_id',
              'tool_name',
              'enabled',
              'needs_approval',
              'json',
              'timeout_seconds',
            }.contains(k),
          )) {
        throw const FormatException(
          'Use a supported action and at most 16 KiB of arguments.',
        );
      }
      if (action == 'list') {
        return jsonEncode({
          'ok': true,
          'request_timeout_seconds': provider.requestTimeoutSeconds,
          'servers': provider.configuredServers.map(_summary).toList(),
        });
      }
      if (action == 'import') {
        return await _import(args, toolCallId, conversationId);
      }
      if (action == 'set_timeout') {
        final seconds = args['timeout_seconds'];
        if (seconds is! int || seconds < 1 || seconds > 86400) {
          throw const FormatException('Expected a positive timeout in seconds');
        }
        await _approve(
          {'action': action, 'timeout_seconds': seconds},
          toolCallId: toolCallId,
          conversationId: conversationId,
        );
        checkAllowed?.call();
        await provider.updateRequestTimeout(Duration(seconds: seconds));
        return jsonEncode({
          'ok': true,
          'request_timeout_seconds': provider.requestTimeoutSeconds,
        });
      }
      final existing = action == 'add' ? null : _target(args['server_id']);
      if (action == 'get') {
        return jsonEncode({'ok': true, 'server': _summary(existing!)});
      }
      if (action == 'test') return await _test(existing!);
      if (const {
        'select',
        'unselect',
        'set_tool',
        'refresh',
        'reconnect',
      }.contains(action)) {
        return await _manageExisting(
          args,
          existing!,
          toolCallId,
          conversationId,
        );
      }
      final autoSelectedAssistant = action == 'add' || action == 'enable'
          ? _assistant(optional: true)
          : null;

      var next =
          existing ??
          McpServerConfig(
            id: '',
            enabled: false,
            name: '',
            transport: McpTransportType.http,
          );
      final input = args['config'];
      final secretFields = <String>{};
      if (action == 'add' || action == 'update') {
        final name = args['name'] ?? existing?.name;
        if (name is! String ||
            name.trim().isEmpty ||
            name.length > 128 ||
            name.contains(RegExp(r'[\x00-\x1f]'))) {
          throw const FormatException(
            'A server name of 1–128 characters is required.',
          );
        }
        if (input != null && input is! Map<String, dynamic>) {
          throw const FormatException('config must be an object.');
        }
        final patch = Map<String, dynamic>.of(
          input as Map<String, dynamic>? ?? const {},
        );
        _validateConfig(patch);
        final config = <String, dynamic>{
          if (existing != null) ..._importConfig(existing),
          ...patch,
        };
        for (final field in ['env', 'headers']) {
          if (!patch.containsKey(field)) continue;
          final previous = field == 'env' ? existing?.env : existing?.headers;
          config[field] = {
            for (final entry in (patch[field] as Map).entries)
              entry.key:
                  entry.value == '' &&
                      McpSecrets.isSecret(
                        entry.key as String,
                        (previous?[entry.key] ?? ''),
                      )
                  ? (previous?[entry.key] ?? '')
                  : entry.value,
          };
        }
        if (patch.containsKey('baseUrl')) config['url'] = patch['baseUrl'];
        if (patch.containsKey('cwd')) config['workingDirectory'] = patch['cwd'];
        var parsed = parseMcpConfigImport(
          jsonEncode({name.trim(): config}),
        ).single;
        if (action == 'add' &&
            parsed.transport == McpTransportType.stdio &&
            !patch.containsKey('workspaceId')) {
          parsed = parsed.copyWith(workspaceId: defaultWorkspaceId);
        }
        if (parsed.workspaceId != null &&
            provider.workspaces?.byId(parsed.workspaceId!) == null) {
          throw const FormatException(
            'Unknown workspace id. Use live workspace ids from manage_assistants options.',
          );
        }
        next = parsed.copyWith(
          id: existing?.id,
          tools: existing?.tools,
          managedSecrets: existing == null
              ? null
              : McpSecrets.privateFields(existing),
          oauth: existing?.oauth,
          oauthClient: existing?.oauthClient,
        );
      } else if (action == 'enable' || action == 'disable') {
        next = next.copyWith(enabled: action == 'enable');
      }
      if (action == 'add' || action == 'update' || action == 'enable') {
        secretFields.addAll(_missingSecrets(next));
      }
      final privateValues = await _approve(
        {
          'action': action,
          if (existing != null && action == 'update')
            'previous_server': _summary(existing),
          'server': _summary(next),
          if (autoSelectedAssistant != null) ...{
            'assistant_id': autoSelectedAssistant.id,
            'assistant_name': autoSelectedAssistant.name,
          },
        },
        secretFields: secretFields,
        toolCallId: toolCallId,
        conversationId: conversationId,
      );
      checkAllowed?.call();
      if (existing != null) {
        final live = _target(existing.id);
        if (!existing.hasSameConfigurationAs(live)) {
          return _error(
            'server_changed',
            'The MCP configuration changed while awaiting confirmation. Read it again and retry.',
          );
        }
      }
      if (secretFields.any((name) => privateValues[name]?.isNotEmpty != true)) {
        return _secretRequired(secretFields);
      }
      if (action == 'remove') {
        await provider.removeServer(
          existing!.id,
          expected: existing,
          beforeCommit: checkAllowed,
        );
        if (provider.onServerRemoved == null) {
          await assistants?.removeMcpServerId(existing.id);
          await chat?.removeMcpServerId(existing.id);
        }
        return jsonEncode({'ok': true, 'removed_id': existing.id});
      }
      if (action == 'add' || action == 'update' || action == 'enable') {
        next = _fillSecrets(next, privateValues);
      }
      privateValues.clear();
      if (action == 'add') {
        await provider.importServers([next], beforeCommit: checkAllowed);
      } else {
        await provider.updateServerMetadata(
          next,
          expected: existing,
          beforeCommit: checkAllowed,
        );
      }
      if (autoSelectedAssistant != null) {
        await _setSelection(autoSelectedAssistant.id, next.id, true);
      }
      return jsonEncode({
        'ok': true,
        'server': _summary(provider.getById(next.id) ?? next),
        if (action == 'add' || action == 'update' || action == 'enable')
          'availability_notice': _availabilityNotice,
      });
    } on _McpManagerError catch (error) {
      if (error.secretFields != null) {
        return _secretRequired(error.secretFields!);
      }
      return _error(error.code, error.message);
    } on FormatException {
      // Import-parser errors can quote arbitrary input; do not return them.
      return _error(
        'invalid_arguments',
        'Invalid MCP configuration. Check name, transport, command/URL, workspace and field limits.',
      );
    } on StateError catch (error) {
      return switch (error.message) {
        'mcp_server_missing' => _error(
          'unknown_server',
          'Unknown MCP server id. Use action list to read the live server ids.',
        ),
        'mcp_server_changed' => _error(
          'server_changed',
          'The MCP configuration changed. Read it again and retry.',
        ),
        'mcp_tool_missing' => _error(
          'unknown_tool',
          'The tool was removed. Refresh this server\'s live tool list.',
        ),
        'permission_denied' => _error(
          'permission_denied',
          'MCP management is disabled for this assistant.',
        ),
        _ => _error(
          'mcp_management_failed',
          'The MCP operation failed or was cancelled.',
        ),
      };
    } catch (_) {
      return _error(
        'mcp_management_failed',
        'The MCP operation failed or was cancelled.',
      );
    }
  }

  Map<String, dynamic> _summary(McpServerConfig server) => {
    ...serverSummary(server, provider),
    if (assistants != null)
      'selected_assistant_ids': [
        for (final assistant in assistants!.assistants)
          if (assistant.mcpServerIds.contains(server.id)) assistant.id,
      ],
  };

  Assistant? _assistant({Object? id, bool optional = false}) {
    final targetId = id ?? currentAssistantId ?? assistants?.currentAssistantId;
    final assistant = targetId is String ? assistants?.getById(targetId) : null;
    if (assistant == null && !(optional && assistants == null && id == null)) {
      throw const _McpManagerError(
        'unknown_assistant',
        'Unknown assistant id. Use live ids from manage_assistants list.',
      );
    }
    return assistant;
  }

  Future<void> _setSelection(
    String assistantId,
    String serverId,
    bool selected,
  ) async {
    checkAllowed?.call();
    _target(serverId);
    final assistant = _assistant(id: assistantId)!;
    final ids = assistant.mcpServerIds
        .where((id) => provider.getById(id) != null)
        .toSet();
    if (selected) {
      ids.add(serverId);
    } else {
      ids.remove(serverId);
    }
    await assistants!.updateAssistant(
      assistant.copyWith(mcpServerIds: ids.toList()),
    );
  }

  Future<Map<String, String>> _approve(
    Map<String, dynamic> arguments, {
    required String toolCallId,
    String? conversationId,
    Set<String> secretFields = const {},
  }) async {
    if (secretFields.length > 32) {
      throw const FormatException('At most 32 private fields may be requested');
    }
    final trusted = autoApproveAll || approvals?.autoApproveAll == true;
    if (trusted && secretFields.isEmpty) return {};
    if (approvals == null) {
      if (secretFields.isNotEmpty) {
        throw _McpManagerError(
          'secret_required',
          'Private input is unavailable.',
          secretFields.toList(),
        );
      }
      throw const _McpManagerError(
        'approval_unavailable',
        'Changing MCP servers requires the user\'s confirmation.',
      );
    }
    final approval = await approvals!.requestApproval(
      toolCallId: toolCallId,
      toolName: toolName,
      arguments: arguments,
      conversationId: conversationId,
      secretFields: secretFields.toList(),
      secretInputOnly: trusted && secretFields.isNotEmpty,
    );
    checkAllowed?.call();
    if (!approval.approved) {
      throw const _McpManagerError(
        'approval_denied',
        'User cancelled the MCP change.',
      );
    }
    final values = approval.takeSecretValues();
    if (secretFields.any(
      (field) =>
          values[field]?.isNotEmpty != true ||
          values[field]!.length > 8192 ||
          values[field]!.contains('\x00'),
    )) {
      values.clear();
      throw _McpManagerError(
        'secret_required',
        'Private values are missing.',
        secretFields.toList(),
      );
    }
    final inputs = {for (final field in secretFields) field: values[field]!};
    values.clear();
    return inputs;
  }

  Future<String> _manageExisting(
    Map<String, dynamic> args,
    McpServerConfig server,
    String toolCallId,
    String? conversationId,
  ) async {
    final action = actionOf(args);
    final assistant = action == 'select' || action == 'unselect'
        ? _assistant(id: args['assistant_id'])
        : null;
    final requestedToolName = args['tool_name'];
    String? toolName;
    if (action == 'set_tool') {
      final privacy = McpToolPrivacy(provider);
      for (final tool in server.tools) {
        if (privacy.toolNameForModel(server, tool.name) == requestedToolName) {
          toolName = tool.name;
          break;
        }
      }
      if (toolName == null) {
        throw const _McpManagerError(
          'unknown_tool',
          'Unknown tool name. Read this server\'s live tool list first.',
        );
      }
      if ((!args.containsKey('enabled') &&
              !args.containsKey('needs_approval')) ||
          (args.containsKey('enabled') && args['enabled'] is! bool) ||
          (args.containsKey('needs_approval') &&
              args['needs_approval'] is! bool)) {
        throw const FormatException('Expected tool settings');
      }
    }
    await _approve(
      {
        'action': action,
        'server': _summary(server),
        if (assistant != null) ...{
          'assistant_id': assistant.id,
          'assistant_name': assistant.name,
        },
        if (action == 'set_tool')
          'tool_settings': {
            'name': requestedToolName,
            if (args.containsKey('enabled')) 'enabled': args['enabled'],
            if (args.containsKey('needs_approval'))
              'needs_approval': args['needs_approval'],
          },
      },
      toolCallId: toolCallId,
      conversationId: conversationId,
    );
    final live = _target(server.id);
    if (!server.hasSameConfigurationAs(live)) {
      throw const _McpManagerError(
        'server_changed',
        'The MCP configuration changed. Read it again and retry.',
      );
    }
    if (assistant != null) {
      await _setSelection(assistant.id, server.id, action == 'select');
    } else if (action == 'set_tool') {
      if (!live.tools.any((tool) => tool.name == toolName)) {
        throw const _McpManagerError(
          'unknown_tool',
          'The tool was removed while awaiting confirmation. Refresh the list.',
        );
      }
      await provider.setToolSettings(
        server.id,
        toolName!,
        enabled: args['enabled'] as bool?,
        needsApproval: args['needs_approval'] as bool?,
        expected: server,
        beforeCommit: checkAllowed,
      );
    } else {
      if (action == 'reconnect') {
        await provider.reconnect(server.id);
      } else {
        await provider.ensureConnected(server.id);
      }
      if (provider.isConnected(server.id)) {
        await provider.refreshTools(server.id);
      }
    }
    checkAllowed?.call();
    return jsonEncode({
      'ok': true,
      'server': _summary(_target(server.id)),
      if (assistant != null) 'assistant_id': assistant.id,
      'availability_notice': _availabilityNotice,
    });
  }

  static Map<String, String> _savedSecrets(McpServerConfig server) => {
    for (final entry in server.env.entries)
      if (McpSecrets.isSecret(entry.key, entry.value)) entry.key: entry.value,
    for (final entry in server.headers.entries)
      if (McpSecrets.isSecret(entry.key, entry.value)) entry.key: entry.value,
    for (final entry in server.managedSecrets.entries)
      if (entry.key.startsWith('env:') || entry.key.startsWith('header:'))
        entry.key.substring(entry.key.indexOf(':') + 1): entry.value,
    ...server.managedSecrets,
  };

  static Set<String> _missingSecrets(McpServerConfig server) {
    final saved = _savedSecrets(server);
    return {
      for (final entry in server.env.entries)
        if (entry.value.isEmpty &&
            McpSecrets.isSecret(entry.key, entry.value) &&
            saved['env:${entry.key}']?.isNotEmpty != true &&
            saved[entry.key]?.isNotEmpty != true)
          'env:${entry.key}',
      for (final entry in server.headers.entries)
        if (entry.value.isEmpty &&
            McpSecrets.isSecret(entry.key, entry.value) &&
            saved['header:${entry.key}']?.isNotEmpty != true &&
            saved[entry.key]?.isNotEmpty != true)
          'header:${entry.key}',
      for (final value in [server.url, ...server.args])
        for (final match in McpSecrets.placeholder.allMatches(value))
          if (saved[match[1]]?.isNotEmpty != true) match[1]!,
    };
  }

  Future<String> _import(
    Map<String, dynamic> args,
    String toolCallId,
    String? conversationId,
  ) async {
    final text = args['json'];
    if (text is! String) throw const FormatException('Expected JSON text');
    final decoded = jsonDecode(text);
    final configs = decoded is Map ? decoded['mcpServers'] ?? decoded : null;
    if (configs is! Map || configs.isEmpty || configs.length > 32) {
      throw const FormatException('Expected 1–32 server entries');
    }
    for (final entry in configs.entries) {
      if (entry.key is! String ||
          (entry.key as String).trim().isEmpty ||
          (entry.key as String).length > 128 ||
          (entry.key as String).contains(RegExp(r'[\x00-\x1f]')) ||
          entry.value is! Map<String, dynamic>) {
        throw const FormatException('Invalid server entry');
      }
      _validateConfig(entry.value as Map<String, dynamic>);
    }
    final imported = parseMcpConfigImport(text).map((server) {
      final config = configs[server.name] as Map;
      final next =
          server.transport == McpTransportType.stdio &&
              !config.containsKey('workspaceId')
          ? server.copyWith(workspaceId: defaultWorkspaceId)
          : server;
      if (next.workspaceId != null &&
          provider.workspaces?.byId(next.workspaceId!) == null) {
        throw const FormatException('Unknown workspace id');
      }
      return next;
    }).toList();
    final assistant = _assistant(optional: true);
    final fields = {
      for (final server in imported) server.id: _missingSecrets(server),
    };
    final inputs = await _approve(
      {
        'action': 'import',
        'servers': imported.map(_summary).toList(),
        if (assistant != null) ...{
          'assistant_id': assistant.id,
          'assistant_name': assistant.name,
        },
      },
      toolCallId: toolCallId,
      conversationId: conversationId,
      secretFields: {
        for (final server in imported)
          for (final field in fields[server.id]!) '${server.name} / $field',
      },
    );
    final prepared = [
      for (final server in imported)
        _fillSecrets(server, {
          for (final field in fields[server.id]!)
            field: inputs['${server.name} / $field']!,
        }),
    ];
    inputs.clear();
    await provider.importServers(prepared, beforeCommit: checkAllowed);
    if (assistant != null) {
      for (final server in prepared) {
        await _setSelection(assistant.id, server.id, true);
      }
    }
    return jsonEncode({
      'ok': true,
      'servers': prepared.map(_summary).toList(),
      'availability_notice': _availabilityNotice,
    });
  }

  McpServerConfig _target(Object? id) {
    for (final server in provider.configuredServers) {
      if (server.id == id) return server;
    }
    throw const _McpManagerError(
      'unknown_server',
      'Unknown MCP server id. Use action list to read the live server ids.',
    );
  }

  void _validateConfig(Map<String, dynamic> config) {
    if (config.keys.any(
      (k) => !const {
        'type',
        'command',
        'args',
        'url',
        'baseUrl',
        'env',
        'headers',
        'cwd',
        'workingDirectory',
        'workspaceId',
        'disabled',
        'isActive',
      }.contains(k),
    )) {
      throw const FormatException('Unknown config field');
    }
    if (McpSecrets.containsLiteralSecret(config) ||
        McpToolPrivacy(provider).containsKnownCredential(config)) {
      throw const _McpManagerError(
        'secret_required',
        'Never supply secret values. Use empty secret env/header values or {{NAME}} in arguments/URLs for the user\'s private input card.',
      );
    }
    for (final entry in config.entries) {
      final value = entry.value;
      if (value is String && (value.length > 2048 || value.contains('\x00'))) {
        throw const FormatException('Field too long');
      }
      if (entry.key == 'disabled' || entry.key == 'isActive') {
        if (value is! bool) throw const FormatException('Expected boolean');
      }
      if (entry.key == 'command' &&
          (value is! String || value.contains(RegExp(r'[\s\x00]')))) {
        throw const FormatException('Expected executable');
      }
    }
    final args = config['args'];
    if (args != null &&
        (args is! List ||
            args.length > 64 ||
            args.any(
              (v) => v is! String || v.length > 2048 || v.contains('\x00'),
            ))) {
      throw const FormatException('Invalid arguments');
    }
    for (final field in ['env', 'headers']) {
      if (!config.containsKey(field)) continue;
      final values = config[field];
      final pattern = field == 'env'
          ? RegExp(r'^[A-Za-z_][A-Za-z0-9_]{0,127}$')
          : RegExp(r'^[A-Za-z0-9_-]{1,128}$');
      if (values is! Map ||
          values.length > 32 ||
          values.keys.any((k) => k is! String || !pattern.hasMatch(k)) ||
          values.values.any(
            (v) => v is! String || v.length > 2048 || v.contains('\x00'),
          )) {
        throw const FormatException(
          'Invalid environment/header names or values',
        );
      }
    }
  }

  static Map<String, dynamic> _importConfig(McpServerConfig s) => {
    'type': s.transport.name,
    'disabled': !s.enabled,
    if (s.transport == McpTransportType.stdio) ...{
      'command': s.command,
      'args': s.args,
      'env': s.env,
      'workingDirectory': s.workingDirectory,
      'workspaceId': s.workspaceId,
    } else ...{
      'url': s.url,
      'headers': s.headers,
    },
  };

  static McpServerConfig _fillSecrets(
    McpServerConfig s,
    Map<String, String> inputs,
  ) {
    final secrets = {..._savedSecrets(s), ...inputs};
    String fill(String value, {bool url = false}) =>
        value.replaceAllMapped(McpSecrets.placeholder, (match) {
          final input = secrets[match[1]]!;
          return url ? Uri.encodeComponent(input) : input;
        });
    return s.copyWith(
      url: fill(s.url, url: true),
      args: s.args.map((v) => fill(v)).toList(),
      env: {
        for (final entry in s.env.entries)
          entry.key:
              inputs['env:${entry.key}'] ??
              (entry.value.isEmpty &&
                      McpSecrets.isSecret(entry.key, entry.value)
                  ? secrets['env:${entry.key}'] ??
                        secrets[entry.key] ??
                        entry.value
                  : entry.value),
      },
      headers: {
        for (final entry in s.headers.entries)
          entry.key:
              inputs['header:${entry.key}'] ??
              (entry.value.isEmpty &&
                      McpSecrets.isSecret(entry.key, entry.value)
                  ? secrets['header:${entry.key}'] ??
                        secrets[entry.key] ??
                        entry.value
                  : entry.value),
      },
      managedSecrets: {...s.managedSecrets, ...inputs},
    );
  }

  Future<String> _test(McpServerConfig server) async {
    if (!server.enabled) {
      return jsonEncode({
        'ok': true,
        'connected': false,
        'tool_count': 0,
        'tools': [],
        'error': 'Server is disabled. Enable it before testing.',
      });
    }
    await provider.connect(server.id);
    if (provider.isConnected(server.id)) await provider.refreshTools(server.id);
    checkAllowed?.call();
    final live = _target(server.id);
    final summary = _summary(live);
    return jsonEncode({
      'ok': true,
      'connected': provider.isConnected(server.id),
      if (provider.isConnected(server.id))
        'availability_notice': _availabilityNotice,
      'tool_count': live.tools.length,
      'tools': summary['tools'],
      'error':
          provider.errorFor(server.id) ??
          (live.transport == McpTransportType.stdio && !provider.supportsStdio
              ? 'Workspace environment is not ready.'
              : null),
    });
  }

  static String _secretRequired(Iterable<String> names) => jsonEncode({
    'ok': false,
    'error': 'secret_required',
    'secret_fields': names.toList(),
    'message':
        'Secret values must be entered by the user through the private input card or MCP settings. Never ask in chat or invent them. No change was applied.',
  });
  static String _error(String code, String message) =>
      jsonEncode({'ok': false, 'error': code, 'message': message});
}

class _McpManagerError implements Exception {
  const _McpManagerError(this.code, this.message, [this.secretFields]);
  final String code;
  final String message;
  final List<String>? secretFields;
}
