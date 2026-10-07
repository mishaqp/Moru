import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:Kelivo/core/database/app_database.dart';
import 'package:Kelivo/core/database/chat_database_observer.dart';
import 'package:Kelivo/core/database/chat_database_repository.dart';
import 'package:Kelivo/core/models/chat_input_data.dart';
import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/models/conversation.dart';
import 'package:Kelivo/core/models/message_part.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/mcp_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/providers/tts_provider.dart';
import 'package:Kelivo/core/providers/user_provider.dart';
import 'package:Kelivo/core/services/chat/chat_service.dart';
import 'package:Kelivo/core/services/mcp/mcp_tool_service.dart';
import 'package:Kelivo/core/services/workspace/task_plan.dart';
import 'package:Kelivo/core/services/workspace/tool_run_registry.dart';
import 'package:Kelivo/features/chat/widgets/computer_response_scope.dart';
import 'package:Kelivo/features/chat/widgets/chat_message_widget.dart';
import 'package:Kelivo/features/home/controllers/home_page_controller.dart';
import 'package:Kelivo/features/home/controllers/scroll_controller.dart';
import 'package:Kelivo/features/home/services/ask_user_interaction_service.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/features/home/widgets/chat_input_bar.dart';
import 'package:Kelivo/features/home/widgets/composer_status_strip.dart';
import 'package:Kelivo/features/home/widgets/message_list_view.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';

import 'business_test_harness.dart';
import 'long_chat_harness.dart';

/// Real persisted send path with only the remote response held by a loopback
/// provider. No artificial delay is introduced in persistence or preparation.
class SendLongChatEnvironment {
  SendLongChatEnvironment._(
    this.directory,
    this.previousPathProvider,
    this.previousHttpOverrides,
  );

  final Directory directory;
  final PathProviderPlatform previousPathProvider;
  final HttpOverrides? previousHttpOverrides;
  final observer = ChatDatabaseObserver();
  late final SendBenchmarkRepository repository;
  late final SendBenchmarkChatService service;
  late final HttpServer server;
  late final SettingsProvider settings;
  late final AssistantProvider assistants;
  late final TtsProvider tts;
  late final UserProvider user;
  late final McpProvider mcp;
  final mcpTools = McpToolService();
  final questions = AskUserInteractionService();
  final approvals = ToolApprovalService();
  final plans = TaskPlanRegistry();
  final toolRuns = ToolRunRegistry();
  final requests = <Map<String, dynamic>>[];
  Completer<void>? responseHold;
  void Function(String name)? onStage;
  var fixtureMessages = 0;
  var fixtureTools = 0;
  var fixtureToolBytes = 0;

