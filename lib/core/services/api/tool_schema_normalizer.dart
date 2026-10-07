import 'dart:convert';

import 'json_schema_utils.dart';

enum ToolSchemaTarget { openaiStrict, openai, claude, gemini }

class NormalizedToolSchema {
  const NormalizedToolSchema(
    this.parameters, {
    required this.strict,
    required this.diagnostics,
  });

  final Map<String, dynamic> parameters;
  final bool strict;

  /// Schema paths/keywords only; never arguments or credential values.
  final List<String> diagnostics;
}

/// The only provider conversion of source tool schemas. Never mutates source.
NormalizedToolSchema normalizeToolSchema(
  Map<String, dynamic> source,
  ToolSchemaTarget target,
) {
  final diagnostics = <String>[];
  final resolved = resolveJsonSchemaRefs(
    source,
    preserveReferences: true,
    expandAdditionalProperties: target != ToolSchemaTarget.gemini,
  );
  final common = _common(resolved, diagnostics, r'$');
  if (!_hasRef(common)) {
    common.remove(r'$defs');
    common.remove('definitions');
  }
  if (target == ToolSchemaTarget.gemini) {
    return NormalizedToolSchema(
      _gemini(common, diagnostics, r'$'),
      strict: false,
      diagnostics: diagnostics,
    );
  }
  if (target == ToolSchemaTarget.openaiStrict) {
    final problems = <String>[];
    _checkStrict(common, problems, r'$', root: true);
    if (problems.isEmpty) {
      return NormalizedToolSchema(
        _strict(common),
        strict: true,
        diagnostics: diagnostics,
      );
    }
    diagnostics.addAll(problems);
  }
  return NormalizedToolSchema(common, strict: false, diagnostics: diagnostics);
}

/// Accepts both Chat Completions and flattened Responses function definitions.
/// Explicit false also protects tools where null means an intentional reset.
Map<String, dynamic> normalizeToolDefinition(
  Map<String, dynamic> tool,
  ToolSchemaTarget target,
) {
  if (tool['type'] != 'function') return Map<String, dynamic>.from(tool);
  final nested = tool['function'] is Map;
  final function = Map<String, dynamic>.from(
    nested ? tool['function'] as Map : tool,
  );
  final requestedStrict = tool['strict'] ?? function['strict'];
  final effective =
      (target == ToolSchemaTarget.openaiStrict && requestedStrict == false)
      ? ToolSchemaTarget.openai
      : (target == ToolSchemaTarget.openai && requestedStrict == true)
      ? ToolSchemaTarget.openaiStrict
      : target;
  final raw = function['parameters'];
  final normalized = normalizeToolSchema(
    raw is Map
        ? Map<String, dynamic>.from(raw)
        : {'type': 'object', 'properties': <String, dynamic>{}},
    effective,
  );
  function['parameters'] = normalized.parameters;
  function.remove('strict');
  if (target == ToolSchemaTarget.openaiStrict ||
      requestedStrict is bool && target == ToolSchemaTarget.openai) {
    function['strict'] = normalized.strict;
  }
  if (!nested) return function;
  return Map<String, dynamic>.from(tool)
    ..remove('strict')
    ..['function'] = function;
}

/// Normalize native Claude/Gemini tools after all request-body overrides.
/// Hosted tools without a client parameter schema pass through untouched.
void normalizeNativeToolSchemas(
  Map<String, dynamic> body,
  ToolSchemaTarget target,
) {
  final raw = body['tools'];
  if (raw is! List) return;
  body['tools'] = [
    for (final tool in raw)
      if (tool is Map)
        _nativeTool(Map<String, dynamic>.from(tool), target)
      else
        tool,
  ];
}

