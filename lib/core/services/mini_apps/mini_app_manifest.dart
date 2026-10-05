import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'mini_app_device.dart';
import 'mini_app_expressions.dart';
import 'mini_app_store.dart' show MiniAppException;

enum MiniAppUiEngine { web, native }

enum MiniAppDanger { read, write, root }

/// A source contract. Schemas are kept verbatim; provider normalization belongs
/// at the existing model-request boundary, never in the installed manifest.
@immutable
class MiniAppAction {
  MiniAppAction({
    required this.name,
    required this.description,
    required Map<String, dynamic> inputSchema,
    required Set<String> permissions,
    required this.danger,
    required Map<String, dynamic> executor,
  }) : inputSchema = _freeze(inputSchema) as Map<String, dynamic>,
       permissions = Set.unmodifiable(permissions),
       executor = _freeze(executor) as Map<String, dynamic>;

  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;
  final Set<String> permissions;
  final MiniAppDanger danger;
  final Map<String, dynamic> executor;

  bool get isMutation => danger != MiniAppDanger.read;
  bool get requiresConfirmation => danger == MiniAppDanger.root;

  factory MiniAppAction.fromJson(
    Map<String, dynamic> json, {
    String path = 'manifest.action',
  }) {
    final name = json['name'];
    final description = json['description'];
    if (name is! String ||
        !RegExp(r'^[a-zA-Z][a-zA-Z0-9_]{0,63}$').hasMatch(name) ||
        description is! String ||
        description.trim().isEmpty ||
        description.length > 2000) {
      _badAt(
        'invalid_action',
        '$path.name',
        'An action needs a unique name and a description.',
        '{"name":"start","description":"Start a Focus session"}',
      );
    }
    final schema = json['inputSchema'];
    if (schema is! Map<String, dynamic>) {
      _badAt(
        'invalid_schema',
        '$path.inputSchema',
        'inputSchema must be an object schema.',
        '{"type":"object","properties":{},"additionalProperties":false}',
      );
    }
    _located(
      '$path.inputSchema',
      () => MiniAppJsonSchema.check(schema),
      '{"type":"object"}',
    );
    final permissions = _located(
      '$path.permissions',
      () => MiniAppManifest.capabilities(json['permissions']),
      '["device.screen.write"]',
    );
    final danger = MiniAppDanger.values
        .where((v) => v.name == json['danger'])
        .firstOrNull;
    if (danger == null) {
      _badAt(
        'invalid_action',
        '$path.danger',
        'danger must be read, write or root.',
        '"write"',
      );
    }
    final executor = json['executor'];
    if (executor is! Map<String, dynamic>) {
      _badAt(
        'invalid_executor',
        '$path.executor',
        'An executor must be an object.',
        '{"kind":"state","patch":{"running":true}}',
      );
    }
    final policy = _policy(executor, path: '$path.executor');
    if (danger.index < policy.danger.index ||
        !permissions.containsAll(policy.permissions)) {
      _badAt(
        'invalid_policy',
        '$path.executor',
        'An action cannot weaken its host permissions or confirmation policy.',
        '{"permissions":${jsonEncode(policy.permissions.toList())},"danger":"${policy.danger.name}"}',
      );
    }
    if ((json['requiresRoot'] == false &&
            policy.danger == MiniAppDanger.root) ||
        (json['confirmation'] == 'none' &&
            policy.danger != MiniAppDanger.read)) {
      _badAt(
        'invalid_policy',
        '$path.executor',
        'An action cannot disable host confirmation or root checks.',
        '{"danger":"${policy.danger.name}","confirmation":"required"}',
      );
    }
    return MiniAppAction(
      name: name,
      description: description,
      inputSchema: schema,
      permissions: permissions,
      danger: danger,
      executor: executor,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'inputSchema': inputSchema,
    'permissions': permissions.toList(),
    'danger': danger.name,
    'executor': executor,
  };

  static ({MiniAppDanger danger, Set<String> permissions}) _policy(
    Map<String, dynamic> executor, {
    required String path,
  }) {
    Never bad(
      String code,
      String message, {
      String? field,
      String example = '{"kind":"state","patch":{"running":true}}',
    }) => _badAt(code, field == null ? path : '$path.$field', message, example);
    final kind = executor['kind'];
    switch (kind) {
      case 'native':
        if (executor.keys.any((k) => !const {'kind', 'handler'}.contains(k))) {
          bad('invalid_executor', 'Unknown native executor field.');
        }
        final handler = executor['handler'];
        if (handler is! String ||
            !MiniAppDeviceService.handlers.contains(handler)) {
          bad(
            'invalid_executor',
            'Unknown native handler.',
            field: 'handler',
            example: '"device.screen.brightness.set"',
          );
        }
        return (
          danger: MiniAppDeviceService.requiresConfirmation(handler)
              ? MiniAppDanger.root
              : MiniAppDeviceService.isMutation(handler)
              ? MiniAppDanger.write
              : MiniAppDanger.read,
          permissions: MiniAppDeviceService.permissionsFor(handler),
        );
      case 'state':
        if (executor.keys.any(
              (k) => !const {'kind', 'patch', 'expressions'}.contains(k),
            ) ||
            executor['patch'] is! Map<String, dynamic>) {
          bad(
            'invalid_executor',
            'A state executor needs a JSON object patch.',
            field: 'patch',
          );
        }
        if (executor.containsKey('expressions') &&
            executor['expressions'] is! bool) {
          bad(
            'invalid_executor',
            'Expression opt in must be a boolean.',
            field: 'expressions',
            example: 'true',
          );
        }
        if (executor['expressions'] == true) {
          MiniAppExpressions.validate(executor['patch'], path: '$path.patch');
        } else {
          _located(
            '$path.patch',
            () => _checkTemplate(executor['patch']),
            '{"running":true}',
          );
        }
        return (danger: MiniAppDanger.write, permissions: <String>{});
      case 'preset':
        if (executor.keys.any((k) => !const {'kind', 'steps'}.contains(k))) {
          bad('invalid_executor', 'Unknown preset field.');
        }
        final steps = executor['steps'];
        if (steps is! List || steps.isEmpty || steps.length > 8) {
          bad(
            'invalid_executor',
            'A preset needs 1–8 reversible steps.',
            field: 'steps',
            example:
                '[{"handler":"device.screen.brightness.set","args":{"value":77}}]',
          );
        }
        var danger = MiniAppDanger.write;
        final permissions = <String>{};
        for (var i = 0; i < steps.length; i++) {
          final step = steps[i];
          if (step is! Map ||
              step.keys.any((k) => !const {'handler', 'args'}.contains(k)) ||
              !reversibleHandlers.contains(step['handler']) ||
              step['args'] is! Map) {
            bad(
              'invalid_executor',
              'Presets accept only fixed reversible device setters.',
              field: 'steps[$i]',
              example:
                  '{"handler":"device.screen.brightness.set","args":{"value":77}}',
            );
          }
          final handler = step['handler'] as String;
          _located(
            '$path.steps[$i].args',
            () => _checkTemplate(step['args']),
            '{"value":77}',
          );
          if (MiniAppDeviceService.requiresConfirmation(handler)) {
            danger = MiniAppDanger.root;
          }
          permissions.addAll(MiniAppDeviceService.permissionsFor(handler));
        }
        return (danger: danger, permissions: permissions);
      case 'restore':
        if (executor.length != 1) {
          bad(
            'invalid_executor',
            'Restore uses the host-owned undo record only.',
          );
        }
        // The record adds its actual capabilities and danger at execution time.
        return (danger: MiniAppDanger.write, permissions: <String>{});
      case 'sequence':
        if (executor.keys.any(
          (key) => !const {'kind', 'steps'}.contains(key),
        )) {
          bad('invalid_executor', 'Unknown sequence field.');
        }
        final steps = executor['steps'];
        if (steps is! List || steps.isEmpty || steps.length > 32) {
          bad(
            'invalid_executor',
            'A sequence needs 1–32 action steps.',
            field: 'steps',
            example: '[{"action":"record","arguments":{}}]',
          );
        }
        for (var i = 0; i < steps.length; i++) {
          final step = steps[i];
          if (step is! Map ||
              step.keys.any(
                (key) =>
                    !const {'action', 'arguments', 'onFailure'}.contains(key),
              )) {
            bad(
              'invalid_executor',
              'A sequence step references a declared action.',
              field: 'steps[$i]',
              example: '{"action":"record","arguments":{}}',
            );
          }
          if (step['action'] is! String ||
              !RegExp(
                r'^[a-zA-Z][a-zA-Z0-9_]{0,63}$',
              ).hasMatch(step['action'] as String)) {
            bad(
              'invalid_executor',
              'Action reference must be a declared action name.',
              field: 'steps[$i].action',
              example: '"record"',
            );
          }
          final arguments = step['arguments'] ?? const <String, dynamic>{};
          if (arguments is! Map) {
            bad(
              'invalid_executor',
              'Step arguments must be an object.',
              field: 'steps[$i].arguments',
              example: '{"durationMs":1500000}',
            );
          }
          if (step['onFailure'] != null &&
              !const {'stop', 'continue'}.contains(step['onFailure'])) {
            bad(
              'invalid_executor',
              'onFailure must be stop or continue.',
              field: 'steps[$i].onFailure',
              example: '"continue"',
            );
          }
          _located(
            '$path.steps[$i].arguments',
            () => _checkTemplate(arguments),
            '{"durationMs":1500000}',
          );
        }
        // Transitive policy is resolved after all same-app actions are known.
        return (danger: MiniAppDanger.read, permissions: <String>{});
      default:
        bad(
          'invalid_executor',
          'Unknown executor kind.',
          field: 'kind',
          example: '"sequence"',
        );
    }
  }
}

class MiniAppManifest {
  const MiniAppManifest({
    required this.formatVersion,
    required this.uiEngine,
    required this.entry,
    required this.actions,
  });
  final int formatVersion;
  final MiniAppUiEngine uiEngine;
  final String? entry;
  final List<MiniAppAction> actions;