  static Future<SendLongChatEnvironment> create({required int rounds}) async {
    final directory = await Directory.systemTemp.createTemp('moru_send_bench_');
    final environment = SendLongChatEnvironment._(
      directory,
      PathProviderPlatform.instance,
      HttpOverrides.current,
    );
    PathProviderPlatform.instance = _SendBenchmarkPaths(directory.path);
    HttpOverrides.global = null;
    final file = File('${directory.path}/kelivo.db');
    environment.repository = SendBenchmarkRepository(
      AppDatabase.open(file: file),
      databaseFile: file,
      observer: environment.observer,
      stage: (name) => environment.onStage?.call(name),
    );
    await environment.repository.ensureReady();

    final fixture = LongChatFixture(rounds: rounds);
    // 400 messages / 270 stored tools: a second edit card in the first 90
    // assistant turns complements the fixture's 180 varied tool cards.
    for (var i = 0; i < (rounds * .45).floor(); i++) {
      final tool = longChatTool(i * 10 + 1);
      final messageIndex = i * 2 + 1;
      final message = fixture.messages[messageIndex];
      fixture.messages[messageIndex] = message.copyWith(
        parts: [...message.parts, ToolCallPart(toolPayload(tool))],
      );
    }
    final events = <String, List<Map<String, dynamic>>>{};
    for (final message in fixture.messages) {
      for (final part in message.parts.whereType<ToolCallPart>()) {
        final event = (jsonDecode(part.payloadJson) as Map)
            .cast<String, dynamic>();
        events.putIfAbsent(message.id, () => []).add(event);
        environment.fixtureTools++;
        environment.fixtureToolBytes += part.payloadJson.length;
      }
    }
    environment.fixtureMessages = fixture.messages.length;
    await environment.repository.putMigrationBatch(
      conversations: [
        Conversation(
          id: 'long-chat',
          title: 'Send benchmark',
          messageIds: fixture.messages.map((m) => m.id).toList(),
        ),
      ],
      messages: [
        for (var i = 0; i < fixture.messages.length; i++)
          (message: fixture.messages[i], messageOrder: i),
      ],
      toolEventsByMessageId: events,
      geminiSignaturesByMessageId: const {},
    );
    environment.service = SendBenchmarkChatService(
      existingRepository: environment.repository,
      stage: (name) => environment.onStage?.call(name),
    );
    await environment.service.init();
    // Keep the full generation history resident; presentation retains the
    // production 360-slot window cap.
    environment.service.setCurrentConversation('long-chat');
    await environment.service.loadMessages('long-chat');
    environment.server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    environment.server.listen(environment._handleRequest);
    final settingsPreferences = createBusinessTestPreferences();
    await settingsPreferences.load();
    environment.settings = SettingsProvider(settingsPreferences);
    await environment.settings.loaded;
    await environment.settings.setProviderConfig(
      'SiliconFlow',
      ProviderConfig(
        id: 'SiliconFlow',
        enabled: true,
        name: 'Benchmark provider',
        apiKey: 'synthetic-benchmark-key',
        baseUrl:
            'http://${environment.server.address.address}:${environment.server.port}/v1',
        providerType: ProviderKind.openai,
      ),
    );
    await environment.settings.setCurrentModel('SiliconFlow', 'test-model');
    await environment.settings.disableSuggestionGeneration();
    final assistantPreferences = createBusinessTestPreferences();
    await assistantPreferences.load();
    environment.assistants = AssistantProvider(
      preferences: assistantPreferences,
    );
    await environment.assistants.loaded;
    final assistantId = await environment.assistants.addAssistant(
      name: 'Bench',
    );
    await environment.assistants.setCurrentAssistant(assistantId);
    await environment.assistants.updateAssistant(
      environment.assistants.currentAssistant!.copyWith(
        limitContextMessages: false,
        systemPrompt: 'Benchmark assistant.',
      ),
    );
    environment.tts = TtsProvider(preferences: createBusinessTestPreferences());
    environment.user = UserProvider(
      preferences: createBusinessTestPreferences(),
    );
    environment.mcp = McpProvider(preferences: createBusinessTestPreferences());
    return environment;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final body = (jsonDecode(await utf8.decoder.bind(request).join()) as Map)
        .cast<String, dynamic>();
    if (body['stream'] == true) {
      requests.add(body);
      onStage?.call('provider.request');
      final hold = responseHold;
      if (hold != null) await hold.future;
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
        charset: 'utf-8',
      );
      for (var chunk = 0; chunk < 3; chunk++) {
        request.response.write(
          'data: ${jsonEncode({
            'id': 'benchmark-response',
            'object': 'chat.completion.chunk',
            'created': 0,
            'model': 'test-model',
            'choices': [
              {
                'index': 0,
                'delta': {'content': 'Продолжаю **проверку**. '},
                'finish_reason': chunk == 2 ? 'stop' : null,
              },
            ],
          })}\n\n',
        );
        await request.response.flush();
      }
      request.response.write('data: [DONE]\n\n');
    } else {
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'choices': [
            {
              'message': {'content': 'Benchmark title'},
            },
          ],
        }),
      );
    }
    await request.response.close();
  }

  void releaseResponse() {
    final hold = responseHold;
    if (hold != null && !hold.isCompleted) hold.complete();
  }

  Future<void> close() async {
    releaseResponse();
    await server.close(force: true);
    await service.close();
    await repository.close();
    PathProviderPlatform.instance = previousPathProvider;
    HttpOverrides.global = previousHttpOverrides;
    await directory.delete(recursive: true);
  }

  Widget app({required GlobalKey<SendLongChatHarnessState> key}) =>
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<AssistantProvider>.value(value: assistants),
          ChangeNotifierProvider<ChatService>.value(value: service),
          ChangeNotifierProvider<TtsProvider>.value(value: tts),
          ChangeNotifierProvider<UserProvider>.value(value: user),
          ChangeNotifierProvider<McpProvider>.value(value: mcp),
          ChangeNotifierProvider<McpToolService>.value(value: mcpTools),
          ChangeNotifierProvider<AskUserInteractionService>.value(
            value: questions,
          ),
          ChangeNotifierProvider<ToolApprovalService>.value(value: approvals),
          ChangeNotifierProvider<TaskPlanRegistry>.value(value: plans),
          ChangeNotifierProvider<ToolRunRegistry>.value(value: toolRuns),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SendLongChatHarness(key: key, environment: this),
        ),
      );
}