Map<String, dynamic> _nativeTool(
  Map<String, dynamic> tool,
  ToolSchemaTarget target,
) {
  if (target == ToolSchemaTarget.claude && tool['input_schema'] is Map) {
    tool['input_schema'] = normalizeToolSchema(
      Map<String, dynamic>.from(tool['input_schema'] as Map),
      target,
    ).parameters;
  }
  if (target == ToolSchemaTarget.gemini) {
    for (final key in ['function_declarations', 'functionDeclarations']) {
      if (tool[key] is! List) continue;
      tool[key] = [
        for (final declaration in tool[key] as List)
          if (declaration is Map)
            {
              ...declaration,
              if (declaration['parameters'] is Map)
                'parameters': normalizeToolSchema(
                  Map<String, dynamic>.from(declaration['parameters'] as Map),
                  target,
                ).parameters,
            }
          else
            declaration,
      ];
    }
  }
  return tool;
}

const _commonKeys = {
  'type',
  'title',
  'description',
  'default',
  'examples',
  'example',
  'enum',
  'properties',
  'required',
  'items',
  'additionalProperties',
  'patternProperties',
  'propertyNames',
  'minProperties',
  'maxProperties',
  'minimum',
  'maximum',
  'exclusiveMinimum',
  'exclusiveMaximum',
  'multipleOf',
  'minLength',
  'maxLength',
  'pattern',
  'format',
  'minItems',
  'maxItems',
  'uniqueItems',
  'anyOf',
  'oneOf',
  'allOf',
  'not',
  'if',
  'then',
  'else',
  'dependentRequired',
  'dependentSchemas',
  'prefixItems',
  'contains',
  'minContains',
  'maxContains',
  'additionalItems',
  'unevaluatedItems',
  'unevaluatedProperties',
  'propertyOrdering',
  r'$ref',
  r'$defs',
  'definitions',
};
const _schemaMaps = {
  'properties',
  'patternProperties',
  'dependentSchemas',
  r'$defs',
  'definitions',
};
const _schemaLists = {'anyOf', 'oneOf', 'allOf', 'prefixItems'};
const _schemaChildren = {
  'items',
  'additionalProperties',
  'propertyNames',
  'not',
  'if',
  'then',
  'else',
  'contains',
  'additionalItems',
  'unevaluatedItems',
  'unevaluatedProperties',
};

Map<String, dynamic> _common(Map source, List<String> notes, String path) {
  final node = <String, dynamic>{};
  for (final entry in source.entries) {
    final key = entry.key.toString();
    final value = entry.value;
    if (!_commonKeys.contains(key)) continue;
    if (_schemaMaps.contains(key) && value is Map) {
      node[key] = {
        for (final e in value.entries)
          e.key.toString(): _common(
            _schemaObject(e.value),
            notes,
            '$path.$key.${e.key}',
          ),
      };
    } else if (_schemaLists.contains(key) && value is List) {
      node[key] = [
        for (final e in value) _common(_schemaObject(e), notes, '$path.$key'),
      ];
    } else if (_schemaChildren.contains(key) && value is Map) {
      node[key] = _common(value, notes, '$path.$key');
    } else if (key == 'items' && value is List) {
      node['prefixItems'] = [
        for (final e in value)
          _common(_schemaObject(e), notes, '$path.prefixItems'),
      ];
      node['items'] = _common(
        _schemaObject(source['additionalItems'] ?? true),
        notes,
        '$path.items',
      );
    } else if (_schemaChildren.contains(key) &&
        value is bool &&
        key != 'additionalProperties') {
      node[key] = _common(_schemaObject(value), notes, '$path.$key');
    } else {
      node[key] = _copy(value);
    }
  }
  if (source['items'] is List) node.remove('additionalItems');
  if (source.containsKey('const')) node['enum'] = [_copy(source['const'])];
  if (node['type'] == null && node['enum'] is List) {
    final types = (node['enum'] as List).map(_typeOf).toSet().toList();
    if (types.contains('integer') && types.contains('number')) {
      types.remove('integer');
    }
    if (types.length == 1) {
      node['type'] = types.single;
    } else if (types.isNotEmpty) {
      node['type'] = types;
    }
  }
  if (node['type'] == null && node['properties'] is Map) {
    node['type'] = 'object';
  }
  if (node['type'] == null && node['items'] != null) node['type'] = 'array';
  final type = node['type'];
  if (type is List) {
    node.remove('type');
    final base = Map<String, dynamic>.from(node);
    node.clear();
    node['anyOf'] = [
      for (final t in type.whereType<String>().toSet()) _typedVariant(base, t),
    ];
  }
  if (source['nullable'] == true && !_allowsNull(node)) return _nullable(node);
  if (node['type'] == 'array' && node['items'] == null) {
    node['items'] = <String, dynamic>{};
  }
  if (node['required'] is List) {
    final props = Map<String, dynamic>.from(node['properties'] as Map? ?? {});
    final required = (node['required'] as List)
        .whereType<String>()
        .toSet()
        .toList();
    for (final name in required) {
      props.putIfAbsent(name, () => <String, dynamic>{});
    }
    node['properties'] = props;
    node['required'] = required;
  }
  return node;
}