  static MiniAppManifest parse(Map<String, dynamic> json) {
    final version = json['formatVersion'] ?? 1;
    if (version != 1 && version != 2 || version is! int) {
      _badAt(
        'invalid_manifest',
        'manifest.formatVersion',
        'formatVersion must be 1 or 2.',
        '2',
      );
    }
    final ui = json['ui'];
    if (ui != null && ui is! Map) {
      _badAt(
        'invalid_manifest',
        'manifest.ui',
        'ui must be an object.',
        '{"engine":"native","entry":"screen.json"}',
      );
    }
    final engineName = ui is Map ? ui['engine'] ?? 'web' : 'web';
    final engine = MiniAppUiEngine.values
        .where((v) => v.name == engineName)
        .firstOrNull;
    if (engine == null) {
      _badAt(
        'invalid_manifest',
        'manifest.ui.engine',
        'ui.engine must be native or web.',
        '"native"',
      );
    }
    final rawActions = json['actions'] ?? const [];
    if (rawActions is! List ||
        rawActions.length > 64 ||
        version == 1 &&
            (rawActions.isNotEmpty || engine != MiniAppUiEngine.web)) {
      _badAt(
        'invalid_manifest',
        'manifest.actions',
        'Version two actions must be a list of at most 64 actions.',
        '[]',
      );
    }
    final actions = <MiniAppAction>[];
    final names = <String>{};
    for (var i = 0; i < rawActions.length; i++) {
      final raw = rawActions[i];
      if (raw is! Map<String, dynamic>) {
        _badAt(
          'invalid_action',
          'manifest.actions[$i]',
          'Each action must be an object.',
          '{"name":"start","description":"Start Focus","inputSchema":{"type":"object"},"permissions":[],"danger":"write","executor":{"kind":"state","patch":{"running":true}}}',
        );
      }
      final action = MiniAppAction.fromJson(raw, path: 'manifest.actions[$i]');
      if (!names.add(action.name)) {
        _badAt(
          'invalid_action',
          'manifest.actions[$i].name',
          'Duplicate action name "${action.name}".',
          '"anotherAction"',
        );
      }
      actions.add(action);
    }
    _validateSequences(actions, rawActions);
    if (version == 2 && json['server'] != null) {
      _bad(
        'invalid_server',
        'Version two mini apps cannot run an unrestricted shell server.',
      );
    }
    final entry = ui is Map ? ui['entry'] ?? json['entry'] : json['entry'];
    if (entry != null && entry is! String) {
      _bad('invalid_path', 'The entry must be a relative file name.');
    }
    return MiniAppManifest(
      formatVersion: version,
      uiEngine: engine,
      entry: entry as String?,
      actions: List.unmodifiable(actions),
    );
  }

