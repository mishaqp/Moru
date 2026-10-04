import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_client/mcp_client.dart' as mcp;

import 'package:Kelivo/core/providers/mcp_provider.dart';
import 'package:Kelivo/core/services/mcp/mcp_tool_privacy.dart';

import '../../../support/business_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('explicit credential containers reject and mask literal payloads', () {
    final provider = _Provider(
      McpServerConfig(
        id: 'server',
        name: 'Server',
        enabled: true,
        transport: McpTransportType.http,
      ),
    );
    addTearDown(provider.dispose);
    final privacy = McpToolPrivacy(provider);
    for (final args in <Map<String, dynamic>>[
      {
        'cookies': [
          {'name': 'session', 'value': 'opaque-private-cookie'},
        ],
      },
      {
        'cookies': {'session': 'opaque-private-cookie'},
      },
      {
        'credentials': {'username': 'user', 'value': 'opaque-private-cookie'},
      },
    ]) {
      expect(privacy.containsCredential(args), isTrue);
      expect(
        privacy.argumentsForModel(args).toString(),
        isNot(contains('opaque-private-cookie')),
      );
      expect(privacy.text('opaque-private-cookie'), 'opaque-private-cookie');
    }
    for (final args in <Map<String, dynamic>>[
      {'cookies': []},
      {'cookies': {}},
      {
        'credentials': {'value': ''},
      },
      {
        'credentials': {'value': '{{TOKEN}}'},
      },
    ]) {
      expect(privacy.containsCredential(args), isFalse);
      expect(privacy.argumentsForModel(args), args);
    }
  });

  test(
    'safe private placeholders stay intact in model configuration copies',
    () {
      final provider = _Provider(
        McpServerConfig(
          id: 'server',
          name: 'Server',
          enabled: true,
          transport: McpTransportType.http,
        ),
      );
      addTearDown(provider.dispose);
      final privacy = McpToolPrivacy(provider);
      final args = {
        'action': 'add',
        'config': {
          'args': ['--token', '{{TOKEN}}', '--token={{TOKEN}}'],
          'url': 'https://example.test/mcp?token={{TOKEN}}',
        },
      };
      expect(privacy.managerArgumentsForModel(args), args);
      expect(privacy.containsKnownCredential(args), isFalse);
    },
  );

  test('manager protocol controls survive coincidental short credentials', () {
    final provider = _Provider(
      McpServerConfig(
        id: 'server-a',
        name: 'Server',
        enabled: true,
        transport: McpTransportType.http,
        headers: {'Authorization': 'a'},
      ),
    );
    addTearDown(provider.dispose);
    final privacy = McpToolPrivacy(provider);
    final safe = privacy.managerArgumentsForModel(
      {
        'action': 'update',
        'server_id': 'server-a',
        'assistant_id': 'assistant-a',
        'config': {
          'type': 'http',
          'workspaceId': 'workspace-a',
          'env': {'TOKEN': 'a'},
        },
      },
      publicIds: ['assistant-a', 'workspace-a'],
    );
    expect(safe['action'], 'update');
    expect(safe['server_id'], 'server-a');
    expect(safe['assistant_id'], 'assistant-a');
    expect((safe['config'] as Map)['type'], 'http');
    expect((safe['config'] as Map)['workspaceId'], 'workspace-a');
    expect((safe['config'] as Map)['env'].toString(), isNot(contains('a')));
  });

  for (final route in ['object', 'tools', 'text', 'content']) {
    test('ordinary endpoint /$route preserves schema and result protocol', () {
      final provider = _Provider(
        McpServerConfig(
          id: 'server',
          name: 'Server',
          enabled: true,
          transport: McpTransportType.http,
          url: 'https://example.test/$route',
          headers: {'Authorization': 'configured-private-value'},
        ),
      );
      addTearDown(provider.dispose);
      final privacy = McpToolPrivacy(provider);
      final tool = privacy.tool(
        McpToolConfig(
          name: 'lookup',
          enabled: true,
          description: 'ordinary $route configured-private-value',
          schema: {
            'type': 'object',
            'properties': {
              'tools': {'type': 'string', 'default': 'business'},
            },
            'required': ['tools'],
          },
          params: [
            McpParamSpec(
              name: 'tools',
              required: true,
              type: 'string',
              defaultValue: 'business',
            ),
          ],
        ),
      );
      expect(tool.schema, {
        'type': 'object',
        'properties': {
          'tools': {'type': 'string', 'default': 'business'},
        },
        'required': ['tools'],
      });
      expect(tool.description, contains('ordinary $route'));
      expect(tool.description, isNot(contains('configured-private-value')));
      expect(tool.params.single.name, 'tools');
      expect(
        privacy
            .result(
              mcp.CallToolResult([mcp.TextContent(text: 'ordinary $route')]),
            )
            .content
            .single,
        isA<mcp.TextContent>(),
      );
      expect(
        (privacy
                    .result(
                      mcp.CallToolResult([
                        mcp.TextContent(text: 'ordinary $route'),
                      ]),
                    )
                    .content
                    .single
                as mcp.TextContent)
            .text,
        'ordinary $route',
      );
    });
  }

  for (final ordinary in [
    '/home/alice/x.json',
    ' 1',
    ' { "key": "invoice-5", "code": "product-7", "session": "afternoon" } ',
    'keyword=term',
    'author=Alice',
  ]) {
    test('business text remains byte-for-byte ordinary: $ordinary', () {
      final provider = _Provider(
        McpServerConfig(
          id: 'server',
          name: 'Server',
          enabled: true,
          transport: McpTransportType.http,
          headers: {'Authorization': 'configured-private-value'},
        ),
      );
      addTearDown(provider.dispose);
      final privacy = McpToolPrivacy(provider);
      expect(privacy.text(ordinary), ordinary);
      expect(privacy.containsCredential({'query': ordinary}), isFalse);
      expect(privacy.argumentsForModel({'query': ordinary}), {
        'query': ordinary,
      });
      final output = privacy.result(
        mcp.CallToolResult([mcp.TextContent(text: ordinary)]),
      );
      expect((output.content.single as mcp.TextContent).text, ordinary);
    });
  }

  test(
    'manager import JSON auth values are masked while business JSON is preserved',
    () {
      final provider = _Provider(
        McpServerConfig(
          id: 'server',
          name: 'Server',
          enabled: true,
          transport: McpTransportType.http,
        ),
      );
      addTearDown(provider.dispose);
      final privacy = McpToolPrivacy(provider);
      final args = {
        'action': 'import',
        'json':
            '{"mcpServers":{"remote":{"url":"https://example.test/mcp","headers":{"Authorization":"opaque-private-literal"},"env":{"LANG":"en_US"}}}}',
      };
      final safe = privacy.argumentsForModel(args);
      expect(safe['json'], isNot(contains('opaque-private-literal')));
      expect(safe['json'], contains('en_US'));
      expect(args['json'], contains('opaque-private-literal'));
    },
  );

  test(
    'unrelated valid binary media survives short credential substring coincidences',
    () {
      final provider = _Provider(
        McpServerConfig(
          id: 'server',
          name: 'Server',
          enabled: true,
          transport: McpTransportType.http,
          headers: {'Authorization': 'A'},
        ),
      );
      addTearDown(provider.dispose);
      final privacy = McpToolPrivacy(provider);
      final result = privacy.result(
        const mcp.CallToolResult([
          mcp.ImageContent(data: 'AQIDBA==', mimeType: 'image/png'),
          mcp.AudioContent(data: 'AQIDBA==', mimeType: 'audio/wav'),
          mcp.ResourceContent(
            uri: 'resource://business',
            blob: 'AQIDBA==',
            mimeType: 'application/octet-stream',
          ),
        ]),
      );
      expect((result.content[0] as mcp.ImageContent).data, 'AQIDBA==');
      expect((result.content[1] as mcp.AudioContent).data, 'AQIDBA==');
      expect((result.content[2] as mcp.ResourceContent).blob, 'AQIDBA==');
      expect(
        privacy.text('Bearer unrelated-private-value'),
        isNot(contains('A')),
      );
    },
  );

  test(
    'structured auth payloads and defaults are masked like JSON-string auth payloads',
    () {
      final provider = _Provider(
        McpServerConfig(
          id: 'server',
          name: 'Server',
          enabled: true,
          transport: McpTransportType.http,
        ),
      );
      addTearDown(provider.dispose);
      final privacy = McpToolPrivacy(provider);
      final tool = privacy.tool(
        McpToolConfig(
          name: 'lookup',
          enabled: true,
          schema: {
            'type': 'object',
            'properties': {
              'value': {
                'type': 'object',
                'default': {
                  'api_key': 'opaque-private-value',
                  'key': 'business-key',
                },
              },
            },
          },
        ),
      );
      expect(
        tool.schema!['properties']['value']['default']['api_key'],
        isNot('opaque-private-value'),
      );
      expect(
        tool.schema!['properties']['value']['default']['key'],
        'business-key',
      );
      final result = privacy.result(
        const mcp.CallToolResult(
          [
            mcp.TextContent(
              text: 'business',
              annotations: {
                'token': 'opaque-private-value',
                'key': 'business-key',
              },
            ),
          ],
          structuredContent: {
            'api_key': 'opaque-private-value',
            'key': 'business-key',
          },
        ),
      );
      expect(
        result.structuredContent!['api_key'],
        isNot('opaque-private-value'),
      );
      expect(result.structuredContent!['key'], 'business-key');
      expect(
        (result.content.single as mcp.TextContent).annotations!['token'],
        isNot('opaque-private-value'),
      );
    },
  );

  test(
    'documented Zapier endpoint credentials stay private without hiding route words',
    () {
      final provider = _Provider(
        McpServerConfig(
          id: 'server',
          name: 'Server',
          enabled: true,
          transport: McpTransportType.http,
          url: 'https://mcp.zapier.com/api/mcp/opaqueRandomCredential',
          managedSecrets: {'url:3': 'opaqueRandomCredential'},
        ),
      );
      addTearDown(provider.dispose);
      final privacy = McpToolPrivacy(provider);
      expect(
        privacy.text(
          'endpoint https://mcp.zapier.com/api/mcp/opaqueRandomCredential',
        ),
        isNot(contains('opaqueRandomCredential')),
      );
      expect(
        privacy.text('ordinary api mcp object tools'),
        'ordinary api mcp object tools',
      );
      expect(
        privacy.containsCredential({'value': 'opaqueRandomCredential'}),
        isTrue,
      );
    },
  );

  for (final credential in ['text', 'content', 'object', 'string']) {
    test(
      'credential equal to protocol word $credential keeps structural controls intact',
      () {
        final provider = _Provider(
          McpServerConfig(
            id: 'server',
            name: 'Server',
            enabled: true,
            transport: McpTransportType.http,
            headers: {'Authorization': credential},
          ),
        );
        addTearDown(provider.dispose);
        final privacy = McpToolPrivacy(provider);
        final result = privacy.result(
          mcp.CallToolResult(
            [mcp.TextContent(text: 'private $credential')],
            structuredContent: {'business': credential},
            isError: true,
          ),
        );
        expect(result.content.single, isA<mcp.TextContent>());
        expect(
          (result.content.single as mcp.TextContent).text,
          isNot(contains(credential)),
        );
        expect(result.structuredContent!['business'], isNot(credential));
        expect(result.isError, isTrue);
        final tool = privacy.tool(
          McpToolConfig(
            name: 'lookup',
            enabled: true,
            schema: {
              'type': 'object',
              'properties': {
                'value': {'type': 'string', 'default': credential},
              },
            },
            params: [
              McpParamSpec(
                name: 'value',
                required: true,
                type: 'string',
                defaultValue: credential,
              ),
            ],
          ),
        );
        expect(tool.schema!['type'], 'object');
        expect(tool.schema!['properties']['value']['type'], 'string');
        expect(
          tool.schema!['properties']['value']['default'],
          isNot(credential),
        );
        expect(tool.params.single.type, 'string');
        expect(tool.params.single.defaultValue, isNot(credential));
      },
    );
  }
}

class _Provider extends McpProvider {
  _Provider(this.server) : super(preferences: createBusinessTestPreferences());
  final McpServerConfig server;
  @override
  List<McpServerConfig> get servers => [server];
}
