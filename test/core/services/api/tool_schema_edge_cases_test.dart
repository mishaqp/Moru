import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/services/api/tool_schema_normalizer.dart';

import '../../../support/tool_schema_contract.dart';

void main() {
  test(
    'array unions and boolean item schemas cannot enable invalid strict',
    () {
      for (final field in <Map<String, dynamic>>[
        {
          'type': ['array', 'null'],
        },
        {'type': 'array', 'items': false},
        {'type': 'array', 'items': true},
      ]) {
        final source = <String, dynamic>{
          'type': 'object',
          'properties': {'value': field},
        };
        final strict = normalizeToolSchema(
          source,
          ToolSchemaTarget.openaiStrict,
        );
        expect(strict.strict, false);
        final google = normalizeToolSchema(source, ToolSchemaTarget.gemini);
        assertToolSchemaForProvider(
          google.parameters,
          ToolSchemaTarget.gemini,
          strict: false,
          path: 'boolean items',
        );
      }
    },
  );

  test(
    'ordinary providers preserve tuple positions and contains constraints',
    () {
      for (final target in [ToolSchemaTarget.openai, ToolSchemaTarget.claude]) {
        final output = normalizeToolSchema({
          'type': 'object',
          'properties': {
            'tuple': {
              'type': 'array',
              'items': [
                {'type': 'string'},
                {'type': 'integer'},
              ],
              'additionalItems': false,
            },
            'rows': {
              'type': 'array',
              'items': {'type': 'string'},
              'contains': {
                'enum': ['x'],
              },
              'minContains': 1,
              'maxContains': 2,
            },
          },
        }, target).parameters;
        expect(output['properties']['tuple']['prefixItems'], [
          {'type': 'string'},
          {'type': 'integer'},
        ]);
        expect(output['properties']['tuple']['items'], {
          'not': <String, dynamic>{},
        });
        expect(output['properties']['rows']['contains']['enum'], ['x']);
        expect(output['properties']['rows']['minContains'], 1);
        expect(output['properties']['rows']['maxContains'], 2);
      }
    },
  );

  test('null detection intersects source conjunctions and union siblings', () {
    final source = <String, dynamic>{
      'type': 'object',
      'properties': {
        'sibling': {
          'anyOf': [
            {'type': 'null'},
            {'type': 'string'},
          ],
          'allOf': [
            {
              'enum': ['x'],
            },
          ],
        },
      },
      'allOf': [
        {
          'properties': {
            'value': {'type': 'string'},
          },
        },
        {
          'properties': {
            'value': {
              'type': ['string', 'null'],
            },
          },
        },
      ],
    };
    expect(
      omitUnsupportedOptionalNulls({'value': null, 'sibling': null}, source),
      isEmpty,
    );
  });

  test(
    'MCP null adaptation preserves unknown keys and walks union array items',
    () {
      final source = <String, dynamic>{
        'type': 'object',
        'additionalProperties': false,
        'properties': {
          'rows': {
            'anyOf': [
              {
                'type': 'array',
                'items': {
                  'type': 'object',
                  'properties': {
                    'optional': {'type': 'string'},
                  },
                },
              },
              {'type': 'null'},
            ],
          },
        },
      };
      expect(
        omitUnsupportedOptionalNulls({
          'unknown': null,
          'rows': [
            {'optional': null},
          ],
        }, source),
        {
          'unknown': null,
          'rows': [<String, dynamic>{}],
        },
      );
    },
  );

  test('unconstrained MCP union alternatives retain permitted null', () {
    expect(
      omitUnsupportedOptionalNulls(
        {'value': null},
        {
          'type': 'object',
          'anyOf': [
            {
              'properties': {
                'value': {'type': 'string'},
              },
            },
            <String, dynamic>{},
          ],
        },
      ),
      {'value': null},
    );
  });

  test('strict rejects unsupported formats and structural budgets', () {
    var deep = <String, dynamic>{'type': 'string'};
    for (var i = 0; i < 12; i++) {
      deep = {
        'type': 'object',
        'properties': {'child': deep},
      };
    }
    for (final source in <Map<String, dynamic>>[
      {
        'type': 'object',
        'properties': {
          'url': {'type': 'string', 'format': 'uri'},
        },
      },
      deep,
      {
        'type': 'object',
        'properties': {
          'large': {
            'type': 'string',
            'enum': [for (var i = 0; i < 1001; i++) '$i'],
          },
        },
      },
    ]) {
      expect(
        normalizeToolSchema(source, ToolSchemaTarget.openaiStrict).strict,
        false,
      );
    }
  });

  test(
    'Gemini intersects allOf object properties and nullable enum siblings',
    () {
      final output = normalizeToolSchema({
        'type': 'object',
        'properties': {
          'value': {
            'allOf': [
              {
                'type': ['string', 'null'],
              },
              {
                'enum': ['x'],
              },
            ],
          },
          'pair': {
            'allOf': [
              {
                'type': 'object',
                'properties': {
                  'x': {'type': 'string'},
                },
                'required': ['x'],
              },
              {
                'type': 'object',
                'properties': {
                  'y': {'type': 'integer'},
                },
                'required': ['y'],
              },
            ],
          },
        },
      }, ToolSchemaTarget.gemini).parameters;
      expect(output['properties']['value']['nullable'], isNot(true));
      expect(output['properties']['value']['enum'], ['x']);
      expect((output['properties']['pair']['properties'] as Map).keys.toSet(), {
        'x',
        'y',
      });
      expect((output['properties']['pair']['required'] as List).toSet(), {
        'x',
        'y',
      });
    },
  );
}
