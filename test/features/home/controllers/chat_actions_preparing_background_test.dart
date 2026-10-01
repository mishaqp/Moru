import 'dart:async';

import 'package:Kelivo/core/database/chat_database_repository.dart';
import 'package:Kelivo/core/database/generation_run.dart';
import 'package:Kelivo/core/models/assistant.dart';
import 'package:Kelivo/core/models/chat_input_data.dart';
import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/models/conversation.dart';
import 'package:Kelivo/core/models/message_part.dart';
import 'package:Kelivo/core/models/mobile_background_settings.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/chat/chat_service.dart';
import 'package:Kelivo/core/services/mobile_background.dart';
import 'package:Kelivo/features/home/controllers/chat_actions.dart';
import 'package:Kelivo/features/home/controllers/chat_controller.dart';
import 'package:Kelivo/features/home/controllers/generation_controller.dart';
import 'package:Kelivo/features/home/controllers/home_view_model.dart';
import 'package:Kelivo/features/home/controllers/stream_controller.dart';
import 'package:Kelivo/features/home/services/ask_user_interaction_service.dart';
import 'package:Kelivo/features/home/services/message_builder_service.dart';
import 'package:Kelivo/features/home/services/message_generation_service.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../../support/business_test_harness.dart';

class _DelayedContextChatService extends ChatService {
  final contextEntered = Completer<void>();
  final contextReady = Completer<int>();
  final terminalStates = <GenerationRunState>[];
  final continuationBegins = <String>[];
  final terminalRunIds = <String?>[];
  VoidCallback? beforeBegin;
  bool failTerminalWrite = false;
  final conversation = Conversation(id: 'chat', title: 'Captured chat');
  late ChatMessage user, assistant;

  @override
  Conversation? getConversation(String id) =>
      id == 'chat' ? conversation : null;

  @override
  Future<GenerationBeginResult> beginSendGeneration({
    required String conversationId,
    required List<MessagePart> userParts,
    required String modelId,
    required String providerId,
    String? queuedInputId,
  }) async {
    beforeBegin?.call();
    user = ChatMessage(
      id: 'user',
      conversationId: conversationId,
      role: 'user',
      parts: userParts,
    );
    assistant = ChatMessage(
      id: 'assistant',
      conversationId: conversationId,
      role: 'assistant',
      content: '',
      isStreaming: true,
    );
    return (
      conversation: conversation,
      userMessage: user,
      assistantMessage: assistant,
      run: GenerationRun(
        id: 'run',
        conversationId: conversationId,
        targetRevisionId: assistant.id,
        state: GenerationRunState.preparing,
        stateRevision: 0,
        checkpointSeq: 0,
        errorCode: null,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        terminalAt: null,
      ),
    );
  }

  @override
  Future<int> resolveMessageCount(String conversationId) {
    contextEntered.complete();
    return contextReady.future;
  }

  @override
  Future<GenerationBeginResult> beginContinuationGeneration({
    required String conversationId,
    required String assistantMessageId,
    required String modelId,
    required String providerId,
  }) {
    continuationBegins.add(assistantMessageId);
    return beginSendGeneration(
      conversationId: conversationId,
      userParts: const [TextPart('prior input')],
      modelId: modelId,
      providerId: providerId,
    );
  }

  @override
  Future<List<ChatMessage>> loadSelectedContextMessages(
    String conversationId, {
    required int truncateIndex,
    required int limit,
    String? throughRevisionId,
    bool includeFollowingAssistant = false,
  }) async => [user, assistant];

  @override
  Future<GenerationRun> transitionGenerationRun({
    required String id,
    required GenerationRunState expectedState,
    required int expectedStateRevision,
    required GenerationRunState nextState,
    String? errorCode,
  }) async => throw StateError('request launch failed');

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
    terminalRunIds.add(generationRunId);
    if (failTerminalWrite) throw StateError('terminal write failed');
    return null;
  }
}