Map<String, dynamic> _typedVariant(Map<String, dynamic> base, String type) {
  final out = Map<String, dynamic>.from(base)..['type'] = type;
  if (type == 'array' && out['items'] == null) {
    out['items'] = <String, dynamic>{};
  }
  if (out['enum'] is List) {
    out['enum'] = (out['enum'] as List)
        .where(
          (value) => _typeOf(value) == type || type == 'number' && value is num,
        )
        .toList();
  }
  if (type != 'object') {
    out.removeWhere(
      (key, _) => {
        'properties',
        'required',
        'additionalProperties',
        'patternProperties',
        'minProperties',
        'maxProperties',
      }.contains(key),
    );
  }
  if (type != 'array') {
    out.removeWhere(
      (key, _) =>
          {'items', 'minItems', 'maxItems', 'uniqueItems'}.contains(key),
    );
  }
  if (type != 'string') {
    out.removeWhere(
      (key, _) => {'minLength', 'maxLength', 'pattern', 'format'}.contains(key),
    );
  }
  if (type != 'number' && type != 'integer') {
    out.removeWhere(
      (key, _) => {
        'minimum',
        'maximum',
        'exclusiveMinimum',
        'exclusiveMaximum',
        'multipleOf',
      }.contains(key),
    );
  }
  return out;
}

void _checkStrict(
  Map node,
  List<String> problems,
  String path, {
  bool root = false,
  int depth = 0,
}) {
  if (root && (node['type'] != 'object' || node.containsKey('anyOf'))) {
    problems.add('$path: strict requires an object root');
  }
  const unsupported = {
    'oneOf',
    'allOf',
    'not',
    'if',
    'then',
    'else',
    'dependentRequired',
    'dependentSchemas',
    'patternProperties',
    'propertyNames',
    'minProperties',
    'maxProperties',
    'uniqueItems',
    'prefixItems',
    'contains',
    'minContains',
    'maxContains',
    'additionalItems',
    'unevaluatedItems',
    'unevaluatedProperties',
    'exclusiveMinimum',
    'exclusiveMaximum',
    r'$ref',
  };
  for (final key in node.keys.where(unsupported.contains)) {
    problems.add('$path.$key: strict unsupported');
  }
  if (node['type'] == null && node['anyOf'] == null) {
    problems.add('$path: unconstrained schema');
  }
  if (node['type'] == 'object') {
    if (node['additionalProperties'] == true ||
        node['additionalProperties'] is Map) {
      problems.add('$path: open dictionary requires non-strict');
    }
    if (!root &&
        (node['properties'] as Map? ?? {}).isEmpty &&
        node['additionalProperties'] != false) {
      problems.add('$path: unconstrained object requires non-strict');
    }
  }
  const formats = {
    'date-time',
    'time',
    'date',
    'duration',
    'email',
    'hostname',
    'ipv4',
    'ipv6',
    'uuid',
  };
  if (node['format'] != null && !formats.contains(node['format'])) {
    problems.add('$path.format: strict unsupported');
  }
  if (node['type'] == 'array' && node['items'] is! Map) {
    problems.add('$path.items: strict requires an item schema');
  }
  final container = node['type'] == 'object' || node['type'] == 'array';
  if (container && depth >= 10) {
    problems.add('$path: strict nesting budget exceeded');
  }
  if ((node['enum'] as List? ?? []).length > 1000) {
    problems.add('$path.enum: strict enum budget exceeded');
  }
  _walk(
    node,
    (child, key) => _checkStrict(
      child,
      problems,
      '$path.$key',
      depth: depth + (container ? 1 : 0),
    ),
  );
  if (root) {
    var properties = 0;
    var enumValues = 0;
    var stringChars = 0;
    void count(Map schema) {
      final props = schema['properties'] as Map? ?? {};
      properties += props.length;
      stringChars += props.keys.fold<int>(
        0,
        (total, name) => total + name.toString().length,
      );
      final values = schema['enum'] as List? ?? [];
      enumValues += values.length;
      final chars = values.whereType<String>().fold<int>(
        0,
        (total, value) => total + value.length,
      );
      stringChars += chars;
      if (values.length > 250 && chars > 7500) {
        problems.add('$path.enum: strict string enum budget exceeded');
      }
      _walk(schema, (child, _) => count(child));
    }

    count(node);
    if (properties > 5000 || enumValues > 1000 || stringChars > 120000) {
      problems.add('$path: strict schema size budget exceeded');
    }
  }
}