  static void _validateSequences(List<MiniAppAction> actions, List rawActions) {
    final indices = {
      for (var i = 0; i < actions.length; i++) actions[i].name: i,
    };
    for (var root = 0; root < actions.length; root++) {
      if (actions[root].executor['kind'] != 'sequence') {
        continue;
      }
      var expanded = 0;
      final rootPath = 'manifest.actions[$root].executor';
      ({MiniAppDanger danger, Set<String> permissions}) visit(
        int index,
        Set<String> stack,
        int depth,
      ) {
        final action = actions[index];
        final required = <String>{...action.permissions};
        var danger = action.danger;
        if (action.executor['kind'] != 'sequence') {
          return (danger: danger, permissions: required);
        }
        if (depth > 8 || !stack.add(action.name)) {
          _badAt(
            'invalid_executor',
            rootPath,
            depth > 8
                ? 'Sequence exceeds eight levels.'
                : 'Sequence has a cycle through "${action.name}".',
            '{"kind":"sequence","steps":[{"action":"record","arguments":{}}]}',
          );
        }
        final steps = action.executor['steps'] as List;
        for (var i = 0; i < steps.length; i++) {
          final step = steps[i] as Map;
          final path = 'manifest.actions[$index].executor.steps[$i].action';
          final target = indices[step['action']];
          if (target == null) {
            _badAt(
              'invalid_executor',
              path,
              'Unknown same-app action "${step['action']}".',
              jsonEncode(actions.first.name),
            );
          }
          if (++expanded > 32) {
            _badAt(
              'invalid_executor',
              rootPath,
              'Sequence expands to more than 32 action invocations; expansion reached $path.',
              '{"kind":"sequence","steps":[{"action":"record","arguments":{}}]}',
            );
          }
          final policy = visit(target, {
            ...stack,
          }, depth + (actions[target].executor['kind'] == 'sequence' ? 1 : 0));
          required.addAll(policy.permissions);
          if (policy.danger.index > danger.index) {
            danger = policy.danger;
          }
        }
        if (!action.permissions.containsAll(required) ||
            action.danger.index < danger.index ||
            rawActions[index]['requiresRoot'] == false &&
                danger == MiniAppDanger.root ||
            rawActions[index]['confirmation'] == 'none' &&
                danger != MiniAppDanger.read) {
          _badAt(
            'invalid_policy',
            'manifest.actions[$index].executor',
            'Sequence cannot weaken its referenced actions: requires ${required.toList()..sort()} and danger ${danger.name}.',
            '{"permissions":${jsonEncode(required.toList()..sort())},"danger":"${danger.name}"}',
          );
        }
        return (danger: danger, permissions: required);
      }

      visit(root, {}, 1);
    }
  }