class SendBenchmarkRepository extends ChatDatabaseRepository {
  SendBenchmarkRepository(
    super.database, {
    super.databaseFile,
    super.observer,
    required this.stage,
  });

  final void Function(String name) stage;
  String? insertedAssistantId;
  String? insertedUserId;
  var toolReadCalls = 0;
  var toolReadMessages = 0;
  var toolReadEvents = 0;
  var toolReadUs = 0;

  @override
  Future<Map<String, List<Map<String, dynamic>>>> getToolEventsForMessages(
    Iterable<String> messageIds,
  ) async {
    final ids = messageIds.toList();
    final watch = Stopwatch()..start();
    toolReadCalls++;
    toolReadMessages += ids.length;
    stage('tools.read.start');
    final result = await super.getToolEventsForMessages(ids);
    toolReadUs += watch.elapsedMicroseconds;
    toolReadEvents += result.values.fold(0, (sum, items) => sum + items.length);
    stage('tools.read.done');
    return result;
  }

  @override
  Future<GenerationBeginResult> beginSendGeneration({
    required Conversation conversation,
    required ChatMessage userMessage,
    required ChatMessage assistantMessage,
    required String runId,
    String? queuedInputId,
  }) async {
    stage('db.begin.start');
    insertedAssistantId = assistantMessage.id;
    insertedUserId = userMessage.id;
    final result = await super.beginSendGeneration(
      conversation: conversation,
      userMessage: userMessage,
      assistantMessage: assistantMessage,
      runId: runId,
      queuedInputId: queuedInputId,
    );
    stage('db.begin.done');
    return result;
  }
}

class SendBenchmarkChatService extends ChatService {
  SendBenchmarkChatService({
    required super.existingRepository,
    required this.stage,
  });
  final void Function(String name) stage;
  var contextMessages = 0;

  @override
  Future<List<ChatMessage>> loadSelectedContextMessages(
    String conversationId, {
    required int truncateIndex,
    required int limit,
    String? throughRevisionId,
    bool includeFollowingAssistant = false,
  }) async {
    stage('context.start');
    final result = await super.loadSelectedContextMessages(
      conversationId,
      truncateIndex: truncateIndex,
      limit: limit,
      throughRevisionId: throughRevisionId,
      includeFollowingAssistant: includeFollowingAssistant,
    );
    contextMessages = result.length;
    stage('context.done');
    return result;
  }
}

