import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';

import '../../../support/business_test_harness.dart';
import 'package:Kelivo/core/services/browser/browser_agent_session.dart';
import 'package:Kelivo/core/services/workspace/task_plan.dart';
import 'package:Kelivo/core/database/chat_database_repository.dart';
import 'package:Kelivo/core/database/app_database.dart';
import 'package:Kelivo/core/database/generation_run.dart';
import 'package:Kelivo/core/models/agent_auth_mode.dart';
import 'package:Kelivo/core/models/chat_input_data.dart';
import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/models/conversation.dart';
import 'package:Kelivo/core/models/message_part.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/mcp_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/chat/chat_service.dart';
import 'package:Kelivo/core/services/mobile_background.dart';
import 'package:Kelivo/core/services/mcp/mcp_tool_service.dart';
import 'package:Kelivo/features/chat/widgets/chat_message_widget.dart'
    show ToolUIPart;
import 'package:Kelivo/features/home/controllers/home_page_controller.dart';
import 'package:Kelivo/features/home/controllers/chat_actions.dart';
import 'package:Kelivo/features/home/controllers/scroll_controller.dart';
import 'package:Kelivo/features/home/services/ask_user_interaction_service.dart';
import 'package:Kelivo/features/home/widgets/chat_input_bar.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.path);

  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;

  @override
  Future<String?> getApplicationSupportPath() async => path;

  @override
  Future<String?> getApplicationCachePath() async => '$path/cache';

  @override
  Future<String?> getTemporaryPath() async => '$path/tmp';
}

class _QueueWriteControlledChatService extends ChatService {
  _QueueWriteControlledChatService({required super.existingRepository});

  Future<void>? queueWriteHold;
  Completer<void>? queueWriteStarted;
  Completer<void>? sendBeginCommitted;
  Future<void>? sendBeginReturnHold;
  Completer<void>? answerWriteStarted;
  Future<void>? answerWriteHold;

  @override
  Future<GenerationBeginResult> beginSendGeneration({
    required String conversationId,
    required List<MessagePart> userParts,
    required String modelId,
    required String providerId,
    String? queuedInputId,
  }) async {
    final result = await super.beginSendGeneration(
      conversationId: conversationId,
      userParts: userParts,
      modelId: modelId,
      providerId: providerId,
      queuedInputId: queuedInputId,
    );
    final hold = sendBeginReturnHold;
    if (hold != null) {
      final committed = sendBeginCommitted;
      if (committed != null && !committed.isCompleted) committed.complete();
      await hold;
    }
    return result;
  }

  @override
  Future<void> upsertToolEvent(
    String assistantMessageId, {
    required String id,
    required String name,
    required Map<String, dynamic> arguments,
    String? content,
    Map<String, dynamic>? metadata,
  }) async {
    final hold = answerWriteHold;
    if (hold != null) {
      final started = answerWriteStarted;
      if (started != null && !started.isCompleted) started.complete();
      await hold;
    }
    await super.upsertToolEvent(
      assistantMessageId,
      id: id,
      name: name,
      arguments: arguments,
      content: content,
      metadata: metadata,
    );
  }

  Future<void> _waitForQueueWriter() async {
    final hold = queueWriteHold;
    if (hold == null) return;
    final started = queueWriteStarted;
    if (started != null && !started.isCompleted) started.complete();
    await hold;
  }

  @override
  Future<void> removeQueuedInput(QueuedChatInput item) async {
    await _waitForQueueWriter();
    await super.removeQueuedInput(item);
  }