Map<String, dynamic> _strict(Map source) {
  final out = Map<String, dynamic>.from(source);
  _transformChildren(out, _strict);
  out.remove('default');
  if (source['type'] == 'object') {
    final required = (source['required'] as List? ?? []).toSet();
    final props = Map<String, dynamic>.from(out['properties'] as Map? ?? {});
    props.updateAll(
      (name, schema) => !required.contains(name) && !_allowsNull(schema as Map)
          ? _nullable(schema as Map<String, dynamic>)
          : schema,
    );
    out['properties'] = props;
    out['required'] = props.keys.toList();
    out['additionalProperties'] = false;
  }
  return out;
}

const _geminiKeys = {
  'type',
  'format',
  'title',
  'description',
  'nullable',
  'enum',
  'maxItems',
  'minItems',
  'properties',
  'required',
  'minProperties',
  'maxProperties',
  'minLength',
  'maxLength',
  'pattern',
  'example',
  'anyOf',
  'propertyOrdering',
  'default',
  'items',
  'minimum',
  'maximum',
};

Map<String, dynamic> _gemini(Map source, List<String> notes, String path) {
  var input = Map<String, dynamic>.from(source);
  if (input['allOf'] is List) {
    final variants = input.remove('allOf') as List;
    for (final variant in variants) {
      input = _intersect(input, _schemaObject(variant), notes, path);
    }
  }
  if (input['oneOf'] is List) {
    final variants = input.remove('oneOf') as List;
    _note(input, notes, path, 'oneOf', 'Exactly one alternative must match.');
    input = _intersect(input, {'anyOf': variants}, notes, path);
  }
  if (input['anyOf'] is List) {
    final raw = input.remove('anyOf') as List;
    final variants = <Map<String, dynamic>>[];
    for (final variant in raw) {
      final combined = _intersect(input, _schemaObject(variant), notes, path);
      if (!_impossible(combined)) {
        variants.add(_gemini(combined, notes, '$path.anyOf'));
      }
    }
    final nullable = variants.any((variant) => variant['type'] == 'null');
    final values = variants
        .where((variant) => variant['type'] != 'null')
        .toList();
    if (values.length == 1) {
      return {...values.single, if (nullable) 'nullable': true};
    }
    if (values.isNotEmpty) {
      return {'anyOf': values, if (nullable) 'nullable': true};
    }
    if (nullable) return {'type': 'null'};
    input = {'description': 'No value satisfies the source schema.'};
    notes.add('$path: unrepresentable empty union');
  }
  for (final key in input.keys.toList()) {
    if (_geminiKeys.contains(key)) continue;
    if (key != r'$defs' && key != 'definitions') {
      _note(
        input,
        notes,
        path,
        key,
        'Source constraint $key: ${jsonEncode(input[key])}.',
      );
    }
    input.remove(key);
  }
  final out = Map<String, dynamic>.from(input);
  _transformChildren(out, (child) => _gemini(child, notes, '$path.child'));
  if (out['enum'] is List && out['type'] != 'string') {
    _note(
      out,
      notes,
      path,
      'enum',
      'Allowed values: ${jsonEncode(out['enum'])}.',
    );
    out.remove('enum');
  } else if (out['enum'] is List) {
    out['enum'] = (out['enum'] as List).whereType<String>().toList();
  }
  if (out['type'] == null && out['anyOf'] == null) {
    // A source {} means any JSON value, never "pick the first type".
    notes.add('$path: unconstrained JSON lowered to REST Schema types');
    out['anyOf'] = [
      for (final type in [
        'string',
        'number',
        'boolean',
        'object',
        'array',
        'null',
      ])
        if (type == 'array')
          {
            'type': 'array',
            'items': {'type': 'string'},
            'description': 'Items may contain any JSON value.',
          }
        else
          _gemini({'type': type}, notes, '$path.any'),
    ];
  }
  if (out['type'] == 'object') {
    out.putIfAbsent('properties', () => <String, dynamic>{});
  }
  if (out['type'] == 'array' && out['items'] is! Map) {
    out['items'] = _gemini(<String, dynamic>{}, notes, '$path.items');
  }
  return out;
}

