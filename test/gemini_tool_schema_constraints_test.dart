import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/services/api/chat_api_helpers.dart';

void main() {
  test(
    'Gemini cleaning filters constraints inside supported anyOf schemas',
    () {
      final cleaned = cleanSchemaForGemini({
        'type': 'object',
        'anyOf': [
          {'type': 'number', 'minimum': 1, 'exclusiveMinimum': 0, 'default': 2},
          {'type': 'string', 'minLength': 1, 'unknown': true},
        ],
      }, stringEnumOnly: true);

      expect(cleaned['anyOf'], [
        {'type': 'number', 'minimum': 1, 'default': 2},
        {'type': 'string', 'minLength': 1},
      ]);
    },
  );

  test(
    'Gemini cleaning keeps supported constraints and drops unknown fields',
    () {
      final cleaned = cleanSchemaForGemini({
        'type': 'object',
        'title': 'Options',
        'default': {'exclusiveMinimum': 4, 'custom': true},
        'additionalProperties': false,
        'properties': {
          'amount': {
            'type': 'number',
            'minimum': 1,
            'maximum': 10,
            'exclusiveMinimum': 0,
            'exclusiveMaximum': 11,
          },
          'hosts': {
            'type': 'array',
            'minItems': 1,
            'maxItems': 3,
            'uniqueItems': true,
            'items': {
              'type': 'string',
              'minLength': 1,
              'maxLength': 40,
              'pattern': r'^[a-z]+$',
              'format': 'hostname',
              'default': 'example',
              'title': 'Host',
              'unknown': true,
            },
          },
        },
      }, stringEnumOnly: true);

      expect(cleaned['title'], 'Options');
      expect(cleaned['default'], {'exclusiveMinimum': 4, 'custom': true});
      expect(cleaned, isNot(contains('additionalProperties')));
      expect(cleaned['properties']['amount'], {
        'type': 'number',
        'minimum': 1,
        'maximum': 10,
      });
      expect(cleaned['properties']['hosts'], {
        'type': 'array',
        'minItems': 1,
        'maxItems': 3,
        'items': {
          'type': 'string',
          'minLength': 1,
          'maxLength': 40,
          'pattern': r'^[a-z]+$',
          'format': 'hostname',
          'default': 'example',
          'title': 'Host',
        },
      });
    },
  );

  test('compatibility cleaning preserves non-Gemini constraints', () {
    final schema = <String, dynamic>{
      'type': 'array',
      'minItems': 1,
      'maxItems': 3,
      'uniqueItems': true,
      'items': {
        'type': 'number',
        'minimum': 1,
        'maximum': 10,
        'exclusiveMinimum': 0,
        'exclusiveMaximum': 11,
        'default': 5,
        'title': 'Amount',
      },
    };

    expect(cleanSchemaForGemini(schema), schema);
  });
}
