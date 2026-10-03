import 'dart:convert';

import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/models/message_part.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/providers/tts_provider.dart';
import 'package:Kelivo/core/providers/user_provider.dart';
import 'package:Kelivo/core/services/workspace/tool_run_registry.dart';
import 'package:Kelivo/core/services/workspace/workspace_tool_metadata.dart';
import 'package:Kelivo/features/chat/widgets/chat_message_widget.dart';
import 'package:Kelivo/features/chat/widgets/computer_response_scope.dart';
import 'package:Kelivo/features/home/controllers/scroll_controller.dart'
    as scroll_ctrl;
import 'package:Kelivo/features/home/controllers/streaming_content_notifier.dart';
import 'package:Kelivo/features/home/services/ask_user_interaction_service.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/features/home/widgets/composer_status_strip.dart';
import 'package:Kelivo/features/home/widgets/message_list_view.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'business_test_harness.dart';

/// TTS is present in the production message tree; this fixture never plays it.
void installLongChatPlatformStubs() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final events = <String>{};
  void stubEvents(String name) {
    events.add(name);
    messenger.setMockMessageHandler(
      name,
      (_) async => const StandardMethodCodec().encodeSuccessEnvelope(null),
    );
  }

  const global = MethodChannel('xyz.luan/audioplayers.global');
  const player = MethodChannel('xyz.luan/audioplayers');
  messenger.setMockMethodCallHandler(global, (_) async => null);
  messenger.setMockMethodCallHandler(player, (call) async {
    if (call.method == 'create') {
      final id = (call.arguments as Map)['playerId'];
      stubEvents('xyz.luan/audioplayers/events/$id');
    }
    return null;
  });
  stubEvents('xyz.luan/audioplayers.global/events');
  addTearDown(() {
    messenger.setMockMethodCallHandler(global, null);
    messenger.setMockMethodCallHandler(player, null);
    for (final name in events) {
      messenger.setMockMessageHandler(name, null);
    }
  });
}

/// Persisted parts plus the restored tool overlays used by HomePage.
class LongChatFixture {
  LongChatFixture({int rounds = 300}) {
    for (var i = 0; i < rounds; i++) {
      messages.add(
        ChatMessage(
          id: 'user-$i',
          role: 'user',
          content: 'Проверь модуль $i.',
          conversationId: 'long-chat',
          timestamp: DateTime(2026),
        ),
      );
      final tool = i % 10 == 0 ? null : longChatTool(i);
      final payload = tool == null ? null : toolPayload(tool);
      messages.add(
        ChatMessage(
          id: 'assistant-$i',
          role: 'assistant',
          conversationId: 'long-chat',
          timestamp: DateTime(2026),
          parts: [
            TextPart('Шаг $i: проверяю **модуль** `module_$i`.\n\n'),
            if (payload != null) ToolCallPart(payload),
            const TextPart('Проверка завершена, продолжаю работу.'),
          ],
        ),
      );
      if (tool != null) tools['assistant-$i'] = [tool];
    }
  }

  final messages = <ChatMessage>[];
  final tools = <String, List<ToolUIPart>>{};
}

String toolPayload(ToolUIPart tool) => jsonEncode({
  'id': tool.id,
  'name': tool.toolName,
  'arguments': tool.arguments,
  'content': tool.content,
  'metadata': tool.metadata,
});

ToolUIPart longChatTool(int i) {
  final name = switch (i % 10) {
    7 || 8 => 'shell',
    9 => 'browser_use',
    _ => 'edit_file',
  };
  final path = 'lib/module_$i.dart';
  final output = List.generate(
    100,
    (line) => 'module $i: output line $line',
  ).join('\n');
  return ToolUIPart(
    id: 'tool-$i',
    toolName: name,
    arguments: switch (name) {
      'shell' => {'command': 'dart analyze $path'},
      'browser_use' => {
        'action': 'navigate',
        'url': 'https://example.com/page/$i',
      },
      _ => {'path': path, 'old_string': 'old value', 'new_string': 'new value'},
    },
    content: name == 'browser_use'
        ? jsonEncode({
            'success': true,
            'url': 'https://example.com/page/$i',
            'title': 'Module $i',
          })
        : name == 'shell'
        ? output
        : 'File updated.',
    metadata: name == 'browser_use'
        ? null
        : WorkspaceToolMetadata(
            tool: name,
            status: 'ok',
            path: path,
            command: name == 'shell' ? 'dart analyze $path' : null,
            exitCode: name == 'shell' ? 0 : null,
            stdoutPreview: name == 'shell' ? output : null,
            // 20 KiB of ASCII unified diff per edit_file.
            diff: name == 'edit_file'
                ? ('+ added line\n- removed line\n' * 800).substring(
                    0,
                    20 * 1024,
                  )
                : null,
            added: name == 'edit_file' ? 400 : null,
            removed: name == 'edit_file' ? 400 : null,
          ).toJson(),
  );
}