class _DelayedFilePreparation extends MessageGenerationService {
  _DelayedFilePreparation({
    required super.chatService,
    required super.messageBuilderService,
    required super.generationController,
    required super.streamController,
    required super.contextProvider,
    required this.entered,
    required this.ready,
  });
  final Completer<void> entered;
  final Completer<PreparedGeneration> ready;

  @override
  ({String? providerKey, String? modelId}) getModelConfig(
    SettingsProvider settings,
    Assistant? assistant, {
    Conversation? conversation,
  }) => (providerKey: 'test', modelId: 'test-model');

  @override
  Future<void> initializeReasoningState({
    required String messageId,
    required bool enableReasoning,
  }) async {}

  @override
  Future<PreparedGeneration> prepareApiMessagesWithInjections({
    required List<ChatMessage> messages,
    required Map<String, int> versionSelections,
    required Conversation? currentConversation,
    required SettingsProvider settings,
    required Assistant? assistant,
    required String? assistantId,
    required String providerKey,
    required String modelId,
    ToolApprovalService? approvalService,
    AskUserInteractionService? askUserService,
    String? processingMessageId,
    String? requiredAttachmentMessageId,
  }) {
    entered.complete();
    return ready.future;
  }
}

class _RecordingBackground extends MobileBackgroundCoordinator {
  _RecordingBackground(MethodChannel channel)
    : super(platform: TargetPlatform.android, channel: channel);
  final starts = <String>[];
  @override
  Future<void> start({
    required String id,
    required String conversationId,
    String assistantMessageId = '',
    required String title,
    required Future<void> Function() cancel,
    Future<void> Function()? beforeRuntimeStop,
    bool scheduled = false,
    bool scheduledNotify = true,
    bool scheduledPreview = true,
  }) {
    starts.add(id);
    return super.start(
      id: id,
      conversationId: conversationId,
      assistantMessageId: assistantMessageId,
      title: title,
      cancel: cancel,
      beforeRuntimeStop: beforeRuntimeStop,
      scheduled: scheduled,
      scheduledNotify: scheduledNotify,
      scheduledPreview: scheduledPreview,
    );
  }
}

