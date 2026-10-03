import 'dart:convert';

import 'package:Kelivo/core/models/provider_oauth.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/api/providers/openai/openai_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  for (final (upstreamModelId, expectedEffort) in const [
    ('gpt-6.1-sol', 'low'),
    ('gpt-6-sol', 'low'),
    ('gpt-6-luna', 'low'),
    ('gpt-5.5', 'none'),
  ]) {
    test(
      'ChatGPT utility requests use $expectedEffort when $upstreamModelId reasoning is off',
      () async {
        final requests = <http.Request>[];
        final client = MockClient((request) async {
          requests.add(request);
          return http.Response(
            'data: ${jsonEncode({
              'type': 'response.completed',
              'response': {'output': []},
            })}\n\n',
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        });
        addTearDown(client.close);
        final config = ProviderConfig(
          id: 'ChatGPT',
          enabled: true,
          name: 'ChatGPT',
          apiKey: 'test-key',
          baseUrl: 'https://chatgpt.com/backend-api/codex',
          providerType: ProviderKind.openai,
          useResponseApi: true,
          oauthProvider: OAuthProvider.chatgpt,
          modelOverrides: {
            'utility-model': {'apiModelId': upstreamModelId},
          },
        );

        await sendOpenAIStream(
          client,
          config,
          'utility-model',
          [
            {'role': 'user', 'content': 'Generate a short title'},
          ],
          thinkingBudget: 0,
          builtInSearchOnly: true,
        ).drain<void>();

        expect(requests, hasLength(1));
        final request = requests.single;
        expect(request.method, 'POST');
        expect(
          request.url,
          Uri.parse('https://chatgpt.com/backend-api/codex/responses'),
        );
        final body = jsonDecode(request.body) as Map;
        expect(body['model'], upstreamModelId);
        expect(body['reasoning'], {'effort': expectedEffort});
      },
    );
  }
}
