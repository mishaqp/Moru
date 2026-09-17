import 'dart:async';

import 'package:Kelivo/core/models/provider_oauth.dart';
import 'package:Kelivo/core/services/auth/oauth_cancellation.dart';
import 'package:Kelivo/core/services/auth/oauth_login_gate.dart';
import 'package:Kelivo/core/services/auth/provider_oauth_adapter.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app.oauth.network');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  test('browser time does not consume the HTTP request timeout', () async {
    final network = Completer<void>();
    var networkWaits = 0;
    var sends = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'awaitNetwork') {
        networkWaits++;
        await network.future;
      }
      return null;
    });
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    final gate = OAuthLoginGate(OAuthCancellation(), isAndroid: true);
    addTearDown(gate.close);
    final client = MockClient((_) async {
      sends++;
      return http.Response('{"ok":true}', 200);
    });
    addTearDown(client.close);
    final pending = OAuthWire(client, beforeRequest: gate.wait).request(
      'https://auth.openai.com/api/accounts/deviceauth/token',
      json: {'device_auth_id': 'synthetic', 'user_code': 'CODE'},
      timeout: const Duration(milliseconds: 5),
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(sends, 0);
    expect(networkWaits, 0);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(networkWaits, 1);
    expect(sends, 0);
    network.complete();
    expect((await pending).status, 200);
    expect(sends, 1);
  });

  test(
    'a DNS retry waits for return and retains the exact OAuth body',
    () async {
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      final gate = OAuthLoginGate(OAuthCancellation(), isAndroid: true);
      addTearDown(gate.close);
      final bodies = <String>[];
      final logs = <String>[];
      final client = MockClient((request) async {
        bodies.add(request.body);
        if (bodies.length == 1) {
          binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
          throw http.ClientException('Failed host lookup: auth.openai.com');
        }
        return http.Response('{"ok":true}', 200);
      });
      addTearDown(client.close);
      final pending =
          OAuthWire(
            client,
            beforeRequest: gate.wait,
            diagnostics: logs.add,
          ).request(
            'https://auth.openai.com/oauth/token',
            form: {'code': 'private-code', 'code_verifier': 'private-verifier'},
          );
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(bodies, hasLength(1));
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect((await pending).status, 200);
      expect(bodies, hasLength(2));
      expect(bodies[0], bodies[1]);
      expect(logs.join('\n'), isNot(contains('private-')));
    },
  );

  for (final background in [false, true]) {
    test(
      'cancellation stops a ${background ? 'foreground' : 'network'} wait',
      () async {
        final native = Completer<void>();
        final calls = <String>[];
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (call.method == 'awaitNetwork') await native.future;
          return null;
        });
        if (background) {
          binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        }
        final cancellation = OAuthCancellation();
        final gate = OAuthLoginGate(cancellation, isAndroid: true);
        addTearDown(gate.close);
        final expectation = expectLater(
          gate.wait(),
          throwsA(
            isA<ProviderOAuthException>().having(
              (e) => e.kind,
              'kind',
              ProviderOAuthFailure.cancelled,
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        cancellation.cancel();
        await expectation;
        await gate.close();
        if (!background) expect(calls, contains('cancelNetworkWait'));
        native.complete();
      },
    );
  }

  test('native network timeout stays distinct from OAuth rejection', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'awaitNetwork') {
        throw PlatformException(code: 'network_timeout', message: 'private');
      }
      return null;
    });
    final gate = OAuthLoginGate(OAuthCancellation(), isAndroid: true);
    addTearDown(gate.close);
    await expectLater(
      gate.wait(),
      throwsA(
        isA<ProviderOAuthException>()
            .having((e) => e.kind, 'kind', ProviderOAuthFailure.timeout)
            .having((e) => e.code, 'code', 'login/network-timeout'),
      ),
    );
  });

  test('non-Android gate does not call native services', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      fail('native network wait must be Android-only');
    });
    final gate = OAuthLoginGate(OAuthCancellation(), isAndroid: false);
    await gate.wait();
    await gate.close();
    await expectLater(gate.wait(), throwsA(isA<ProviderOAuthException>()));
  });
}
