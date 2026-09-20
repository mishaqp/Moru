import 'dart:convert';
import 'dart:io';

import 'package:Kelivo/core/providers/model_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/api/provider_request_headers.dart';
import 'package:Kelivo/core/services/auth/oauth_pkce.dart';
import 'package:Kelivo/core/services/auth/openrouter_oauth_callback.dart';
import 'package:Kelivo/core/services/auth/provider_oauth_adapter.dart';
import 'package:Kelivo/core/services/auth/provider_oauth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../../support/business_test_harness.dart';

class _RealHttpOverrides extends HttpOverrides {}

/// Sends a plain loopback GET, exactly like a real browser redirect would,
/// bypassing the test's mocked http.Client (which never touches the network).
Future<int> sendLoopbackCallback(Uri uri) async {
  final client = HttpOverrides.runWithHttpOverrides(
    HttpClient.new,
    _RealHttpOverrides(),
  )..findProxy = (_) => 'DIRECT';
  try {
    final request = await client.getUrl(uri);
    final response = await request.close().timeout(const Duration(seconds: 2));
    await response.drain<void>();
    return response.statusCode;
  } finally {
    client.close(force: true);
  }
}

http.Response response(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

ProviderOAuthCredentials openRouterCredentials({
  String accessToken = 'sk-or-v1-access',
}) => ProviderOAuthCredentials(
  accessToken: accessToken,
  refreshToken: null,
  expiresAt: null,
  sessionId: 'session',
);

ProviderConfig openRouterConfig() => ProviderConfig(
  id: 'openrouter-account',
  enabled: true,
  name: 'OpenRouter',
  apiKey: '',
  baseUrl: OAuthProvider.openrouter.baseUrl,
  providerType: ProviderKind.openai,
  oauthProvider: OAuthProvider.openrouter,
  oauthCredentials: openRouterCredentials(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SettingsProvider settings;
  setUp(() async {
    final harness = await createBusinessTestHarness();
    settings = SettingsProvider(harness.preferences);
    await settings.loaded;
  });
  tearDown(() => settings.dispose());

  test(
    'OpenRouter authorize URL has exactly the documented params and no state',
    () async {
      late OAuthLoginPrompt prompt;
      await OpenRouterOAuthAdapter().login(
        OAuthWire(
          MockClient(
            (_) async => response({'key': 'sk-or-v1-x', 'user_id': 'user_x'}),
          ),
        ),
        OAuthCancellation(),
        (value) async {
          prompt = value;
          expect(prompt.url.origin, 'https://openrouter.ai');
          expect(prompt.url.path, '/auth');
          expect(prompt.url.queryParameters.keys.toSet(), {
            'callback_url',
            'code_challenge',
            'code_challenge_method',
            'key_label',
          });
          expect(prompt.url.queryParameters['code_challenge_method'], 'S256');
          expect(prompt.url.queryParameters.containsKey('state'), isFalse);
          expect(prompt.url.queryParametersAll['state'], isNull);
          expect(prompt.browserAuthorization, isTrue);
          prompt.submitAuthorizationCode!('does-not-matter');
        },
      );
    },
  );

  test('OpenRouter browser login completes through the loopback callback and '
      'exchanges the documented body shape', () async {
    final requests = <http.Request>[];
    late OAuthLoginPrompt prompt;
    final result = await OpenRouterOAuthAdapter().login(
      OAuthWire(
        MockClient((request) async {
          requests.add(request);
          return response({'key': 'sk-or-v1-test', 'user_id': 'user_abc'});
        }),
      ),
      OAuthCancellation(),
      (value) async => prompt = value,
      launcher: (url) async {
        final redirect = Uri.parse(url.queryParameters['callback_url']!);
        final status = await sendLoopbackCallback(
          redirect.replace(queryParameters: {'code': 'auth-code-1'}),
        );
        expect(status, HttpStatus.ok);
        return true;
      },
    );
    expect(requests, hasLength(1));
    expect(
      requests.single.url.toString(),
      OAuthProvider.openrouter.tokenEndpoint,
    );
    expect(
      requests.single.headers['content-type'],
      contains('application/json'),
    );
    final body = jsonDecode(requests.single.body) as Map;
    expect(body['code'], 'auth-code-1');
    expect(body['code_challenge_method'], 'S256');
    expect(body.containsKey('client_id'), isFalse);
    expect(
      oauthPkceChallenge(body['code_verifier'] as String),
      prompt.url.queryParameters['code_challenge'],
    );
    expect(result.accessToken, 'sk-or-v1-test');
    expect(result.accountId, 'user_abc');
    expect(result.refreshToken, isNull);
    expect(result.expiresAt, isNull);
    expect(result.requiresLogin, isFalse);
    expect(result.sessionId, isNotEmpty);
  });

  for (final asBareCode in [true, false]) {
    test(
      'OpenRouter manual code paste completes the exchange like the loopback '
      'path (asBareCode=$asBareCode)',
      () async {
        final requests = <http.Request>[];
        final result = await OpenRouterOAuthAdapter().login(
          OAuthWire(
            MockClient((request) async {
              requests.add(request);
              return response({
                'key': 'sk-or-v1-manual',
                'user_id': 'user_manual',
              });
            }),
          ),
          OAuthCancellation(),
          (prompt) async {
            final input = asBareCode
                ? 'manual-code'
                : Uri.parse(prompt.url.queryParameters['callback_url']!)
                      .replace(queryParameters: {'code': 'manual-code'})
                      .toString();
            expect(prompt.submitAuthorizationCode!(input), isTrue);
          },
          launcher: (_) async =>
              throw StateError('manual entry already completed'),
        );
        expect(result.accessToken, 'sk-or-v1-manual');
        expect(jsonDecode(requests.single.body)['code'], 'manual-code');
      },
    );
  }

  test('OpenRouter loopback callback rejects a mismatched nonce path but '
      'accepts the correct one', () async {
    final callback = await OpenRouterOAuthCallback.bind();
    addTearDown(callback.close);
    final wrongPath = callback.redirectUri.replace(
      path: '${callback.redirectUri.path}-wrong',
    );
    final stolen = await sendLoopbackCallback(
      wrongPath.replace(queryParameters: {'code': 'stolen'}),
    );
    expect(stolen, HttpStatus.notFound);
    final ok = await sendLoopbackCallback(
      callback.redirectUri.replace(queryParameters: {'code': 'real-code'}),
    );
    expect(ok, HttpStatus.ok);
    final result = await callback.waitForCallback(const Duration(seconds: 2));
    expect(result.queryParameters['code'], 'real-code');
  });

  test(
    'a stale nonce delivered to a fresh OpenRouter login attempt is rejected, '
    'not accepted',
    () async {
      final requests = <http.Request>[];
      var staleStatus = -1;
      final result = await OpenRouterOAuthAdapter().login(
        OAuthWire(
          MockClient((request) async {
            requests.add(request);
            return response({'key': 'sk-or-v1-fresh', 'user_id': 'user_y'});
          }),
        ),
        OAuthCancellation(),
        (_) async {},
        launcher: (url) async {
          final redirect = Uri.parse(url.queryParameters['callback_url']!);
          // A callback from a different (e.g. earlier, cancelled) attempt
          // never matches this attempt's freshly generated nonce path.
          staleStatus = await sendLoopbackCallback(
            redirect.replace(
              path: '/oauth/callback/not-the-real-nonce',
              queryParameters: {'code': 'stolen-code'},
            ),
          );
          final status = await sendLoopbackCallback(
            redirect.replace(queryParameters: {'code': 'fresh-code'}),
          );
          expect(status, HttpStatus.ok);
          return true;
        },
      );
      expect(staleStatus, HttpStatus.notFound);
      expect(result.accessToken, 'sk-or-v1-fresh');
      expect(jsonDecode(requests.single.body)['code'], 'fresh-code');
    },
  );

  test(
    'OpenRouter surfaces a denial only when an error callback is delivered',
    () async {
      var exchanged = false;
      final login = OpenRouterOAuthAdapter().login(
        OAuthWire(
          MockClient((_) async {
            exchanged = true;
            return response({'key': 'sk-or-v1-x', 'user_id': 'user_x'});
          }),
        ),
        OAuthCancellation(),
        (_) async {},
        launcher: (url) async {
          final redirect = Uri.parse(url.queryParameters['callback_url']!);
          await sendLoopbackCallback(
            redirect.replace(queryParameters: {'error': 'access_denied'}),
          );
          return true;
        },
      );
      await expectLater(
        login.timeout(const Duration(seconds: 3)),
        throwsA(
          isA<ProviderOAuthException>().having(
            (error) => error.kind,
            'kind',
            ProviderOAuthFailure.denied,
          ),
        ),
      );
      expect(exchanged, isFalse);
    },
  );

  for (final status in [400, 403, 500]) {
    test('OpenRouter exchange failure HTTP $status is surfaced without a '
        'loginRequired classification', () async {
      await expectLater(
        OpenRouterOAuthAdapter().login(
          OAuthWire(
            MockClient(
              (_) async => response({
                'message': status == 403
                    ? 'Only management keys can perform this operation'
                    : 'invalid params',
              }, status),
            ),
          ),
          OAuthCancellation(),
          (prompt) async {
            prompt.submitAuthorizationCode!('code');
          },
        ),
        throwsA(
          isA<ProviderOAuthException>()
              .having(
                (e) => e.kind,
                'kind',
                isNot(ProviderOAuthFailure.loginRequired),
              )
              .having((e) => e.statusCode, 'status', status),
        ),
      );
    });
  }

  test(
    'a mid-login exchange failure never leaks the code, verifier or issued key',
    () async {
      const code = 'super-secret-auth-code-zzz';
      const leakedKey = 'sk-or-v1-should-not-leak';
      String? verifier;
      Object? failure;
      try {
        await OpenRouterOAuthAdapter().login(
          OAuthWire(
            MockClient((request) async {
              final body = jsonDecode(request.body) as Map;
              verifier = body['code_verifier'] as String;
              return response({
                'message':
                    'invalid code=$code verifier=$verifier key=$leakedKey',
              }, 400);
            }),
          ),
          OAuthCancellation(),
          (prompt) async {
            prompt.submitAuthorizationCode!(code);
          },
        );
      } catch (e) {
        failure = e;
      }
      expect(failure, isA<ProviderOAuthException>());
      expect(verifier, isNotNull);
      final text = failure.toString();
      expect(text, isNot(contains(code)));
      expect(text, isNot(contains(verifier!)));
      expect(text, isNot(contains(leakedKey)));
      final asException = failure as ProviderOAuthException;
      expect(asException.message ?? '', isNot(contains(code)));
      expect(asException.message ?? '', isNot(contains(verifier!)));
      expect(asException.message ?? '', isNot(contains(leakedKey)));
      expect(asException.code ?? '', isNot(contains(code)));
    },
  );

  test('OpenRouter credentials mapping requires a non-empty issued key', () {
    expect(
      () => OpenRouterOAuthAdapter().credentials({'user_id': 'user_x'}),
      throwsA(
        isA<ProviderOAuthException>().having(
          (e) => e.kind,
          'kind',
          ProviderOAuthFailure.invalidResponse,
        ),
      ),
    );
    expect(
      () => OpenRouterOAuthAdapter().credentials({'key': ''}),
      throwsA(isA<ProviderOAuthException>()),
    );
  });

  test(
    'OpenRouter refresh never calls the network and always requires login',
    () async {
      var calls = 0;
      final wire = OAuthWire(
        MockClient((_) async {
          calls++;
          return response({});
        }),
      );
      await expectLater(
        OpenRouterOAuthAdapter().refresh(wire, openRouterCredentials()),
        throwsA(
          isA<ProviderOAuthException>().having(
            (e) => e.kind,
            'kind',
            ProviderOAuthFailure.loginRequired,
          ),
        ),
      );
      expect(calls, 0);
    },
  );

  test('OpenRouter models excludes Jev and non-text rows, sends '
      'output_modalities=text, and follows links.next pagination', () async {
    final requests = <Uri>[];
    final result = await OpenRouterOAuthAdapter().models(
      OAuthWire(
        MockClient((request) async {
          requests.add(request.url);
          if (requests.length == 1) {
            expect(request.url.path, '/api/v1/models/user');
            expect(request.url.queryParameters['output_modalities'], 'text');
            expect(request.headers['authorization'], 'Bearer sk-or-v1-access');
            return response({
              'data': [
                {
                  'id': 'openai/gpt-4o',
                  'name': 'GPT-4o',
                  'architecture': {
                    'input_modalities': ['text', 'image'],
                    'output_modalities': ['text'],
                    'modality': 'text+image->text',
                  },
                  'supported_parameters': ['temperature', 'tools', 'reasoning'],
                },
                {
                  'id': 'openrouter/jev',
                  'name': 'Jev',
                  'architecture': {
                    'input_modalities': ['text'],
                    'output_modalities': ['text', 'decisions'],
                  },
                },
                {
                  'id': 'openrouter/jev-alpha',
                  'name': 'Jev alpha',
                  'architecture': {
                    'input_modalities': ['text'],
                    'output_modalities': ['decisions'],
                  },
                },
                {
                  'id': 'stability/sdxl',
                  'name': 'SDXL',
                  'architecture': {
                    'input_modalities': ['text'],
                    'output_modalities': ['image'],
                  },
                },
                {
                  'id': 'openai/text-embedding-3',
                  'name': 'Embed',
                  'architecture': {
                    'input_modalities': ['text'],
                    'output_modalities': ['embeddings'],
                  },
                },
              ],
              'total_count': 5,
              'links': {
                'next':
                    'https://openrouter.ai/api/v1/models/user?output_modalities=text&limit=1000&offset=1000',
              },
            });
          }
          expect(request.url.toString(), contains('offset=1000'));
          return response({
            'data': [
              {
                'id': 'anthropic/claude-4',
                'name': 'Claude 4',
                'architecture': {
                  'input_modalities': ['text'],
                  'output_modalities': ['text'],
                },
                'supported_parameters': <String>[],
              },
            ],
            'total_count': 5,
            'links': {'next': null},
          });
        }),
      ),
      openRouterCredentials(),
    );
    expect(requests, hasLength(2));
    expect(result.map((m) => m['id']), ['openai/gpt-4o', 'anthropic/claude-4']);
    final gpt = result.first;
    expect(gpt['display_name'], 'GPT-4o');
    expect(gpt['input_modalities'], ['text', 'image']);
    expect(gpt['supports_image_in'], isTrue);
    expect(gpt['supports_reasoning'], isTrue);
    final claude = result.last;
    expect(claude['display_name'], 'Claude 4');
    expect(claude['supports_image_in'], isFalse);
    expect(claude['supports_reasoning'], isFalse);
  });

  test(
    'OpenRouter models pagination bails out defensively on a repeating cursor',
    () async {
      const next = 'https://openrouter.ai/api/v1/models/user?offset=1000';
      await expectLater(
        OpenRouterOAuthAdapter().models(
          OAuthWire(
            MockClient(
              (_) async => response({
                'data': <Map<String, dynamic>>[],
                'links': {'next': next},
              }),
            ),
          ),
          openRouterCredentials(),
        ),
        throwsA(
          isA<ProviderOAuthException>().having(
            (e) => e.kind,
            'kind',
            ProviderOAuthFailure.invalidResponse,
          ),
        ),
      );
    },
  );

  test(
    'OpenRouter usage parses limit, usage and rate limit into a credits window',
    () async {
      final usage = await OpenRouterOAuthAdapter().usage(
        OAuthWire(
          MockClient((request) async {
            expect(request.url.path, '/api/v1/key');
            expect(request.headers['authorization'], 'Bearer sk-or-v1-access');
            return response({
              'data': {
                'label': 'Moru key',
                'limit': 100.0,
                'limit_remaining': 40.0,
                'usage': 60.0,
                'is_free_tier': false,
                'rate_limit': {
                  'requests': 200,
                  'interval': '10s',
                  'note': 'per interval',
                },
              },
            });
          }),
        ),
        openRouterCredentials(),
      );
      expect(usage.windows, hasLength(1));
      final window = usage.windows.single;
      expect(window.id, 'credits');
      expect(window.unit, 'usd');
      expect(window.used, 60.0);
      expect(window.limit, 100.0);
      expect(window.usedPercent, 60.0);
      expect(usage.plan, isNull);
      expect(usage.resetCredits, isNull);
      expect(usage.hasData, isTrue);
    },
  );

  test(
    'OpenRouter usage handles a null limit (unlimited/BYOK key) without crashing',
    () async {
      final usage = await OpenRouterOAuthAdapter().usage(
        OAuthWire(
          MockClient(
            (_) async => response({
              'data': {'limit': null, 'limit_remaining': null, 'usage': 12.5},
            }),
          ),
        ),
        openRouterCredentials(),
      );
      expect(usage.hasData, isTrue);
      final window = usage.windows.single;
      expect(window.used, 12.5);
      expect(window.limit, isNull);
      expect(window.usedPercent, isNull);
    },
  );

  test(
    'ProviderOAuthCredentials round-trips with and without refreshToken/expiresAt',
    () {
      final withBoth = ProviderOAuthCredentials(
        accessToken: 'a',
        refreshToken: 'r',
        expiresAt: DateTime.utc(2026, 1, 1),
        sessionId: 's',
      );
      final roundTripped = ProviderOAuthCredentials.fromJson(withBoth.toJson());
      expect(roundTripped.refreshToken, 'r');
      expect(roundTripped.expiresAt, DateTime.utc(2026, 1, 1));
      expect(withBoth.toJson()['refreshToken'], 'r');
      expect(withBoth.toJson()['expiresAt'], isNotNull);

      final withoutEither = ProviderOAuthCredentials(
        accessToken: 'a',
        refreshToken: null,
        expiresAt: null,
        sessionId: 's',
      );
      final json = withoutEither.toJson();
      expect(json.containsKey('refreshToken'), isFalse);
      expect(json.containsKey('expiresAt'), isFalse);
      final restored = ProviderOAuthCredentials.fromJson(json);
      expect(restored.refreshToken, isNull);
      expect(restored.expiresAt, isNull);
      expect(restored.shouldRefresh(DateTime.now()), isFalse);
      expect(restored.copyWith().refreshToken, isNull);
      expect(restored.copyWith().expiresAt, isNull);
    },
  );

  test(
    'ProviderOAuthService.login stores an OpenRouter OAuth provider config',
    () async {
      final service = ProviderOAuthService(
        clientFactory: (_) => MockClient(
          (_) async => response({'key': 'sk-or-v1-e2e', 'user_id': 'user_e2e'}),
        ),
      )..bind(settings);
      final created = await service.login(
        provider: OAuthProvider.openrouter,
        cancellation: OAuthCancellation(),
        onPrompt: (prompt) {
          prompt.submitAuthorizationCode!('code-e2e');
        },
      );
      expect(created.oauthProvider, OAuthProvider.openrouter);
      expect(created.providerType, ProviderKind.openai);
      expect(created.baseUrl, OAuthProvider.openrouter.baseUrl);
      expect(created.oauthCredentials!.accessToken, 'sk-or-v1-e2e');
      expect(created.oauthCredentials!.accountId, 'user_e2e');
      expect(created.oauthCredentials!.refreshToken, isNull);
      expect(created.oauthCredentials!.expiresAt, isNull);
      expect(created.oauthCredentials!.requiresLogin, isFalse);
      expect(isOpenRouterProvider(created), isTrue);
      expect(providerDefaultHeaders(created)['X-OpenRouter-Title'], isNotNull);
      final restored = ProviderConfig.fromJson(
        jsonDecode(jsonEncode(created.toJson())) as Map<String, dynamic>,
      );
      expect(restored.oauthProvider, OAuthProvider.openrouter);
      expect(restored.oauthCredentials!.refreshToken, isNull);
      expect(restored.oauthCredentials!.expiresAt, isNull);
    },
  );

  test(
    'resolve never refreshes an OpenRouter session because it never expires',
    () async {
      var calls = 0;
      final service = ProviderOAuthService(
        clientFactory: (_) => MockClient((_) async {
          calls++;
          return response({});
        }),
      )..bind(settings);
      final config = openRouterConfig();
      await settings.setProviderConfig(config.id, config);
      final resolved = await service.resolve(config);
      expect(resolved.apiKey, 'sk-or-v1-access');
      expect(calls, 0);
    },
  );

  test(
    'a 401 from a live OpenRouter request marks login required in one attempt',
    () async {
      final service = ProviderOAuthService()..bind(settings);
      final config = openRouterConfig();
      await settings.setProviderConfig(config.id, config);
      var calls = 0;
      final client = service.authenticatedClient(
        MockClient((request) async {
          calls++;
          return http.Response('', 401);
        }),
        config,
      );
      await expectLater(
        client.post(
          Uri.parse('${config.baseUrl}/chat/completions'),
          body: '{}',
        ),
        throwsA(
          isA<ProviderOAuthException>().having(
            (e) => e.kind,
            'kind',
            ProviderOAuthFailure.loginRequired,
          ),
        ),
      );
      expect(calls, 1);
      expect(
        settings.providerConfigs[config.id]!.oauthCredentials!.requiresLogin,
        isTrue,
      );
    },
  );

  test(
    'OpenRouter model sync flattens architecture and supported_parameters into '
    'ModelInfo',
    () async {
      final service = ProviderOAuthService(
        clientFactory: (_) => MockClient(
          (_) async => response({
            'data': [
              {
                'id': 'openai/gpt-4o',
                'name': 'GPT-4o',
                'architecture': {
                  'input_modalities': ['text', 'image'],
                  'output_modalities': ['text'],
                },
                'supported_parameters': ['reasoning', 'tools'],
              },
            ],
            'links': {'next': null},
          }),
        ),
      )..bind(settings);
      final config = openRouterConfig();
      await settings.setProviderConfig(config.id, config);
      final models = await service.models(config);
      expect(models, hasLength(1));
      final model = models.single;
      expect(model.id, 'openai/gpt-4o');
      expect(model.displayName, 'GPT-4o');
      expect(model.input, contains(Modality.image));
      expect(model.abilities, contains(ModelAbility.reasoning));
    },
  );
}
