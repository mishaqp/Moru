import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/services/api/tool_schema_normalizer.dart';

void assertToolSchemaForProvider(
  Map schema,
  ToolSchemaTarget target, {
  required bool strict,
  required String path,
}) {
  const types = {
    'object',
    'array',
    'string',
    'integer',
    'number',
    'boolean',
    'null',
  };
  final type = schema['type'];
  if (type != null) expect(types, contains(type), reason: path);
  if (target == ToolSchemaTarget.gemini) {
    const keys = {
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
    expect(schema.keys, everyElement(isIn(keys)), reason: path);
    expect(type != null || schema['anyOf'] is List, true, reason: path);
    if (schema['enum'] != null) {
      expect(type, 'string', reason: path);
      expect(schema['enum'], everyElement(isA<String>()), reason: path);
    }
  }
  final props = schema['properties'] as Map?;
  if (type == 'object') {
    if (strict) {
      expect(schema['additionalProperties'], false, reason: path);
      expect(
        (schema['required'] as List).toSet(),
        (props ?? {}).keys.toSet(),
        reason: path,
      );
    }
    expect(
      (schema['required'] as List? ?? []).toSet().difference(
        (props ?? {}).keys.toSet(),
      ),
      isEmpty,
      reason: path,
    );
  }
  if (type == 'array') expect(schema['items'], isA<Map>(), reason: path);
  for (final entry in (props ?? {}).entries) {
    assertToolSchemaForProvider(
      entry.value as Map,
      target,
      strict: strict,
      path: '$path.${entry.key}',
    );
  }
  for (final key in ['items', 'additionalProperties']) {
    if (schema[key] is Map) {
      assertToolSchemaForProvider(
        schema[key] as Map,
        target,
        strict: strict,
        path: '$path.$key',
      );
    }
  }
  for (final key in ['anyOf', 'oneOf', 'allOf']) {
    if (strict) {
      expect(
        schema.containsKey('oneOf') || schema.containsKey('allOf'),
        false,
        reason: path,
      );
    }
    for (final child in schema[key] as List? ?? []) {
      assertToolSchemaForProvider(
        child as Map,
        target,
        strict: strict,
        path: '$path.$key',
      );
    }
  }
}
