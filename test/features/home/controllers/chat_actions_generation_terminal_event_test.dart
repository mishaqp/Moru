import 'dart:async' as async;
import 'dart:convert';
import 'dart:io';

import 'package:Kelivo/core/database/app_database.dart';
import 'package:Kelivo/core/database/chat_database_repository.dart';
import 'package:Kelivo/core/database/generation_run.dart';
import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/models/message_part.dart';
import 'package:Kelivo/core/models/provider_oauth.dart';
import 'package:Kelivo/core/models/workspace.dart';
import 'package:Kelivo/core/models/workspace_binding.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/chat/chat_service.dart';
import 'package:Kelivo/core/services/acp/acp_connection.dart';
import 'package:Kelivo/core/services/api/chat_api_service.dart';
import 'package:Kelivo/core/services/mobile_background.dart';
import 'package:Kelivo/core/services/api/stream/stream_chunk.dart';
import 'package:Kelivo/core/services/workspace/tool_run_registry.dart';
import 'package:Kelivo/core/services/workspace/workspace_paths.dart';
import 'package:Kelivo/core/services/workspace/workspace_runtime.dart';
import 'package:Kelivo/core/services/workspace/workspace_tools_service.dart';
import 'package:Kelivo/features/chat/widgets/chat_message_widget.dart';
import 'package:Kelivo/features/chat/widgets/computer_response_scope.dart';
import 'package:Kelivo/features/home/controllers/chat_actions.dart';
import 'package:Kelivo/features/home/controllers/chat_controller.dart';
import 'package:Kelivo/features/home/controllers/generation_controller.dart';
import 'package:Kelivo/features/home/controllers/generation_terminal_event.dart';
import 'package:Kelivo/features/home/controllers/home_view_model.dart';
import 'package:Kelivo/features/home/controllers/stream_controller.dart';
import 'package:Kelivo/features/home/services/message_builder_service.dart';
import 'package:Kelivo/features/home/services/message_generation_service.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/utils/mcp_structured_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/business_test_harness.dart';

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.root);
  final String root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getApplicationCachePath() async => '$root/cache';
}

/// Records native process identities independently of reused API call IDs.
class _RecordingRuntime extends WorkspaceRuntime {
  final requests = <CommandRequest>[];
  final cancelled = <String>[];
  final streams = <String, async.StreamController<CommandEvent>>{};
  final _started = <String, async.Completer<void>>{};

  @override
  Future<RuntimeStatus> status() async =>
      const RuntimeStatus(ready: true, engine: 'fake', sandboxed: true);

  @override
  Stream<CommandEvent> run(CommandRequest request) {
    requests.add(request);
    final controller = async.StreamController<CommandEvent>();
    streams[request.runId] = controller;
    controller.add(const CommandStarted());
    final started = _started.putIfAbsent(request.command, async.Completer.new);
    if (!started.isCompleted) started.complete();
    return controller.stream;
  }

  Future<void> whenStarted(String command) => _started
      .putIfAbsent(command, async.Completer.new)
      .future
      .timeout(const Duration(seconds: 10));

  @override
  Future<void> cancel(String runId) async {
    cancelled.add(runId);
    await finish(runId, cancelled: true);
  }

  Future<void> finish(String runId, {bool cancelled = false}) async {
    final controller = streams[runId]!;
    if (controller.isClosed) return;
    controller.add(
      CommandExited(
        exitCode: cancelled ? 137 : 0,
        timedOut: false,
        cancelled: cancelled,
        interrupted: false,
        duration: Duration.zero,
      ),
    );
    await controller.close();
  }
}

/// [failCompletion] mirrors `chat_actions_terminal_persist_test.dart`'s own
/// fake: when true, a `completed` write throws, so
/// `_finalizeStreamingCheckpoint`'s `committed` guard must stay false and
/// [ChatActions.generationTerminalEvents] must never fire for it.
class _FakeChatService extends ChatService {
  _FakeChatService({this.failCompletion = false});
  final bool failCompletion;
  List<Map<String, dynamic>> lastToolEvents = [];

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
    lastToolEvents = toolEvents;
    if (failCompletion && terminalState == GenerationRunState.completed) {
      throw StateError('persist failed');
    }
    return null;
  }
}

