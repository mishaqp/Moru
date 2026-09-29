import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/providers/environment_provider.dart';
import 'package:Kelivo/core/services/acp/acp_agent.dart';
import 'package:Kelivo/core/services/acp/acp_agent_catalog.dart';
import 'package:Kelivo/core/services/acp/acp_agent_manager.dart';
import 'package:Kelivo/core/services/acp/acp_error_messages.dart';
import 'package:Kelivo/core/services/workspace/workspace_runtime.dart';
import 'package:Kelivo/features/home/services/acp_chat_bridge.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

import '../../../support/business_test_harness.dart';

class _FailingChannel extends AcpChannel {
  _FailingChannel(
    this.error, {
    this.failAt = 'session/prompt',
    this.crash = false,
  });
  final AcpError error;
  final String failAt;
  final bool crash;
  final incoming = StreamController<dynamic>();
  final ended = Completer<void>();
  @override
  Stream<dynamic> get messages => incoming.stream;
  @override
  Future<void> get closed => ended.future;
  @override
  String describeError(Object error) => this.error.message;
  @override
  Future<void> send(Map<String, Object?> message) async {
    scheduleMicrotask(() {
      if (message['method'] == failAt) {
        if (crash) {
          close();
          return;
        }
        incoming.add({
          'jsonrpc': '2.0',
          'id': message['id'],
          'error': {
            'code': error.code,
            'message': error.message,
            'data': error.data,
          },
        });
        return;
      }
      incoming.add({
        'jsonrpc': '2.0',
        'id': message['id'],
        'result': message['method'] == 'initialize'
            ? {'protocolVersion': 1}
            : {'sessionId': 's1'},
      });
    });
  }

  @override
  void close() {
    if (!ended.isCompleted) ended.complete();
    unawaited(incoming.close());
  }
}

class _CheckingManager extends AcpAgentManager {
  _CheckingManager(this.channel)
    : super(
        preferences: createBusinessTestPreferences(),
        runtimeProvider: WorkspaceRuntimeProvider(),
        environment: EnvironmentProvider(
          preferences: createBusinessTestPreferences(),
        ),
      );
  final AcpChannel channel;
  @override
  Future<AcpAgent> start(
    AcpAgentSpec spec,
    AcpProviderInput provider, {
    String cwd = '/root',
    List<Mount> mounts = const [],
    bool Function()? isCancelled,
  }) => AcpAgent.start(channel, clientVersion: '1');
}

void main() {
  const cases = [
    (AcpError(-32603, 'HTTP 401 Unauthorized'), AcpFailureKind.apiKey),
    (AcpError(-32603, 'Invalid API key: secret'), AcpFailureKind.apiKey),
    (AcpError(-32603, 'Incorrect_api_key'), AcpFailureKind.apiKey),
    (
      AcpError(-32603, 'Request failed', {'status': 401}),
      AcpFailureKind.apiKey,
    ),
    (
      AcpError(-32603, 'The model `missing` does not exist'),
      AcpFailureKind.model,
    ),
    (AcpError(-32603, 'ProviderModelNotFoundError'), AcpFailureKind.model),
    (
      AcpError(-32603, 'failed', {'code': 'model_not_found'}),
      AcpFailureKind.model,
    ),
    (
      AcpError(-1, 'getaddrinfo ENOTFOUND api.example.com'),
      AcpFailureKind.network,
    ),
    (AcpError(-1, 'EAI_AGAIN api.example.com'), AcpFailureKind.network),
    (AcpError(-1, 'fetch failed'), AcpFailureKind.network),
    (AcpError(-1, 'connect ECONNREFUSED'), AcpFailureKind.network),
  ];
  final translations = <Locale, List<String>>{
    const Locale('en'): [
      'Invalid API key for the provider.',
      'Model not found. Check the provider model settings.',
      'No network connection. Check your connection and try again.',
    ],
    const Locale('ru'): [
      'Неверный API-ключ у провайдера.',
      'Модель не найдена. Проверьте модель в настройках провайдера.',
      'Нет сети. Проверьте подключение и попробуйте снова.',
    ],
    const Locale('zh'): [
      '提供商的 API 密钥无效。',
      '未找到模型。请检查提供商的模型设置。',
      '无法连接网络。请检查网络连接后重试。',
    ],
    const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'): [
      '提供商的 API 密钥无效。',
      '未找到模型。请检查提供商的模型设置。',
      '无法连接网络。请检查网络连接后重试。',
    ],
    const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'): [
      '供應商的 API 金鑰無效。',
      '找不到模型。請檢查供應商的模型設定。',
      '無法連線網路。請檢查網路連線後重試。',
    ],
  };
  for (final entry in translations.entries) {
    final l10n = lookupAppLocalizations(entry.key);
    for (final (error, kind) in cases) {
      test('${entry.key}: protocol prompt error ${error.message}', () async {
        final channel = _FailingChannel(error);
        final agent = await AcpAgent.start(channel, clientVersion: '1');
        addTearDown(agent.close);
        final session = await agent.newSession(cwd: '/root');
        await expectLater(
          AcpChatBridge.localizeStreamErrors(
            agent.prompt(session.id, const []),
            l10n,
          ).drain<void>(),
          throwsA(
            isA<AcpError>()
                .having(
                  (e) => e.message,
                  'localized message',
                  entry.value[kind.index],
                )
                .having((e) => e.code, 'original code', error.code),
          ),
        );
      });
    }
    for (final (error, kind) in [cases[0], cases[4], cases[7]]) {
      test('${entry.key}: manager initialize failure ${kind.name}', () async {
        final channel = _FailingChannel(error, failAt: 'initialize');
        final manager = _CheckingManager(channel);
        addTearDown(manager.dispose);
        final result = await manager.check(
          AcpAgentSpec.byId('opencode')!,
          const AcpProviderInput(
            baseUrl: 'https://example.com',
            apiKey: 'key',
            model: 'missing',
          ),
        );
        expect(result.ok, isFalse);
        expect(result.failureKind, kind);
        expect(result.errorMessage(l10n), entry.value[kind.index]);
        expect(manager.failure, AcpAgentFailure.check);
        expect(channel.ended.isCompleted, isTrue);
      });
    }
  }
  test(
    'stderr on process exit is translated instead of displayed raw',
    () async {
      final channel = _FailingChannel(
        const AcpError(-1, 'Invalid API key: SECRET'),
        crash: true,
      );
      final agent = await AcpAgent.start(channel, clientVersion: '1');
      addTearDown(agent.close);
      await expectLater(
        AcpChatBridge.localizeStreamErrors(
          agent.prompt('s1', const []),
          lookupAppLocalizations(const Locale('ru')),
        ).drain<void>(),
        throwsA(
          isA<AcpError>().having(
            (e) => e.message,
            'message',
            'Неверный API-ключ у провайдера.',
          ),
        ),
      );
    },
  );
  test('unrelated errors keep their identity and useful diagnostics', () {
    final l10n = lookupAppLocalizations(const Locale('ru'));
    for (final error in [
      const AcpError(404, 'File not found'),
      const AcpError(-1, 'Model configuration file not found'),
      const AcpError(-1, 'tool exited with code 1401'),
      StateError('unexpected'),
    ]) {
      expect(localizeAcpError(error, l10n), same(error));
    }
    expect(
      classifyAcpFailure(const SocketException('unreachable')),
      AcpFailureKind.network,
    );
  });
}