void main() {
  const channel = MethodChannel('test.preparing_background');
  for (final finish in [
    'stop',
    'prepare error',
    'unpersisted prepare error',
    'execution',
    'send entry stop',
    'regenerate entry stop',
    'continue entry stop',
    'send entry error',
    'regenerate entry error',
    'continue entry error',
    'continue durable execution',
  ]) {
    testWidgets(
      'Public request protects preparation before Home; $finish releases captured task',
      (tester) async {
        late SettingsProvider settings;
        late AssistantProvider assistants;
        late _DelayedContextChatService service;
        late _RecordingBackground background;
        late Completer<void> fileEntered, finished;
        late Completer<PreparedGeneration> fileReady;
        final calls = <MethodCall>[];
        final committedRunIds = <String?>[];
        var ownedBeforeBegin = false;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            calls.add(call);
            return call.method == 'sync' || call.method == 'getStatus'
                ? <String, Object?>{}
                : null;
          },
        );
        await tester.runAsync(() async {
          settings = SettingsProvider(createBusinessTestPreferences());
          await settings.loaded;
          await settings.setMobileBackground(
            const MobileBackgroundSettings(
              androidEnabled: true,
              notificationsEnabled: true,
            ),
          );
          assistants = AssistantProvider(
            preferences: createBusinessTestPreferences(),
          );
          await assistants.loaded;
          service = _DelayedContextChatService();
          background = _RecordingBackground(channel);
          service.beforeBegin = () {
            ownedBeforeBegin = background.activeTaskIds.isNotEmpty;
          };
          fileEntered = Completer<void>();
          fileReady = Completer<PreparedGeneration>();
          finished = Completer<void>();
        });
        addTearDown(settings.dispose);
        addTearDown(assistants.dispose);
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
              ChangeNotifierProvider<AssistantProvider>.value(
                value: assistants,
              ),
            ],
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Builder(
                builder: (context) {
                  final chats = ChatController(chatService: service);
                  if (finish == 'continue durable execution') {
                    chats.messages.add(
                      ChatMessage(
                        id: 'assistant',
                        conversationId: 'chat',
                        role: 'assistant',
                        content: 'prior answer',
                      ),
                    );
                  }
                  final stream = StreamController(
                    onStateChanged: () {},
                    getSettingsProvider: () => settings,
                    getCurrentConversationId: () => null,
                  );
                  final builder = MessageBuilderService(
                    chatService: service,
                    contextProvider: context,
                  );
                  final generation = GenerationController(
                    chatService: service,
                    chatController: chats,
                    streamController: stream,
                    messageBuilderService: builder,
                    contextProvider: context,
                    onStateChanged: () {},
                    getTitleForLocale: (_) => 'title',
                  );
                  final preparation = _DelayedFilePreparation(
                    chatService: service,
                    messageBuilderService: builder,
                    generationController: generation,
                    streamController: stream,
                    contextProvider: context,
                    entered: fileEntered,
                    ready: fileReady,
                  );
                  final viewModel = HomeViewModel(
                    chatService: service,
                    messageBuilderService: builder,
                    messageGenerationService: preparation,
                    generationController: generation,
                    streamController: stream,
                    chatController: chats,
                    contextProvider: context,
                    getTitleForLocale: (_) => 'title',
                  );
                  actions = ChatActions(
                    chatService: service,
                    chatController: chats,
                    streamController: stream,
                    generationController: generation,
                    messageGenerationService: preparation,
                    contextProvider: context,
                    viewModel: viewModel,
                    backgroundCoordinator: background,
                  );
                  actions.onStreamError = (_) {
                    if (!finished.isCompleted) finished.complete();
                  };
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );
        await tester.runAsync(() async {
          background.didChangeAppLifecycleState(AppLifecycleState.resumed);
          if (finish.contains('entry')) {
            final entered = Completer<void>();
            final release = Completer<void>();
            Future<void> beforePreparation() {
              entered.complete();
              return release.future;
            }

            final message = ChatMessage(
              id: 'assistant',
              conversationId: 'chat',
              role: 'assistant',
              content: 'reply',
            );
            final pending = finish.startsWith('send')
                ? actions.sendMessage(
                    input: const ChatInputData(text: 'reply'),
                    conversation: service.conversation,
                    modelOverride: (providerKey: 'test', modelId: 'test-model'),
                    beforePreparation: beforePreparation,
                  )
                : finish.startsWith('regenerate')
                ? actions.regenerateAtMessage(
                    message: message,
                    conversation: service.conversation,
                    modelOverride: (providerKey: 'test', modelId: 'test-model'),
                    beforePreparation: beforePreparation,
                  )
                : actions.continueAssistantMessageAfterToolAnswer(
                    message: message,
                    conversation: service.conversation,
                    beforePreparation: beforePreparation,
                  );
            await entered.future;
            expect(background.starts, hasLength(1));
            expect(background.activeTaskIds, {background.starts.single});
            background.didChangeAppLifecycleState(AppLifecycleState.paused);
            if (finish.endsWith('stop')) {
              final stopped = actions.cancelStreamingById('chat');
              await pumpEventQueue();
              try {
                expect(background.activeTaskIds, isEmpty);
              } finally {
                release.complete();
                await pending;
                await stopped;
              }
            } else {
              release.completeError(StateError('preparation entry failed'));
              final rejected = await pending;
              expect(rejected.success, isFalse);
              expect(
                rejected.errorMessage,
                contains('preparation entry failed'),
              );
            }
            await background.flush();
            expect(service.terminalStates, isEmpty);
            expect(background.activeTaskIds, isEmpty);
            expect(calls.where((call) => call.method == 'showResult'), isEmpty);
            return;
          }
          final continued = finish == 'continue durable execution'
              ? actions.continueAssistantMessageAfterToolAnswer(
                  message: actions.chatController.messages.single,
                  conversation: service.conversation,
                  onGenerationCommitted: (runId) async {
                    expect(background.activeTaskIds, {'run'});
                    expect(service.contextEntered.isCompleted, isFalse);
                    committedRunIds.add(runId);
                  },
                )
              : null;
          if (continued == null) {
            final result = await actions.sendMessage(
              input: const ChatInputData(text: 'reply'),
              conversation: service.conversation,
              modelOverride: (providerKey: 'test', modelId: 'test-model'),
              onGenerationCommitted: (runId) async {
                expect(background.activeTaskIds, {'run'});
                expect(service.contextEntered.isCompleted, isFalse);
                committedRunIds.add(runId);
              },
            );
            expect(result.success, isTrue);
          }
          await service.contextEntered.future;
          expect(committedRunIds, ['run']);
          expect(ownedBeforeBegin, isTrue);
          expect(background.activeTaskIds, {'run'});
          final activeSync =
              calls.lastWhere((call) => call.method == 'sync').arguments as Map;
          expect(
            (activeSync['tasks'] as List).single,
            containsPair('id', 'run'),
          );
          expect(
            ((activeSync['tasks'] as List).single as Map)['detail'],
            isNotEmpty,
          );
          background.didChangeAppLifecycleState(AppLifecycleState.paused);
          await background.flush();
          expect(background.activeTaskIds, {'run'});
          if (finish == 'stop') {
            await actions.cancelStreamingById('chat');
            expect(service.terminalStates, [GenerationRunState.cancelled]);
            service.contextReady.completeError(
              StateError('late context result'),
            );
            await pumpEventQueue();
          } else {
            service.contextReady.complete(2);
            await fileEntered.future;
            expect(background.starts, hasLength(1));
            expect(background.activeTaskIds, {'run'});
            if (finish == 'execution' || continued != null) {
              fileReady.complete(
                PreparedGeneration(
                  apiMessages: const [],
                  toolDefs: const [],
                  hasBuiltInSearch: false,
                  lastUserImagePaths: const [],
                ),
              );
            } else {
              service.failTerminalWrite = finish == 'unpersisted prepare error';
              fileReady.completeError(StateError('private preparation error'));
            }
            await finished.future;
            expect(service.terminalStates, [GenerationRunState.failed]);
            if (continued != null) {
              final result = await continued;
              expect(result.success, isTrue);
              expect(result.generationRunId, 'run');
              expect(result.executionId, 'run');
              expect(service.continuationBegins, ['assistant']);
              expect(service.terminalRunIds, ['run']);
            }
          }
          await background.flush();
          expect(background.activeTaskIds, isEmpty);
          expect(background.starts, hasLength(1));
          expect(background.starts.single, isNot('run'));
          final ownerSnapshots = calls
              .where((call) => call.method == 'sync')
              .map((call) => (call.arguments as Map)['tasks'] as List)
              .toList();
          final firstOwner = ownerSnapshots.indexWhere(
            (tasks) => tasks.isNotEmpty,
          );
          final lastOwner = ownerSnapshots.lastIndexWhere(
            (tasks) => tasks.isNotEmpty,
          );
          expect(
            ownerSnapshots.sublist(firstOwner, lastOwner + 1),
            everyElement(hasLength(1)),
          );
          final results = calls
              .where((call) => call.method == 'showResult')
              .toList();
          expect(
            results,
            hasLength(
              finish == 'stop' || finish == 'unpersisted prepare error' ? 0 : 1,
            ),
          );
          if (results.isNotEmpty) {
            expect(
              results.single.arguments,
              containsPair('generationRunId', 'run'),
            );
            expect(results.single.arguments, containsPair('outcome', 'failed'));
            expect(
              (results.single.arguments as Map)['body'],
              isNot(contains('private preparation error')),
            );
          }
        });
        expect(tester.takeException(), isNull);
      },
    );
  }
}
