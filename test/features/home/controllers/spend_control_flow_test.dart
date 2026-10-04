import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:Kelivo/core/database/chat_database_repository.dart';
import 'package:Kelivo/core/models/chat_input_data.dart';
import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/models/spend_limits.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/mcp_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/chat/chat_service.dart';
import 'package:Kelivo/core/services/api/tool_call_cancellation.dart';
import 'package:Kelivo/core/services/mcp/mcp_tool_service.dart';
import 'package:Kelivo/core/services/model_catalog/model_catalog.dart';
import 'package:Kelivo/features/home/controllers/chat_controller.dart';
import 'package:Kelivo/features/home/controllers/generation_controller.dart';
import 'package:Kelivo/features/home/controllers/home_view_model.dart';
import 'package:Kelivo/features/home/controllers/stream_controller.dart'
    as streams;
import 'package:Kelivo/features/home/services/message_builder_service.dart';
import 'package:Kelivo/features/home/services/message_generation_service.dart';
import 'package:Kelivo/features/home/services/spend_control_service.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/features/home/services/tool_handler_service.dart';
import 'package:Kelivo/features/home/widgets/chat_token_sheet.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import '../../../support/business_test_harness.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late ChatDatabaseRepository repo;
  late ChatService chats;
  late SettingsProvider settings;
  late AssistantProvider assistants;
  late ToolApprovalService approvals;
  late HttpServer server;
  late PathProviderPlatform oldPaths;
  late HttpOverrides? oldHttp;
  final requests = <Map<String, dynamic>>[];
  late ChatController chatController;
  late streams.StreamController streamController;
  late MessageGenerationService generation;
  late HomeViewModel viewModel;
  late ToolHandlerService toolHandler;
  final errors = <String>[];
  Completer<void>? responseGate;
  int? responseGateRequest;
  Map<String, dynamic> Function(int requestNumber)? scriptedResponse;

  Future<void> mount(WidgetTester tester) async {
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('moru-spend-flow-');
      oldPaths = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _Paths(root.path);
      oldHttp = HttpOverrides.current;
      HttpOverrides.global = null;
      repo = ChatDatabaseRepository.open(file: File('${root.path}/chat.db'));
      await repo.ensureReady();
      chats = ChatService(existingRepository: repo);
      await chats.init();
      settings = SettingsProvider(createBusinessTestPreferences());
      assistants = AssistantProvider(
        preferences: createBusinessTestPreferences(),
      );
      await settings.loaded;
      await assistants.loaded;
      approvals = ToolApprovalService();
      responseGate = null;
      responseGateRequest = null;
      scriptedResponse = null;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final body =
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>;
        requests.add(body);
        if (responseGateRequest == null ||
            responseGateRequest == requests.length) {
          await responseGate?.future;
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(
            scriptedResponse?.call(requests.length) ??
                {
                  'choices': [
                    {
                      'message': {
                        'role': 'assistant',
                        'content': 'Condensed context',
                      },
                    },
                  ],
                },
          ),
        );
        await request.response.close();
      });
      await settings.setProviderConfig(
        'p',
        ProviderConfig(
          id: 'p',
          name: 'Test',
          enabled: true,
          baseUrl: 'http://127.0.0.1:${server.port}/v1',
          apiKey: 'test',
          providerType: ProviderKind.openai,
          modelOverrides: {
            'priced': {'contextWindow': 200000, 'abilities': []},
          },
        ),
      );
      await settings.setCurrentModel('p', 'priced');
      await settings.disableTitleGeneration();
      await settings.disableSuggestionGeneration();
      final id = await assistants.addAssistant(name: 'Budget assistant');
      await assistants.setCurrentAssistant(id);
      await assistants.updateAssistant(
        assistants.getById(id)!.copyWith(streamOutput: false),
      );
    });
    requests.clear();
    errors.clear();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ChatService>.value(value: chats),
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<AssistantProvider>.value(value: assistants),
          ChangeNotifierProvider<ToolApprovalService>.value(value: approvals),
          ChangeNotifierProvider<McpProvider>(
            create: (_) =>
                McpProvider(preferences: createBusinessTestPreferences()),
          ),
          ChangeNotifierProvider<McpToolService>(
            create: (_) => McpToolService(),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              chatController = ChatController(chatService: chats);
              streamController = streams.StreamController(
                onStateChanged: () {},
                getSettingsProvider: () => settings,
                getCurrentConversationId: () =>
                    chatController.currentConversation?.id,
              );
              final builder = MessageBuilderService(
                chatService: chats,
                contextProvider: context,
              );
              final controller = GenerationController(
                chatService: chats,
                chatController: chatController,
                streamController: streamController,
                messageBuilderService: builder,
                contextProvider: context,
                onStateChanged: () {},
                getTitleForLocale: (_) => 'Chat',
              );
              toolHandler = controller.toolHandlerService;
              generation = MessageGenerationService(
                chatService: chats,
                messageBuilderService: builder,
                generationController: controller,
                streamController: streamController,
                contextProvider: context,
              );
              viewModel = HomeViewModel(
                chatService: chats,
                messageBuilderService: builder,
                messageGenerationService: generation,
                generationController: controller,
                streamController: streamController,
                chatController: chatController,
                contextProvider: context,
                getTitleForLocale: (_) => 'Chat',
              );
              viewModel.onError = errors.add;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
  }

  Future<void> cleanup(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    viewModel.dispose();
    streamController.dispose();
    chatController.dispose();
    settings.dispose();
    assistants.dispose();
    approvals.dispose();
    await tester.runAsync(() async {
      await server.close(force: true);
      await chats.close();
      await repo.close();
      PathProviderPlatform.instance = oldPaths;
      HttpOverrides.global = oldHttp;
      await root.delete(recursive: true);
    });
  }

  Future<String> seed() async {
    final convo = await chats.createConversation(
      title: 'Source',
      assistantId: assistants.currentAssistantId,
    );
    final now = DateTime.now();
    for (final message in [
      ChatMessage(
        role: 'user',
        content: 'Remember the task',
        conversationId: convo.id,
      ),
      ChatMessage(
        id: 'paid-first',
        role: 'assistant',
        content: 'First answer',
        conversationId: convo.id,
        providerId: 'p',
        modelId: 'priced',
        promptTokens: 1000000,
        completionTokens: 100000,
        cachedTokens: 500000,
        timestamp: now,
      ),
      ChatMessage(
        id: 'paid-version',
        groupId: 'paid-first',
        version: 1,
        role: 'assistant',
        content: 'Other version',
        conversationId: convo.id,
        providerId: 'p',
        modelId: 'unpriced',
        promptTokens: 1000,
        completionTokens: 100,
        timestamp: now,
      ),
    ]) {
      await chats.addMessageDirectly(convo.id, message);
    }
    await chatController.setCurrentConversationAndLoad(convo);
    return convo.id;
  }

  Future<String> seedRoundBudget() async {
    final assistant = assistants.currentAssistant!;
    await assistants.updateAssistant(
      assistant.copyWith(localToolIds: ['spend_control']),
    );
    await settings.setProviderConfig(
      'p',
      settings
          .getProviderConfig('p')
          .copyWith(
            modelOverrides: {
              'priced': {
                'contextWindow': 200000,
                'abilities': ['tool'],
              },
            },
          ),
    );
    final conversation = await chats.createConversation(
      title: 'Round budget',
      assistantId: assistant.id,
    );
    await chats.addMessageDirectly(
      conversation.id,
      ChatMessage(
        id: 'round-paid',
        role: 'assistant',
        content: 'Previous paid answer',
        conversationId: conversation.id,
        providerId: 'p',
        modelId: 'priced',
        promptTokens: 720,
      ),
    );
    await chatController.setCurrentConversationAndLoad(conversation);
    return conversation.id;
  }

  Map<String, dynamic> roundReply({
    required int input,
    required int output,
    int cached = 0,
    bool callTool = false,
    bool changeLimits = false,
  }) => {
    'choices': [
      {
        'message': {
          'role': 'assistant',
          'content': callTool ? 'Checking the budget' : 'Round done',
          if (callTool)
            'tool_calls': [
              {
                'id': 'budget-round-tool',
                'type': 'function',
                'function': {
                  'name': 'spend_control',
                  'arguments': jsonEncode(
                    changeLimits
                        ? {
                            'action': 'set_limits',
                            'limits': {'chat_tokens': 2000},
                          }
                        : {'action': 'status'},
                  ),
                },
              },
            ],
        },
        'finish_reason': callTool ? 'tool_calls' : 'stop',
      },
    ],
    'usage': {
      'prompt_tokens': input,
      'completion_tokens': output,
      'total_tokens': input + output,
      'prompt_tokens_details': {'cached_tokens': cached},
    },
  };

  testWidgets(
    'completed model round crosses warning threshold before the next request and counts usage once',
    (tester) async {
      await mount(tester);
      await tester.runAsync(() async {
        final id = await seedRoundBudget();
        await settings.setSpendLimits(const SpendLimits(chatTokens: 1000));
        scriptedResponse = (number) => number == 1
            ? roundReply(input: 100, output: 10, cached: 75, callTool: true)
            : roundReply(input: 130, output: 5, cached: 100);
        final done = viewModel.generationTerminalEvents.first;
        expect(
          await viewModel.sendMessage(ChatInputData(text: 'Continue the task')),
          ChatInputSubmissionResult.sent,
        );
        await done.timeout(const Duration(seconds: 10));
        expect(requests, hasLength(2));
        expect(
          jsonEncode(requests.first['messages']),
          isNot(contains('Spend control')),
        );
        expect(jsonEncode(requests.last['messages']), contains('170 tokens'));
        final toolMessage = (requests.last['messages'] as List)
            .cast<Map>()
            .singleWhere((message) => message['role'] == 'tool');
        final toolStatus = jsonDecode(toolMessage['content'] as String) as Map;
        expect((toolStatus['chat'] as Map)['total_tokens'], 830);
        expect((toolStatus['chat'] as Map)['used_percent'], {'tokens': 83.0});
        expect(
          toolStatus['current_response'],
          containsPair('completed_requests', 1),
        );
        expect(
          toolStatus['current_response'],
          containsPair('accounting', 'partial'),
        );
        final reply = (await chats.loadMessages(id)).last;
        expect(reply.promptTokens, 230);
        expect(reply.completionTokens, 15);
        expect(reply.cachedTokens, 175);
        expect(reply.totalTokens, 135);
        expect(reply.content, isNot(contains('Spend control')));
        final status = await SpendControlService(
          chats: chats,
          settings: settings,
        ).status(id, includeContext: false);
        expect(SpendControlStatus.total(status.chat), 965);
        expect(
          status.toJson()['current_response'],
          containsPair('accounting', 'not_included'),
        );
        final prompts = await repo.getMessagePrompts(
          await chats.getMessageIds(id),
        );
        expect(
          prompts.values.any(
            (prompt) => prompt.payload.contains('Spend control'),
          ),
          isFalse,
        );
      });
      await cleanup(tester);
    },
  );

  testWidgets(
    'hard stop after a completed round prevents the next request and cancels pending limit changes',
    (tester) async {
      await mount(tester);
      await tester.runAsync(() async {
        final id = await seedRoundBudget();
        await settings.setSpendLimits(
          const SpendLimits(chatTokens: 1000, hardStop: true),
        );
        scriptedResponse = (number) => number == 1
            ? roundReply(
                input: 300,
                output: 10,
                cached: 200,
                callTool: true,
                changeLimits: true,
              )
            : roundReply(input: 10, output: 5);
        final done = viewModel.generationTerminalEvents.first;
        expect(
          await viewModel.sendMessage(ChatInputData(text: 'Keep working')),
          ChatInputSubmissionResult.sent,
        );
        await done.timeout(const Duration(seconds: 10));
        expect(requests, hasLength(1));
        expect(approvals.pendingRequests, isEmpty);
        expect(settings.spendLimits.chatTokens, 1000);
        final reply = (await chats.loadMessages(id)).last;
        expect(
          reply.content,
          contains('Reply stopped: spending limit reached.'),
        );
        expect(reply.promptTokens, 300);
        expect(reply.completionTokens, 10);
        expect(reply.cachedTokens, 200);
        expect(reply.isStreaming, isFalse);
        expect(streamController.hasLoadingTools(reply.id), isFalse);
        final status = await SpendControlService(
          chats: chats,
          settings: settings,
        ).status(id, includeContext: false);
        expect(SpendControlStatus.total(status.chat), 1030);
        expect(status.blocked, isTrue);
      });
      await cleanup(tester);
    },
  );

  testWidgets(
    'user Stop while the next request is pending preserves completed round spending',
    (tester) async {
      await mount(tester);
      await tester.runAsync(() async {
        final id = await seedRoundBudget();
        await settings.setSpendLimits(const SpendLimits(chatTokens: 1000));
        scriptedResponse = (number) => number == 1
            ? roundReply(input: 100, output: 10, cached: 75, callTool: true)
            : roundReply(input: 130, output: 5, cached: 100);
        responseGate = Completer<void>();
        responseGateRequest = 2;
        final done = viewModel.generationTerminalEvents.first;
        expect(
          await viewModel.sendMessage(ChatInputData(text: 'Keep working')),
          ChatInputSubmissionResult.sent,
        );
        final deadline = DateTime.now().add(const Duration(seconds: 10));
        while (requests.length < 2 && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect(requests, hasLength(2));
        await viewModel.cancelStreaming();
        responseGate!.complete();
        await done.timeout(const Duration(seconds: 10));
        final reply = (await chats.loadMessages(id)).last;
        expect(reply.promptTokens, 100);
        expect(reply.completionTokens, 10);
        expect(reply.cachedTokens, 75);
        expect(reply.totalTokens, 110);
        expect(reply.isStreaming, isFalse);
        expect(streamController.hasLoadingTools(reply.id), isFalse);
        expect(approvals.pendingRequests, isEmpty);
        final status = await SpendControlService(
          chats: chats,
          settings: settings,
        ).status(id, includeContext: false);
        expect(SpendControlStatus.total(status.chat), 830);
        expect(
          status.toJson()['current_response'],
          containsPair('accounting', 'not_included'),
        );
      });
      await cleanup(tester);
    },
  );

  testWidgets(
    'without limits the tool loop preserves the request system messages',
    (tester) async {
      await mount(tester);
      await tester.runAsync(() async {
        final id = await seedRoundBudget();
        scriptedResponse = (number) => number == 1
            ? roundReply(input: 100, output: 10, callTool: true)
            : roundReply(input: 130, output: 5);
        final done = viewModel.generationTerminalEvents.first;
        expect(
          await viewModel.sendMessage(ChatInputData(text: 'Use the tool')),
          ChatInputSubmissionResult.sent,
        );
        await done.timeout(const Duration(seconds: 10));
        expect(requests, hasLength(2));
        List<Map> systems(Map request) => (request['messages'] as List)
            .cast<Map>()
            .where(
              (message) => ['system', 'developer'].contains(message['role']),
            )
            .toList();
        expect(systems(requests.last), systems(requests.first));
        expect(
          jsonEncode(systems(requests.last)),
          isNot(contains('Spend control')),
        );
        expect(
          (await chats.loadMessages(id)).last.content,
          contains('Round done'),
        );
      });
      await cleanup(tester);
    },
  );

  testWidgets(
    'status agrees with the token sheet and today includes other chats and temporary usage once',
    (tester) async {
      await mount(tester);
      await tester.runAsync(() async {
        final id = await seed();
        const price = ModelCatalogEntry(
          inputPrice: 2,
          outputPrice: 10,
          cacheReadPrice: 0.5,
        );
        ModelCatalogEntry? priceFor(String? p, String m) =>
            m == 'priced' ? price : null;
        final expected = ChatTokenSummary.of(
          await chats.loadMessages(id),
          priceFor: priceFor,
        );
        final other = await chats.createConversation(title: 'Other');
        for (final (name, date) in [
          ('yesterday', DateTime.now().subtract(const Duration(days: 2))),
          ('today', DateTime.now()),
        ]) {
          await chats.addMessageDirectly(
            other.id,
            ChatMessage(
              id: name,
              role: 'assistant',
              content: 'private body',
              conversationId: other.id,
              timestamp: date,
              modelId: 'priced',
              promptTokens: 100,
              completionTokens: 50,
            ),
          );
        }
        final temporary = await chats.createDraftConversation(
          title: 'Temporary',
          temporary: true,
        );
        final temporaryReply = await chats.addMessage(
          conversationId: temporary.id,
          role: 'assistant',
          content: 'private temporary',
          modelId: 'priced',
        );
        await chats.updateMessage(
          temporaryReply.id,
          promptTokens: 10,
          completionTokens: 5,
        );
        final result = await SpendControlService(
          chats: chats,
          settings: settings,
          priceFor: priceFor,
        ).status(id, assistant: assistants.currentAssistant);
        expect(result.chat.input, expected.input);
        expect(result.chat.output, expected.output);
        expect(result.chat.cached, expected.cached);
        expect(result.chat.cost, expected.cost);
        expect(result.chat.costComplete, isFalse);
        expect(result.today.input, expected.input + 110);
        expect(result.today.output, expected.output + 55);
        expect(result.contextTokens, 1100);
        expect(result.contextWindow, 200000);
        final metadata = await repo.querySpendMessages(conversationId: id);
        expect(metadata.every((m) => m.content.isEmpty), isTrue);
      });
      await cleanup(tester);
    },
  );

  testWidgets(
    'hard stop rejects a send before saving its pair; disabled hard stop sends',
    (tester) async {
      await mount(tester);
      await tester.runAsync(() async {
        final id = await seed();
        final before = await chats.getMessageIds(id);
        await settings.setSpendLimits(
          const SpendLimits(chatTokens: 100, hardStop: true),
        );
        expect(
          await viewModel.sendMessage(ChatInputData(text: 'Blocked')),
          ChatInputSubmissionResult.rejected,
        );
        expect(await chats.getMessageIds(id), before);
        expect(requests, isEmpty);
        expect(errors.single, contains('Spending limit reached'));
        await settings.setSpendLimits(const SpendLimits(chatTokens: 100));
        final done = viewModel.generationTerminalEvents.first;
        expect(
          await viewModel.sendMessage(ChatInputData(text: 'Allowed')),
          ChatInputSubmissionResult.sent,
        );
        await done.timeout(const Duration(seconds: 10));
        expect(requests, hasLength(1));
        expect(
          jsonEncode(requests.single['messages']),
          contains('Spend control'),
        );
        expect(
          (await chats.loadMessages(
            id,
          )).any((m) => m.content.contains('Spend control')),
          isFalse,
        );
      });
      await cleanup(tester);
    },
  );

  testWidgets(
    'request stays unchanged without limits; threshold note is transient',
    (tester) async {
      await mount(tester);
      await tester.runAsync(() async {
        final id = await seed();
        Future<String> prepare() async {
          final prepared = await generation.prepareApiMessagesWithInjections(
            messages: await chats.loadMessages(id),
            versionSelections: {},
            currentConversation: chats.getConversation(id),
            settings: settings,
            assistant: assistants.currentAssistant,
            assistantId: assistants.currentAssistantId,
            providerKey: 'p',
            modelId: 'priced',
          );
          return jsonEncode(prepared.apiMessages);
        }

        final baseline = await prepare();
        expect(baseline, isNot(contains('Spend control')));
        await settings.setSpendLimits(const SpendLimits(chatTokens: 3000000));
        expect(await prepare(), baseline);
        await settings.setSpendLimits(const SpendLimits(chatTokens: 1200000));
        final withWarning = jsonDecode(await prepare()) as List;
        expect(withWarning.first['role'], 'system');
        expect(withWarning.first['content'], contains('98900 tokens'));
        expect(
          withWarning
              .where((m) => m['role'] != 'system')
              .map((m) => jsonEncode(m))
              .join(),
          (jsonDecode(baseline) as List)
              .where((m) => m['role'] != 'system')
              .map((m) => jsonEncode(m))
              .join(),
        );
        final prompts = await repo.getMessagePrompts(
          await chats.getMessageIds(id),
        );
        expect(
          prompts.values.any((p) => p.payload.contains('Spend control')),
          isFalse,
        );
        expect(
          (await chats.loadMessages(
            id,
          )).any((m) => m.content.contains('Spend control')),
          isFalse,
        );
        await settings.setSpendLimits(const SpendLimits());
        expect(await prepare(), baseline);
        expect(requests, isEmpty);
      });
      await cleanup(tester);
    },
  );

  testWidgets('compact keeps a temporary source and its live reply selected', (
    tester,
  ) async {
    await mount(tester);
    await tester.runAsync(() async {
      final temporary = await chats.createDraftConversation(
        title: 'Temporary',
        assistantId: assistants.currentAssistantId,
        temporary: true,
      );
      await chats.addMessage(
        conversationId: temporary.id,
        role: 'user',
        content: 'Remember this temporary task',
      );
      final live = await chats.addMessage(
        conversationId: temporary.id,
        role: 'assistant',
        content: 'Currently calling compact',
        isStreaming: true,
      );
      await chatController.setCurrentConversationAndLoad(temporary);
      final result = await viewModel.compactForSpendControl(temporary.id);
      expect(result['ok'], isTrue);
      expect(viewModel.currentConversation!.id, temporary.id);
      expect(chats.currentConversationId, temporary.id);
      expect(chats.getConversation(temporary.id), isNotNull);
      expect(await chats.getMessageIds(temporary.id), contains(live.id));
      expect(
        (await chats.loadMessages(
          result['conversation_id'] as String,
        )).single.content,
        'Condensed context',
      );
      expect(jsonEncode(requests.single), isNot(contains(live.content)));
    });
    await cleanup(tester);
  });

  testWidgets(
    'compact keepRecent does not charge retained replies a second time',
    (tester) async {
      await mount(tester);
      await tester.runAsync(() async {
        final source = await seed();
        await chats.addMessage(
          conversationId: source,
          role: 'user',
          content: 'Latest turn to retain',
        );
        final paid = await chats.addMessage(
          conversationId: source,
          role: 'assistant',
          content: 'Retained paid reply',
          modelId: 'priced',
          providerId: 'p',
        );
        await chats.updateMessage(
          paid.id,
          promptTokens: 100,
          completionTokens: 50,
          cachedTokens: 40,
        );
        await settings.setCompressLimitMode(
          CompressContextLimitMode.keepRecent,
        );
        await settings.setCompressKeepUserMessages(1);
        await settings.setSpendLimits(
          const SpendLimits(dailyTokens: 1101300, hardStop: true),
        );
        final spending = SpendControlService(chats: chats, settings: settings);
        final before = await spending.status(source);
        final result = await viewModel.compactForSpendControl(source);
        expect(result['ok'], isTrue);
        final after = await spending.status(
          result['conversation_id'] as String,
        );
        expect(after.today.input, before.today.input);
        expect(after.today.output, before.today.output);
        expect(after.today.cached, before.today.cached);
        expect(after.blocked, isFalse);
        expect(after.chat.input, 0);
        expect(after.chat.output, 0);
        final retained = await chats.loadMessages(
          result['conversation_id'] as String,
        );
        expect(retained.map((m) => m.content), contains('Retained paid reply'));
        expect(
          (await chats.loadMessages(source)).map((m) => m.id),
          contains(paid.id),
        );
      });
      await cleanup(tester);
    },
  );

  testWidgets(
    'stopping compact prevents subsequent chunk requests and a new chat',
    (tester) async {
      await mount(tester);
      await tester.runAsync(() async {
        final source = await seed();
        await chats.addMessage(
          conversationId: source,
          role: 'user',
          content: 'Long task ' * 1000,
        );
        final config = settings.getProviderConfig('p');
        await settings.setProviderConfig(
          'p',
          config.copyWith(
            modelOverrides: {
              'priced': {'contextWindow': 512, 'abilities': []},
            },
          ),
        );
        await settings.setCompressLimitMode(CompressContextLimitMode.unlimited);
        responseGate = Completer<void>();
        final stopped = Completer<void>();
        var cancelled = false;
        final compacting = ToolCallCancellation(
          isCancelled: () => cancelled,
          cancelled: stopped.future,
        ).run(() => viewModel.compactForSpendControl(source));
        while (requests.isEmpty) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        cancelled = true;
        stopped.complete();
        responseGate!.complete();
        final result = await compacting.timeout(const Duration(seconds: 10));
        expect(result['ok'], isFalse);
        expect(requests, hasLength(1));
        expect(viewModel.currentConversation!.id, source);
        expect(chats.getAllConversations(), hasLength(1));
      });
      await cleanup(tester);
    },
  );

  testWidgets('disabling spend control during compact prevents further work', (
    tester,
  ) async {
    await mount(tester);
    await tester.runAsync(() async {
      final source = await seed();
      await chats.addMessage(
        conversationId: source,
        role: 'user',
        content: 'Long task ' * 1000,
      );
      final assistant = assistants.currentAssistant!;
      await assistants.updateAssistant(
        assistant.copyWith(localToolIds: ['spend_control']),
      );
      await settings.setToolAutoApproveAll(true);
      await settings.setCompressLimitMode(CompressContextLimitMode.unlimited);
      await settings.setProviderConfig(
        'p',
        settings
            .getProviderConfig('p')
            .copyWith(
              modelOverrides: {
                'priced': {'contextWindow': 512, 'abilities': []},
              },
            ),
      );
      final handler = toolHandler.buildToolCallHandler(
        settings,
        assistants.currentAssistant,
        approvalService: approvals,
        conversationId: source,
      )!;
      responseGate = Completer<void>();
      final compacting = handler('spend_control', {
        'action': 'compact',
      }, toolCallId: 'compact');
      while (requests.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await assistants.updateAssistant(assistant.copyWith(localToolIds: []));
      responseGate!.complete();
      final result = jsonDecode(await compacting as String) as Map;
      expect(result['ok'], isFalse);
      expect(requests, hasLength(1));
      expect(chats.getAllConversations(), hasLength(1));
      expect(viewModel.currentConversation!.id, source);
    });
    await cleanup(tester);
  });

  testWidgets(
    'compact reuses configured compression on the calling chat and preserves another selection',
    (tester) async {
      await mount(tester);
      await tester.runAsync(() async {
        final source = await seed();
        final other = await chats.createConversation(title: 'Other');
        await chats.addMessage(
          conversationId: other.id,
          role: 'user',
          content: 'OTHER_CHAT_SENTINEL',
        );
        await chatController.setCurrentConversationAndLoad(other);
        await settings.setCompressLimitMode(CompressContextLimitMode.recent);
        await settings.setCompressMaxChars(4000);
        final result = await viewModel.compactForSpendControl(source);
        expect(result['ok'], isTrue);
        expect(result['conversation_id'], isNot(source));
        expect(viewModel.currentConversation!.id, other.id);
        expect(requests, hasLength(1));
        final prompt = jsonEncode(requests.single);
        expect(prompt, contains('Remember the task'));
        expect(prompt, isNot(contains('OTHER_CHAT_SENTINEL')));
        expect((await chats.loadMessages(source)).length, 3);
        final compacted = await chats.loadMessages(
          result['conversation_id'] as String,
        );
        expect(compacted.single.content, 'Condensed context');
      });
      await cleanup(tester);
    },
  );
}
