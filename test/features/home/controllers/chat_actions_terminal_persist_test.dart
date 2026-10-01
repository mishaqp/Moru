import 'dart:async';

import 'package:Kelivo/core/database/generation_run.dart';
import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/models/message_part.dart';
import 'package:Kelivo/core/models/provider_oauth.dart';
import 'package:Kelivo/core/models/mobile_background_settings.dart';
import 'package:Kelivo/core/services/mobile_background.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/chat/chat_service.dart';
import 'package:Kelivo/core/services/api/stream/stream_chunk.dart';
import 'package:Kelivo/features/home/controllers/chat_controller.dart';
import 'package:Kelivo/features/home/controllers/chat_actions.dart';
import 'package:Kelivo/features/home/controllers/generation_controller.dart';
import 'package:Kelivo/features/home/controllers/home_view_model.dart';
import 'package:Kelivo/features/home/controllers/stream_controller.dart';
import 'package:Kelivo/features/home/services/message_builder_service.dart';
import 'package:Kelivo/features/home/services/message_generation_service.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/business_test_harness.dart';

class _ThrowingFinalizeChatService extends ChatService {
  _ThrowingFinalizeChatService({this.failCompletion = true});
  final bool failCompletion;
  final terminalStates = <GenerationRunState>[];
  ChatMessage? lastMessage;
  String? lastErrorCode;
  final checkpoints = <ChatMessage>[];

  @override
  Future<void> updateStreamingCheckpointSilent(
    ChatMessage message,
    List<Map<String, dynamic>> toolEvents, {
    String? generationRunId,
    int? checkpointSeq,
  }) async {
    checkpoints.add(message);
  }

  @override
  Future<GenerationRun?> finalizeGenerationRunSilent({
    required ChatMessage message,
    required List<Map<String, dynamic>> toolEvents,
    required String? generationRunId,
    required GenerationRunState? expectedState,
    required int? expectedStateRevision,
    required GenerationRunState terminalState,
    int? checkpointSeq,
    String? errorCode,
  }) async {
    terminalStates.add(terminalState);
    lastMessage = message;
    lastErrorCode = errorCode;
    if (failCompletion && terminalState == GenerationRunState.completed) {
      throw StateError('persist failed');
    }
    return null;
  }
}

({ChatActions actions, HomeViewModel viewModel}) _actionsFor(
  BuildContext context,
  ChatService service,
  SettingsProvider settings,
  MobileBackgroundCoordinator background,
) {
  final chatController = ChatController(chatService: service);
  final streamController = StreamController(
    onStateChanged: () {},
    getSettingsProvider: () => settings,
    getCurrentConversationId: () => 'conversation-1',
  );
  final messageBuilder = MessageBuilderService(
    chatService: service,
    contextProvider: context,
  );
  final generationController = GenerationController(
    chatService: service,
    chatController: chatController,
    streamController: streamController,
    messageBuilderService: messageBuilder,
    contextProvider: context,
    onStateChanged: () {},
    getTitleForLocale: (_) => 'title',
  );
  final messageGeneration = MessageGenerationService(
    chatService: service,
    messageBuilderService: messageBuilder,
    generationController: generationController,
    streamController: streamController,
    contextProvider: context,
  );
  final viewModel = HomeViewModel(
    chatService: service,
    messageBuilderService: messageBuilder,
    messageGenerationService: messageGeneration,
    generationController: generationController,
    streamController: streamController,
    chatController: chatController,
    contextProvider: context,
    getTitleForLocale: (_) => 'title',
  );
  final actions = ChatActions(
    chatService: service,
    chatController: chatController,
    streamController: streamController,
    generationController: generationController,
    messageGenerationService: messageGeneration,
    contextProvider: context,
    viewModel: viewModel,
    backgroundCoordinator: background,
  );
  return (actions: actions, viewModel: viewModel);
}

