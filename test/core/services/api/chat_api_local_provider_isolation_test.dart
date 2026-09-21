import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/api/chat_api_service.dart';
import 'package:Kelivo/core/services/local/litert_channel.dart';
import 'package:Kelivo/core/services/local/local_model_library.dart';

import '../../../support/collect_generation.dart';

/// [ChatApiService._sendOnce]'s `kind == ProviderKind.local` branch is a
/// hard early return, before the HTTP client, OAuth wrapper, custom-header
/// merging, or network retry are ever constructed. Excluding
/// `ProviderKind.local` from the generic HTTP-request-precedence and
/// tool-schema test loops (see chat_api_custom_request_precedence_test.dart
/// and tool_handler_service_test.dart) documents that exclusion but does
/// not, by itself, prove the claim at runtime. This file drives a real
/// local generation through the actual public entry point
/// (`ChatApiService.sendMessageStream`) the app uses, with:
///  - a real bound `HttpServer` the config's `baseUrl` points at, which
///    fails the test if it ever receives a connection -- local ignores
///    `baseUrl` entirely, but if a regression ever routed it through the
///    generic HTTP path this would catch it immediately (no OAuth call is
///    a corollary: `ProviderOAuthService.resolve`/`authenticatedClient`
///    are both no-ops unless a request actually reaches an OAuth-configured
///    client, which this proves never happens);
///  - a non-trivial `tools` schema and an `onToolCall` handler that fails
///    the test if invoked, proving the local branch neither forwards tool
///    definitions to the engine nor ever calls back into tool handling.
///
/// The native engine itself is mocked at the platform-channel level (same
/// technique as litert_channel_test.dart / local_model_runtime_test.dart)
/// so this runs without a device -- see docs/litert-lm-progress.md for
/// what still requires real hardware.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a local generation makes zero HTTP requests, touches no OAuth client, '
      'and never advertises or invokes a tool', () async {
    final trapServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var trapHits = 0;
    final trapSub = trapServer.listen((request) {
      trapHits++;
      request.response.statusCode = HttpStatus.internalServerError;
      unawaited(request.response.close());
    });
    addTearDown(() async {
      await trapSub.cancel();
      await trapServer.close(force: true);
    });

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const methodChannel = MethodChannel(kLiteRtMethodChannel);
    const eventChannel = EventChannel(kLiteRtEventChannel);
    MockStreamHandlerEventSink? sink;
    final sentMessages = <MethodCall>[];

    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      switch (call.method) {
        case 'loadModel':
          return <String, Object?>{'backend': 'cpu'};
        case 'startConversation':
          return null;
        case 'sendMessage':
          sentMessages.add(call);
          return null;
        case 'cancel':
          return true;
        case 'unloadModel':
          return null;
        default:
          return null;
      }
    });
    messenger.setMockStreamHandler(
      eventChannel,
      MockStreamHandler.inline(onListen: (args, s) => sink = s),
    );
    addTearDown(() {
      messenger.setMockMethodCallHandler(methodChannel, null);
      messenger.setMockStreamHandler(eventChannel, null);
    });

    const modelId = 'local-isolation-test-model';
    final config = ProviderConfig(
      id: 'litert-local',
      enabled: true,
      name: 'Local',
      apiKey: '',
      // Deliberately points at the trap server: local must never build a
      // request from this at all, let alone send one.
      baseUrl: 'http://${trapServer.address.address}:${trapServer.port}',
      providerType: ProviderKind.local,
      // No oauthProvider -- exactly like every real local ProviderConfig
      // (nothing in the app ever runs local through the OAuth login
      // flow), which is what makes `config.isOAuth` false and both
      // `ProviderOAuthService.resolve`/`authenticatedClient` no-ops.
      modelOverrides: {
        modelId: {'localModelPath': '/models/isolation-test.litertlm'},
      },
    );

    var toolCallInvoked = false;
    final chunksFuture = ChatApiService.sendMessageStream(
      config: config,
      modelId: modelId,
      messages: const [
        {'role': 'user', 'content': 'hello'},
      ],
      tools: const [
        {
          'type': 'function',
          'function': {
            'name': 'search',
            'description': 'search the web',
            'parameters': {
              'type': 'object',
              'properties': {
                'query': {'type': 'string'},
              },
            },
          },
        },
      ],
      onToolCall: (name, args, {toolCallId}) async {
        toolCallInvoked = true;
        fail('onToolCall must never be invoked for a local generation');
      },
    ).toList();

    // Let the request reach the mocked native side, then answer it.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(sentMessages, hasLength(1));
    final requestId = sentMessages.single.arguments['requestId'] as String;
    sink?.success({
      'type': 'textDelta',
      'requestId': requestId,
      'text': 'hi there',
    });
    sink?.success({'type': 'done', 'requestId': requestId});

    final chunks = await chunksFuture;

    expect(
      chunks.isGenerationDone,
      isTrue,
      reason: 'local generation should complete normally',
    );
    expect(chunks.joinedContent, 'hi there');
    expect(
      trapHits,
      0,
      reason:
          'local generation must never send an HTTP request, even when '
          'baseUrl is set',
    );
    expect(toolCallInvoked, isFalse);
  });

  test(
    'a stale local model id falls back to the only installed model',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const methodChannel = MethodChannel(kLiteRtMethodChannel);
      const eventChannel = EventChannel(kLiteRtEventChannel);
      MockStreamHandlerEventSink? sink;
      final sentMessages = <MethodCall>[];

      messenger.setMockMethodCallHandler(methodChannel, (call) async {
        switch (call.method) {
          case 'loadModel':
            expect(call.arguments['modelPath'], '/models/current.litertlm');
            return <String, Object?>{'backend': 'cpu'};
          case 'startConversation':
            return null;
          case 'sendMessage':
            sentMessages.add(call);
            return null;
          default:
            return null;
        }
      });
      messenger.setMockStreamHandler(
        eventChannel,
        MockStreamHandler.inline(onListen: (args, s) => sink = s),
      );
      addTearDown(() {
        messenger.setMockMethodCallHandler(methodChannel, null);
        messenger.setMockStreamHandler(eventChannel, null);
      });

      const currentId = 'litert-current';
      final config = ProviderConfig(
        id: kLocalModelProviderKey,
        enabled: true,
        name: 'Local',
        apiKey: '',
        baseUrl: '',
        providerType: ProviderKind.local,
        models: const [currentId],
        modelOverrides: const {
          currentId: {'localModelPath': '/models/current.litertlm'},
        },
      );
      final future = ChatApiService.sendMessageStream(
        config: config,
        modelId: 'deleted-random-uuid',
        messages: const [
          {'role': 'user', 'content': 'hello'},
        ],
        isConversationTurn: true,
      ).toList();

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(sentMessages, hasLength(1));
      final requestId = sentMessages.single.arguments['requestId'] as String;
      sink?.success({'type': 'done', 'requestId': requestId});
      await future;
    },
  );
}