  static Set<String> capabilities(Object? raw) {
    if (raw == null) {
      return {};
    }
    if (raw is! List ||
        raw.length > knownCapabilities.length ||
        raw.any((v) => v is! String || !knownCapabilities.contains(v))) {
      _bad('invalid_permissions', 'Unknown mini app capability.');
    }
    return Set<String>.from(raw);
  }

  static Set<String> get knownCapabilities => {
    'actions.ai',
    ...MiniAppDeviceService.knownCapabilities,
  };

  /// Bounded declarative UI validation; no embedded code or arbitrary widgets.
  static void validateScreen(Object? screen, List<MiniAppAction> actions) {
    if (screen is! Map ||
        screen['version'] != 1 ||
        screen['components'] is! List ||
        screen.keys.any(
          (k) => !const {'version', 'components', 'title'}.contains(k),
        )) {
      _badAt(
        'invalid_screen',
        'screen.components',
        'A native screen needs version 1 and components.',
        '{"version":1,"components":[{"type":"timer","bind":"data.endsAt"}]}',
      );
    }
    if (utf8.encode(jsonEncode(screen)).length > 256 * 1024) {
      _bad('invalid_screen', 'The native screen is too large.');
    }
    final names = actions.map((a) => a.name).toSet();
    var count = 0;
    void visit(Object? raw, int depth, String path) {
      Never bad(
        String message, {
        String? field,
        String example = '{"type":"timer","bind":"data.endsAt"}',
      }) => _badAt(
        'invalid_screen',
        field == null ? path : '$path.$field',
        message,
        example,
      );
      if (raw is! Map || depth > 12 || ++count > 256) {
        bad('Invalid or oversized native component tree.');
      }
      final type = raw['type'];
      if (!const {
        'card',
        'text',
        'value',
        'button',
        'switch',
        'slider',
        'list',
        'indicator',
        'timer',
        'progress',
      }.contains(type)) {
        bad(
          'Unknown native component type.',
          field: 'type',
          example: '"timer"',
        );
      }
      final unknown = raw.keys
          .where(
            (k) => !const {
              'type',
              'id',
              'title',
              'label',
              'text',
              'description',
              'bind',
              'action',
              'args',
              'children',
              'min',
              'max',
              'step',
              'unit',
              'format',
              'values',
              'maxBind',
              'minBind',
              'startBind',
              'mode',
              'valueKey',
              'labelKey',
              'itemLabel',
              'itemValue',
              'emptyText',
              'disabled',
              'enabled',
              'color',
              'icon',
              'options',
            }.contains(k),
          )
          .firstOrNull;
      if (unknown != null) {
        bad('Unknown native component field.', field: '$unknown');
      }
      for (final key in [
        'title',
        'label',
        'text',
        'description',
        'unit',
        'emptyText',
      ]) {
        final text = raw[key];
        if (text != null &&
            !(text is String && text.length <= 4000) &&
            !(text is Map &&
                text.length <= 20 &&
                text.keys.every((k) => k is String && k.length <= 32) &&
                text.values.every((v) => v is String && v.length <= 4000))) {
          bad(
            'Display text must be a string or locale map.',
            field: key,
            example: '{"en":"Focus","ru":"Фокус"}',
          );
        }
      }
      if (raw['bind'] != null &&
          (raw['bind'] is! String ||
              !RegExp(
                r'^(data|device|revision)(\.[a-zA-Z0-9_-]+)*$',
              ).hasMatch(raw['bind'] as String))) {
        bad('Invalid state binding.', field: 'bind', example: '"data.endsAt"');
      }
      for (final bound in ['minBind', 'maxBind', 'startBind']) {
        if (raw[bound] != null &&
            (raw[bound] is! String ||
                !RegExp(
                  r'^(data|device)(\.[a-zA-Z0-9_-]+)*$',
                ).hasMatch(raw[bound] as String))) {
          bad(
            'Invalid state range binding.',
            field: bound,
            example: '"data.startedAt"',
          );
        }
      }
      if ((type == 'timer' || type == 'progress') && raw['bind'] == null) {
        bad(
          'Timestamp component requires a timestamp binding.',
          field: 'bind',
          example: '"data.endsAt"',
        );
      }
      if (type == 'progress' && raw['startBind'] == null) {
        bad(
          'Progress requires its start timestamp binding.',
          field: 'startBind',
          example: '"data.startedAt"',
        );
      }
      if (raw['mode'] != null &&
          (type != 'timer' ||
              !const {'countdown', 'elapsed'}.contains(raw['mode']))) {
        bad(
          'Timer mode must be countdown or elapsed.',
          field: 'mode',
          example: '"countdown"',
        );
      }
      if (raw['startBind'] != null && type != 'progress') {
        bad(
          'startBind is used by progress components.',
          field: 'startBind',
          example:
              '{"type":"progress","bind":"data.endsAt","startBind":"data.startedAt"}',
        );
      }
      if (raw['format'] != null &&
          !const {
            'bytes',
            'duration',
            'date',
            'time',
            'datetime',
          }.contains(raw['format'])) {
        bad('Unknown display format.', field: 'format', example: '"datetime"');
      }
      for (final key in ['valueKey', 'labelKey']) {
        if (raw[key] != null &&
            (raw[key] is! String ||
                !RegExp(
                  r'^[a-zA-Z0-9_-]+(\.[a-zA-Z0-9_-]+)*$',
                ).hasMatch(raw[key] as String))) {
          bad('Invalid list selector.', field: key, example: '"label"');
        }
      }
      if (raw['values'] != null) {
        _located(
          '$path.values',
          () => _checkTemplate(raw['values'], allowValue: true),
          '{"true":"Running","false":"Stopped"}',
        );
      }
      if (raw['action'] != null && !names.contains(raw['action'])) {
        bad(
          'A component references an unknown action.',
          field: 'action',
          example: names.isEmpty ? '"start"' : jsonEncode(names.first),
        );
      }
      if (raw['args'] != null) {
        if (raw['args'] is! Map) {
          bad(
            'Action args must be an object.',
            field: 'args',
            example: '{"durationMs":1500000}',
          );
        }
        _located(
          '$path.args',
          () => _checkTemplate(raw['args'], allowValue: true),
          '{"durationMs":1500000}',
        );
      }
      for (final key in ['min', 'max', 'step']) {
        if (raw[key] != null &&
            (raw[key] is! num || !(raw[key] as num).isFinite)) {
          bad('Invalid numeric limit.', field: key, example: '100');
        }
      }
      if ((raw['step'] is num && raw['step'] <= 0) ||
          (raw['min'] is num &&
              raw['max'] is num &&
              raw['min'] >= raw['max'])) {
        bad(
          'Invalid numeric range.',
          field: 'max',
          example: '{"min":0,"max":100,"step":1}',
        );
      }
      if (raw['children'] != null) {
        if (type != 'card' || raw['children'] is! List) {
          bad(
            'Only cards can contain child components.',
            field: 'children',
            example:
                '{"type":"card","children":[{"type":"timer","bind":"data.endsAt"}]}',
          );
        }
        final children = raw['children'] as List;
        for (var i = 0; i < children.length; i++) {
          visit(children[i], depth + 1, '$path.children[$i]');
        }
      }
      if (raw['options'] != null) {
        _located(
          '$path.options',
          () => _checkTemplate(raw['options'], allowValue: true),
          '[{"value":1500000,"label":"25 min"}]',
        );
      }
    }

    final components = screen['components'] as List;
    for (var i = 0; i < components.length; i++) {
      visit(components[i], 0, 'screen.components[$i]');
    }
  }
}

const reversibleHandlers = <String>{
  'device.screen.brightness.set',
  'device.screen.timeout.set',
  'device.audio.volume.set',
  'device.audio.dnd.set',
  'device.root.dnd.set',
  'device.flashlight.set',
  'device.root.power_save.set',
  'device.root.wifi.set',
  'device.root.bluetooth.set',
  'device.root.data.set',
  'device.root.airplane.set',
};

void _checkTemplate(Object? value, {bool allowValue = false, int depth = 0}) {
  if (depth > 20) {
    _bad('invalid_executor', 'JSON template is too deep.');
  }
  if (value is Map) {
    if (value.keys.any((k) => k is! String)) {
      _bad('invalid_executor', 'JSON keys must be strings.');
    }
    if (value.containsKey(r'$arg')) {
      if (allowValue ||
          value.length != 1 ||
          value[r'$arg'] is! String ||
          (value[r'$arg'] as String).length > 200) {
        _bad('invalid_executor', 'Invalid argument substitution.');
      }
    } else if (value.containsKey(r'$value')) {
      if (!allowValue || value.length != 1 || value[r'$value'] != true) {
        _bad('invalid_executor', 'Invalid control value substitution.');
      }
    } else {
      for (final child in value.values) {
        _checkTemplate(child, allowValue: allowValue, depth: depth + 1);
      }
    }
  } else if (value is List) {
    if (value.length > 256) {
      _bad('invalid_executor', 'JSON template is too large.');
    }
    for (final child in value) {
      _checkTemplate(child, allowValue: allowValue, depth: depth + 1);
    }
  } else if (value != null &&
          value is! String &&
          value is! bool &&
          value is! num ||
      value is num && !value.isFinite) {
    _bad('invalid_executor', 'Templates contain JSON values only.');
  }
  if (depth == 0 && utf8.encode(jsonEncode(value)).length > 64 * 1024) {
    _bad('invalid_executor', 'JSON template is too large.');
  }
}

Object? _freeze(Object? value) => value is Map
    ? Map<String, dynamic>.unmodifiable(
        value.map((k, v) => MapEntry(k as String, _freeze(v))),
      )
    : value is List
    ? List<dynamic>.unmodifiable(value.map(_freeze))
    : value;

Never _bad(String code, String message) =>
    throw MiniAppException(code, message);

Never _badAt(String code, String path, String message, String example) =>
    throw MiniAppException(code, '$path: $message Example: $example');

T _located<T>(String path, T Function() operation, String example) {
  try {
    return operation();
  } on MiniAppException catch (error) {
    if (error.message.startsWith(path)) {
      rethrow;
    }
    _badAt(error.code, path, error.message, example);
  }
}

/// A bounded validator for source JSON Schema. Unsupported assertion keywords
/// are rejected at installation rather than silently weakening a contract.
class MiniAppJsonSchema {
  static const _types = {
    'object',
    'array',
    'string',
    'number',
    'integer',
    'boolean',
    'null',
  };
  static const _keywords = {
    r'$schema',
    r'$id',
    r'$ref',
    r'$defs',
    'definitions',
    'title',
    'description',
    'default',
    'examples',
    'deprecated',
    'readOnly',
    'writeOnly',
    'format',
    'type',
    'properties',
    'required',
    'additionalProperties',
    'items',
    'prefixItems',
    'enum',
    'const',
    'anyOf',
    'oneOf',
    'allOf',
    'not',
    'minimum',
    'maximum',
    'exclusiveMinimum',
    'exclusiveMaximum',
    'multipleOf',
    'minLength',
    'maxLength',
    'pattern',
    'minItems',
    'maxItems',
    'uniqueItems',
    'minProperties',
    'maxProperties',
  };

