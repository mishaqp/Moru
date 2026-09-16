import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/auth/oauth_callback_io.dart';
import 'package:Kelivo/core/services/auth/oauth_callback_types.dart';
import 'package:Kelivo/core/services/auth/oauth_pkce.dart';
import 'package:Kelivo/core/services/auth/provider_oauth_adapter.dart'
    show ChatGptOAuthAdapter, OAuthWire;
import 'package:Kelivo/core/services/auth/provider_oauth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../../support/business_test_harness.dart';

class _StuckBrowser implements OAuthCallback {
  @override
  final redirectUri = Uri.parse('psyche.kelivo://mcp-oauth-callback/test');
  final returned = Completer<Uri>();
  final launched = Completer<void>();

  @override
  Future<Uri> authorize(Uri url, Duration timeout, OAuthUrlLauncher launch) {
    launched.complete();
    return returned.future;
  }

  @override
  Future<Uri> waitForCallback(Duration timeout) => returned.future;

  @override
  Future<void> close() async {
    if (!returned.isCompleted) {
      returned.completeError(
        const OAuthCallbackException('cancelled', cancelled: true),
      );
    }
  }
}

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'browser login opens once and exchanges a code using the original PKCE verifier',
    () async {
      final harness = await createBusinessTestHarness();
      final settings = SettingsProvider(harness.preferences);
      await settings.loaded;
      addTearDown(settings.dispose);
      late Uri authorization;
      var launches = 0;
      var prompts = 0;
      var exchanges = 0;
      final service = ProviderOAuthService(
        clientFactory: (_) => MockClient((request) async {
          exchanges++;
          expect(request.url.toString(), OAuthProvider.chatgpt.tokenEndpoint);
          expect(request.bodyFields['code'], 'browser-code');
          expect(
            request.bodyFields['redirect_uri'],
            'http://localhost:1455/auth/callback',
          );
          expect(
            oauthPkceChallenge(request.bodyFields['code_verifier']!),
            authorization.queryParameters['code_challenge'],
          );
          final claims = base64UrlEncode(
            utf8.encode(
              jsonEncode({
                'https://api.openai.com/profile': {'email': 'test@example.com'},
              }),
            ),
          );
          return http.Response(
            jsonEncode({
              'access_token': 'e30.$claims.signature',
              'refresh_token': 'refresh',
              'expires_in': 3600,
            }),
            200,
          );
        }),
      )..bind(settings);
      final saved = await service.login(
        provider: OAuthProvider.chatgpt,
        cancellation: OAuthCancellation(),
        deviceCode: false,
        onPrompt: (prompt) {
          prompts++;
          expect(prompt.browserAuthorization, true);
          expect(prompt.userCode, isNull);
        },
        launcher: (url) async {
          launches++;
          authorization = url;
          expect(url.host, 'auth.openai.com');
          final client = HttpOverrides.runWithHttpOverrides(
            HttpClient.new,
            _RealHttpOverrides(),
          )..findProxy = (_) => 'DIRECT';
          try {
            final request = await client.getUrl(
              Uri.parse(url.queryParameters['redirect_uri']!).replace(
                queryParameters: {
                  'code': 'browser-code',
                  'state': url.queryParameters['state']!,
                },
              ),
            );
            final response = await request.close();
            await response.drain<void>();
          } finally {
            client.close(force: true);
          }
          return true;
        },
      );
      expect(launches, 1);
      expect(prompts, 1);
      expect(exchanges, 1);
      expect(saved.oauthCredentials!.email, 'test@example.com');
      final rebound = await HttpServer.bind(InternetAddress.loopbackIPv4, 1455);
      await rebound.close(force: true);
    },
  );

  for (final occupied in [false, true]) {
    test(
      'manual Codex callback works with occupied listener: $occupied',
      () async {
        HttpServer? blocker;
        if (occupied) {
          blocker = await HttpServer.bind(InternetAddress.loopbackIPv4, 1455);
        }
        addTearDown(() async => blocker?.close(force: true));
        final cancellation = OAuthCancellation();
        addTearDown(cancellation.cancel);
        late OAuthLoginPrompt prompt;
        var exchanges = 0;
        var launches = 0;
        final client = MockClient((request) async {
          exchanges++;
          expect(request.url.toString(), OAuthProvider.chatgpt.tokenEndpoint);
          expect(request.bodyFields['code'], 'synthetic-code');
          expect(
            request.bodyFields['redirect_uri'],
            'http://localhost:1455/auth/callback',
          );
          expect(
            oauthPkceChallenge(request.bodyFields['code_verifier']!),
            prompt.url.queryParameters['code_challenge'],
          );
          final claims = base64UrlEncode(
            utf8.encode(
              jsonEncode({
                'exp': 4102444800,
                'https://api.openai.com/auth': {
                  'chatgpt_account_id': 'synthetic-account',
                  'chatgpt_plan_type': 'pro',
                },
              }),
            ),
          );
          return http.Response(
            jsonEncode({
              'access_token': 'e30.$claims.signature',
              'refresh_token': 'synthetic-refresh',
            }),
            200,
          );
        });
        addTearDown(client.close);
        final saved = await ChatGptOAuthAdapter()
            .login(
              OAuthWire(client),
              cancellation,
              (value) async {
                prompt = value;
                expect(
                  value.submitAuthorizationCode,
                  isNotNull,
                  reason: 'A failed localhost page must have a recovery path',
                );
              },
              deviceCode: false,
              launcher: (url) async {
                launches++;
                final submit = prompt.submitAuthorizationCode!;
                final valid = Uri.parse('http://localhost:1455/auth/callback')
                    .replace(
                      queryParameters: {
                        'code': 'synthetic-code',
                        'state': url.queryParameters['state']!,
                      },
                    );
                for (final invalid in [
                  'synthetic-code',
                  valid.replace(host: 'attacker.invalid').toString(),
                  valid.replace(userInfo: 'user:password').toString(),
                  valid.replace(port: 1456).toString(),
                  valid.replace(path: '/other').toString(),
                  valid.replace(fragment: 'fragment').toString(),
                  valid
                      .replace(query: 'code=synthetic-code&state=old-login')
                      .toString(),
                  '${valid.toString()}&state=${url.queryParameters['state']}',
                  '${valid.toString()}&code=another-code',
                  '${valid.toString()}&error=access_denied',
                ]) {
                  expect(submit(invalid), false);
                }
                expect(exchanges, 0);
                expect(submit(valid.toString()), true);
                expect(submit(valid.toString()), false);
                return true;
              },
            )
            .timeout(const Duration(seconds: 4));
        expect(saved.plan, 'pro');
        expect(saved.accountId, 'synthetic-account');
        expect(exchanges, 1);
        expect(launches, 1);
        expect(prompt.submitAuthorizationCode!('anything'), false);
      },
    );
  }

  test(
    'validated loopback does not depend on a second Android intent',
    () async {
      final browser = _StuckBrowser();
      final callback = await createMobileLoopbackOAuthCallbackForTesting(
        browser,
      );
      final client = HttpOverrides.runWithHttpOverrides(
        HttpClient.new,
        _RealHttpOverrides(),
      )..findProxy = (_) => 'DIRECT';
      addTearDown(() => client.close(force: true));
      addTearDown(callback.close);
      final pending = callback.authorize(
        Uri.parse(
          'https://auth.openai.com/oauth/authorize?state=synthetic-state',
        ),
        const Duration(seconds: 3),
        (_) async => true,
      );
      final outcome = expectLater(
        pending.timeout(const Duration(seconds: 1)),
        completion(
          isA<Uri>().having(
            (uri) => uri.queryParameters['code'],
            'code',
            'synthetic-code',
          ),
        ),
      );
      await browser.launched.future;
      final request = await client.getUrl(
        callback.redirectUri.replace(
          queryParameters: {
            'code': 'synthetic-code',
            'state': 'synthetic-state',
          },
        ),
      );
      request.followRedirects = false;
      final response = await request.close();
      expect(
        response.headers.value('location'),
        isNot(contains('synthetic-code')),
      );
      await response.drain<void>();
      await outcome;
    },
  );

  test(
    'device network failure reports safe stage and cause, never credentials',
    () async {
      final client = MockClient(
        (request) async => throw http.ClientException(
          'Failed host lookup: auth.openai.com; code=DO-NOT-LOG; verifier=PRIVATE',
          Uri.parse('https://auth.openai.com/?code=DO-NOT-LOG'),
        ),
      );
      addTearDown(client.close);
      await expectLater(
        ChatGptOAuthAdapter().login(
          OAuthWire(client),
          OAuthCancellation(),
          (_) async {},
        ),
        throwsA(
          isA<ProviderOAuthException>()
              .having((e) => e.kind, 'kind', ProviderOAuthFailure.network)
              .having(
                (e) => e.code,
                'safe diagnostic',
                'device-authorization/dns',
              )
              .having(
                (e) => '${e.message} ${e.code}',
                'no credentials',
                allOf(
                  isNot(contains('DO-NOT-LOG')),
                  isNot(contains('PRIVATE')),
                ),
              ),
        ),
      );
    },
  );
}