class LongChatHarness extends StatefulWidget {
  const LongChatHarness({super.key, required this.fixture});
  final LongChatFixture fixture;

  @override
  State<LongChatHarness> createState() => LongChatHarnessState();
}

class LongChatHarnessState extends State<LongChatHarness> {
  final scrollController = scroll_ctrl.ChatAutoFollowScrollController();
  final notifier = StreamingContentNotifier();
  final processingFiles = ValueNotifier<String?>(null);
  late final scroll_ctrl.ChatScrollController scroll;
  late final messages = List<ChatMessage>.of(widget.fixture.messages);
  late final tools = Map<String, List<ToolUIPart>>.of(widget.fixture.tools);
  String? activeId;
  var sends = 0;
  var chunks = 0;

  @override
  void initState() {
    super.initState();
    scroll = scroll_ctrl.ChatScrollController(
      scrollController: scrollController,
      getAutoScrollEnabled: () => true,
      getAutoScrollIdleSeconds: () => 3,
      isGenerating: () => activeId != null,
    );
  }

  void send() => setState(() {
    if (activeId != null) {
      messages[messages.length - 1] = messages.last.copyWith(
        isStreaming: false,
      );
    }
    final id = 'new-assistant-${sends++}';
    messages.add(
      ChatMessage(
        id: 'new-user-$sends',
        role: 'user',
        content: 'Продолжай.',
        conversationId: 'long-chat',
      ),
    );
    messages.add(
      ChatMessage(
        id: id,
        role: 'assistant',
        content: '',
        conversationId: 'long-chat',
        isStreaming: true,
      ),
    );
    activeId = id;
    chunks = 0;
    notifier.getNotifier(id);
  });

  void streamChunk() {
    final id = activeId!;
    chunks++;
    final content = 'Продолжаю **проверку**. ' * chunks;
    final parts = ChatMessage.partsWithReplacedText(
      messages.last.parts,
      content,
    );
    messages[messages.length - 1] = messages.last.copyWith(parts: parts);
    notifier.updateContent(id, content, chunks, parts: parts);
  }

  void toolCard() {
    final id = activeId!;
    final tool = longChatTool(1001 + (tools[id]?.length ?? 0));
    tools[id] = [...?tools[id], tool];
    final parts = [...messages.last.parts, ToolCallPart(toolPayload(tool))];
    messages[messages.length - 1] = messages.last.copyWith(parts: parts);
    notifier.updateContent(id, messages.last.content, chunks, parts: parts);
    notifier.notifyToolPartsUpdated(id);
  }

  void goToEnd() {
    if (scrollController.hasClients) {
      scrollController.jumpTo(scrollController.position.maxScrollExtent);
    }
  }

  @override
  void dispose() {
    scroll.dispose();
    scrollController.dispose();
    notifier.dispose();
    processingFiles.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MultiProvider(
    providers: [
      ChangeNotifierProvider(
        create: (_) => SettingsProvider(createBusinessTestPreferences()),
      ),
      ChangeNotifierProvider(
        create: (_) =>
            AssistantProvider(preferences: createBusinessTestPreferences()),
      ),
      ChangeNotifierProvider(
        create: (_) =>
            TtsProvider(preferences: createBusinessTestPreferences()),
      ),
      ChangeNotifierProvider(
        create: (_) =>
            UserProvider(preferences: createBusinessTestPreferences()),
      ),
      ChangeNotifierProvider(create: (_) => AskUserInteractionService()),
      ChangeNotifierProvider(create: (_) => ToolApprovalService()),
      ChangeNotifierProvider(create: (_) => ToolRunRegistry()),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ComputerToolSource(
          readMessages: () => messages,
          readSteps: (id) {
            final live = tools[id];
            if (live != null && live.isNotEmpty) {
              return computerStepsFromToolUi(live);
            }
            final message = messages.where((m) => m.id == id).firstOrNull;
            return message == null ? [] : computerStepsFromMessage(message);
          },
          updates: notifier.toolHeightEvents,
          child: Column(
            children: [
              Expanded(
                child: MessageListView(
                  scrollController: scrollController,
                  listController: scroll.messageListController,
                  messages: messages,
                  byGroup: const {},
                  versionSelections: const {},
                  reasoning: const {},
                  reasoningSegments: const {},
                  contentSplits: const {},
                  toolParts: tools,
                  translations: const {},
                  selecting: false,
                  selectedItems: const {},
                  dividerPadding: EdgeInsets.zero,
                  processingFilesMessageId: processingFiles,
                  streamingContentNotifier: notifier,
                ),
              ),
              ComposerStatusStrip(
                conversationId: 'long-chat',
                generating: activeId != null,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