// Built directly (not through HomeViewModel, whose ChatActions always
// defaults to the real MobileBackgroundCoordinator.instance singleton and
// its unmocked platform channels) so each test gets an isolated, explicit
// MobileBackgroundCoordinator -- the same pattern
// chat_actions_terminal_persist_test.dart already uses.
ChatActions _actionsFor(
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
  return ChatActions(
    chatService: service,
    chatController: chatController,
    streamController: streamController,
    generationController: generationController,
    messageGenerationService: messageGeneration,
    contextProvider: context,
    viewModel: viewModel,
    backgroundCoordinator: background,
  );
}

StreamingState _stateFor(
  SettingsProvider settings, {
  required String messageId,
  required String content,
}) => StreamingState(
  GenerationContext(
    assistantMessage: ChatMessage(
      id: messageId,
      role: 'assistant',
      content: '',
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
)..fullContentRaw = content;

void main() {
  // The native Android background host is outside these persistence tests.
  // Keep the real Android coordinator with a deterministic channel boundary.
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('app.mobile_background'),
          (call) async => call.method == 'sync' ? <String, Object?>{} : null,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('app.mobile_background'),
          null,
        );
  });

  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(const {});

  Future<ChatActions> pumpActions(
    WidgetTester tester,
    ChatService service,
    SettingsProvider settings, {
    required MobileBackgroundCoordinator background,
    ToolRunRegistry? registry,
  }) async {
    late ChatActions actions;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<ChatService>.value(value: service),
          if (registry != null)
            ChangeNotifierProvider<ToolRunRegistry>.value(value: registry),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              actions = _actionsFor(context, service, settings, background);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    return actions;
  }

  testWidgets(
    'a successful finish emits a completed event carrying the real content',
    (tester) async {
      final service = _FakeChatService();
      final settings = SettingsProvider(createBusinessTestPreferences());
      addTearDown(settings.dispose);
      final background = MobileBackgroundCoordinator(
        platform: TargetPlatform.android,
      );
      addTearDown(background.dispose);
      final actions = await pumpActions(
        tester,
        service,
        settings,
        background: background,
      );
      final events = <GenerationTerminalEvent>[];
      actions.generationTerminalEvents.listen(events.add);

      final state = _stateFor(
        settings,
        messageId: 'assistant-1',
        content: 'The final answer.',
      );
      await actions.debugFinishStreaming(state);

      expect(events, hasLength(1));
      final event = events.single;
      expect(event.conversationId, 'conversation-1');
      expect(event.assistantMessageId, 'assistant-1');
      expect(event.terminalState, GenerationRunState.completed);
      expect(event.succeeded, isTrue);
      expect(event.cancelled, isFalse);
      expect(event.message.content, 'The final answer.');
      expect(event.errorCode, isNull);
    },
  );

  testWidgets(
    'a failed terminal write never emits: a listener would otherwise wait '
    'forever for a run that never actually finished',
    (tester) async {
      final service = _FakeChatService(failCompletion: true);
      final settings = SettingsProvider(createBusinessTestPreferences());
      addTearDown(settings.dispose);
      final background = MobileBackgroundCoordinator(
        platform: TargetPlatform.android,
      );
      addTearDown(background.dispose);
      final actions = await pumpActions(
        tester,
        service,
        settings,
        background: background,
      );
      final events = <GenerationTerminalEvent>[];
      actions.generationTerminalEvents.listen(events.add);

      final state = _stateFor(
        settings,
        messageId: 'assistant-1',
        content: 'unwritten',
      );
      await expectLater(
        actions.debugFinishStreaming(state),
        throwsA(isA<StateError>()),
      );
      await tester.pump();

      expect(events, isEmpty);
    },
  );

  testWidgets(
    'a stream error emits a failed event with the error code, not the '
    'success path',
    (tester) async {
      final service = _FakeChatService();
      final settings = SettingsProvider(createBusinessTestPreferences());
      addTearDown(settings.dispose);
      final background = MobileBackgroundCoordinator(
        platform: TargetPlatform.android,
      );
      addTearDown(background.dispose);
      final actions = await pumpActions(
        tester,
        service,
        settings,
        background: background,
      );
      final events = <GenerationTerminalEvent>[];
      actions.generationTerminalEvents.listen(events.add);

      final state = _stateFor(
        settings,
        messageId: 'assistant-1',
        content: 'Partial reply',
      );
      await actions.debugHandleStreamError(
        const ProviderOAuthException(
          ProviderOAuthFailure.loginRequired,
          providerId: 'account',
        ),
        state,
      );
      await tester.pump();

      expect(events, hasLength(1));
      final event = events.single;
      expect(event.terminalState, GenerationRunState.failed);
      expect(event.succeeded, isFalse);
      expect(event.cancelled, isFalse);
      expect(event.errorCode, 'oauth_login_required');
      expect(event.message.content, 'Partial reply');
    },
  );

  testWidgets('a manual cancel (Stop) emits a cancelled event', (tester) async {
    final service = _FakeChatService();
    final settings = SettingsProvider(createBusinessTestPreferences());
    addTearDown(settings.dispose);
    final background = MobileBackgroundCoordinator(
      platform: TargetPlatform.android,
    );
    addTearDown(background.dispose);
    final actions = await pumpActions(
      tester,
      service,
      settings,
      background: background,
    );
    final events = <GenerationTerminalEvent>[];
    actions.generationTerminalEvents.listen(events.add);

    actions.debugTrackActiveMessage(
      ChatMessage(
        id: 'assistant-1',
        role: 'assistant',
        content: 'partial before stop',
        conversationId: 'conversation-1',
        isStreaming: true,
      ),
    );

    await actions.cancelStreamingById('conversation-1');
    await tester.pump();

    expect(events, hasLength(1));
    final event = events.single;
    expect(event.assistantMessageId, 'assistant-1');
    expect(event.terminalState, GenerationRunState.cancelled);
    expect(event.succeeded, isFalse);
    expect(event.cancelled, isTrue);
  });

  for (final scenario in [
    'update_plan',
    'shell',
    'background',
    'background_pending',
  ]) {
    testWidgets('Stop during $scenario survives closing and reopening SQLite', (
      tester,
    ) async {
      final originalPaths = PathProviderPlatform.instance;
      final temp = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('moru-stopped-plan-'),
      ))!;
      PathProviderPlatform.instance = _TestPaths(temp.path);
      addTearDown(() async {
        PathProviderPlatform.instance = originalPaths;
        await temp.delete(recursive: true);
      });
      final dbFile = File('${temp.path}/chat-test.sqlite');
      final repository = ChatDatabaseRepository(
        AppDatabase(NativeDatabase(dbFile)),
      );
      final service = ChatService(existingRepository: repository);
      final conversation = (await tester.runAsync(() async {
        await service.init();
        return service.createConversation();
      }))!;
      final pending = ChatMessage(
        id: 'pending-plan',
        role: 'assistant',
        conversationId: conversation.id,
        isStreaming: true,
        parts: [
          ToolCallPart(
            jsonEncode({
              'id': 'plan',
              'name': scenario == 'update_plan' ? 'update_plan' : 'shell',
              'arguments': {
                if (scenario == 'update_plan')
                  'plan': [
                    {'step': 'Inspect', 'status': 'in_progress'},
                  ]
                else
                  'command': 'sleep 100',
                if (scenario.startsWith('background')) 'background': true,
              },
              if (scenario == 'background')
                'content': jsonEncode({
                  'background': true,
                  'job_id': 'persisted-job',
                }),
            }),
          ),
        ],
      );
      await tester.runAsync(
        () => service.addMessageDirectly(conversation.id, pending),
      );
      final settings = SettingsProvider(createBusinessTestPreferences());
      final registry = ToolRunRegistry();
      final run = scenario == 'update_plan'
          ? null
          : registry.start(
              'plan',
              'shell',
              conversationId: conversation.id,
              responseId: pending.id,
              background: scenario.startsWith('background'),
              runtimeRunId: 'persisted-job',
            );
      final background = MobileBackgroundCoordinator(
        platform: TargetPlatform.android,
      );
      addTearDown(settings.dispose);
      addTearDown(registry.dispose);
      addTearDown(background.dispose);
      final actions = await pumpActions(
        tester,
        service,
        settings,
        background: background,
        registry: registry,
      );
      actions.debugTrackActiveMessage(pending);
      await tester.runAsync(() async {
        await actions.cancelStreamingById(conversation.id);
        await service.close();
        await repository.close();
      });

      final reopenedRepository = ChatDatabaseRepository(
        AppDatabase(NativeDatabase(dbFile)),
      );
      final reopened = ChatService(existingRepository: reopenedRepository);
      final restored = (await tester.runAsync(() async {
        await reopened.init();
        return reopenedRepository.getMessage('pending-plan');
      }))!;
      expect(restored.isStreaming, isFalse);
      final step = computerStepsFromMessage(restored).single;
      expect(step.isStopped, !scenario.startsWith('background'));
      expect(step.responseStopped, isTrue);
      if (run != null) {
        expect(
          run.status,
          scenario.startsWith('background')
              ? ToolRunStatus.running
              : ToolRunStatus.cancelled,
        );
      }
      if (scenario.startsWith('background')) {
        if (scenario == 'background') {
          expect(jsonDecode(step.content!)['job_id'], 'persisted-job');
        } else {
          expect(step.metadata?['computer']['runtimeRunId'], 'persisted-job');
          expect(
            toolUiFromPayload(
              restored.parts.whereType<ToolCallPart>().single.payloadJson,
            )!.loading,
            isFalse,
          );
        }
        expect(
          withComputerRuns(
            [step],
            registry,
            conversation.id,
            responseId: pending.id,
          ).single.run,
          same(run),
        );
        run!.complete(status: ToolRunStatus.succeeded);
      }
      actions.streamController.restoreMessageUiState(
        restored,
        getToolEventsFromDb: (_) => [
          for (final part in restored.parts.whereType<ToolCallPart>())
            Map<String, dynamic>.from(jsonDecode(part.payloadJson) as Map),
        ],
      );
      expect(actions.streamController.hasLoadingTools(restored.id), isFalse);
      await tester.runAsync(() async {
        await reopened.close();
        await reopenedRepository.close();
      });
    });
  }

  for (final tool in ['update_plan', 'shell']) {
    testWidgets('Stop settles pending $tool in live and durable state', (
      tester,
    ) async {
      final service = _FakeChatService();
      final settings = SettingsProvider(createBusinessTestPreferences());
      final registry = ToolRunRegistry();
      final background = MobileBackgroundCoordinator(
        platform: TargetPlatform.android,
      );
      addTearDown(settings.dispose);
      addTearDown(registry.dispose);
      addTearDown(background.dispose);
      final actions = await pumpActions(
        tester,
        service,
        settings,
        background: background,
        registry: registry,
      );
      final events = <GenerationTerminalEvent>[];
      actions.generationTerminalEvents.listen(events.add);
      final state = _stateFor(settings, messageId: 'stopped', content: '');
      actions.debugTrackStreamingState(state);
      await actions.debugHandleStreamChunk(
        ToolCallStart(
          id: 'pending',
          toolName: tool,
          metadata: tool == 'shell'
              ? {
                  'workspace': {'tool': 'shell', 'status': 'error'},
                }
              : null,
        ),
        state,
      );
      await actions.debugHandleStreamChunk(
        ToolCallDelta(
          id: 'pending',
          inputDelta: jsonEncode(
            tool == 'shell'
                ? {'command': 'sleep 10'}
                : {
                    'plan': [
                      {'step': 'Inspect', 'status': 'in_progress'},
                    ],
                  },
          ),
        ),
        state,
      );
      await actions.debugHandleStreamChunk(const ToolCallEnd('pending'), state);
      final foreground = tool == 'shell'
          ? registry.start('pending', tool, conversationId: 'conversation-1')
          : null;
      final unrelated = registry.start(
        'other',
        'shell',
        conversationId: 'conversation-2',
      );
      expect(actions.streamController.hasLoadingTools('stopped'), isTrue);

      await actions.cancelStreamingById('conversation-1');
      await tester.pump();

      expect(actions.streamController.hasLoadingTools('stopped'), isFalse);
      expect(
        actions.chatController.isConversationLoading('conversation-1'),
        isFalse,
      );
      expect(
        foreground?.status,
        tool == 'shell' ? ToolRunStatus.cancelled : null,
      );
      expect(unrelated.status, ToolRunStatus.running);
      final stoppedPart = events.single.message.parts
          .whereType<ToolCallPart>()
          .single;
      final restored =
          MessagePart.fromRow(stoppedPart.kind, stoppedPart.encodePayload())
              as ToolCallPart;
      final restoredUi = toolUiFromPayload(restored.payloadJson)!;
      expect(restoredUi.metadata?['computer'], {
        'status': 'stopped',
        'responseStopped': true,
      });
      expect(restoredUi.loading, isFalse);
      expect(
        computerStepsFromMessage(events.single.message).single.loading,
        isFalse,
      );
      expect(service.lastToolEvents.single['metadata']['computer'], {
        'status': 'stopped',
        'responseStopped': true,
      });
      unrelated.complete(status: ToolRunStatus.succeeded);
    });
  }

  testWidgets(
    'Stop cancels each owned native runtime once despite a reused call id',
    (tester) async {
      final service = _FakeChatService();
      final settings = SettingsProvider(createBusinessTestPreferences());
      final registry = ToolRunRegistry();
      final background = MobileBackgroundCoordinator(
        platform: TargetPlatform.android,
      );
      addTearDown(settings.dispose);
      addTearDown(registry.dispose);
      addTearDown(background.dispose);
      final actions = await pumpActions(
        tester,
        service,
        settings,
        background: background,
        registry: registry,
      );
      actions.debugTrackActiveMessage(
        ChatMessage(
          id: 'stopped',
          role: 'assistant',
          conversationId: 'conversation-1',
          isStreaming: true,
          parts: [
            ToolCallPart(
              jsonEncode({
                'id': 'reused-call',
                'name': 'shell',
                'arguments': {'command': 'owned first'},
              }),
            ),
          ],
        ),
      );

      // Exercise the real request cancellation token and shell handler, with
      // an observed native backend rather than direct registry completion.
      await tester.runAsync(() async {
        final previousHttpOverrides = HttpOverrides.current;
        HttpOverrides.global = null;
        const keepAliveChannel = MethodChannel('app.keep_alive');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          keepAliveChannel,
          (call) async => call.method == 'hold' ? true : null,
        );
        final temp = await Directory.systemTemp.createTemp('stop-owned-runs-');
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final runtime = _RecordingRuntime();
        final provider = WorkspaceRuntimeProvider()..register(runtime);
        final tools = WorkspaceToolsService(
          registry: registry,
          runtimeProvider: provider,
          reportBackgroundShellResult:
              ({
                required id,
                required conversationId,
                required succeeded,
              }) async {},
        );
        final paths = WorkspacePaths.native(
          workspaceHostRoot: temp.path,
          sessionHostDir: '${temp.path}/session',
          skillsHostDir: '${temp.path}/skills',
        );
        await Directory(paths.sessionHostDir).create();
        await Directory(paths.skillsHostDir).create();
        final ctx = WorkspaceToolContext(
          workspace: Workspace(
            id: 'workspace',
            name: 'Workspace',
            kind: WorkspaceKind.managed,
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
          ),
          binding: const WorkspaceBinding(
            workspaceId: 'workspace',
            allowAll: true,
          ),
          paths: paths,
          sessionDir: Directory(paths.sessionHostDir),
          outputsDir: Directory('${paths.sessionHostDir}/outputs'),
          conversationId: 'conversation-1',
          runtimeStatus: await runtime.status(),
          runtimeRegistered: true,
        );
        ToolApprovalOwner owner(String responseId, [String? conversationId]) =>
            ToolApprovalOwner(
              conversationId: conversationId ?? 'conversation-1',
              generationRunId: 'generation-$responseId',
              assistantMessageId: responseId,
              isActive: () => true,
            );
        final pending = <Future<Object?>>[];
        async.StreamSubscription<StreamChunk>? subscription;
        final ownedFinished = async.Completer<void>();
        var requestCount = 0;
        server.listen((request) async {
          await request.drain<void>();
          requestCount++;
          request.response.headers.contentType = ContentType(
            'text',
            'event-stream',
          );
          request.response.write(
            'data: ${jsonEncode({
              'choices': [
                {
                  'index': 0,
                  'delta': requestCount == 1 ? {
                          'role': 'assistant',
                          'tool_calls': [
                            {
                              'index': 0,
                              'id': 'reused-call',
                              'type': 'function',
                              'function': {
                                'name': 'shell',
                                'arguments': jsonEncode({'command': 'owned first'}),
                              },
                            },
                          ],
                        } : {'content': 'done'},
                  'finish_reason': requestCount == 1 ? 'tool_calls' : 'stop',
                },
              ],
            })}\n\n',
          );
          request.response.write('data: [DONE]\n\n');
          await request.response.close();
        });
        try {
          // These genuine foreground processes belong to other identities;
          // neither inherits the stopped response's request cancellation zone.
          pending.add(
            owner('other-chat-response', 'conversation-2').run(
              () => tools.handle(
                ctx,
                'shell',
                {'command': 'other chat'},
                toolCallId: 'reused-call',
                conversationId: 'conversation-2',
              ),
            ),
          );
          pending.add(
            owner('sibling-response').run(
              () => tools.handle(ctx, 'shell', {
                'command': 'sibling response',
              }, toolCallId: 'reused-call'),
            ),
          );
          await Future.wait([
            runtime.whenStarted('other chat'),
            runtime.whenStarted('sibling response'),
          ]);
          subscription = ChatApiService.sendMessageStream(
            config: ProviderConfig(
              id: 'StopRegression',
              enabled: true,
              name: 'Stop regression',
              apiKey: 'local-test',
              baseUrl: 'http://127.0.0.1:${server.port}/v1',
              providerType: ProviderKind.openai,
            ),
            modelId: 'gpt-4o',
            requestId: 'conversation-1',
            messages: const [
              {'role': 'user', 'content': 'Run commands'},
            ],
            tools: tools.buildToolDefinitions(ctx),
            onToolCall: (name, args, {toolCallId}) =>
                owner('stopped').run(() async {
                  // A background job launched by this same token must detach
                  // from reply Stop and remain controllable by its real job ID.
                  await tools.handle(ctx, 'shell', {
                    'command': 'owned background',
                    'background': true,
                  }, toolCallId: toolCallId!);
                  final executions = [
                    tools.handle(ctx, name, args, toolCallId: toolCallId),
                    tools.handle(ctx, name, {
                      'command': 'owned second',
                    }, toolCallId: toolCallId),
                  ];
                  pending.addAll(executions);
                  final results = await Future.wait(executions);
                  ownedFinished.complete();
                  return results.first;
                }),
          ).listen((_) {}, onError: (Object _) {});
          await Future.wait([
            runtime.whenStarted('owned first'),
            runtime.whenStarted('owned second'),
          ]);
          final owned = runtime.requests
              .where(
                (request) =>
                    request.command == 'owned first' ||
                    request.command == 'owned second',
              )
              .toList();
          final surviving = runtime.requests
              .where((request) => !owned.contains(request))
              .toList();
          expect(owned, hasLength(2));
          expect(surviving, hasLength(3));
          expect(owned.map((request) => request.runId).toSet(), hasLength(2));
          for (final request in owned) {
            expect(
              registry
                  .byRuntimeRunId(
                    request.runId,
                    conversationId: 'conversation-1',
                  )
                  ?.responseId,
              'stopped',
            );
          }

          final stopping = actions.cancelStreamingById('conversation-1');
          final duplicate = actions.cancelStreamingById('conversation-1');
          expect(duplicate, same(stopping));
          await Future.wait([stopping, duplicate]);
          await ownedFinished.future.timeout(const Duration(seconds: 10));
          final expectedCancelled = owned
              .map((request) => request.runId)
              .toList();
          expect(runtime.cancelled, orderedEquals(expectedCancelled));
          for (final request in owned) {
            expect(
              registry
                  .byRuntimeRunId(
                    request.runId,
                    conversationId: 'conversation-1',
                  )
                  ?.status,
              ToolRunStatus.cancelled,
            );
          }
          for (final request in surviving) {
            expect(request.isCancelled?.call() ?? false, isFalse);
            expect(
              registry
                  .byRuntimeRunId(
                    request.runId,
                    conversationId: request.command == 'other chat'
                        ? 'conversation-2'
                        : 'conversation-1',
                  )
                  ?.status,
              ToolRunStatus.running,
            );
          }
          final jobId = surviving
              .singleWhere((request) => request.command == 'owned background')
              .runId;
          final jobResult = ClientToolResult.fromHandler(
            await tools.handle(ctx, 'shell_output', {
              'job_id': jobId,
            }, toolCallId: 'read-background'),
          );
          expect(jsonDecode(jobResult.content)['job_id'], jobId);
          expect(jsonDecode(jobResult.content)['status'], 'running');
          await actions.cancelStreamingById('conversation-1');
          expect(runtime.cancelled, orderedEquals(expectedCancelled));
          expect(requestCount, 1);
        } finally {
          ChatApiService.cancelRequest('conversation-1');
          for (final request in runtime.requests) {
            await runtime.finish(request.runId);
          }
          await Future.wait(pending);
          await subscription?.cancel();
          await server.close(force: true);
          provider.dispose();
          await temp.delete(recursive: true);
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            keepAliveChannel,
            null,
          );
          HttpOverrides.global = previousHttpOverrides;
        }
      });
    },
  );

  testWidgets('Stop preserves owned background jobs and reused call owners', (
    tester,
  ) async {
    final service = _FakeChatService();
    final settings = SettingsProvider(createBusinessTestPreferences());
    final registry = ToolRunRegistry();
    final background = MobileBackgroundCoordinator(
      platform: TargetPlatform.android,
    );
    addTearDown(settings.dispose);
    addTearDown(registry.dispose);
    addTearDown(background.dispose);
    final actions = await pumpActions(
      tester,
      service,
      settings,
      background: background,
      registry: registry,
    );
    final job = registry.start(
      'reused',
      'shell',
      conversationId: 'conversation-1',
      responseId: 'stopped',
      background: true,
      runtimeRunId: 'job',
    );
    final superseding = registry.start(
      'reused',
      'shell',
      conversationId: 'conversation-1',
      responseId: 'other-response',
    );
    final orphanForeground = registry.start(
      'orphan',
      'shell',
      conversationId: 'conversation-1',
      responseId: 'stopped',
    );
    final events = <GenerationTerminalEvent>[];
    actions.generationTerminalEvents.listen(events.add);
    final pending = ChatMessage(
      id: 'stopped',
      role: 'assistant',
      conversationId: 'conversation-1',
      isStreaming: true,
      parts: [
        ToolCallPart(
          jsonEncode({
            'id': 'reused',
            'name': 'shell',
            'arguments': {'command': 'sleep 100', 'background': true},
            'content': jsonEncode({'background': true, 'job_id': 'job'}),
          }),
        ),
        ToolCallPart(
          jsonEncode({
            'id': 'read-job',
            'name': 'shell_output',
            'arguments': {'job_id': 'job', 'wait_seconds': 30},
          }),
        ),
      ],
    );
    actions.debugTrackActiveMessage(pending);
    await actions.cancelStreamingById('conversation-1');
    await tester.pump();
    expect(job.status, ToolRunStatus.running);
    expect(superseding.status, ToolRunStatus.running);
    expect(orphanForeground.status, ToolRunStatus.cancelled);
    final steps = computerStepsFromMessage(events.single.message);
    expect(steps.first.isStopped, isFalse);
    expect(steps.last.isStopped, isTrue);
    expect(steps.every((step) => step.responseStopped), isTrue);
    orphanForeground.complete(status: ToolRunStatus.succeeded, exitCode: 0);
    expect(orphanForeground.status, ToolRunStatus.cancelled);
    job.complete(status: ToolRunStatus.succeeded);
    superseding.complete(status: ToolRunStatus.succeeded);
  });

  testWidgets('Stop settles a background launch before its result arrives', (
    tester,
  ) async {
    final service = _FakeChatService();
    final settings = SettingsProvider(createBusinessTestPreferences());
    final registry = ToolRunRegistry();
    final background = MobileBackgroundCoordinator(
      platform: TargetPlatform.android,
    );
    addTearDown(settings.dispose);
    addTearDown(registry.dispose);
    addTearDown(background.dispose);
    final actions = await pumpActions(
      tester,
      service,
      settings,
      background: background,
      registry: registry,
    );
    final state = _stateFor(settings, messageId: 'stopped', content: '');
    actions.debugTrackStreamingState(state);
    await actions.debugHandleStreamChunk(
      const ToolCallStart(id: 'reused', toolName: 'shell'),
      state,
    );
    await actions.debugHandleStreamChunk(
      ToolCallDelta(
        id: 'reused',
        inputDelta: jsonEncode({'command': 'sleep 100', 'background': true}),
      ),
      state,
    );
    await actions.debugHandleStreamChunk(const ToolCallEnd('reused'), state);
    final job = registry.start(
      'reused',
      'shell',
      conversationId: 'conversation-1',
      responseId: 'stopped',
      background: true,
      runtimeRunId: 'pending-job',
    );
    final newer = registry.start(
      'reused',
      'shell',
      conversationId: 'conversation-1',
      responseId: 'newer',
    );
    final events = <GenerationTerminalEvent>[];
    actions.generationTerminalEvents.listen(events.add);
    await actions.cancelStreamingById('conversation-1');
    await tester.pump();
    expect(actions.streamController.hasLoadingTools('stopped'), isFalse);
    expect(job.status, ToolRunStatus.running);
    final part = events.single.message.parts.whereType<ToolCallPart>().single;
    final hydrated = toolUiFromPayload(part.payloadJson)!;
    expect(hydrated.loading, isFalse);
    final steps = computerStepsFromMessage(events.single.message);
    expect(steps.single.isStopped, isFalse);
    expect(steps.single.metadata?['computer']['runtimeRunId'], 'pending-job');
    expect(
      withComputerRuns(
        steps,
        registry,
        'conversation-1',
        responseId: 'stopped',
      ).single.run,
      same(job),
    );
    expect(newer.status, ToolRunStatus.running);
    job.complete(status: ToolRunStatus.succeeded);
    newer.complete(status: ToolRunStatus.succeeded);
  });

  for (final partial in ['', 'Partial agent reply']) {
    testWidgets('ACP errors retain diagnostics after "$partial"', (
      tester,
    ) async {
      final service = _FakeChatService();
      final settings = SettingsProvider(createBusinessTestPreferences());
      addTearDown(settings.dispose);
      final background = MobileBackgroundCoordinator(
        platform: TargetPlatform.android,
      );
      addTearDown(background.dispose);
      final actions = await pumpActions(
        tester,
        service,
        settings,
        background: background,
      );
      final events = <GenerationTerminalEvent>[];
      final notifications = <String>[];
      actions.generationTerminalEvents.listen(events.add);
      actions.onStreamError = notifications.add;
      final state = _stateFor(
        settings,
        messageId: 'agent-error',
        content: partial,
      );
      await actions.debugHandleStreamError(
        const AcpError(
          -32603,
          'Internal error',
          {'nested': 'safe data'},
          null,
          'Internal error\n\nsafe data\n\nstderr explanation',
        ),
        state,
      );
      await tester.pump();

      final message = events.single.message;
      final part = message.parts.where((part) => part.kind == 'agent_error');
      expect(part, hasLength(1));
      expect(jsonDecode(part.single.encodePayload()), {
        'message': 'Internal error',
        'details': 'Internal error\n\nsafe data\n\nstderr explanation',
      });
      expect(message.content, partial);
      expect(events.single.terminalState, GenerationRunState.failed);
      expect(notifications, ['Internal error']);
    });
  }

  testWidgets(
    'a preparation failure before streaming ever started still emits',
    (tester) async {
      final service = _FakeChatService();
      final settings = SettingsProvider(createBusinessTestPreferences());
      addTearDown(settings.dispose);
      final background = MobileBackgroundCoordinator(
        platform: TargetPlatform.android,
      );
      addTearDown(background.dispose);
      final actions = await pumpActions(
        tester,
        service,
        settings,
        background: background,
      );
      final events = <GenerationTerminalEvent>[];
      actions.generationTerminalEvents.listen(events.add);

      await actions.handleSendGenerationFailure(
        error: StateError('generation failed'),
        conversationId: 'conversation-1',
        assistantMessage: ChatMessage(
          id: 'assistant-1',
          role: 'assistant',
          content: '',
          conversationId: 'conversation-1',
          isStreaming: true,
        ),
      );
      await tester.pump();

      expect(events, hasLength(1));
      final event = events.single;
      expect(event.terminalState, GenerationRunState.failed);
      expect(event.errorCode, 'preparation_failed');
    },
  );
}