class _SendBenchmarkPaths extends PathProviderPlatform {
  _SendBenchmarkPaths(this.path);
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

class SendLongChatHarness extends StatefulWidget {
  const SendLongChatHarness({super.key, required this.environment});
  final SendLongChatEnvironment environment;
  @override
  State<SendLongChatHarness> createState() => SendLongChatHarnessState();
}

class SendLongChatHarnessState extends State<SendLongChatHarness>
    with TickerProviderStateMixin {
  final scaffoldKey = GlobalKey<ScaffoldState>();
  final inputBarKey = GlobalKey();
  final inputFocus = FocusNode();
  final inputController = TextEditingController();
  final mediaController = ChatInputBarController();
  final scrollController = ChatAutoFollowScrollController();
  late final HomePageController controller;
  Future<ChatInputSubmissionResult>? lastSubmission;

  @override
  void initState() {
    super.initState();
    controller = HomePageController(
      context: context,
      vsync: this,
      scaffoldKey: scaffoldKey,
      inputBarKey: inputBarKey,
      inputFocus: inputFocus,
      inputController: inputController,
      mediaController: mediaController,
      scrollController: scrollController,
    );
    controller.addListener(_changed);
    controller.chatController.addListener(_timelineChanged);
    widget.environment.service.addListener(_serviceChanged);
  }

  void _changed() {
    widget.environment.onStage?.call('notify.home');
    if (mounted) setState(() {});
  }

  void _timelineChanged() =>
      widget.environment.onStage?.call('notify.timeline');
  void _serviceChanged() => widget.environment.onStage?.call('notify.service');

  Future<void> open() async {
    final conversation = widget.environment.service.getConversation(
      'long-chat',
    )!;
    await controller.chatController.setCurrentConversationAndLoad(conversation);
    await controller.chatController.loadEndWindow();
    controller.debugViewModel.restoreMessageUiState();
    controller.scrollCtrl.positionAtBottomOnNextLayout();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.environment.settings;
    return Scaffold(
      key: scaffoldKey,
      body: ComputerToolSource(
        readMessages: () => controller.messages,
        readSteps: (id) {
          final live = controller.toolParts[id];
          if (live != null && live.isNotEmpty) {
            return computerStepsFromToolUi(live);
          }
          final message = controller.messages
              .where((m) => m.id == id)
              .firstOrNull;
          final stored = computerStepsFromEvents(
            widget.environment.service.getToolEvents(id),
            streaming: message?.isStreaming ?? false,
          );
          return stored.isNotEmpty || message == null
              ? stored
              : computerStepsFromMessage(message);
        },
        updates: controller.streamingContentNotifier.toolHeightEvents,
        child: Column(
          children: [
            Expanded(
              child: MessageListView(
                scrollController: scrollController,
                listController: controller.scrollCtrl.messageListController,
                messages: controller.chatController.collapsedMessages,
                renderModels: controller.chatController.messageRenderModels,
                byGroup: controller.chatController.groupedMessages,
                versionSelections: controller.versionSelections,
                reasoning: controller.reasoning,
                reasoningSegments: controller.reasoningSegments,
                contentSplits: controller.contentSplits,
                toolParts: controller.toolParts,
                translations: const {},
                selecting: false,
                selectedItems: const {},
                dividerPadding: EdgeInsets.zero,
                processingFilesMessageId: controller.processingFilesMessageId,
                streamingContentNotifier: controller.streamingContentNotifier,
                onUserScrollIntent:
                    controller.scrollCtrl.handleUserScrollIntent,
                chatFontScale: settings.chatFontScale,
                collapseThinking: settings.autoCollapseThinking,
                collapseThinkingSteps: settings.collapseThinkingSteps,
                showThinkingCards: settings.showThinkingCards,
                showToolCards: settings.showToolCards,
                showProducedFiles: settings.showProducedFiles,
                showToolResultSummary: settings.showToolResultSummary,
                hideToolResultImages: settings.hideToolResultImages,
                assistant: widget.environment.assistants.currentAssistant,
              ),
            ),
            ComposerStatusStrip(
              conversationId: controller.currentConversation?.id,
              generating: controller.isCurrentConversationLoading,
            ),
            ChatInputBar(
              key: inputBarKey,
              chatModelProviderKey: 'SiliconFlow',
              chatModelId: 'test-model',
              controller: inputController,
              focusNode: inputFocus,
              mediaController: mediaController,
              conversationId: controller.currentConversation?.id,
              loading: controller.isCurrentConversationLoading,
              onSend: (input) {
                widget.environment.onStage?.call('composer.submit');
                final submission = controller.sendMessage(input);
                lastSubmission = submission;
                return submission;
              },
              onStop: controller.cancelStreaming,
              queuedInputs: controller.queuedInputs,
              onEditQueuedInput: controller.editQueuedMessage,
              onRemoveQueuedInput: controller.removeQueuedMessage,
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    widget.environment.service.removeListener(_serviceChanged);
    controller.chatController.removeListener(_timelineChanged);
    controller.removeListener(_changed);
    controller.dispose();
    inputFocus.dispose();
    inputController.dispose();
    scrollController.dispose();
    super.dispose();
  }
}
