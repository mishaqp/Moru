import 'dart:convert';

import '../../../core/providers/mcp_provider.dart';
import '../../../core/services/mcp/mcp_config_import.dart';
import '../../../core/services/mcp/mcp_secrets.dart';
import 'tool_approval_service.dart';

/// Opt-in MCP configuration through the normal approval service. Only the
/// provider starts servers; installing packages is a separate workspace shell.
class McpManagerTool {
  McpManagerTool({
    required this.provider,
    this.approvals,
    this.autoApproveAll = false,
    this.checkAllowed,
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
  ];
  final McpProvider provider;
  final ToolApprovalService? approvals;
  final bool autoApproveAll;
  final void Function()? checkAllowed;

  static String actionOf(Map<String, dynamic> args) =>
      (args['action'] ?? '').toString().trim().toLowerCase();
  static bool requiresApproval(Map<String, dynamic> args) => const {
    'add',
    'update',
    'enable',
    'disable',
    'remove',
  }.contains(actionOf(args));

  static Map<String, dynamic> get definition => {
    'type': 'function',
    'function': {
      'name': toolName,
      'description':
          'Manage the user\'s MCP servers in Moru. list/get show saved configuration, status and tools without credentials. Use live server_id from list. add/update/enable/disable/remove need confirmation; test connects and lists tools using the existing MCP runtime. config uses the MCP JSON import format for one server. update only changes supplied fields. env and headers values MUST be empty strings: the user enters them privately on the approval card; existing values with the same name are preserved. For secret arguments or URL parts use {{NAME}}, never literal keys, tokens or passwords. Secrets are entered by the user, never requested in chat. Full-trust mode cannot supply missing secrets: direct the user to MCP settings. Install npm/pip packages separately with the workspace shell tool and its own approval; this tool has no installer or shell executor. New servers are available to assistants through their MCP selection (manage_assistants can change it).',
      'parameters': {
        'type': 'object',
        'additionalProperties': false,
        'properties': {
          'action': {'type': 'string', 'enum': actions},
          'server_id': {
            'type': 'string',
            'description':
                'Existing id from list, required except for list/add.',
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
                'additionalProperties': {
                  'type': 'string',
                  'enum': [''],
                },
                'description':
                    'Environment names mapped to empty strings; user supplies values.',
              },
              'headers': {
                'type': 'object',
                'additionalProperties': {
                  'type': 'string',
                  'enum': [''],
                },
                'description':
                    'Header names mapped to empty strings; user supplies values, including the Bearer/Basic prefix.',
              },
              'cwd': {'type': 'string'},
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
    Map<String, Object?> names(Map<String, String> values) => {
      for (final entry in values.entries)
        secrets.text(entry.key): {'value_set': entry.value.isNotEmpty},
    };
    return {
      'id': server.id,
      'name': secrets.text(server.name),
      'type': server.transport.name,
      'enabled': server.enabled,
      'status': provider.statusFor(server.id).name,
      'error': provider.errorFor(server.id),
      if (server.transport == McpTransportType.stdio) ...{
        'command': secrets.text(server.command ?? ''),
        'args': server.args.map(secrets.text).toList(),
        'env': names(server.env),
        'cwd': secrets.value(server.workingDirectory),
        'workspaceId': server.workspaceId,
        'environment_available': provider.supportsStdio,
      } else if (server.transport != McpTransportType.inmemory) ...{
        'url': secrets.text(server.url),
        'headers': names(server.headers),
        'authorization_set': server.oauth?.accessToken.isNotEmpty == true,
      },
      'secrets': names(server.managedSecrets),
      'tool_count': server.tools.length,
      'tools': [
        for (final tool in server.tools)
          {
            'name': secrets.text(tool.name),
            'description': secrets.value(tool.description),
            'enabled': tool.enabled,
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
          jsonEncode(args).length > 16384 ||
          args.keys.any(
            (k) => !const {'action', 'server_id', 'name', 'config'}.contains(k),
          )) {
        throw const FormatException(
          'Use a supported action and at most 16 KiB of arguments.',
        );
      }
      if (action == 'list') {
        return jsonEncode({
          'ok': true,
          'servers': provider.configuredServers
              .map((s) => serverSummary(s, provider))
              .toList(),
        });
      }
      final existing = action == 'add' ? null : _target(args['server_id']);
      if (action == 'get') {
        return jsonEncode({
          'ok': true,
          'server': serverSummary(existing!, provider),
        });
      }
      if (action == 'test') return await _test(existing!);

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
            for (final name in (patch[field] as Map).keys)
              name: previous?[name] ?? '',
          };
        }
        if (patch.containsKey('baseUrl')) config['url'] = patch['baseUrl'];
        if (patch.containsKey('cwd')) config['workingDirectory'] = patch['cwd'];
        final parsed = parseMcpConfigImport(
          jsonEncode({name.trim(): config}),
        ).single;
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
        for (final field in ['env', 'headers']) {
          final values = field == 'env' ? next.env : next.headers;
          for (final entry in values.entries) {
            if (entry.value.isEmpty) {
              secretFields.add(
                '${field == 'env' ? 'env' : 'header'}:${entry.key}',
              );
            }
          }
        }
        for (final value in [next.url, ...next.args]) {
          for (final match in McpSecrets.placeholder.allMatches(value)) {
            final name = match[1]!;
            if (next.managedSecrets[name]?.isNotEmpty != true) {
              secretFields.add(name);
            }
          }
        }
      }
      if (secretFields.length > 32) {
        throw const FormatException(
          'At most 32 private fields may be requested.',
        );
      }
      final trusted = autoApproveAll || approvals?.autoApproveAll == true;
      if (trusted && secretFields.isNotEmpty) {
        return _secretRequired(secretFields);
      }
      if (!trusted && approvals == null) {
        return _error(
          'approval_unavailable',
          'Changing MCP servers needs the user\'s confirmation, which is unavailable here.',
        );
      }
      Map<String, String> privateValues = {};
      if (approvals != null) {
        final approval = await approvals!.requestApproval(
          toolCallId: toolCallId,
          toolName: toolName,
          arguments: {
            'action': action,
            if (existing != null && action == 'update')
              'previous_server': serverSummary(existing, provider),
            'server': serverSummary(next, provider),
          },
          secretFields: secretFields.toList(),
          conversationId: conversationId,
        );
        if (!approval.approved) {
          return _error('approval_denied', 'User denied the MCP change.');
        }
        privateValues = approval.takeSecretValues();
      }
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
      return jsonEncode({
        'ok': true,
        'server': serverSummary(provider.getById(next.id) ?? next, provider),
      });
    } on _McpManagerError catch (error) {
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
    if (McpSecrets.containsLiteralSecret(config)) {
      throw const _McpManagerError(
        'secret_in_arguments',
        'Never supply secret values. Use empty env/header values or {{NAME}} in arguments/URLs for private user input.',
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
          values.keys.any((k) => k is! String || !pattern.hasMatch(k))) {
        throw const FormatException('Invalid private field names');
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
    final secrets = {...s.managedSecrets, ...inputs};
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
          entry.key: inputs['env:${entry.key}'] ?? entry.value,
      },
      headers: {
        for (final entry in s.headers.entries)
          entry.key: inputs['header:${entry.key}'] ?? entry.value,
      },
      managedSecrets: secrets,
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
    final summary = serverSummary(live, provider);
    return jsonEncode({
      'ok': true,
      'connected': provider.isConnected(server.id),
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
        'Secret values must be entered by the user in MCP settings. Never ask for them in chat or invent them. No change was applied.',
  });
  static String _error(String code, String message) =>
      jsonEncode({'ok': false, 'error': code, 'message': message});
}

class _McpManagerError implements Exception {
  const _McpManagerError(this.code, this.message);
  final String code;
  final String message;
}