  static void check(Map<String, dynamic> root) {
    if (utf8.encode(jsonEncode(root)).length > 64 * 1024) {
      _bad('invalid_schema', 'Schema is too large.');
    }
    var count = 0;
    void visit(Object? raw, int depth) {
      if (raw is bool) {
        return;
      }
      if (raw is! Map || depth > 32 || ++count > 1024) {
        _bad('invalid_schema', 'Invalid or oversized schema.');
      }
      if (raw.keys.any((k) => k is! String || !_keywords.contains(k))) {
        _bad('invalid_schema', 'Unsupported schema assertion.');
      }
      final type = raw['type'];
      if (type != null &&
          !(type is String && _types.contains(type)) &&
          !(type is List && type.isNotEmpty && type.every(_types.contains))) {
        _bad('invalid_schema', 'Unknown schema type.');
      }
      if (raw[r'$ref'] != null) {
        _resolve(root, raw[r'$ref']);
      }
      for (final key in ['properties', r'$defs', 'definitions']) {
        if (raw[key] == null) {
          continue;
        }
        if (raw[key] is! Map ||
            (raw[key] as Map).keys.any((k) => k is! String)) {
          _bad('invalid_schema', 'Invalid schema map.');
        }
        for (final child in (raw[key] as Map).values) {
          visit(child, depth + 1);
        }
      }
      final required = raw['required'];
      if (required != null &&
          (required is! List ||
              required.any((v) => v is! String) ||
              required.toSet().length != required.length)) {
        _bad('invalid_schema', 'Invalid required fields.');
      }
      for (final key in ['anyOf', 'oneOf', 'allOf', 'prefixItems']) {
        if (raw[key] == null) {
          continue;
        }
        if (raw[key] is! List ||
            (raw[key] as List).isEmpty ||
            (raw[key] as List).length > 64) {
          _bad('invalid_schema', 'Invalid schema union.');
        }
        for (final child in raw[key] as List) {
          visit(child, depth + 1);
        }
      }
      for (final key in ['items', 'additionalProperties', 'not']) {
        if (raw[key] != null) {
          visit(raw[key], depth + 1);
        }
      }
      if (raw['enum'] != null &&
          (raw['enum'] is! List || (raw['enum'] as List).isEmpty)) {
        _bad('invalid_schema', 'Invalid enum.');
      }
      for (final key in [
        'minimum',
        'maximum',
        'exclusiveMinimum',
        'exclusiveMaximum',
        'multipleOf',
      ]) {
        final value = raw[key];
        if (value != null &&
            (value is! num ||
                !value.isFinite ||
                key == 'multipleOf' && value <= 0)) {
          _bad('invalid_schema', 'Invalid numeric constraint.');
        }
      }
      for (final key in [
        'minLength',
        'maxLength',
        'minItems',
        'maxItems',
        'minProperties',
        'maxProperties',
      ]) {
        final value = raw[key];
        if (value != null && (value is! int || value < 0)) {
          _bad('invalid_schema', 'Invalid size constraint.');
        }
      }
      if (raw['uniqueItems'] != null && raw['uniqueItems'] is! bool) {
        _bad('invalid_schema', 'uniqueItems must be boolean.');
      }
      if (raw['pattern'] != null) {
        if (raw['pattern'] is! String ||
            (raw['pattern'] as String).length > 256) {
          _bad('invalid_schema', 'Invalid string pattern.');
        }
        _checkPattern(raw['pattern'] as String);
        try {
          RegExp(raw['pattern'] as String);
        } on FormatException {
          _bad('invalid_schema', 'Invalid string pattern.');
        }
      }
    }

    visit(root, 0);
    final seenRoots = <Object>{};
    void objectRoot(Object? raw) {
      if (raw == true) {
        return;
      }
      if (raw is! Map || !seenRoots.add(raw)) {
        if (raw is Map) {
          return;
        }
        _bad(
          'invalid_schema',
          'Action arguments must have an object-compatible schema root.',
        );
      }
      final type = raw['type'];
      if (type != null &&
          (type is List ? type.any((v) => v != 'object') : type != 'object')) {
        _bad(
          'invalid_schema',
          'Action arguments must have an object-compatible schema root.',
        );
      }
      if (raw.containsKey('const') && raw['const'] is! Map ||
          raw['enum'] is List && (raw['enum'] as List).any((v) => v is! Map)) {
        _bad('invalid_schema', 'Action argument root values must be objects.');
      }
      if (raw[r'$ref'] != null) {
        objectRoot(_resolve(root, raw[r'$ref']));
      }
      for (final key in ['anyOf', 'oneOf', 'allOf']) {
        for (final child in raw[key] as List? ?? const []) {
          objectRoot(child);
        }
      }
    }

    objectRoot(root);
  }