bool _impossible(Map schema) =>
    schema['enum'] is List && (schema['enum'] as List).isEmpty ||
    schema['not'] is Map && (schema['not'] as Map).isEmpty;

/// Intersection is used only for Gemini, whose REST Schema lacks allOf.
Map<String, dynamic> _intersect(
  Map left,
  Map right,
  List<String> notes,
  String path,
) {
  if (_impossible(left) || _impossible(right)) {
    return {'not': <String, dynamic>{}};
  }
  for (final pair in [(left, right), (right, left)]) {
    final union = pair.$1['anyOf'];
    if (union is List) {
      if (union.length > 128) {
        final broad = <String, dynamic>{};
        _note(
          broad,
          notes,
          path,
          'anyOf',
          'Source intersection: ${jsonEncode([left, right])}.',
        );
        return broad;
      }
      final base = Map<String, dynamic>.from(pair.$1)..remove('anyOf');
      return {
        'anyOf': [
          for (final variant in union)
            _intersect(
              _intersect(base, _schemaObject(variant), notes, path),
              pair.$2,
              notes,
              path,
            ),
        ],
      };
    }
  }
  final out = Map<String, dynamic>.from(left);
  for (final entry in right.entries) {
    final key = entry.key.toString();
    final value = entry.value;
    if (!out.containsKey(key)) {
      out[key] = _copy(value);
      continue;
    }
    final previous = out[key];
    if (jsonEncode(previous) == jsonEncode(value)) continue;
    if (key == 'properties' && previous is Map && value is Map) {
      final props = Map<String, dynamic>.from(previous);
      for (final property in value.entries) {
        final name = property.key.toString();
        props[name] = props.containsKey(name)
            ? _intersect(
                _schemaObject(props[name]),
                _schemaObject(property.value),
                notes,
                '$path.$name',
              )
            : _copy(property.value);
      }
      out[key] = props;
    } else if (key == 'required' && previous is List && value is List) {
      out[key] = {...previous, ...value}.toList();
    } else if (key == 'enum' && previous is List && value is List) {
      out[key] = previous
          .where(
            (item) => value.any(
              (other) => item == other || jsonEncode(item) == jsonEncode(other),
            ),
          )
          .toList();
    } else if (key == 'type') {
      if ({previous, value}.containsAll({'integer', 'number'})) {
        out[key] = 'integer';
      } else {
        return {'not': <String, dynamic>{}};
      }
    } else if (key.startsWith('min') && previous is num && value is num) {
      out[key] = previous > value ? previous : value;
    } else if (key.startsWith('max') && previous is num && value is num) {
      out[key] = previous < value ? previous : value;
    } else if (key == 'items' && previous is Map && value is Map) {
      out[key] = _intersect(previous, value, notes, '$path.items');
    } else if (key == 'description') {
      out[key] = '$previous\n$value';
    } else if (key != 'title' &&
        key != 'default' &&
        key != 'examples' &&
        key != 'example') {
      out.remove(key);
      _note(
        out,
        notes,
        path,
        key,
        'Source constraints $key must both hold: ${jsonEncode([previous, value])}.',
      );
    }
  }
  final type = out['type'];
  if (type is String && out['enum'] is List) {
    out['enum'] = (out['enum'] as List)
        .where(
          (value) => _typeOf(value) == type || type == 'number' && value is num,
        )
        .toList();
  }
  return out;
}

