import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:Kelivo/core/models/provider_oauth.dart';
import 'package:Kelivo/core/services/auth/provider_oauth_adapter.dart';
import 'package:Kelivo/core/services/network/dio_http_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'real Dio transport preserves device JSON and OAuth form bytes',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final received = <String>[];
      server.listen((request) async {
        received.add(await utf8.decoder.bind(request).join());
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"ok":true}');
        await request.response.close();
      });
      final client = DioHttpClient(logRequests: false);
      addTearDown(client.close);
      final logs = <String>[];
      final wire = OAuthWire(client, diagnostics: logs.add);
      final base = 'http://127.0.0.1:${server.port}';
      final init = await wire.request(
        '$base/api/accounts/deviceauth/usercode',
        json: {'client_id': 'synthetic-client'},
      );
      final exchange = await wire.request(
        '$base/oauth/token',
        form: {
          'grant_type': 'authorization_code',
          'code': 'synthetic + secret',
          'code_verifier': 'private-verifier',
        },
      );
      expect(init.data, {'ok': true});
      expect(exchange.data, {'ok': true});
      expect(jsonDecode(received.first), {'client_id': 'synthetic-client'});
      expect(Uri.splitQueryString(received.last), {
        'grant_type': 'authorization_code',
        'code': 'synthetic + secret',
        'code_verifier': 'private-verifier',
      });
      expect(
        logs.join('\n'),
        allOf(
          contains('device-authorization http-200'),
          contains('token-exchange http-200'),
          isNot(contains('synthetic')),
          isNot(contains('private-verifier')),
          isNot(contains('127.0.0.1')),
        ),
      );
    },
  );

  for (final entry in {
    'HandshakeException: CERTIFICATE_VERIFY_FAILED': 'tls',
    'DioException [connection timeout]': 'timeout',
    'SocketException: Connection refused': 'connection-refused',
    'SocketException: Network is unreachable': 'network-unreachable',
  }.entries) {
    test('classifies ${entry.value} without logging exception text', () async {
      final logs = <String>[];
      final client = MockClient(
        (request) async => throw http.ClientException(
          '${entry.key}: sensitive-password code=private-code',
          request.url,
        ),
      );
      addTearDown(client.close);
      await expectLater(
        OAuthWire(client, diagnostics: logs.add).request(
          'https://auth.openai.com/oauth/token?private-query=true',
          form: {'refresh_token': 'private-refresh'},
        ),
        throwsA(
          isA<ProviderOAuthException>()
              .having(
                (error) => error.code,
                'diagnostic',
                'token-exchange/${entry.value}',
              )
              .having(
                (error) => error.kind,
                'kind',
                entry.value == 'timeout'
                    ? ProviderOAuthFailure.timeout
                    : ProviderOAuthFailure.network,
              ),
        ),
      );
      expect(
        logs.join('\n'),
        allOf(
          contains('failed-${entry.value}'),
          isNot(contains('private')),
          isNot(contains('sensitive-password')),
        ),
      );
    });
  }

  test('the outer OAuth timeout is classified and bounded', () async {
    final client = MockClient((request) => Completer<http.Response>().future);
    addTearDown(client.close);
    await expectLater(
      OAuthWire(client).request(
        'https://auth.openai.com/oauth/token',
        form: {'code': 'synthetic'},
        timeout: const Duration(milliseconds: 10),
      ),
      throwsA(
        isA<ProviderOAuthException>().having(
          (error) => error.code,
          'diagnostic',
          'token-exchange/timeout',
        ),
      ),
    );
  });
}