  static Map<String, dynamic> arguments(
    Map<String, dynamic> schema,
    Map<String, dynamic> input,
  ) {
    final copy = jsonDecode(jsonEncode(input)) as Map<String, dynamic>;
    if (utf8.encode(jsonEncode(copy)).length > 64 * 1024) {
      _bad('invalid_arguments', 'Arguments are too large.');
    }
    _stripOptionalNulls(schema, copy, schema, 0);
    final error = _boundedError(schema, copy, schema);
    if (error != null) {
      _bad('invalid_arguments', error);
    }
    return copy;
  }

  static void validate(Map<String, dynamic> schema, Object? value) {
    final error = _boundedError(schema, value, schema);
    if (error != null) {
      _bad('invalid_arguments', error);
    }
  }

  static String? _boundedError(
    Object? schema,
    Object? value,
    Map<String, dynamic> root,
  ) {
    final budget = _SchemaBudget();
    final error = _error(schema, value, root, 0, budget);
    if (budget.exceeded) {
      _bad(
        'invalid_arguments',
        'Schema validation exceeds the evaluation limit.',
      );
    }
    return error;
  }

  /// Deliberately conservative linear-time regex subset. General patterns may
  /// use literals/classes/anchors and one anchored finite or variable repeat.
  /// Groups, alternatives, backreferences and stacked repeats need a future
  /// bounded regex backend; rejecting them preserves every source assertion.
  static void _checkPattern(String pattern) {
    const packagePattern = r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$';
    if (pattern == packagePattern) {
      return;
    } // Fixed disjoint dot-delimited atoms.
    var inClass = false;
    var repeats = 0;
    for (var i = 0; i < pattern.length; i++) {
      final char = pattern[i];
      if (char == r'\') {
        if (++i >= pattern.length ||
            !inClass && RegExp(r'[1-9k]').hasMatch(pattern[i])) {
          _bad('invalid_schema', 'Unsupported unsafe pattern assertion.');
        }
        continue;
      }
      if (inClass) {
        if (char == ']') {
          inClass = false;
        }
        continue;
      }
      if (char == '[') {
        inClass = true;
        continue;
      }
      if (char == '(' || char == ')' || char == '|') {
        _bad('invalid_schema', 'Unsupported unsafe pattern assertion.');
      }
      if (char == '{') {
        final end = pattern.indexOf('}', i);
        if (end < 0) {
          _bad('invalid_schema', 'Invalid bounded pattern repetition.');
        }
        final body = pattern.substring(i + 1, end);
        if (!RegExp(r'^\d+(,\d+)?$').hasMatch(body) ||
            body.split(',').any((v) => (int.tryParse(v) ?? 4097) > 4096)) {
          _bad('invalid_schema', 'Unsupported bounded pattern repetition.');
        }
        repeats++;
        i = end;
      } else if (char == '*' || char == '+' || char == '?') {
        repeats++;
      }
      if (repeats > 1 || repeats > 0 && !pattern.startsWith('^')) {
        _bad('invalid_schema', 'Unsupported unsafe pattern assertion.');
      }
    }
  }

