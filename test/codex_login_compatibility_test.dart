import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../lib/core/models/provider_oauth.dart';
import '../lib/core/services/auth/oauth_cancellation.dart';
import '../lib/core/services/auth/provider_oauth_adapter.dart';

String _jwt(Map<String, dynamic> claims) {
  String encode(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${encode({'alg': 'none'})}.${encode(claims)}.test-signature';
}

Map<String, dynamic> _tokens({bool expiresIn = true}) => {
  'access_token': _jwt({
    'exp': 4102444800,
    'https://api.openai.com/auth': {
      'chatgpt_account_id': 'test-personal-account',
      'chatgpt_plan_type': 'pro',
    },
    'https://api.openai.com/profile': {'email': 'test@example.invalid'},
  }),
  'refresh_token': 'test-refresh-token',
  if (expiresIn) 'expires_in': 3600,
};

void main() {
  group('Codex ChatGPT subscription login', () {
    for (final field in ['user_code', 'usercode']) {
      test(
        'completes device login with $field and keeps the Pro plan',
        () async {
          final requests = <String>[];
          final prompts = <OAuthLoginPrompt>[];
          final client = MockClient((request) async {
            requests.add(request.url.path);
            expect(request.method, 'POST');
            expect(request.url.host, 'auth.openai.com');
            switch (request.url.path) {
              case '/api/accounts/deviceauth/usercode':
                expect(jsonDecode(request.body), {
                  'client_id': OAuthProvider.chatgpt.clientId,
                });
                return http.Response(
                  jsonEncode({
                    'device_auth_id': 'test-device-id',
                    field: 'TEST-CODE',
                    'interval': '1',
                  }),
                  200,
                );
              case '/api/accounts/deviceauth/token':
                expect(jsonDecode(request.body), {
                  'device_auth_id': 'test-device-id',
                  'user_code': 'TEST-CODE',
                });
                return http.Response(
                  jsonEncode({
                    'authorization_code': 'test-authorization-code',
                    'code_verifier': 'test-pkce-verifier',
                  }),
                  200,
                );
              case '/oauth/token':
                expect(request.bodyFields, {
                  'grant_type': 'authorization_code',
                  'client_id': OAuthProvider.chatgpt.clientId,
                  'code': 'test-authorization-code',
                  'code_verifier': 'test-pkce-verifier',
                  'redirect_uri': 'https://auth.openai.com/deviceauth/callback',
                });
                return http.Response(jsonEncode(_tokens()), 200);
              default:
                fail('Unexpected OAuth endpoint: ${request.url.path}');
            }
          });
          addTearDown(client.close);
          final credentials = await ChatGptOAuthAdapter().login(
            OAuthWire(client),
            OAuthCancellation(),
            (prompt) async => prompts.add(prompt),
          );
          expect(prompts, hasLength(1));
          expect(
            prompts.single.url.toString(),
            'https://auth.openai.com/codex/device',
          );
          expect(prompts.single.userCode, 'TEST-CODE');
          expect(credentials.plan, 'pro');
          expect(credentials.accountId, 'test-personal-account');
          expect(credentials.refreshToken, 'test-refresh-token');
          expect(requests, [
            '/api/accounts/deviceauth/usercode',
            '/api/accounts/deviceauth/token',
            '/oauth/token',
          ]);
        },
      );
    }

    test('accepts access-token exp when expires_in is absent', () {
      final credentials = ChatGptOAuthAdapter().credentials(
        _tokens(expiresIn: false),
      );
      expect(credentials.expiresAt.millisecondsSinceEpoch, 4102444800000);
      expect(credentials.plan, 'pro');
      expect(credentials.accountId, 'test-personal-account');
      expect(credentials.shouldRefresh(DateTime.utc(2026)), isFalse);
      expect(credentials.shouldRefresh(DateTime.utc(2100)), isTrue);
    });

    test(
      'refresh without expires_in keeps the session and rotates the token',
      () async {
        final adapter = ChatGptOAuthAdapter();
        final original = adapter.credentials(_tokens());
        final client = MockClient((request) async {
          expect(request.url.toString(), OAuthProvider.chatgpt.tokenEndpoint);
          expect(request.bodyFields['grant_type'], 'refresh_token');
          expect(request.bodyFields['refresh_token'], original.refreshToken);
          return http.Response(
            jsonEncode({
              ..._tokens(expiresIn: false),
              'refresh_token': 'test-rotated-refresh-token',
            }),
            200,
          );
        });
        addTearDown(client.close);
        final refreshed = await adapter.refresh(OAuthWire(client), original);
        expect(refreshed.sessionId, original.sessionId);
        expect(refreshed.refreshToken, 'test-rotated-refresh-token');
        expect(refreshed.plan, 'pro');
        expect(refreshed.expiresAt.millisecondsSinceEpoch, 4102444800000);
      },
    );

    test('still rejects credentials without any usable expiry', () {
      expect(
        () => ChatGptOAuthAdapter().credentials({
          'access_token': _jwt({
            'https://api.openai.com/auth': {
              'chatgpt_account_id': 'test-account',
            },
          }),
          'refresh_token': 'test-refresh-token',
        }),
        throwsA(
          isA<ProviderOAuthException>().having(
            (error) => error.kind,
            'kind',
            ProviderOAuthFailure.invalidResponse,
          ),
        ),
      );
    });

    test('does not infer Pro from the selected provider', () {
      final credentials = ChatGptOAuthAdapter().credentials({
        'access_token': _jwt({
          'exp': 4102444800,
          'https://api.openai.com/auth': {'chatgpt_account_id': 'test-account'},
        }),
        'refresh_token': 'test-refresh-token',
        'expires_in': 3600,
      });
      expect(credentials.plan, isNull);
    });
  });
}
