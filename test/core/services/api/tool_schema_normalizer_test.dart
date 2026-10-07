import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/services/api/tool_schema_normalizer.dart';
import 'package:Kelivo/core/services/api/providers/openai/chat_completions_api.dart';
import 'package:Kelivo/core/services/api/providers/openai/responses_api.dart';
import 'package:Kelivo/core/services/memory/memory_prompts.dart';
import 'package:Kelivo/core/services/tools/built_in_tool_catalog.dart';
import 'package:Kelivo/features/home/services/local_tools_service.dart';

import '../../../support/tool_schema_fixtures.dart';
import '../../../support/tool_schema_contract.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every catalog and MCP schema satisfies each provider contract', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final definitions = <String, Map<String, dynamic>>{};
    for (final lang in MemoryPromptLang.values) {
      for (final legacy in [false, true]) {
        for (final entry in BuiltInToolCatalog.entries(
          lang: lang,
          legacyMemoryMode: legacy,
        )) {
          definitions['${lang.name}/$legacy/${entry.name}'] =
              entry.defaultDefinition;
        }
      }
    }
    // Retired/gated local names are still reserved and must remain valid.
    definitions.addAll(LocalToolsService.definitions);
    for (final entry in mcpToolSchemaFixtures.entries) {
      definitions['mcp/${entry.key}'] = {
        'type': 'function',
        'function': {'name': entry.key, 'parameters': entry.value},
      };
    }
    var strictCount = 0;
    for (final entry in definitions.entries) {
      final before = jsonEncode(entry.value);
      for (final target in ToolSchemaTarget.values) {
        final output = normalizeToolDefinition(entry.value, target);
        final fn = output['function'] as Map;
        final parameters = fn['parameters'] as Map<String, dynamic>;
        final strict = fn['strict'] == true;
        if (strict) strictCount++;
        assertToolSchemaForProvider(
          parameters,
          target,
          strict: strict,
          path: entry.key,
        );
      }
      expect(jsonEncode(entry.value), before, reason: entry.key);
    }
    expect(strictCount, greaterThan(0));
  });

  test('strict recursively closes objects and makes optionals nullable', () {
    final schema = normalizeToolSchema(
      mcpToolSchemaFixtures['nested_refs']!,
      ToolSchemaTarget.openaiStrict,
    );
    expect(schema.strict, isTrue);
    final rows = schema.parameters['properties']['rows'];
    expect(rows['minItems'], 1);
    final row = rows['items'];
    expect(row['additionalProperties'], false);
    expect(row['required'], ['id', 'mode', 'note']);
    expect(row['properties']['id']['minimum'], 1);
    expect(row['properties']['mode']['anyOf'], [
      {
        'type': 'string',
        'enum': ['read', 'write'],
      },
      {'type': 'null'},
    ]);
  });

  test('MCP unions and nullable survive every provider path', () {
    for (final target in ToolSchemaTarget.values) {
      final schema = normalizeToolSchema(
        mcpToolSchemaFixtures['nullable_and_unions']!,
        target,
      );
      final props = schema.parameters['properties'] as Map;
      expect(jsonEncode(props['label']), contains('null'), reason: target.name);
      expect(
        jsonEncode(props['legacy']),
        contains('null'),
        reason: target.name,
      );
      final choice = props['choice'] as Map;
      expect((choice['anyOf'] as List).length, greaterThanOrEqualTo(2));
      expect(jsonEncode(choice), contains('integer'));
      expect(jsonEncode(choice), contains('string'));
    }
  });

  test(
    'strict falls back for free dictionaries and unsupported conjunctions',
    () {
      for (final fixture in ['dictionaries_and_empty_objects', 'conjunction']) {
        final source = mcpToolSchemaFixtures[fixture]!;
        final output = normalizeToolSchema(
          source,
          ToolSchemaTarget.openaiStrict,
        );
        expect(output.strict, isFalse);
        expect(output.diagnostics, isNotEmpty);
        expect(
          output.parameters,
          normalizeToolSchema(source, ToolSchemaTarget.openai).parameters,
        );
      }
    },
  );

  test('Chat Completions and Responses use the same strict contract', () {
    final tool = {
      'type': 'function',
      'function': {
        'name': 'sequential_thinking',
        'strict': true,
        'parameters': mcpToolSchemaFixtures['sequential_thinking'],
      },
    };
    final chat = cleanToolsForCompatibility([tool]).single['function'] as Map;
    final responses = toResponsesToolsFormat([tool]).single;
    expect(chat['parameters'], responses['parameters']);
    expect(chat['strict'], true);
    expect(responses['strict'], true);
    expect(chat['parameters']['properties']['thoughtNumber']['minimum'], 1);
    expect(chat['parameters']['properties']['isRevision']['anyOf'], [
      {'type': 'boolean'},
      {'type': 'null'},
    ]);
    expect(toResponsesToolsFormat([responses]).single, responses);
  });

  test('Responses default strict never rewrites a free dictionary', () {
    final output = toResponsesToolsFormat([
      {
        'type': 'function',
        'function': {
          'name': 'dict',
          'parameters': mcpToolSchemaFixtures['dictionaries_and_empty_objects'],
        },
      },
    ]).single;
    expect(output['strict'], false);
    expect(
      output['parameters']['properties']['free']['additionalProperties'],
      true,
    );
  });

  test('explicit false preserves intentional optional null clears', () {
    final output = normalizeToolDefinition({
      'type': 'function',
      'function': {
        'name': 'clearable',
        'strict': false,
        'parameters': {
          'type': 'object',
          'properties': {
            'path': {
              'type': ['string', 'null'],
            },
          },
        },
      },
    }, ToolSchemaTarget.openaiStrict);
    expect(output['function']['strict'], false);
    expect(output['function']['parameters']['required'], isNull);
  });

  test('MCP drops only unsupported optional nulls, recursively', () {
    final source = <String, dynamic>{
      'type': 'object',
      'properties': {
        'optional': {'type': 'integer', 'minimum': 1},
        'required': {'type': 'integer'},
        'nullable': {
          'type': ['string', 'null'],
        },
        'nested': {
          'type': 'object',
          'properties': {
            'value': {'type': 'string'},
          },
        },
        'rows': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'value': {'type': 'string'},
            },
          },
        },
      },
      'required': ['required'],
    };
    final args = <String, dynamic>{
      'optional': null,
      'required': null,
      'nullable': null,
      'nested': {'value': null},
      'rows': [
        {'value': null},
      ],
      'unknown': null,
    };
    final result = omitUnsupportedOptionalNulls(args, source);
    expect(result, {
      'required': null,
      'nullable': null,
      'nested': <String, dynamic>{},
      'rows': [<String, dynamic>{}],
      'unknown': null,
    });
    expect(args, contains('optional'));
  });

  test('MCP null omission follows refs and every union variant', () {
    final source = <String, dynamic>{
      'type': 'object',
      r'$defs': {
        'Maybe': {'type': 'integer', 'nullable': true},
      },
      'anyOf': [
        {
          'properties': {
            'value': {'type': 'string'},
          },
        },
        {
          'properties': {
            'value': {r'$ref': r'#/$defs/Maybe'},
          },
        },
      ],
      'properties': {
        'payload': {
          'type': 'object',
          'properties': {
            'optional': {'type': 'boolean'},
          },
        },
      },
    };
    expect(
      omitUnsupportedOptionalNulls({
        'value': null,
        'payload': {'optional': null},
      }, source),
      {'value': null, 'payload': <String, dynamic>{}},
    );
  });
}