void _note(
  Map<String, dynamic> schema,
  List<String> notes,
  String path,
  String keyword,
  String text,
) {
  notes.add('$path.$keyword: lowered to provider subset');
  final description = schema['description']?.toString() ?? '';
  schema['description'] = '${description.isEmpty ? '' : '$description\n'}$text';
}

Map<String, dynamic> _nullable(Map<String, dynamic> schema) => {
  'anyOf': [
    schema,
    {'type': 'null'},
  ],
};
bool _allowsNull(Map schema) {
  if (schema['nullable'] == true) return true;
  if (schema['enum'] is List && !(schema['enum'] as List).contains(null)) {
    return false;
  }
  if (schema.containsKey('const') && schema['const'] != null) return false;
  final type = schema['type'];
  if (type is String && type != 'null' ||
      type is List && !type.contains('null')) {
    return false;
  }
  if (schema['anyOf'] is List &&
      !(schema['anyOf'] as List).map(_schemaObject).any(_allowsNull)) {
    return false;
  }
  if (schema['oneOf'] is List &&
      (schema['oneOf'] as List).map(_schemaObject).where(_allowsNull).length !=
          1) {
    return false;
  }
  if (schema['allOf'] is List &&
      !(schema['allOf'] as List).whereType<Map>().every(_allowsNull)) {
    return false;
  }
  if (schema['not'] is Map && _allowsNull(schema['not'] as Map)) return false;
  return true;
}

/// Undo only synthetic optional nulls before invoking an MCP server. Required
/// nulls still reach server validation, and explicitly nullable fields keep null.
Map<String, dynamic> omitUnsupportedOptionalNulls(
  Map<String, dynamic> arguments,
  Map<String, dynamic> source,
) {
  final schema = resolveJsonSchemaRefs(source, preserveReferences: true);
  return _omitNulls(arguments, schema) as Map<String, dynamic>;
}

dynamic _omitNulls(dynamic value, Map schema) {
  if (value is Map) {
    final out = <String, dynamic>{};
    for (final entry in value.entries) {
      final name = entry.key.toString();
      final field = _propertySchema(schema, name);
      if (entry.value == null &&
          _hasPropertyConstraint(schema, name) &&
          field.isNotEmpty &&
          !_requiredProperty(schema, name) &&
          !_allowsNull(field)) {
        continue;
      }
      out[name] = _omitNulls(entry.value, field);
    }
    return out;
  }
  if (value is List) {
    return [
      for (var index = 0; index < value.length; index++)
        _omitNulls(value[index], _itemSchema(schema, index)),
    ];
  }
  return value;
}

Map<String, dynamic> _propertySchema(Map schema, String name) {
  if (_impossible(schema) || !_acceptsContainer(schema, 'object')) {
    return {'not': <String, dynamic>{}};
  }
  final constraints = <Map<String, dynamic>>[];
  final properties = schema['properties'] as Map? ?? {};
  if (properties.containsKey(name)) {
    constraints.add(_schemaObject(properties[name]));
  } else if (schema['additionalProperties'] is Map) {
    constraints.add(_schemaObject(schema['additionalProperties']));
  } else if (schema['additionalProperties'] == false) {
    constraints.add({'not': <String, dynamic>{}});
  }
  for (final child in (schema['allOf'] as List? ?? [])) {
    constraints.add(_propertySchema(_schemaObject(child), name));
  }
  for (final key in ['anyOf', 'oneOf']) {
    if (schema[key] is List) {
      constraints.add({
        'anyOf': [
          for (final child in schema[key] as List)
            _propertySchema(_schemaObject(child), name),
        ],
      });
    }
  }
  if (constraints.isEmpty) return <String, dynamic>{};
  return constraints.length == 1 ? constraints.single : {'allOf': constraints};
}

bool _acceptsContainer(Map schema, String type) {
  final declared = schema['type'];
  return declared == null ||
      declared == type ||
      declared is List && declared.contains(type);
}