  static Object _resolve(Map<String, dynamic> root, Object? ref) {
    if (ref is! String || !ref.startsWith('#/') || ref.length > 512) {
      _bad(
        'invalid_schema',
        'Only bounded local schema references are supported.',
      );
    }
    Object? value = root;
    for (final token in ref.substring(2).split('/')) {
      final key = token.replaceAll('~1', '/').replaceAll('~0', '~');
      if (value is! Map || !value.containsKey(key)) {
        _bad('invalid_schema', 'Missing local schema reference.');
      }
      value = value[key];
    }
    if (value is! Map && value is! bool) {
      _bad('invalid_schema', 'Reference is not a schema.');
    }
    return value!;
  }

  static void _stripOptionalNulls(
    Object? raw,
    Object? value,
    Map<String, dynamic> root,
    int depth,
  ) {
    if (raw is! Map || depth > 32) {
      return;
    }
    if (raw[r'$ref'] != null) {
      _stripOptionalNulls(_resolve(root, raw[r'$ref']), value, root, depth + 1);
    }
    if (value is Map && raw['properties'] is Map) {
      final required = raw['required'] as List? ?? const [];
      for (final e in (raw['properties'] as Map).entries) {
        if (!value.containsKey(e.key)) {
          continue;
        }
        if (value[e.key] == null &&
            !required.contains(e.key) &&
            _boundedError(e.value, null, root) != null) {
          value.remove(e.key);
        } else {
          _stripOptionalNulls(e.value, value[e.key], root, depth + 1);
        }
      }
    }
    if (value is List && raw['items'] != null) {
      for (final child in value) {
        _stripOptionalNulls(raw['items'], child, root, depth + 1);
      }
    }
  }