  @override
  Future<void> setQueuedInputEditing(QueuedChatInput item, bool editing) async {
    await _waitForQueueWriter();
    await super.setQueuedInputEditing(item, editing);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory directory;
  late PathProviderPlatform previousPathProvider;
  late ChatDatabaseRepository repository;
  late AppDatabase database;
  late _QueueWriteControlledChatService service;
  late HttpServer server;
  late SettingsProvider settings;
  late AssistantProvider assistantProvider;
  var streamRequestCount = 0;
  final streamRequests = <Map<String, dynamic>>[];
  final apiRequests = <Map<String, dynamic>>[];
  Completer<void>? streamHold;
  Completer<void>? suggestionHold;
  final suggestionRequests = <Map<String, dynamic>>[];
  var suggestionResponse =
      '{"suggestions":["suggestion one","suggestion two"]}';
  var suggestionResponsesSent = 0;
  late AskUserInteractionService questions;
  late TaskPlanRegistry plans;

  Future<void> handleApiRequest(HttpRequest request) async {
    final body =
        jsonDecode(await utf8.decoder.bind(request).join())
            as Map<String, dynamic>;
    apiRequests.add(body);
    if (body['model'] == 'gpt-4o' &&
        body['stream'] != true &&
        !(body['messages'] as List).any((m) => m['role'] == 'tool')) {
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'choices': [
            {
              'message': {
                'role': 'assistant',
                'content': null,
                'tool_calls': [
                  {
                    'id': 'scheduled-ask',
                    'type': 'function',
                    'function': {
                      'name': AskUserToolNames.askUser,
                      'arguments': jsonEncode({
                        'questions': [
                          {'id': 'q1', 'question': 'Which option?'},
                        ],
                      }),
                    },
                  },
                ],
              },
              'finish_reason': 'tool_calls',
            },
          ],
        }),
      );
      await request.response.close();
      return;
    }
    if (body['stream'] == true) {
      streamRequestCount++;
      streamRequests.add(body);
      final hold = streamHold;
      if (hold != null) await hold.future;
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
        charset: 'utf-8',
      );
      request.response.write(
        'data: ${jsonEncode({
          'id': 'cmpl-race',
          'object': 'chat.completion.chunk',
          'created': 0,
          'model': 'test-model',
          'choices': [
            {
              'index': 0,
              'delta': {'role': 'assistant', 'content': 'ok'},
              'finish_reason': 'stop',
            },
          ],
        })}\n\n',
      );
      request.response.write('data: [DONE]\n\n');
      await request.response.close();
      return;
    }
    final isSuggestion = (body['messages'] as List).any(
      (m) =>
          m['role'] == 'system' &&
          (m['content'] as String).contains('candidate next messages'),
    );
    final response = suggestionResponse;
    if (isSuggestion) {
      suggestionRequests.add(body);
      final hold = suggestionHold;
      if (hold != null) await hold.future;
    }
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType.json;
    request.response.write(
      jsonEncode({
        'choices': [
          {
            'message': {'content': isSuggestion ? response : 'Test title'},
          },
        ],
      }),
    );
    await request.response.close();
    if (isSuggestion) suggestionResponsesSent++;
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('kelivo_send_race_');
    previousPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProviderPlatform(directory.path);
    // The widget-test binding replaces HttpClient with a 400-only mock; the
    // loopback API server below needs real networking.
    HttpOverrides.global = null;
    database = AppDatabase.open(file: File('${directory.path}/kelivo.db'));
    repository = ChatDatabaseRepository(
      database,
      databaseFile: File('${directory.path}/kelivo.db'),
    );
    await repository.ensureReady();
    service = _QueueWriteControlledChatService(existingRepository: repository);
    await service.init();
    streamRequestCount = 0;
    streamRequests.clear();
    apiRequests.clear();
    streamHold = null;
    suggestionHold = null;
    suggestionRequests.clear();
    suggestionResponsesSent = 0;
    suggestionResponse = '{"suggestions":["suggestion one","suggestion two"]}';
    questions = AskUserInteractionService();
    plans = TaskPlanRegistry();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(handleApiRequest);
  });

  tearDown(() async {
    PathProviderPlatform.instance = previousPathProvider;
    try {
      await server.close(force: true);
    } catch (_) {}
    try {
      await service.close().timeout(const Duration(seconds: 10));
    } catch (_) {}
    try {
      await repository.close().timeout(const Duration(seconds: 10));
    } catch (_) {}
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  Future<HomePageController> pumpHarness(
    WidgetTester tester, {
    bool withSuggestions = false,
  }) async {
    HomePageController? controller;
    final baseUrl = 'http://${server.address.address}:${server.port}/v1';
    // Futures only complete for awaits on the zone that created them, and the
    // send path runs inside runAsync: build and fully configure every provider
    // there so its loaded/write futures belong to the real-async zone.
    await tester.runAsync(() async {
      final settingsPrefs = createBusinessTestPreferences();
      await settingsPrefs.load();
      settings = SettingsProvider(settingsPrefs);
      await settings.loaded;
      await settings.setProviderConfig(
        'SiliconFlow',
        ProviderConfig(
          id: 'SiliconFlow',
          enabled: true,
          name: 'SiliconFlow',
          apiKey: 'race-test-key',
          baseUrl: baseUrl,
          providerType: ProviderKind.openai,
        ),
      );
      await settings.setCurrentModel('SiliconFlow', 'test-model');
      if (withSuggestions) {
        await settings.resetSuggestionModel();
      }

      final assistantPrefs = createBusinessTestPreferences();
      await assistantPrefs.load();
      assistantProvider = AssistantProvider(preferences: assistantPrefs);
      await assistantProvider.loaded;
      final assistantId = await assistantProvider.addAssistant(
        name: 'Test Assistant',
      );
      await assistantProvider.setCurrentAssistant(assistantId);
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AskUserInteractionService>.value(
            value: questions,
          ),
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<ChatService>.value(value: service),
          ChangeNotifierProvider<AssistantProvider>.value(
            value: assistantProvider,
          ),
          ChangeNotifierProvider<McpProvider>(
            create: (_) =>
                McpProvider(preferences: createBusinessTestPreferences()),
          ),
          ChangeNotifierProvider<McpToolService>(
            create: (_) => McpToolService(),
          ),
          ChangeNotifierProvider<TaskPlanRegistry>.value(value: plans),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: _ControllerHarness(onCreated: (value) => controller = value),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    return controller!;
  }

  Future<Conversation> openConversation(HomePageController controller) async {
    final convo = await service.createConversation(title: 'Race test');
    await controller.chatController.setCurrentConversationAndLoad(convo);
    return convo;
  }

  Future<void> waitFor(bool Function() condition, String description) async {
    for (var i = 0; i < 200; i++) {
      if (condition()) return;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    fail('timed out waiting for $description');
  }

  List<List<Map<String, dynamic>>> recordBackgroundSnapshots() {
    const channel = MethodChannel('app.mobile_background');
    final snapshots = <List<Map<String, dynamic>>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'sync') {
            final tasks = (call.arguments as Map)['tasks'] as List;
            snapshots.add([
              for (final task in tasks) Map<String, dynamic>.from(task as Map),
            ]);
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    return snapshots;
  }

  Future<void> runtimeStop(Iterable<String> ids) async {
    const channel = MethodChannel('app.mobile_background');
    final response = Completer<void>();
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('cancelTasks', {'ids': ids.toList()}),
          ),
          (data) {
            const StandardMethodCodec().decodeEnvelope(data!);
            response.complete();
          },
        );
    await response.future;
  }

  testWidgets('a new reply and a regenerated one start without the plan the '
      'last reply left open', (tester) async {
    final controller = await pumpHarness(tester);
    const stale = TaskPlan([
      PlanStep('Done', PlanStepStatus.completed),
      PlanStep('Left open', PlanStepStatus.inProgress),
    ]);
    await tester.runAsync(() async {
      final convo = await openConversation(controller);
      plans.set(convo.id, stale);
      await controller.sendMessage(ChatInputData(text: 'hello'));
      expect(plans.of(convo.id), isNull);
      await waitFor(
        () => !controller.chatController.isConversationLoading(convo.id),
        'streaming to finish',
      );

      plans.set(convo.id, stale);
      final assistantMessage = (await service.loadMessages(
        convo.id,
      )).firstWhere((m) => m.role == 'assistant');
      await controller.regenerateAtMessage(assistantMessage);
      expect(plans.of(convo.id), isNull);
      await waitFor(
        () => !controller.chatController.isConversationLoading(convo.id),
        'regeneration to finish',
      );
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('concurrent sends persist a single user/assistant pair', (
    tester,
  ) async {
    final controller = await pumpHarness(tester);
    await tester.runAsync(() async {
      final convo = await openConversation(controller);
      final first = controller.sendMessage(ChatInputData(text: 'hello')).then((
        r,
      ) {
        return r;
      });
      final second = controller.sendMessage(ChatInputData(text: 'hello')).then((
        r,
      ) {
        return r;
      });
      await Future.wait([first, second]);
      // sendMessage resolves once the pair is persisted; the streamed reply
      // keeps running in the background, so wait for it to finish.
      await waitFor(() => streamRequestCount == 1, 'stream request to fire');
      await waitFor(
        () => !controller.chatController.isConversationLoading(convo.id),
        'streaming to finish',
      );

      final messages = await service.loadMessages(convo.id);
      expect(messages.where((m) => m.role == 'user'), hasLength(1));
      expect(messages.where((m) => m.role == 'assistant'), hasLength(1));
      expect(
        messages.where((m) => m.role == 'assistant').single.isStreaming,
        isFalse,
      );
      expect(streamRequestCount, 1);
      expect(
        controller.chatController.isConversationLoading(convo.id),
        isFalse,
      );
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'queued acknowledgement is durable before returning and drain consumes once',
    (tester) async {
      final controller = await pumpHarness(tester);
      await tester.runAsync(() async {
        final convo = await openConversation(controller);
        streamHold = Completer<void>();
        await controller.sendMessage(const ChatInputData(text: 'first'));
        await waitFor(() => streamRequestCount == 1, 'first request');
        ChatInputSubmissionResult? result;
        final queued = controller
            .sendMessage(const ChatInputData(text: 'queued next'))
            .then((value) => result = value);
        await waitFor(() => result != null, 'durable queued acknowledgement');
        await queued;
        expect(result, ChatInputSubmissionResult.queued);
        expect(
          (await repository.queuedInputsForConversation(
            convo.id,
          )).map((item) => item.input.text),
          ['queued next'],
        );
        streamHold!.complete();
        streamHold = null;
        await waitFor(() => streamRequestCount == 2, 'queued request');
        await waitFor(
          () => !controller.chatController.isConversationLoading(convo.id),
          'queued completion',
        );
        expect(await repository.queuedInputsForConversation(convo.id), isEmpty);
        expect(
          (await service.loadMessages(
            convo.id,
          )).where((m) => m.role == 'user').map((m) => m.content),
          ['first', 'queued next'],
        );
      });
    },
  );

  for (final operation in ['remove', 'edit', 'switch']) {
    testWidgets('idle drain resumes once after a delayed durable $operation', (
      tester,
    ) async {
      final controller = await pumpHarness(tester);
      await tester.runAsync(() async {
        final convo = await openConversation(controller);
        final firstResponse = streamHold = Completer<void>();
        final writerRelease = Completer<void>();
        String? completedRunId;
        final terminal = controller.debugViewModel.generationTerminalEvents
            .listen((event) {
              completedRunId ??= event.generationRunId;
            });
        try {
          await controller.sendMessage(const ChatInputData(text: 'first'));
          await waitFor(() => streamRequestCount == 1, 'first request');
          await controller.sendMessage(const ChatInputData(text: 'eligible A'));
          await controller.sendMessage(const ChatInputData(text: 'blocked B'));
          final item = controller.queuedInputs.last;
          Conversation? other;
          if (operation == 'switch') {
            other = await service.createConversation(title: 'Other');
            await controller.debugViewModel.insertQueuedInput(
              id: 'e45ecc24-0420-42ae-9d7e-007ab7ee72c2',
              conversationId: other.id,
              index: 0,
              input: const ChatInputData(text: 'eligible C'),
            );
          }
          service.queueWriteStarted = Completer<void>();
          service.queueWriteHold = writerRelease.future;
          final mutation = operation == 'edit'
              ? controller.editQueuedMessage(item)
              : controller.removeQueuedMessage(item.id);
          await waitFor(
            () => service.queueWriteStarted!.isCompleted,
            'durable writer to be blocked',
          );
          firstResponse.complete();
          streamHold = null;
          await waitFor(
            () =>
                completedRunId != null &&
                !controller.chatController.isConversationLoading(convo.id),
            'first durable terminal',
          );
          expect(
            (await repository.getGenerationRun(completedRunId!))!.state,
            GenerationRunState.completed,
          );
          expect(streamRequestCount, 1);
          expect(
            (await repository.queuedInputsForConversation(
              convo.id,
            )).map((item) => item.input.text),
            ['eligible A', 'blocked B'],
          );
          if (other != null) {
            await controller.debugViewModel.switchConversation(other.id);
          }
          writerRelease.complete();
          await mutation;
          await waitFor(
            () => streamRequestCount == 2,
            'eligible FIFO after writer completion',
          );
          final activeId = other?.id ?? convo.id;
          await waitFor(
            () => !controller.chatController.isConversationLoading(activeId),
            'eligible FIFO completion',
          );
          expect(streamRequestCount, 2);
          expect(
            (await service.loadMessages(
              activeId,
            )).where((m) => m.role == 'user').map((m) => m.content),
            other == null ? ['first', 'eligible A'] : ['eligible C'],
          );
          final remaining = await repository.queuedInputsForConversation(
            convo.id,
          );
          if (operation == 'edit') {
            expect(remaining.single.id, item.id);
            expect(remaining.single.isEditing, isTrue);
            expect(controller.queuedMessageEditState?.id, item.id);
          } else if (other != null) {
            expect(remaining.single.input.text, 'eligible A');
          } else {
            expect(remaining, isEmpty);
          }
        } finally {
          if (!firstResponse.isCompleted) firstResponse.complete();
          if (!writerRelease.isCompleted) writerRelease.complete();
          streamHold = null;
          service.queueWriteHold = null;
          await terminal.cancel();
        }
      });
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'runtime Stop holds the durable FIFO before cancellation and across restart',
    (tester) async {
      final snapshots = recordBackgroundSnapshots();
      final controller = await pumpHarness(tester);
      await tester.runAsync(() async {
        final convo = await openConversation(controller);
        final firstResponse = streamHold = Completer<void>();
        String? cancelledRunId;
        final terminal = controller.debugViewModel.generationTerminalEvents
            .listen((event) {
              if (event.terminalState == GenerationRunState.cancelled) {
                cancelledRunId = event.generationRunId;
              }
            });
        try {
          await controller.sendMessage(const ChatInputData(text: 'first'));
          await waitFor(() => streamRequestCount == 1, 'first request');
          await controller.sendMessage(const ChatInputData(text: 'pending A'));
          final queuedId = controller.queuedInputs.single.id;
          final owner =
              snapshots.last.singleWhere(
                    (task) => task['conversationId'] == convo.id,
                  )['id']
                  as String;
          await runtimeStop([owner]);
          await waitFor(
            () =>
                cancelledRunId != null ||
                controller.debugViewModel.debugChatActions.isStopping(convo.id),
            'native cancellation claim',
          );
          firstResponse.complete();
          streamHold = null;
          await waitFor(
            () =>
                cancelledRunId != null &&
                !controller.chatController.isConversationLoading(convo.id),
            'durable runtime cancellation',
          );
          await MobileBackgroundCoordinator.instance.flush();
          expect(streamRequestCount, 1);
          expect(controller.queuedInputs, hasLength(1));
          expect(controller.queuedInputs.single.id, queuedId);
          expect(
            (await repository.queuedInputsForConversation(convo.id)).single.id,
            queuedId,
          );
          expect(
            (await repository.getGenerationRun(cancelledRunId!))!.state,
            GenerationRunState.cancelled,
          );
          expect(controller.interruptedMessageIds, isEmpty);
          expect(service.isQueueHeldAfterInterruption(convo.id), isTrue);
          await service.close();
          await service.init();
          await controller.debugViewModel.drainQueuedInputs();
          expect(service.isQueueHeldAfterInterruption(convo.id), isTrue);
          expect(streamRequestCount, 1);
          expect(controller.queuedInputs.single.id, queuedId);

          await controller.sendMessage(const ChatInputData(text: 'after Stop'));
          await waitFor(
            () => streamRequestCount == 3,
            'explicit turn and FIFO',
          );
          await waitFor(
            () => !controller.chatController.isConversationLoading(convo.id),
            'FIFO after explicit restart',
          );
          expect(
            await repository.queuedInputsForConversation(convo.id),
            isEmpty,
          );
          expect(
            (await service.loadMessages(convo.id))
                .where((message) => message.role == 'user')
                .map((message) => message.content),
            ['first', 'after Stop', 'pending A'],
          );
          expect(
            (await repository.getGenerationRun(cancelledRunId!))!.state,
            GenerationRunState.cancelled,
          );
        } finally {
          if (!firstResponse.isCompleted) firstResponse.complete();
          streamHold = null;
          await terminal.cancel();
        }
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'foreground owner spans blocked queue mutation and successor registration',
    (tester) async {
      final snapshots = recordBackgroundSnapshots();
      final controller = await pumpHarness(tester);
      await tester.runAsync(() async {
        final convo = await openConversation(controller);
        final firstResponse = streamHold = Completer<void>();
        final writerRelease = Completer<void>();
        String? completedRunId;
        final terminal = controller.debugViewModel.generationTerminalEvents
            .listen((event) => completedRunId ??= event.generationRunId);
        try {
          await controller.sendMessage(const ChatInputData(text: 'first'));
          await waitFor(() => streamRequestCount == 1, 'first request');
          await controller.sendMessage(const ChatInputData(text: 'eligible A'));
          await controller.sendMessage(const ChatInputData(text: 'removed B'));
          final oldOwner =
              snapshots.last.singleWhere(
                    (task) => task['conversationId'] == convo.id,
                  )['id']
                  as String;
          final boundary = snapshots.length;
          service.queueWriteStarted = Completer<void>();
          service.queueWriteHold = writerRelease.future;
          final removal = controller.removeQueuedMessage(
            controller.queuedInputs.last.id,
          );
          await waitFor(
            () => service.queueWriteStarted!.isCompleted,
            'blocked queue persistence',
          );
          firstResponse.complete();
          streamHold = null;
          await waitFor(
            () =>
                completedRunId != null &&
                !controller.chatController.isConversationLoading(convo.id),
            'first durable terminal',
          );
          await MobileBackgroundCoordinator.instance.flush();
          expect(
            (await repository.getGenerationRun(completedRunId!))!.state,
            GenerationRunState.completed,
          );
          expect(
            MobileBackgroundCoordinator.instance.activeTaskIds,
            contains(oldOwner),
          );
          writerRelease.complete();
          await removal;
          await waitFor(() => streamRequestCount == 2, 'successor request');
          await waitFor(
            () => !controller.chatController.isConversationLoading(convo.id),
            'successor completion',
          );
          await MobileBackgroundCoordinator.instance.flush();
          final duringHandoff = snapshots.skip(boundary).toList();
          final oldReleased = duringHandoff.indexWhere(
            (tasks) => tasks.every((task) => task['id'] != oldOwner),
          );
          expect(oldReleased, greaterThanOrEqualTo(0));
          expect(
            duringHandoff
                .take(oldReleased + 1)
                .every(
                  (tasks) =>
                      tasks.any((task) => task['conversationId'] == convo.id),
                ),
            isTrue,
          );
          expect(
            duringHandoff.any(
              (tasks) =>
                  tasks.any((task) => task['id'] == oldOwner) &&
                  tasks.any(
                    (task) =>
                        task['conversationId'] == convo.id &&
                        task['id'] != oldOwner,
                  ),
            ),
            isTrue,
          );
          expect(streamRequestCount, 2);
        } finally {
          if (!firstResponse.isCompleted) firstResponse.complete();
          if (!writerRelease.isCompleted) writerRelease.complete();
          streamHold = null;
          service.queueWriteHold = null;
          await terminal.cancel();
        }
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a late accepted input cannot acknowledge a newer runtime Stop', (
    tester,
  ) async {
    final snapshots = recordBackgroundSnapshots();
    final controller = await pumpHarness(tester);
    await tester.runAsync(() async {
      final convo = await openConversation(controller);
      const pendingId = '318d5c2c-468b-44c5-bf47-30ffcd5e0c9e';
      await repository.putQueuedInput(
        QueuedChatInput(
          id: pendingId,
          conversationId: convo.id,
          input: const ChatInputData(text: 'pending'),
        ),
      );
      await controller.debugViewModel.restoreQueuedInputs();
      final beginReturn = Completer<void>();
      service.sendBeginCommitted = Completer<void>();
      service.sendBeginReturnHold = beginReturn.future;
      String? cancelledRunId;
      final terminal = controller.debugViewModel.generationTerminalEvents
          .listen((event) => cancelledRunId = event.generationRunId);
      try {
        final accepted = controller.sendMessage(
          const ChatInputData(text: 'accepted'),
        );
        await waitFor(
          () => service.sendBeginCommitted!.isCompleted,
          'durable begin before return',
        );
        final owner =
            snapshots.last.singleWhere(
                  (task) => task['conversationId'] == convo.id,
                )['id']
                as String;
        await runtimeStop([owner]);
        await waitFor(
          () => controller.debugViewModel.debugChatActions.isStopping(convo.id),
          'Stop during durable begin',
        );
        beginReturn.complete();
        await accepted;
        await waitFor(
          () =>
              cancelledRunId != null &&
              !controller.chatController.isConversationLoading(convo.id),
          'late committed cancellation',
        );
        await MobileBackgroundCoordinator.instance.flush();
        expect(
          (await repository.getGenerationRun(cancelledRunId!))!.state,
          GenerationRunState.cancelled,
        );
        expect(
          await repository.unacknowledgedInterruptedConversationIds(),
          contains(convo.id),
        );
        expect(service.isQueueHeldAfterInterruption(convo.id), isTrue);
        expect(controller.queuedInputs.single.id, pendingId);
        expect(streamRequestCount, 0);
        expect(await repository.getMessageCount(convo.id), 2);
      } finally {
        if (!beginReturn.isCompleted) beginReturn.complete();
        service.sendBeginReturnHold = null;
        await terminal.cancel();
      }
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'selected FIFO waits for another chats delayed begin then starts once',
    (tester) async {
      recordBackgroundSnapshots();
      final controller = await pumpHarness(tester);
      await tester.runAsync(() async {
        final first = await openConversation(controller);
        final selected = await service.createConversation(title: 'Selected B');
        await repository.putQueuedInput(
          QueuedChatInput(
            id: 'queued-A',
            conversationId: first.id,
            input: const ChatInputData(text: 'A pending'),
          ),
        );
        await repository.putQueuedInput(
          QueuedChatInput(
            id: 'queued-B',
            conversationId: selected.id,
            input: const ChatInputData(text: 'B pending'),
          ),
        );
        await controller.debugViewModel.restoreQueuedInputs();
        final beginReturn = Completer<void>();
        service.sendBeginCommitted = Completer<void>();
        service.sendBeginReturnHold = beginReturn.future;
        try {
          final firstDrain = controller.debugViewModel.drainQueuedInputs();
          await waitFor(
            () => service.sendBeginCommitted!.isCompleted,
            'A committed begin before return',
          );
          await controller.debugViewModel.switchConversation(selected.id);
          expect(controller.currentConversation?.id, selected.id);
          expect(streamRequestCount, 0);
          service.sendBeginReturnHold = null;
          beginReturn.complete();
          await firstDrain;
          await waitFor(
            () => streamRequestCount == 2,
            'selected B FIFO after A admission barrier',
          );
          await waitFor(
            () =>
                !controller.chatController.isConversationLoading(first.id) &&
                !controller.chatController.isConversationLoading(selected.id),
            'both conversation terminals',
          );
          expect(
            (await service.loadMessages(
              first.id,
            )).where((m) => m.role == 'user').map((m) => m.content),
            ['A pending'],
          );
          expect(
            (await service.loadMessages(
              selected.id,
            )).where((m) => m.role == 'user').map((m) => m.content),
            ['B pending'],
          );
          expect(await repository.allQueuedInputs(), isEmpty);
          expect(streamRequestCount, 2);
          await MobileBackgroundCoordinator.instance.flush();
        } finally {
          if (!beginReturn.isCompleted) beginReturn.complete();
          service.sendBeginReturnHold = null;
        }
      });
      expect(tester.takeException(), isNull);
    },
  );

  for (final streaming in [true, false]) {
    testWidgets(
      'recovered Ask User ${streaming ? 'streaming' : 'nonstreaming'} continuation protects answer write and releases held FIFO at durable begin',
      (tester) async {
        final snapshots = recordBackgroundSnapshots();
        final controller = await pumpHarness(tester);
        await tester.runAsync(() async {
          final convo = await openConversation(controller);
          await assistantProvider.updateAssistant(
            assistantProvider.currentAssistant!.copyWith(
              streamOutput: streaming,
            ),
          );
          const part = ToolUIPart(
            id: 'recovered-question',
            toolName: AskUserToolNames.askUser,
            arguments: {
              'questions': [
                {'id': 'q1', 'question': 'Which?'},
              ],
            },
            loading: false,
          );
          final partial = ChatMessage(
            id: 'recovered-answer',
            conversationId: convo.id,
            role: 'assistant',
            isStreaming: true,
            parts: [
              const TextPart('saved partial'),
              ToolCallPart(
                jsonEncode({
                  'id': part.id,
                  'name': part.toolName,
                  'arguments': part.arguments,
                }),
              ),
            ],
          );
          await repository.beginSendGeneration(
            conversation: convo,
            userMessage: ChatMessage(
              id: 'question-user',
              conversationId: convo.id,
              role: 'user',
              content: 'question',
            ),
            assistantMessage: partial,
            runId: 'interrupted-question-run',
          );
          await repository.putQueuedInput(
            QueuedChatInput(
              id: 'after-question',
              conversationId: convo.id,
              input: const ChatInputData(text: 'pending A'),
            ),
          );
          await service.close();
          await service.init();
          await settings.setNewChatOnLaunch(false);
          await controller.initChat();
          expect(controller.currentConversation?.id, convo.id);
          expect(controller.interruptedMessageIds, contains(partial.id));
          expect(service.isQueueHeldAfterInterruption(convo.id), isTrue);
          final answerRelease = Completer<void>();
          service.answerWriteStarted = Completer<void>();
          service.answerWriteHold = answerRelease.future;
          final terminalRuns = <String?>[];
          final terminal = controller.debugViewModel.generationTerminalEvents
              .listen((event) => terminalRuns.add(event.generationRunId));
          const answer = AskUserResult.answer({
            'q1': AskUserAnswerValue.single(value: 'A', custom: false),
          });
          try {
            final continuation = controller.submitRecoveredAskUserAnswer(
              controller.messages.singleWhere(
                (message) => message.id == partial.id,
              ),
              part,
              answer,
            );
            await waitFor(
              () => service.answerWriteStarted!.isCompleted,
              'blocked recovered answer persistence',
            );
            expect(snapshots, isNotEmpty);
            expect(
              snapshots.last.where(
                (task) => task['conversationId'] == convo.id,
              ),
              hasLength(1),
            );
            answerRelease.complete();
            await continuation;
            await waitFor(
              () =>
                  terminalRuns.length == 2 &&
                  !controller.chatController.isConversationLoading(convo.id),
              'continuation and held FIFO completion',
            );
            await MobileBackgroundCoordinator.instance.flush();
            final runs = await (database.select(
              database.generationRunRows,
            )..where((row) => row.conversationId.equals(convo.id))).get();
            expect(runs, hasLength(3));
            expect(
              runs
                  .singleWhere((run) => run.id == 'interrupted-question-run')
                  .state,
              'interrupted',
            );
            expect(
              runs
                  .where(
                    (run) =>
                        run.targetRevisionId == partial.id &&
                        run.id != 'interrupted-question-run',
                  )
                  .single
                  .state,
              'completed',
            );
            expect(
              await repository.queuedInputsForConversation(convo.id),
              isEmpty,
            );
            expect(service.isQueueHeldAfterInterruption(convo.id), isFalse);
            expect(
              controller.interruptedMessageIds,
              isNot(contains(partial.id)),
            );
            expect(
              (await repository.getMessage(partial.id))!.content,
              contains('saved partial'),
            );
            expect(
              service.getToolEvents(partial.id).single['content'],
              answer.toJsonString(),
            );
            final pendingRequests = apiRequests.where(
              (request) => (request['messages'] as List).any(
                (message) =>
                    message['role'] == 'user' &&
                    message['content'] == 'pending A',
              ),
            );
            expect(pendingRequests, hasLength(1));
            final ownerBoundary = snapshots.indexWhere(
              (tasks) =>
                  tasks.any((task) => task['conversationId'] == convo.id),
            );
            final activeSnapshots = snapshots.skip(ownerBoundary).toList();
            final firstOwner = activeSnapshots.first.singleWhere(
              (task) => task['conversationId'] == convo.id,
            )['id'];
            final firstEmpty = activeSnapshots.indexWhere(
              (tasks) => tasks.isEmpty,
            );
            expect(firstEmpty, greaterThan(0));
            expect(
              activeSnapshots
                  .take(firstEmpty)
                  .every((tasks) => tasks.isNotEmpty),
              isTrue,
            );
            expect(
              activeSnapshots.skip(firstEmpty).every((tasks) => tasks.isEmpty),
              isTrue,
            );
            expect(
              activeSnapshots
                  .take(firstEmpty)
                  .any(
                    (tasks) => tasks.any((task) => task['id'] != firstOwner),
                  ),
              isTrue,
            );
            await service.close();
            await service.init();
            expect(service.interruptedMessageIds, isNot(contains(partial.id)));
            expect(
              (await repository.getGenerationRun(
                'interrupted-question-run',
              ))!.state,
              GenerationRunState.interrupted,
            );
          } finally {
            if (!answerRelease.isCompleted) answerRelease.complete();
            service.answerWriteHold = null;
            await terminal.cancel();
          }
        });
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'failed pending input write keeps the draft and rejects acknowledgement',
    (tester) async {
      final controller = await pumpHarness(tester);
      final errors = <String>[];
      controller.debugViewModel.onError = errors.add;
      await tester.runAsync(() async {
        final convo = await openConversation(controller);
        final hold = streamHold = Completer<void>();
        try {
          await controller.sendMessage(const ChatInputData(text: 'first'));
          await waitFor(() => streamRequestCount == 1, 'first request');
          await database.customStatement(
            "CREATE TRIGGER reject_pending_input BEFORE INSERT ON chat_storage_meta_rows WHEN NEW.key GLOB 'pending_inputs_v1.*' BEGIN SELECT RAISE(ABORT, 'queue write failed'); END",
          );
          controller.inputController.text = 'keep this draft';
          final result = await controller.sendMessage(
            const ChatInputData(text: 'keep this draft'),
          );
          expect(result, ChatInputSubmissionResult.rejected);
          expect(controller.inputController.text, 'keep this draft');
          expect(errors, [
            'Could not save the queued message. Your draft is still available.',
          ]);
          expect(controller.queuedInputs, isEmpty);
          expect(
            await repository.queuedInputsForConversation(convo.id),
            isEmpty,
          );
        } finally {
          if (!hold.isCompleted) hold.complete();
          streamHold = null;
          await waitFor(
            () => !controller.chatController.isConversationLoading(convo.id),
            'first completion',
          );
        }
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'selected cold interrupted chat preserves partials and holds FIFO until explicit continuation',
    (tester) async {
      late Conversation convo;
      late Conversation hidden;
      late ChatMessage partial;
      const queuedId = 'a5bef43a-e04f-45b3-a81c-b5a740cbdf3f';
      const hiddenQueuedId = '61d5a232-575e-437e-a6e8-7ff69dc6d8d5';
      await tester.runAsync(() async {
        hidden = await service.createConversation(title: 'Hidden');
        await repository.putQueuedInput(
          QueuedChatInput(
            id: hiddenQueuedId,
            conversationId: hidden.id,
            input: const ChatInputData(text: 'hidden pending'),
          ),
        );
        convo = await service.createConversation(title: 'Selected');
        partial = ChatMessage(
          id: 'cold-partial',
          conversationId: convo.id,
          role: 'assistant',
          content: 'saved partial',
          isStreaming: true,
        );
        await repository.beginSendGeneration(
          conversation: convo,
          userMessage: ChatMessage(
            id: 'cold-user',
            conversationId: convo.id,
            role: 'user',
            content: 'original',
          ),
          assistantMessage: partial,
          runId: 'cold-run',
        );
        await repository.putQueuedInput(
          QueuedChatInput(
            id: queuedId,
            conversationId: convo.id,
            input: const ChatInputData(text: 'queued next'),
            isEditing: true,
          ),
        );
        await service.close();
        await service.init();
      });
      final controller = await pumpHarness(tester);
      await tester.runAsync(() async {
        await settings.setNewChatOnLaunch(false);
        await controller.initChat();
        expect(controller.currentConversation?.id, convo.id);
        expect(controller.interruptedMessageIds, contains(partial.id));
        expect(controller.queuedInputs.single.id, queuedId);
        expect(controller.queuedInputs.single.isEditing, isFalse);
        expect(
          controller.messages.firstWhere((m) => m.id == partial.id).content,
          'saved partial',
        );
        expect(controller.isCurrentConversationLoading, isFalse);
        final writerRelease = Completer<void>();
        service.queueWriteStarted = Completer<void>();
        service.queueWriteHold = writerRelease.future;
        final edit = controller.editQueuedMessage(
          controller.queuedInputs.single,
        );
        await waitFor(
          () => service.queueWriteStarted!.isCompleted,
          'held interrupted queue writer',
        );
        await controller.debugViewModel.drainQueuedInputs();
        writerRelease.complete();
        await edit;
        service.queueWriteHold = null;
        await controller.cancelQueuedMessageEdit();
        await controller.debugViewModel.drainQueuedInputs();
        expect(streamRequestCount, 0);
        expect(
          (await repository.queuedInputsForConversation(convo.id)).single.id,
          queuedId,
        );

        await controller.continueInterruptedReply(partial);
        await waitFor(
          () => streamRequestCount == 2,
          'explicit continuation and queued request',
        );
        await waitFor(
          () => !controller.chatController.isConversationLoading(convo.id),
          'continued FIFO completion',
        );
        final messages = await service.loadMessages(convo.id);
        final users = messages.where((m) => m.role == 'user').toList();
        expect(users.map((m) => m.content), [
          'original',
          'Continue from the saved context after the interruption. Check what has already completed before taking further actions.',
          'queued next',
        ]);
        expect(
          (await repository.getGenerationRun('cold-run'))!.state,
          GenerationRunState.interrupted,
        );
        expect(
          (await repository.getMessage(partial.id))!.content,
          'saved partial',
        );
        expect(await repository.queuedInputsForConversation(convo.id), isEmpty);
        expect(
          (await repository.queuedInputsForConversation(hidden.id)).single.id,
          hiddenQueuedId,
        );
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed queued begin restores the head and retries only after an explicit drain',
    (tester) async {
      final controller = await pumpHarness(tester);
      final errors = <String>[];
      controller.debugViewModel.onError = errors.add;
      await tester.runAsync(() async {
        final convo = await openConversation(controller);
        const id = '7d743677-bd18-4f8b-bac3-7a01ef116b31';
        await repository.putQueuedInput(
          QueuedChatInput(
            id: id,
            conversationId: convo.id,
            input: const ChatInputData(text: 'pending'),
          ),
        );
        await controller.debugViewModel.restoreQueuedInputs();
        await database.customStatement(
          "CREATE TRIGGER reject_generation_run BEFORE INSERT ON generation_run_rows BEGIN SELECT RAISE(ABORT, 'run insert failed'); END",
        );
        await controller.debugViewModel.drainQueuedInputs();
        expect(controller.queuedInputs.single.id, id);
        expect(
          (await repository.queuedInputsForConversation(convo.id)).single.id,
          id,
        );
        expect(await repository.getMessageCount(convo.id), 0);
        expect(streamRequestCount, 0);
        expect(errors, hasLength(1));
        await controller.debugViewModel.insertQueuedInput(
          id: id,
          conversationId: convo.id,
          index: 0,
          input: const ChatInputData(text: 'pending'),
        );
        expect(controller.queuedInputs.single.id, id);
        expect(await repository.getMessageCount(convo.id), 0);
        expect(streamRequestCount, 0);
        expect(errors, hasLength(1));
        await database.customStatement('DROP TRIGGER reject_generation_run');
        await controller.debugViewModel.drainQueuedInputs();
        await waitFor(() => streamRequestCount == 1, 'retried request');
        await waitFor(
          () => !controller.chatController.isConversationLoading(convo.id),
          'retried completion',
        );
        expect(controller.queuedInputs, isEmpty);
        expect(await repository.queuedInputsForConversation(convo.id), isEmpty);
        expect(
          (await service.loadMessages(
            convo.id,
          )).where((m) => m.role == 'user').map((m) => m.content),
          ['pending'],
        );
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed queued edit keeps the original durable slot and the edited draft',
    (tester) async {
      final controller = await pumpHarness(tester);
      final errors = <String>[];
      controller.debugViewModel.onError = errors.add;
      await tester.runAsync(() async {
        final convo = await openConversation(controller);
        const firstId = 'e7c9c152-5e82-4b93-8f15-6eaa72a1643c';
        const nextId = '09501d83-16dc-4147-aefd-8e4e51cb0c96';
        await repository.putQueuedInput(
          QueuedChatInput(
            id: firstId,
            conversationId: convo.id,
            input: const ChatInputData(text: 'original'),
          ),
        );
        await repository.putQueuedInput(
          QueuedChatInput(
            id: nextId,
            conversationId: convo.id,
            input: const ChatInputData(text: 'next'),
          ),
        );
        await controller.debugViewModel.restoreQueuedInputs();
        await controller.editQueuedMessage(controller.queuedInputs.first);
        controller.inputController.text = 'edited draft';
        await database.customStatement(
          "CREATE TRIGGER reject_pending_input BEFORE INSERT ON chat_storage_meta_rows WHEN NEW.key GLOB 'pending_inputs_v1.*' BEGIN SELECT RAISE(ABORT, 'queue write failed'); END",
        );
        await controller.saveQueuedMessageEditOnly();
        expect(controller.queuedMessageEditState?.id, firstId);
        expect(controller.inputController.text, 'edited draft');
        final pending = await repository.queuedInputsForConversation(convo.id);
        expect(pending.map((item) => item.id), [firstId, nextId]);
        expect(pending.first.input.text, 'original');
        expect(pending.first.isEditing, isTrue);
        expect(errors, hasLength(1));
        await database.customStatement('DROP TRIGGER reject_pending_input');
        await controller.saveQueuedMessageEditOnly();
        final saved = await repository.queuedInputsForConversation(convo.id);
        expect(saved.map((item) => item.id), [firstId, nextId]);
        expect(saved.first.input.text, 'edited draft');
        expect(saved.first.isEditing, isFalse);
        expect(controller.queuedMessageEditState, isNull);
        expect(streamRequestCount, 0);
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('single-flight cancel hides loading before slow teardown', (
    tester,
  ) async {
    final controller = await pumpHarness(tester);
    await tester.runAsync(() async {
      final convo = await openConversation(controller);
      controller.chatController.setConversationLoading(convo.id, true);
      final releaseCancel = Completer<void>();
      var cancelCalls = 0;
      final source = StreamController<void>(
        onCancel: () async {
          cancelCalls++;
          await releaseCancel.future;
          throw StateError('cancel failed');
        },
      );
      controller.chatController.setStreamSubscription(
        convo.id,
        source.stream.listen((_) {}),
      );

      final firstCancel = controller.cancelStreaming();
      await Future<void>.delayed(Duration.zero);

      expect(controller.isCurrentConversationLoading, isFalse);
      expect(controller.chatController.isConversationLoading(convo.id), isTrue);
      expect(controller.loadingConversationIds, isNot(contains(convo.id)));

      final recoveredMessage = ChatMessage(
        id: 'stopping-assistant',
        role: 'assistant',
        content: '',
        conversationId: convo.id,
      );
      const recoveredPart = ToolUIPart(
        id: 'ask-user',
        toolName: AskUserToolNames.askUser,
        arguments: <String, dynamic>{},
        loading: true,
      );
      await controller.submitRecoveredAskUserAnswer(
        recoveredMessage,
        recoveredPart,
        const AskUserResult.answer(<String, AskUserAnswerValue>{}),
      );
      expect(service.getToolEvents(recoveredMessage.id), isEmpty);
      expect(controller.toolParts[recoveredMessage.id], isNull);

      var secondCompleted = false;
      final secondCancel = controller.cancelStreaming().whenComplete(
        () => secondCompleted = true,
      );
      await Future<void>.delayed(Duration.zero);
      expect(cancelCalls, 1);
      expect(secondCompleted, isFalse);

      releaseCancel.complete();
      await Future.wait([firstCancel, secondCancel]);

      expect(
        controller.chatController.isConversationLoading(convo.id),
        isFalse,
      );
      await source.close();
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('Stop interrupts the shared browser only for its own chat', (
    tester,
  ) async {
    final controller = await pumpHarness(tester);
    final browser = BrowserAgentSession.instance;
    addTearDown(() {
      browser.endAction();
      browser.setOwnerConversationId(null);
    });
    await tester.runAsync(() async {
      final convo = await openConversation(controller);
      browser.setOwnerConversationId('another-chat');
      browser.beginAction();
      await controller.cancelStreaming();
      expect(browser.stopRequested, isFalse);
      browser.endAction();

      browser.setOwnerConversationId(convo.id);
      browser.beginAction();
      await controller.cancelStreaming();
      expect(browser.stopRequested, isTrue);
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('double suggestion tap persists a single user/assistant pair', (
    tester,
  ) async {
    final controller = await pumpHarness(tester);
    await tester.runAsync(() async {
      final convo = await openConversation(controller);
      final first = controller.sendSuggestion('hello');
      final second = controller.sendSuggestion('hello');
      await Future.wait([first, second]);
      await waitFor(() => streamRequestCount == 1, 'stream request to fire');
      await waitFor(
        () => !controller.chatController.isConversationLoading(convo.id),
        'streaming to finish',
      );

      final messages = await service.loadMessages(convo.id);
      expect(messages.where((m) => m.role == 'user'), hasLength(1));
      expect(messages.where((m) => m.role == 'assistant'), hasLength(1));
      expect(streamRequestCount, 1);
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('double regenerate tap creates a single new version', (
    tester,
  ) async {
    final controller = await pumpHarness(tester);
    await tester.runAsync(() async {
      final convo = await openConversation(controller);
      await controller.sendMessage(ChatInputData(text: 'hello'));
      await waitFor(() => streamRequestCount == 1, 'stream request to fire');
      await waitFor(
        () => !controller.chatController.isConversationLoading(convo.id),
        'initial streaming to finish',
      );
      final before = await service.loadMessages(convo.id);
      expect(before, hasLength(2));
      final assistantMessage = before.firstWhere((m) => m.role == 'assistant');

      final first = controller.regenerateAtMessage(assistantMessage);
      final second = controller.regenerateAtMessage(assistantMessage);
      await Future.wait([first, second]);
      await waitFor(() => streamRequestCount == 2, 'second stream to fire');
      await waitFor(
        () => !controller.chatController.isConversationLoading(convo.id),
        'regeneration streaming to finish',
      );

      final messages = await service.loadMessages(convo.id);
      // user + original assistant revision + exactly one regenerated revision
      expect(messages, hasLength(3));
      expect(
        messages.where((m) => m.role == 'assistant' && m.version == 1),
        hasLength(1),
      );
      expect(streamRequestCount, 2);
      expect(
        controller.chatController.isConversationLoading(convo.id),
        isFalse,
      );
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('assistant edit save and send creates a new reply slot', (
    tester,
  ) async {
    final controller = await pumpHarness(tester);
    await tester.runAsync(() async {
      final convo = await openConversation(controller);
      await controller.sendMessage(ChatInputData(text: 'hello'));
      await waitFor(
        () => !controller.chatController.isConversationLoading(convo.id),
        'initial streaming to finish',
      );
      final before = await service.loadMessages(convo.id);
      final original = before.firstWhere((m) => m.role == 'assistant');
      final edited = await service.appendMessageVersion(
        messageId: original.id,
        content: 'edited answer',
      );
      expect(edited, isNotNull);

      await controller.regenerateAtMessage(edited!, assistantAsNewReply: true);

      await waitFor(() => streamRequestCount == 2, 'second stream to fire');
      await waitFor(
        () => !controller.chatController.isConversationLoading(convo.id),
        'new reply streaming to finish',
      );
      final messages = await service.loadMessages(convo.id);
      final editedGroupId = original.groupId ?? original.id;
      final newReplies = messages.where(
        (message) =>
            message.role == 'assistant' &&
            (message.groupId ?? message.id) != editedGroupId,
      );
      expect(
        messages.where((message) => message.role == 'assistant'),
        hasLength(3),
      );
      expect(newReplies, hasLength(1));
      expect(
        newReplies.single.groupId ?? newReplies.single.id,
        newReplies.single.id,
      );
      expect(newReplies.single.version, 0);
      expect(newReplies.single.isStreaming, isFalse);
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('temporary user edit saves and sends the in-memory version', (
    tester,
  ) async {
    final controller = await pumpHarness(tester);
    await tester.runAsync(() async {
      final convo = await service.createDraftConversation(
        title: 'Temporary Chat',
        temporary: true,
      );
      controller.chatController.setDraftConversation(convo);
      await controller.sendMessage(ChatInputData(text: 'original question'));
      await waitFor(
        () => !controller.chatController.isConversationLoading(convo.id),
        'initial temporary streaming to finish',
      );
      final original = service
          .getMessages(convo.id)
          .firstWhere((message) => message.role == 'user');

      await controller.startUserMessageEdit(original);
      final result = await controller.sendMessage(
        ChatInputData(text: 'edited question'),
      );

      expect(result, ChatInputSubmissionResult.sent);
      await waitFor(() => streamRequestCount == 2, 'edited stream to fire');
      await waitFor(
        () => !controller.chatController.isConversationLoading(convo.id),
        'edited temporary streaming to finish',
      );
      final edited = service
          .getMessages(convo.id)
          .firstWhere(
            (message) =>
                message.role == 'user' &&
                (message.groupId ?? message.id) ==
                    (original.groupId ?? original.id) &&
                message.version == 1,
          );
      expect(edited.content, 'edited question');
      expect(
        service.getVersionSelections(convo.id),
        containsPair(original.groupId ?? original.id, 1),
      );
      expect(service.isTemporaryConversation(convo.id), isTrue);
      expect(service.getAllConversations(), isEmpty);
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'suggestion requests isolate rules and preserve literal placeholders',
    (tester) async {
      final controller = await pumpHarness(tester, withSuggestions: true);
      await tester.runAsync(() async {
        final convo = await openConversation(controller);
        await controller.sendMessage(
          ChatInputData(text: 'Explain {locale} and {content}'),
        );
        await waitFor(
          () => service.getConversation(convo.id)!.chatSuggestions.isNotEmpty,
          'suggestions',
        );
        final request = suggestionRequests.single;
        final messages = request['messages'] as List;
        expect(messages.first['role'], 'system');
        expect(messages.first['content'], contains('JSON object'));
        expect(messages.last['role'], 'user');
        expect(
          messages.last['content'],
          contains('Explain {locale} and {content}'),
        );
        expect(messages.last['content'], contains('"role":"assistant"'));
        expect(request.containsKey('response_format'), isFalse);
      });
      expect(tester.takeException(), isNull);
    },
  );

  for (final mutation in [
    'clear context',
    'edit answer',
    'disable',
    'send again',
  ]) {
    testWidgets('discard delayed suggestions after $mutation', (tester) async {
      final controller = await pumpHarness(tester, withSuggestions: true);
      await tester.runAsync(() async {
        suggestionHold = Completer<void>();
        final convo = await openConversation(controller);
        await controller.sendMessage(ChatInputData(text: 'hello'));
        await waitFor(
          () => suggestionRequests.length == 1,
          'pending suggestions',
        );
        await waitFor(
          () => !controller.chatController.isConversationLoading(convo.id),
          'first reply to finish',
        );
        switch (mutation) {
          case 'clear context':
            await controller.clearContext();
          case 'edit answer':
            final messages = await service.loadMessages(convo.id);
            await service.updateMessage(
              messages.last.id,
              content: 'Edited answer',
            );
          case 'disable':
            await settings.disableSuggestionGeneration();
          case 'send again':
            streamHold = Completer<void>();
            await controller.sendMessage(ChatInputData(text: 'new question'));
            await waitFor(
              () => streamRequestCount == 2,
              'second stream to start',
            );
        }
        suggestionHold!.complete();
        await waitFor(() => suggestionResponsesSent == 1, 'delayed response');
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(service.getConversation(convo.id)!.chatSuggestions, isEmpty);
        if (streamHold != null) {
          await settings.disableSuggestionGeneration();
          streamHold!.complete();
          await waitFor(
            () => !controller.chatController.isConversationLoading(convo.id),
            'second reply to finish',
          );
        }
      });
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('an empty suggestions array is not a background error', (
    tester,
  ) async {
    final controller = await pumpHarness(tester, withSuggestions: true);
    final errors = <Object>[];
    controller.debugViewModel.onBackgroundTaskError = (_, error) =>
        errors.add(error);
    await tester.runAsync(() async {
      suggestionResponse = '{"suggestions":[]}';
      final convo = await openConversation(controller);
      await controller.sendMessage(ChatInputData(text: 'Thanks, that is all.'));
      await waitFor(() => suggestionResponsesSent == 1, 'empty response');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(service.getConversation(convo.id)!.chatSuggestions, isEmpty);
      expect(errors, isEmpty);
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'background suggestions use that conversations selected version',
    (tester) async {
      final controller = await pumpHarness(tester, withSuggestions: true);
      await tester.runAsync(() async {
        final convo = await openConversation(controller);
        await service.addMessage(
          conversationId: convo.id,
          role: 'user',
          content: 'Compare storage',
        );
        final answer = await service.addMessage(
          conversationId: convo.id,
          role: 'assistant',
          content: 'SELECTED ANSWER',
        );
        await service.addMessage(
          conversationId: convo.id,
          role: 'assistant',
          groupId: answer.groupId ?? answer.id,
          version: 1,
          content: 'UNSELECTED ANSWER',
        );
        await service.setSelectedVersion(
          convo.id,
          answer.groupId ?? answer.id,
          0,
        );
        final other = await service.createConversation(title: 'Other');
        await controller.chatController.setCurrentConversationAndLoad(other);
        controller.debugViewModel.debugChatActions.onMaybeGenerateSuggestions!(
          convo.id,
        );
        await waitFor(
          () => service.getConversation(convo.id)!.chatSuggestions.isNotEmpty,
          'background suggestions',
        );
        final prompt =
            (suggestionRequests.single['messages'] as List).last['content']
                as String;
        expect(prompt, contains('SELECTED ANSWER'));
        expect(prompt, isNot(contains('UNSELECTED ANSWER')));
        expect(controller.currentConversation!.id, other.id);
        expect(service.getConversation(other.id)!.chatSuggestions, isEmpty);
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('older suggestion requests cannot overwrite a newer result', (
    tester,
  ) async {
    final controller = await pumpHarness(tester, withSuggestions: true);
    await tester.runAsync(() async {
      final convo = await openConversation(controller);
      await service.addMessage(
        conversationId: convo.id,
        role: 'user',
        content: 'Question',
      );
      await service.addMessage(
        conversationId: convo.id,
        role: 'assistant',
        content: 'Answer',
      );
      final oldHold = Completer<void>();
      suggestionHold = oldHold;
      suggestionResponse = '{"suggestions":["old suggestion"]}';
      controller.debugViewModel.debugChatActions.onMaybeGenerateSuggestions!(
        convo.id,
      );
      await waitFor(() => suggestionRequests.length == 1, 'old request');
      suggestionHold = null;
      suggestionResponse = '{"suggestions":["new suggestion"]}';
      controller.debugViewModel.debugChatActions.onMaybeGenerateSuggestions!(
        convo.id,
      );
      await waitFor(
        () => service.getConversation(convo.id)!.chatSuggestions.isNotEmpty,
        'new result',
      );
      expect(service.getConversation(convo.id)!.chatSuggestions, [
        'new suggestion',
      ]);
      oldHold.complete();
      await waitFor(() => suggestionResponsesSent == 2, 'old response');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(service.getConversation(convo.id)!.chatSuggestions, [
        'new suggestion',
      ]);
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('multi-version conversation still saves generated suggestions', (
    tester,
  ) async {
    final controller = await pumpHarness(tester, withSuggestions: true);
    await tester.runAsync(() async {
      final convo = await openConversation(controller);
      await controller.sendMessage(ChatInputData(text: 'hello'));
      await waitFor(
        () => !controller.chatController.isConversationLoading(convo.id),
        'initial streaming to finish',
      );
      final before = await service.loadMessages(convo.id);
      final assistantMessage = before.firstWhere((m) => m.role == 'assistant');

      // Make the conversation multi-version, then wait for the automatic
      // suggestion generation that follows the regenerated reply.
      await controller.regenerateAtMessage(assistantMessage);
      await waitFor(
        () => !controller.chatController.isConversationLoading(convo.id),
        'regeneration streaming to finish',
      );
      expect(await service.loadMessages(convo.id), hasLength(3));

      await waitFor(
        () =>
            service.getConversation(convo.id)?.chatSuggestions.isNotEmpty ??
            false,
        'suggestions to be saved',
      );
      expect(
        service.getConversation(convo.id)!.chatSuggestions,
        contains('suggestion one'),
      );
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a second conversation can send while the first is still streaming',
    (tester) async {
      final controller = await pumpHarness(tester);
      await tester.runAsync(() async {
        streamHold = Completer<void>();
        final first = await openConversation(controller);
        await controller.sendMessage(ChatInputData(text: 'from a'));
        await waitFor(
          () => controller.chatController.isConversationLoading(first.id),
          'first conversation to start streaming',
        );

        final second = await service.createConversation(title: 'Second');
        await controller.chatController.setCurrentConversationAndLoad(second);
        final result = await controller.sendMessage(
          ChatInputData(text: 'from b'),
        );

        expect(result, ChatInputSubmissionResult.sent);
        expect(
          controller.chatController.isConversationLoading(first.id),
          isTrue,
        );
        expect(
          controller.chatController.isConversationLoading(second.id),
          isTrue,
        );

        streamHold!.complete();
        await waitFor(
          () =>
              !controller.chatController.isConversationLoading(first.id) &&
              !controller.chatController.isConversationLoading(second.id),
          'both streams to finish',
        );

        final firstMessages = await service.loadMessages(first.id);
        final secondMessages = await service.loadMessages(second.id);
        expect(
          firstMessages.where((m) => m.role == 'user').single.content,
          'from a',
        );
        expect(
          secondMessages.where((m) => m.role == 'user').single.content,
          'from b',
        );
      });
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('scheduled send uses its model over the conversation pin', (
    tester,
  ) async {
    final controller = await pumpHarness(tester);
    await tester.runAsync(() async {
      final target = await openConversation(controller);
      await controller.sendMessage(ChatInputData(text: 'Previous question'));
      await waitFor(
        () => !controller.chatController.isConversationLoading(target.id),
        'initial reply',
      );
      await service.setConversationModel(
        target.id,
        providerKey: 'SiliconFlow',
        modelId: 'pinned-model',
      );
      final foreground = await openConversation(controller);
      String? startedMessage;
      final result = await controller.debugViewModel.sendScheduledMessage(
        input: ChatInputData(text: 'Scheduled follow-up'),
        conversation: service.getConversation(target.id)!,
        assistant: assistantProvider.currentAssistant!,
        modelOverride: (providerKey: 'SiliconFlow', modelId: 'scheduled-model'),
        onGenerationStarted: (id) => startedMessage = id,
      );
      expect(result.success, isTrue);
      expect(startedMessage, result.assistantMessage!.id);
      await waitFor(
        () => !controller.chatController.isConversationLoading(target.id),
        'scheduled reply',
      );
      expect(streamRequests.last['model'], 'scheduled-model');
      final messages = streamRequests.last['messages'] as List;
      expect(
        messages.where((m) => m['role'] == 'user').map((m) => m['content']),
        ['Previous question', 'Scheduled follow-up'],
      );
      expect(service.getConversation(target.id)!.chatModelId, 'pinned-model');
      expect(settings.currentModelId, 'test-model');
      expect(controller.chatController.currentConversation!.id, foreground.id);
    });
    expect(tester.takeException(), isNull);
  });

  for (final action in ['send', 'regenerate']) {
    testWidgets(
      'subscription $action keeps agent metadata over a model override',
      (tester) async {
        final controller = await pumpHarness(tester);
        await tester.runAsync(() async {
          final target = await openConversation(controller);
          await service.setConversationModel(
            target.id,
            providerKey: 'SiliconFlow',
            modelId: 'pinned-model',
          );
          await settings.resetCurrentModel();
          await assistantProvider.updateAssistant(
            assistantProvider.currentAssistant!.copyWith(
              agentId: 'codex',
              agentAuthMode: AgentAuthMode.subscription,
              chatModelProvider: 'SiliconFlow',
              chatModelId: 'saved-api-model',
            ),
          );
          final assistant = assistantProvider.currentAssistant!;
          final savedAssistant = assistant.toJson();
          Future<void>? stopped;
          void stopBeforeNativeLaunch(String messageId) {
            stopped = ChatActions.cancelActiveGenerationFor(
              target.id,
              expectedMessageId: messageId,
            );
          }

          late ChatActionResult result;
          if (action == 'send') {
            result = await controller.debugViewModel.sendScheduledMessage(
              input: ChatInputData(text: 'Subscription question'),
              conversation: service.getConversation(target.id)!,
              assistant: assistant,
              modelOverride: (
                providerKey: 'SiliconFlow',
                modelId: 'override-model',
              ),
              onGenerationStarted: stopBeforeNativeLaunch,
            );
          } else {
            final question = await service.addMessage(
              conversationId: target.id,
              role: 'user',
              content: 'Previous question',
            );
            await service.addMessage(
              conversationId: target.id,
              role: 'assistant',
              content: 'Previous answer',
            );
            result = await controller.debugViewModel.regenerateScheduledMessage(
              message: question,
              conversation: service.getConversation(target.id)!,
              assistant: assistant,
              modelOverride: (
                providerKey: 'SiliconFlow',
                modelId: 'override-model',
              ),
              onGenerationStarted: stopBeforeNativeLaunch,
            );
          }
          expect(result.success, isTrue, reason: result.errorMessage);
          expect(stopped, isNotNull);
          await stopped;
          final persisted = (await service.loadMessages(
            target.id,
          )).firstWhere((message) => message.id == result.assistantMessage!.id);
          expect(persisted.providerId, 'acp:codex');
          expect(persisted.modelId, 'codex');
          expect(apiRequests, isEmpty);
          expect(
            service.getConversation(target.id)!.chatModelId,
            'pinned-model',
          );
          expect(assistantProvider.currentAssistant!.toJson(), savedAssistant);
          expect(settings.currentModelProvider, isNull);
          expect(settings.currentModelId, isNull);
        });
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'subscription suggestions honor an explicitly configured API model',
    (tester) async {
      final controller = await pumpHarness(tester, withSuggestions: true);
      await tester.runAsync(() async {
        final target = await openConversation(controller);
        await assistantProvider.updateAssistant(
          assistantProvider.currentAssistant!.copyWith(
            agentId: 'codex',
            agentAuthMode: AgentAuthMode.subscription,
          ),
        );
        await settings.setSuggestionModel('SiliconFlow', 'suggestion-model');
        await service.addMessage(
          conversationId: target.id,
          role: 'user',
          content: 'Question',
        );
        await service.addMessage(
          conversationId: target.id,
          role: 'assistant',
          content: 'Answer',
        );
        controller.debugViewModel.debugChatActions.onMaybeGenerateSuggestions!(
          target.id,
        );
        await waitFor(
          () => service.getConversation(target.id)!.chatSuggestions.isNotEmpty,
          'configured subscription suggestions',
        );
        expect(suggestionRequests.single['model'], 'suggestion-model');
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'scheduled rerun preserves later messages and the foreground chat',
    (tester) async {
      final controller = await pumpHarness(tester);
      await tester.runAsync(() async {
        final target = await openConversation(controller);
        for (final question in ['First question', 'Later question']) {
          await controller.sendMessage(ChatInputData(text: question));
          await waitFor(
            () => !controller.chatController.isConversationLoading(target.id),
            'reply to $question',
          );
        }
        final before = List<ChatMessage>.of(
          await service.loadMessages(target.id),
        );
        final question = before.firstWhere((m) => m.role == 'user');
        await settings.setRegenerateDeleteTrailingMessages(true);
        final foreground = await openConversation(controller);
        final selections = Map<String, int>.of(
          controller.debugViewModel.versionSelections,
        );
        final result = await controller.debugViewModel
            .regenerateScheduledMessage(
              message: question,
              conversation: service.getConversation(target.id)!,
              assistant: assistantProvider.currentAssistant!,
              modelOverride: (
                providerKey: 'SiliconFlow',
                modelId: 'rerun-model',
              ),
            );
        expect(result.success, isTrue);
        expect(result.generationRunId, isNotNull);
        await waitFor(
          () => !controller.chatController.isConversationLoading(target.id),
          'scheduled rerun',
        );
        final after = await service.loadMessages(target.id);
        expect(after, hasLength(before.length + 1));
        expect(after.map((m) => m.id), containsAll(before.map((m) => m.id)));
        expect(streamRequests.last['model'], 'rerun-model');
        final messages = streamRequests.last['messages'] as List;
        expect(
          messages.where((m) => m['role'] == 'user').map((m) => m['content']),
          ['First question'],
        );
        expect(
          controller.chatController.currentConversation!.id,
          foreground.id,
        );
        expect(controller.debugViewModel.versionSelections, selections);
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a busy scheduled target and stale cancellation leave the user stream running',
    (tester) async {
      final controller = await pumpHarness(tester);
      await tester.runAsync(() async {
        streamHold = Completer<void>();
        final target = await openConversation(controller);
        await controller.sendMessage(ChatInputData(text: 'User is chatting'));
        await waitFor(() => streamRequestCount == 1, 'held user request');
        final question = (await service.loadMessages(
          target.id,
        )).firstWhere((m) => m.role == 'user');
        var starts = 0;
        final send = await controller.debugViewModel.sendScheduledMessage(
          input: ChatInputData(text: 'Scheduled follow-up'),
          conversation: target,
          assistant: assistantProvider.currentAssistant!,
          onGenerationStarted: (_) => starts++,
        );
        final rerun = await controller.debugViewModel
            .regenerateScheduledMessage(
              message: question,
              conversation: target,
              assistant: assistantProvider.currentAssistant!,
              onGenerationStarted: (_) => starts++,
            );
        expect(send.errorMessage, 'in_flight');
        expect(rerun.errorMessage, 'in_flight');
        expect(starts, 0);
        await ChatActions.cancelActiveGenerationFor(
          target.id,
          expectedMessageId: 'finished-scheduled-run',
        );
        expect(
          controller.chatController.isConversationLoading(target.id),
          isTrue,
        );
        streamHold!.complete();
        await waitFor(
          () => !controller.chatController.isConversationLoading(target.id),
          'original user reply',
        );
        expect(streamRequestCount, 1);
        expect((await service.loadMessages(target.id)).last.content, 'ok');
      });
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'scheduled rerun before context reset succeeds without changing the cutoff',
    (tester) async {
      final controller = await pumpHarness(tester);
      await tester.runAsync(() async {
        final target = await openConversation(controller);
        await controller.sendMessage(ChatInputData(text: 'Original question'));
        await waitFor(
          () => !controller.chatController.isConversationLoading(target.id),
          'original reply',
        );
        final question = (await service.loadMessages(
          target.id,
        )).firstWhere((m) => m.role == 'user');
        await service.toggleTruncateAtTail(target.id);
        final current = service.getConversation(target.id)!;
        final choices = await repository.getSelectedMessageProjections(
          target.id,
        );
        expect(choices.any((m) => m.id == question.id), isTrue);
        expect(await repository.getMessage(question.id), isNotNull);
        final result = await controller.debugViewModel
            .regenerateScheduledMessage(
              message: question,
              conversation: current,
              assistant: assistantProvider.currentAssistant!,
            );
        expect(result.success, isTrue);
        await waitFor(
          () => !controller.chatController.isConversationLoading(target.id),
          'scheduled rerun',
        );
        expect(streamRequestCount, 2);
        expect(
          service.getConversation(target.id)!.truncateIndex,
          current.truncateIndex,
        );
        expect(
          (streamRequests.last['messages'] as List)
              .where((m) => m['role'] == 'user')
              .map((m) => m['content']),
          ['Original question'],
        );
        await controller.debugViewModel.sendScheduledMessage(
          input: ChatInputData(text: 'After clear'),
          conversation: service.getConversation(target.id)!,
          assistant: assistantProvider.currentAssistant!,
        );
        await waitFor(
          () => !controller.chatController.isConversationLoading(target.id),
          'follow-up after clear',
        );
        expect(
          (streamRequests.last['messages'] as List)
              .where((m) => m['role'] == 'user')
              .map((m) => m['content']),
          ['After clear'],
        );
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'scheduled nonstream rerun returns a run while user input is pending',
    (tester) async {
      final controller = await pumpHarness(tester);
      await tester.runAsync(() async {
        final target = await openConversation(controller);
        await controller.sendMessage(ChatInputData(text: 'Original question'));
        await waitFor(
          () => !controller.chatController.isConversationLoading(target.id),
          'original reply',
        );
        final question = (await service.loadMessages(
          target.id,
        )).firstWhere((m) => m.role == 'user');
        await assistantProvider.updateAssistant(
          assistantProvider.currentAssistant!.copyWith(
            localToolIds: [AskUserToolNames.askUser],
          ),
        );
        var returned = false;
        final run = controller.debugViewModel
            .regenerateScheduledMessage(
              message: question,
              conversation: service.getConversation(target.id)!,
              assistant: assistantProvider.currentAssistant!.copyWith(
                streamOutput: false,
              ),
              modelOverride: (providerKey: 'SiliconFlow', modelId: 'gpt-4o'),
            )
            .then((result) {
              returned = true;
              return result;
            });
        try {
          await waitFor(
            () => questions.pendingRequests.isNotEmpty,
            'real ask-user tool request',
          );
          await Future<void>.delayed(const Duration(milliseconds: 700));
          expect(returned, isTrue);
          final result = await run;
          expect(result.success, isTrue);
          expect(result.generationRunId, isNotNull);
          expect(
            (await repository.getGenerationRun(
              result.generationRunId!,
            ))!.state.isTerminal,
            isFalse,
          );
          expect(
            questions.pendingRequests.values.single.conversationId,
            target.id,
          );
        } finally {
          await ChatActions.cancelActiveGenerationFor(target.id);
          await run.timeout(const Duration(seconds: 10));
        }
      });
      expect(tester.takeException(), isNull);
    },
  );
}

class _ControllerHarness extends StatefulWidget {
  const _ControllerHarness({required this.onCreated});

  final ValueChanged<HomePageController> onCreated;

  @override
  State<_ControllerHarness> createState() => _ControllerHarnessState();
}

class _ControllerHarnessState extends State<_ControllerHarness>
    with TickerProviderStateMixin {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _inputBarKey = GlobalKey();
  final _inputFocus = FocusNode();
  final _inputController = TextEditingController();
  final _mediaController = ChatInputBarController();
  final _scrollController = ChatAutoFollowScrollController();
  late final HomePageController _controller;

  @override
  void initState() {
    super.initState();
    _controller = HomePageController(
      context: context,
      vsync: this,
      scaffoldKey: _scaffoldKey,
      inputBarKey: _inputBarKey,
      inputFocus: _inputFocus,
      inputController: _inputController,
      mediaController: _mediaController,
      scrollController: _scrollController,
    );
    widget.onCreated(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    _inputFocus.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(key: _scaffoldKey);
}