bool _hasPropertyConstraint(Map schema, String name) {
  if ((schema['properties'] as Map? ?? {}).containsKey(name) ||
      schema['additionalProperties'] is Map) {
    return true;
  }
  for (final key in ['allOf', 'anyOf', 'oneOf']) {
    if ((schema[key] as List? ?? [])
        .map(_schemaObject)
        .any((child) => _hasPropertyConstraint(child, name))) {
      return true;
    }
  }
  return false;
}

Map<String, dynamic> _itemSchema(Map schema, int index) {
  if (_impossible(schema) || !_acceptsContainer(schema, 'array')) {
    return {'not': <String, dynamic>{}};
  }
  final constraints = <Map<String, dynamic>>[];
  final prefix =
      schema['prefixItems'] ??
      (schema['items'] is List ? schema['items'] : null);
  if (prefix is List && index < prefix.length) {
    constraints.add(_schemaObject(prefix[index]));
  } else if (schema['items'] is Map || schema['items'] is bool) {
    constraints.add(_schemaObject(schema['items']));
  }
  for (final child in schema['allOf'] as List? ?? []) {
    constraints.add(_itemSchema(_schemaObject(child), index));
  }
  for (final key in ['anyOf', 'oneOf']) {
    if (schema[key] is List) {
      constraints.add({
        'anyOf': [
          for (final child in schema[key] as List)
            _itemSchema(_schemaObject(child), index),
        ],
      });
    }
  }
  return constraints.length == 1 ? constraints.single : {'allOf': constraints};
}

bool _requiredProperty(Map schema, String name) {
  if ((schema['required'] as List? ?? []).contains(name)) return true;
  if ((schema['allOf'] as List? ?? []).whereType<Map>().any(
    (child) => _requiredProperty(child, name),
  )) {
    return true;
  }
  for (final key in ['anyOf', 'oneOf']) {
    final children = schema[key] as List?;
    if (children != null &&
        children.isNotEmpty &&
        children.whereType<Map>().every(
          (child) => _requiredProperty(child, name),
        )) {
      return true;
    }
  }
  return false;
}

Map<String, dynamic> _schemaObject(dynamic value) => value is Map
    ? Map<String, dynamic>.from(value)
    : value == false
    ? {'not': <String, dynamic>{}}
    : <String, dynamic>{};

String _typeOf(Object? value) => switch (value) {
  null => 'null',
  String() => 'string',
  bool() => 'boolean',
  int() => 'integer',
  num() => 'number',
  List() => 'array',
  _ => 'object',
};
dynamic _copy(dynamic value) =>
    value is Map || value is List ? jsonDecode(jsonEncode(value)) : value;
bool _hasRef(Map node) {
  if (node.containsKey(r'$ref')) return true;
  var found = false;
  _walk(node, (child, _) {
    if (_hasRef(child)) found = true;
  });
  return found;
}

void _walk(Map node, void Function(Map, String) visit) {
  for (final key in _schemaMaps) {
    if (node[key] is Map) {
      for (final e in (node[key] as Map).entries) {
        if (e.value is Map) visit(e.value as Map, '$key.${e.key}');
      }
    }
  }
  for (final key in _schemaLists) {
    if (node[key] is List) {
      for (final child in (node[key] as List).whereType<Map>()) {
        visit(child, key);
      }
    }
  }
  for (final key in _schemaChildren) {
    if (node[key] is Map) visit(node[key] as Map, key);
  }
}

void _transformChildren(
  Map<String, dynamic> node,
  Map<String, dynamic> Function(Map) transform,
) {
  for (final key in _schemaMaps) {
    if (node[key] is Map) {
      node[key] = <String, dynamic>{
        for (final e in (node[key] as Map).entries)
          e.key: transform(e.value as Map),
      };
    }
  }
  for (final key in _schemaLists) {
    if (node[key] is List) {
      node[key] = [
        for (final child in (node[key] as List).whereType<Map>())
          transform(child),
      ];
    }
  }
  for (final key in _schemaChildren) {
    if (node[key] is Map) node[key] = transform(node[key] as Map);
  }
}