  static String? _error(
    Object? raw,
    Object? value,
    Map<String, dynamic> root,
    int depth, [
    _SchemaBudget? work,
  ]) {
    final budget = work ?? _SchemaBudget();
    if (++budget.visits > 8192) {
      budget.exceeded = true;
      return 'Schema validation exceeds the evaluation limit.';
    }
    if (depth > 48) {
      return 'Schema or argument nesting exceeds the limit.';
    }
    if (raw == true) {
      return null;
    }
    if (raw == false || raw is! Map) {
      return 'Value is forbidden by the source schema.';
    }
    String? check(Object? schema) =>
        _error(schema, value, root, depth + 1, budget);
    if (raw[r'$ref'] != null) {
      final error = check(_resolve(root, raw[r'$ref']));
      if (error != null) {
        return error;
      }
    }
    if (raw['allOf'] is List &&
        (raw['allOf'] as List).any((s) => check(s) != null)) {
      return 'Value does not match allOf.';
    }
    if (raw['anyOf'] is List &&
        !(raw['anyOf'] as List).any((s) => check(s) == null)) {
      return 'Value does not match anyOf.';
    }
    if (raw['oneOf'] is List &&
        (raw['oneOf'] as List).where((s) => check(s) == null).length != 1) {
      return 'Value does not match oneOf.';
    }
    if (raw['not'] != null && check(raw['not']) == null) {
      return 'Value matches a forbidden schema.';
    }
    bool matches(Object? type) => switch (type) {
      'object' => value is Map,
      'array' => value is List,
      'string' => value is String,
      'number' => value is num && value.isFinite,
      'integer' =>
        value is num && value.isFinite && value == value.roundToDouble(),
      'boolean' => value is bool,
      'null' => value == null,
      _ => false,
    };
    final type = raw['type'];
    if (type != null && !(type is List ? type.any(matches) : matches(type))) {
      return 'Value has the wrong source-schema type.';
    }
    if (raw['enum'] is List &&
        !(raw['enum'] as List).any((v) => _equal(v, value))) {
      return 'Value is outside the allowed enum.';
    }
    if (raw.containsKey('const') && !_equal(raw['const'], value)) {
      return 'Value differs from const.';
    }
    if (value is num) {
      if (!value.isFinite ||
          raw['minimum'] is num && value < raw['minimum'] ||
          raw['maximum'] is num && value > raw['maximum'] ||
          raw['exclusiveMinimum'] is num && value <= raw['exclusiveMinimum'] ||
          raw['exclusiveMaximum'] is num && value >= raw['exclusiveMaximum']) {
        return 'Value is outside the allowed numeric range.';
      }
      if (raw['multipleOf'] is num) {
        final ratio = value / raw['multipleOf'];
        if ((ratio - ratio.roundToDouble()).abs() > 1e-9) {
          return 'Value is not a multipleOf.';
        }
      }
    }
    if (value is String) {
      final size = value.runes.length;
      if (raw['pattern'] is String) {
        _checkPattern(raw['pattern'] as String);
      }
      if (raw['minLength'] is int && size < raw['minLength'] ||
          raw['maxLength'] is int && size > raw['maxLength'] ||
          raw['pattern'] is String && !RegExp(raw['pattern']).hasMatch(value)) {
        return 'String violates its source-schema constraints.';
      }
    }
    if (value is Map) {
      if (raw['minProperties'] is int && value.length < raw['minProperties'] ||
          raw['maxProperties'] is int && value.length > raw['maxProperties']) {
        return 'Object has an invalid property count.';
      }
      for (final key in raw['required'] as List? ?? const []) {
        if (!value.containsKey(key)) {
          return 'Missing required argument "$key".';
        }
      }
      final props = raw['properties'] as Map? ?? const {};
      for (final entry in value.entries) {
        final schema = props.containsKey(entry.key)
            ? props[entry.key]
            : raw['additionalProperties'];
        if (schema == null) {
          continue;
        }
        final error = _error(schema, entry.value, root, depth + 1, budget);
        if (error != null) {
          return '${entry.key}: $error';
        }
      }
    }
    if (value is List) {
      if (raw['minItems'] is int && value.length < raw['minItems'] ||
          raw['maxItems'] is int && value.length > raw['maxItems']) {
        return 'Array has an invalid length.';
      }
      if (raw['uniqueItems'] == true &&
          value.map((v) => jsonEncode(_canonical(v))).toSet().length !=
              value.length) {
        return 'Array items must be unique.';
      }
      final prefix = raw['prefixItems'] as List? ?? const [];
      for (var i = 0; i < value.length; i++) {
        final schema = i < prefix.length ? prefix[i] : raw['items'];
        if (schema != null) {
          final error = _error(schema, value[i], root, depth + 1, budget);
          if (error != null) {
            return error;
          }
        }
      }
    }
    return null;
  }

  static bool _equal(Object? a, Object? b) {
    if (a is Map && b is Map) {
      return a.length == b.length &&
          a.keys.every((k) => b.containsKey(k) && _equal(a[k], b[k]));
    }
    if (a is List && b is List) {
      return a.length == b.length &&
          Iterable<int>.generate(a.length).every((i) => _equal(a[i], b[i]));
    }
    return a == b;
  }

  static Object? _canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: _canonical(value[key])};
    }
    if (value is List) {
      return value.map(_canonical).toList();
    }
    if (value is double && value.isFinite && value == value.toInt()) {
      return value.toInt();
    }
    return value;
  }
}

class _SchemaBudget {
  int visits = 0;
  bool exceeded = false;
}