void main() {
  for (final failed in [false, true]) {
    testWidgets(
      'terminal ${failed ? 'failure' : 'completion'} keeps foreground owner until FIFO successor registers',
      (tester) async {
        final service = _ThrowingFinalizeChatService(failCompletion: false);
        final settings = SettingsProvider(createBusinessTestPreferences());
        const channel = MethodChannel('test.chat_actions.fifo_handoff');
        final snapshots = <Map>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            if (call.method == 'sync') snapshots.add(call.arguments as Map);
            return call.method == 'sync' ? <String, Object?>{} : null;
          },
        );
        final background = MobileBackgroundCoordinator(
          platform: TargetPlatform.android,
          channel: channel,
        );
        addTearDown(settings.dispose);
        addTearDown(background.dispose);
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        late ChatActions actions;
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<SettingsProvider>.value(value: settings),
            ],
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Builder(
                builder: (context) {
                  actions = _actionsFor(
                    context,
                    service,
                    settings,
                    background,
                  ).actions;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );
        await tester.runAsync(() async {
          await background.configure(
            const MobileBackgroundSettings(androidEnabled: true),
            await AppLocalizations.delegate.load(const Locale('en')),
          );
          await background.start(
            id: 'first',
            conversationId: 'conversation-1',
            title: 'First',
            cancel: () async {},
          );
          background.didChangeAppLifecycleState(AppLifecycleState.paused);
          final entered = Completer<void>();
          final release = Completer<void>();
          actions.onLoadingChanged = (_, loading) {
            if (!loading) expect(background.activeTaskIds, contains('first'));
          };
          actions.onGenerationReadyForNext = (cid, finishingId) async {
            expect(cid, 'conversation-1');
            expect(finishingId, 'first');
            expect(service.terminalStates, [
              failed ? GenerationRunState.failed : GenerationRunState.completed,
            ]);
            entered.complete();
            await release.future;
          };
          final state = StreamingState(
            GenerationContext(
              executionId: 'first',
              assistantMessage: ChatMessage(
                id: 'assistant',
                conversationId: 'conversation-1',
                role: 'assistant',
                content: 'reply',
                isStreaming: true,
              ),
              apiMessages: const [],
              userImagePaths: const [],
              allowImagesApiRouting: false,
              providerKey: 'test',
              modelId: 'test-model',
              assistant: null,
              settings: settings,
              config: ProviderConfig(
                id: 'test',
                enabled: true,
                name: 'Test',
                apiKey: '',
                baseUrl: '',
              ),
              toolDefs: const [],
              supportsReasoning: false,
              enableReasoning: false,
              streamOutput: true,
            ),
          );
          actions.debugTrackStreamingState(state);
          final terminal = failed
              ? actions.debugHandleStreamError(StateError('failed'), state)
              : actions.debugFinishStreaming(state);
          await entered.future;
          expect(background.activeTaskIds, {'first'});
          await background.start(
            id: 'successor',
            conversationId: 'conversation-1',
            title: 'Next',
            cancel: () async {},
          );
          expect(background.activeTaskIds, {'first', 'successor'});
          release.complete();
          await terminal;
          expect(background.activeTaskIds, {'successor'});
          final protected = snapshots.skipWhile(
            (snapshot) => (snapshot['tasks'] as List).isEmpty,
          );
          expect(
            protected.map((snapshot) => snapshot['tasks']),
            everyElement(isNotEmpty),
          );
          await background.finish('successor', BackgroundTaskOutcome.cancelled);
        });
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'late callbacks cannot finish a newer continuation of the same message',
    (tester) async {
      final service = _ThrowingFinalizeChatService(failCompletion: false);
      final settings = SettingsProvider(createBusinessTestPreferences());
      final background = MobileBackgroundCoordinator(
        platform: TargetPlatform.linux,
      );
      addTearDown(settings.dispose);
      addTearDown(background.dispose);
      late ChatActions actions;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsProvider>.value(value: settings),
            ChangeNotifierProvider<ChatService>.value(value: service),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                actions = _actionsFor(
                  context,
                  service,
                  settings,
                  background,
                ).actions;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      StreamingState continuation() => StreamingState(
        GenerationContext(
          assistantMessage: ChatMessage(
            id: 'same-assistant',
            role: 'assistant',
            content: 'reply',
            conversationId: 'conversation-1',
            isStreaming: true,
          ),
          apiMessages: const [],
          userImagePaths: const [],
          allowImagesApiRouting: false,
          providerKey: 'test',
          modelId: 'test-model',
          assistant: null,
          settings: settings,
          config: ProviderConfig(
            id: 'test',
            enabled: true,
            name: 'Test',
            apiKey: '',
            baseUrl: '',
          ),
          toolDefs: const [],
          supportsReasoning: false,
          enableReasoning: false,
          streamOutput: true,
        ),
      );
      final previous = continuation();
      final current = continuation();
      actions.debugTrackStreamingState(previous);
      actions.debugTrackStreamingState(current);
      await actions.debugHandleStreamChunk(
        const TextDelta(id: 'old', text: 'stale'),
        previous,
      );
      await actions.debugHandleStreamError(
        StateError('old execution'),
        previous,
      );
      await actions.debugFinishStreaming(previous);
      expect(previous.fullContentRaw, 'reply');
      expect(current.fullContentRaw, 'reply');
      expect(service.terminalStates, isEmpty);
      expect(service.checkpoints, isEmpty);
      expect(actions.activeStreamingMessageIds, {'same-assistant'});
      await actions.debugHandleStreamChunk(
        const TextDelta(id: 'new', text: ' current'),
        current,
      );
      expect(current.fullContentRaw, 'reply current');
      final finished = actions.debugFinishStreaming(current);
      for (var tick = 0; tick < 10; tick++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await finished;
      expect(service.terminalStates, [GenerationRunState.completed]);
      expect(service.lastMessage!.content, 'reply current');
    },
  );

  testWidgets(
    'lifecycle flush includes both active chats outside the selected timeline',
    (tester) async {
      final service = _ThrowingFinalizeChatService(failCompletion: false);
      final settings = SettingsProvider(createBusinessTestPreferences());
      final background = MobileBackgroundCoordinator(
        platform: TargetPlatform.linux,
      );
      addTearDown(settings.dispose);
      addTearDown(background.dispose);
      late ChatActions actions;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsProvider>.value(value: settings),
            ChangeNotifierProvider<ChatService>.value(value: service),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                actions = _actionsFor(
                  context,
                  service,
                  settings,
                  background,
                ).actions;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      actions.debugTrackActiveMessage(
        ChatMessage(
          id: 'a-message',
          role: 'assistant',
          content: 'partial a',
          conversationId: 'a',
          isStreaming: true,
        ),
      );
      actions.debugTrackActiveMessage(
        ChatMessage(
          id: 'b-message',
          role: 'assistant',
          content: 'partial b',
          conversationId: 'b',
          isStreaming: true,
        ),
      );
      await actions.flushAllActiveGenerationProgress();
      expect(
        service.checkpoints.map((message) => message.conversationId),
        unorderedEquals(['a', 'b']),
      );
      expect(
        service.checkpoints.map((message) => message.content),
        unorderedEquals(['partial a', 'partial b']),
      );
    },
  );
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(const {});

  testWidgets('OAuth 失效保留部分回复并持久化恢复入口，不触发普通错误提示', (tester) async {
    final service = _ThrowingFinalizeChatService(failCompletion: false);
    final settings = SettingsProvider(createBusinessTestPreferences());
    final background = MobileBackgroundCoordinator(
      platform: TargetPlatform.linux,
    );
    addTearDown(background.dispose);
    addTearDown(settings.dispose);
    final errors = <String>[];
    late ChatActions actions;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<ChatService>.value(value: service),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              actions = _actionsFor(
                context,
                service,
                settings,
                background,
              ).actions;
              actions.onStreamError = errors.add;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    final state = StreamingState(
      GenerationContext(
        executionId: 'assistant-1',
        assistantMessage: ChatMessage(
          id: 'assistant-1',
          role: 'assistant',
          content: '',
          providerId: 'account',
          conversationId: 'conversation-1',
          isStreaming: true,
        ),
        apiMessages: const [],
        userImagePaths: const [],
        allowImagesApiRouting: false,
        providerKey: 'account',
        modelId: 'test',
        assistant: null,
        settings: settings,
        config: ProviderConfig(
          id: 'account',
          enabled: true,
          name: 'ChatGPT',
          apiKey: '',
          baseUrl: '',
        ),
        toolDefs: const [],
        supportsReasoning: false,
        enableReasoning: false,
        streamOutput: true,
      ),
    );
    state.fullContentRaw = 'Partial reply';
    await actions.debugHandleStreamError(
      const ProviderOAuthException(
        ProviderOAuthFailure.loginRequired,
        providerId: 'account',
      ),
      state,
    );
    expect(state.terminalPersisted, true);
    expect(service.lastErrorCode, 'oauth_login_required');
    expect(service.terminalStates, [GenerationRunState.failed]);
    expect(service.lastMessage!.content, 'Partial reply');
    expect(
      service.lastMessage!.parts
          .whereType<ProviderAuthErrorPart>()
          .single
          .providerId,
      'account',
    );
    expect(service.lastMessage!.isStreaming, false);
    expect(errors, isEmpty);
  });

  testWidgets('终态写库失败仍走 failed 收尾并通知 onStreamError', (tester) async {
    final service = _ThrowingFinalizeChatService();
    final settings = SettingsProvider(createBusinessTestPreferences());
    final streamErrors = <String>[];
    var assistantFinishedCount = 0;
    late ChatActions actions;
    const channel = MethodChannel('test.chat_actions.background');
    final notifications = <String?>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => call.method == 'sync' ? <String, dynamic>{} : null,
        );
    final background = MobileBackgroundCoordinator(
      platform: TargetPlatform.android,
      channel: channel,
      notificationSender: ({required conversationId, title, body}) async {
        expect(service.terminalStates.last, GenerationRunState.failed);
        notifications.add(body);
      },
    );
    addTearDown(background.dispose);
    await background.configure(
      const MobileBackgroundSettings(notificationsEnabled: true),
      await AppLocalizations.delegate.load(const Locale('en')),
    );
    await background.start(
      id: 'assistant-1',
      conversationId: 'conversation-1',
      title: 'Test',
      cancel: () async {},
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<ChatService>.value(value: service),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              final graph = _actionsFor(context, service, settings, background);
              actions = graph.actions;
              actions.onStreamError = streamErrors.add;
              actions.onAssistantMessageFinished = (_) {
                assistantFinishedCount++;
              };
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    final state = StreamingState(
      GenerationContext(
        executionId: 'assistant-1',
        assistantMessage: ChatMessage(
          id: 'assistant-1',
          role: 'assistant',
          content: 'partial',
          conversationId: 'conversation-1',
          isStreaming: true,
        ),
        apiMessages: const [],
        userImagePaths: const [],
        allowImagesApiRouting: false,
        providerKey: 'test',
        modelId: 'test-model',
        assistant: null,
        settings: settings,
        config: ProviderConfig(
          id: 'test',
          enabled: true,
          name: 'Test',
          apiKey: '',
          baseUrl: '',
        ),
        toolDefs: const [],
        supportsReasoning: true,
        enableReasoning: true,
        streamOutput: true,
      ),
    );
    state.fullContentRaw = 'partial';

    await expectLater(
      actions.debugFinishStreaming(state),
      throwsA(isA<StateError>()),
    );
    expect(state.finishHandled, isTrue);
    expect(state.terminalPersisted, isFalse);
    expect(service.terminalStates, [GenerationRunState.completed]);
    expect(background.activeTaskIds, {'assistant-1'});
    expect(notifications, isEmpty);

    await actions.debugHandleStreamError(StateError('persist failed'), state);

    expect(state.terminalPersisted, isTrue);
    expect(service.terminalStates, [
      GenerationRunState.completed,
      GenerationRunState.failed,
    ]);
    expect(streamErrors, ['Bad state: persist failed']);
    expect(assistantFinishedCount, 0);
    expect(background.activeTaskIds, isEmpty);
    expect(notifications, ['Generation failed. Open the chat for details.']);
  });

  test('isEmptyAssistantReply only matches replies with nothing to show', () {
    ChatMessage reply({String content = '', List<MessagePart>? parts}) =>
        ChatMessage(
          id: 'a',
          role: 'assistant',
          content: content,
          parts: parts,
          conversationId: 'c',
        );
    expect(ChatActions.isEmptyAssistantReply(reply()), isTrue);
    expect(ChatActions.isEmptyAssistantReply(reply(content: ' \n ')), isTrue);
    expect(ChatActions.isEmptyAssistantReply(reply(content: 'hi')), isFalse);
    expect(
      ChatActions.isEmptyAssistantReply(
        reply().copyWith(reasoningText: 'thinking'),
      ),
      isFalse,
    );
    expect(
      ChatActions.isEmptyAssistantReply(
        reply(parts: [const TextPart(''), ReasoningPart('thinking')]),
      ),
      isFalse,
    );
  });

  testWidgets(
    'empty completed reply is stored as failed with a visible error',
    (tester) async {
      final service = _ThrowingFinalizeChatService(failCompletion: false);
      final settings = SettingsProvider(createBusinessTestPreferences());
      final background = MobileBackgroundCoordinator(
        platform: TargetPlatform.linux,
      );
      addTearDown(background.dispose);
      addTearDown(settings.dispose);
      final streamErrors = <String>[];
      final titleRequests = <String>[];
      var assistantFinishedCount = 0;
      late ChatActions actions;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsProvider>.value(value: settings),
            ChangeNotifierProvider<ChatService>.value(value: service),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) {
                actions = _actionsFor(
                  context,
                  service,
                  settings,
                  background,
                ).actions;
                actions.onStreamError = streamErrors.add;
                actions.onMaybeGenerateTitle = titleRequests.add;
                actions.onAssistantMessageFinished = (_) {
                  assistantFinishedCount++;
                };
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      final state = StreamingState(
        GenerationContext(
          executionId: 'assistant-1',
          assistantMessage: ChatMessage(
            id: 'assistant-1',
            role: 'assistant',
            content: '',
            modelId: 'test-model',
            conversationId: 'conversation-1',
            isStreaming: true,
          ),
          apiMessages: const [],
          userImagePaths: const [],
          allowImagesApiRouting: false,
          providerKey: 'test',
          modelId: 'test-model',
          assistant: null,
          settings: settings,
          config: ProviderConfig(
            id: 'test',
            enabled: true,
            name: 'Test',
            apiKey: '',
            baseUrl: '',
          ),
          toolDefs: const [],
          supportsReasoning: false,
          enableReasoning: false,
          streamOutput: true,
        ),
      );

      await actions.debugFinishStreaming(state);

      final expected = (await AppLocalizations.delegate.load(
        const Locale('en'),
      )).chatEmptyAssistantReply('test-model');
      expect(state.terminalPersisted, isTrue);
      expect(service.terminalStates, [GenerationRunState.failed]);
      expect(service.lastErrorCode, 'empty_response');
      expect(service.lastMessage!.content, expected);
      expect(service.lastMessage!.isStreaming, isFalse);
      expect(streamErrors, [expected]);
      expect(assistantFinishedCount, 0);
      expect(titleRequests, isEmpty);
    },
  );

  testWidgets(
    'generation waits for narration handoff through the ViewModel callback',
    (tester) async {
      final service = _ThrowingFinalizeChatService(failCompletion: false);
      final settings = SettingsProvider(createBusinessTestPreferences());
      const channel = MethodChannel('test.chat_actions.handoff');
      var terminalSyncs = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'sync' &&
            (call.arguments as Map)['terminal'] != null) {
          terminalSyncs++;
        }
        return call.method == 'sync' ? <String, dynamic>{} : null;
      });
      final background = MobileBackgroundCoordinator(
        platform: TargetPlatform.android,
        channel: channel,
      );
      addTearDown(background.dispose);
      addTearDown(settings.dispose);
      await background.configure(
        const MobileBackgroundSettings(androidEnabled: true),
        await AppLocalizations.delegate.load(const Locale('en')),
      );
      await background.start(
        id: 'assistant-1',
        conversationId: 'conversation-1',
        title: 'Test',
        cancel: () async {},
      );
      final preparing = Completer<void>();
      final ready = Completer<void>();
      late ChatActions actions;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsProvider>.value(value: settings),
            ChangeNotifierProvider<ChatService>.value(value: service),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) {
                final graph = _actionsFor(
                  context,
                  service,
                  settings,
                  background,
                );
                actions = graph.actions;
                actions.onAssistantMessageFinished =
                    graph.viewModel.debugChatActions.onAssistantMessageFinished;
                graph.viewModel.onAssistantMessageFinished = (_) async {
                  expect(service.terminalStates, [
                    GenerationRunState.completed,
                  ]);
                  preparing.complete();
                  await ready.future;
                };
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      final state = StreamingState(
        GenerationContext(
          executionId: 'assistant-1',
          assistantMessage: ChatMessage(
            id: 'assistant-1',
            role: 'assistant',
            content: 'reply',
            conversationId: 'conversation-1',
            isStreaming: true,
          ),
          apiMessages: const [],
          userImagePaths: const [],
          allowImagesApiRouting: false,
          providerKey: 'test',
          modelId: 'test-model',
          assistant: null,
          settings: settings,
          config: ProviderConfig(
            id: 'test',
            enabled: true,
            name: 'Test',
            apiKey: '',
            baseUrl: '',
          ),
          toolDefs: const [],
          supportsReasoning: true,
          enableReasoning: true,
          streamOutput: true,
        ),
      )..fullContentRaw = 'reply';
      final finished = actions.debugFinishStreaming(state);
      await preparing.future;
      await tester.pump(const Duration(milliseconds: 40));
      await background.flush();
      expect(background.activeTaskIds, {'assistant-1'});
      expect(terminalSyncs, 0);
      ready.complete();
      await finished;
      await background.flush();
      expect(background.activeTaskIds, isEmpty);
      expect(terminalSyncs, 1);
    },
  );
}
