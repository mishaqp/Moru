/// Representative MCP source schemas, not provider-shaped schemas.
const mcpToolSchemaFixtures = <String, Map<String, dynamic>>{
  'nullable_and_unions': {
    'type': 'object',
    'properties': {
      'label': {
        'type': ['string', 'null'],
        'enum': ['a', 'b', null],
      },
      'legacy': {'type': 'integer', 'nullable': true, 'minimum': 1},
      'choice': {
        'anyOf': [
          {'type': 'string', 'pattern': '^x'},
          {'type': 'integer', 'minimum': 2},
          {'type': 'null'},
        ],
      },
      'exclusive': {
        'oneOf': [
          {'type': 'boolean'},
          {'type': 'string'},
        ],
      },
    },
  },
  'sequential_thinking': {
    'type': 'object',
    'properties': {
      'thought': {'type': 'string', 'minLength': 1, 'maxLength': 1000},
      'thoughtNumber': {'type': 'integer', 'minimum': 1, 'maximum': 100},
      'totalThoughts': {'type': 'integer', 'minimum': 1},
      'nextThoughtNeeded': {'type': 'boolean'},
      'isRevision': {'type': 'boolean'},
    },
    'required': [
      'thought',
      'thoughtNumber',
      'totalThoughts',
      'nextThoughtNeeded',
    ],
    'additionalProperties': false,
  },
  'nested_refs': {
    'type': 'object',
    r'$defs': {
      'Row': {
        'type': 'object',
        'properties': {
          'id': {'type': 'integer', 'minimum': 1},
          'mode': {
            'type': 'string',
            'enum': ['read', 'write'],
          },
          'note': {'type': 'string', 'pattern': r'^[a-z]+$'},
        },
        'required': ['id'],
        'additionalProperties': false,
      },
    },
    'properties': {
      'rows': {
        'type': 'array',
        'minItems': 1,
        'maxItems': 4,
        'items': {r'$ref': r'#/$defs/Row'},
      },
      'selected': {
        'anyOf': [
          {r'$ref': r'#/$defs/Row'},
          {'type': 'null'},
        ],
      },
    },
    'required': ['rows'],
  },
  'dictionaries_and_empty_objects': {
    'type': 'object',
    'properties': {
      'empty': {
        'type': 'object',
        'properties': {},
        'additionalProperties': false,
      },
      'free': {'type': 'object', 'additionalProperties': true},
      'scores': {
        'type': 'object',
        'additionalProperties': {'type': 'number', 'minimum': 0, 'maximum': 1},
      },
    },
  },
  'enums': {
    'type': 'object',
    'properties': {
      'number': {
        'type': 'integer',
        'enum': [1, 2],
      },
      'boolean': {
        'type': 'boolean',
        'enum': [true, false],
      },
      'untyped': {
        'enum': ['a', 1, true, null],
      },
      'constant': {'const': 3},
    },
  },
  'conjunction': {
    'type': 'object',
    'properties': {
      'value': {
        'allOf': [
          {'type': 'number', 'minimum': 1},
          {'type': 'number', 'maximum': 10},
        ],
      },
    },
  },
  'no_arguments': {'type': 'object', 'properties': {}},
  'boolean_schemas_and_tuple': {
    'type': 'object',
    'properties': {
      'never': false,
      'anything': true,
      'emptyArray': {'type': 'array', 'items': false},
      'tuple': {
        'type': 'array',
        'items': [
          {'type': 'string'},
          {'type': 'integer'},
        ],
        'additionalItems': false,
      },
      'choice': {
        'anyOf': [
          false,
          {'type': 'string'},
          true,
        ],
      },
    },
  },
};
