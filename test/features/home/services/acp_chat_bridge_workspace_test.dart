import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:Kelivo/core/services/acp/acp_agent.dart';
import 'package:Kelivo/core/services/acp/acp_agent_catalog.dart';
import 'package:Kelivo/core/services/acp/acp_chat_sessions.dart';
import 'package:Kelivo/features/home/widgets/acp_mode_chip.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/widgets/ios_tile_button.dart';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:Kelivo/core/database/app_database.dart';
import 'package:Kelivo/core/database/extension_entity_store.dart';
import 'package:Kelivo/core/models/workspace_binding.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/providers/workspace_provider.dart';
import 'package:Kelivo/core/services/chat/chat_service.dart';
import 'package:Kelivo/features/home/services/acp_chat_bridge.dart';

import '../../../support/business_test_harness.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.path);

  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;

  @override
  Future<String?> getApplicationSupportPath() async => path;

  @override
  Future<String?> getApplicationCachePath() async => p.join(path, 'cache');

  @override
  Future<String?> getTemporaryPath() async => p.join(path, 'tmp');
}

class _ModeChannel extends AcpChannel {
  final incoming = StreamController<dynamic>();
  final ended = Completer<void>();
  final sent = <Map<String, Object?>>[];
  @override
  Stream<dynamic> get messages => incoming.stream;
  @override
  Future<void> get closed => ended.future;
  @override
  Future<void> send(Map<String, Object?> message) async {
    sent.add(message);
    scheduleMicrotask(
      () => incoming.add({
        'jsonrpc': '2.0',
        'id': message['id'],
        'result': switch (message['method']) {
          'initialize' => {'protocolVersion': 1},
          'session/new' => {
            'sessionId': 's1',
            'modes': {
              'currentModeId': 'ask',
              'availableModes': [
                {'id': 'ask', 'name': 'Ask'},
                {'id': 'code', 'name': 'Code'},
              ],
            },
          },
          _ => {'stopReason': 'end_turn'},
        },
      }),
    );
  }

  @override
  void close() {
    if (!ended.isCompleted) ended.complete();
    unawaited(incoming.close());
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late PathProviderPlatform previousPathProvider;
  late AppDatabase database;
  late WorkspaceProvider workspaces;
  late ChatService chats;
  late AssistantProvider assistants;
  late SettingsProvider settings;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('kelivo_acp_workspace_');
    previousPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    database = AppDatabase(NativeDatabase.memory());
    await database.customSelect('SELECT 1;').getSingle();
    workspaces = WorkspaceProvider(store: ExtensionEntityStore(database));
    await workspaces.loaded;
    chats = ChatService();
    await chats.init();
    assistants = AssistantProvider(
      preferences: createBusinessTestPreferences(),
    );
    await assistants.loaded;
    settings = SettingsProvider(createBusinessTestPreferences());
    await settings.loaded;
  });

  tearDown(() async {
    settings.dispose();
    await chats.close();
    await Hive.close();
    PathProviderPlatform.instance = previousPathProvider;
    await database.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  testWidgets(
    'mode sheet saves the choice and applies it only on the next turn',
    (tester) async {
      final channel = _ModeChannel();
      final sessions = AcpChatSessions(
        start: (spec, provider, {required cwd, required mounts}) =>
            AcpAgent.start(channel, clientVersion: '1'),
      );
      addTearDown(sessions.dispose);
      final conversation = (await tester.runAsync(
        () => chats.createConversation(),
      ))!;
      AcpChatTurn turn({String? mode}) => AcpChatTurn(
        conversationId: conversation.id,
        spec: AcpAgentSpec.byId('opencode')!,
        provider: const AcpProviderInput(
          baseUrl: 'https://example.com',
          apiKey: 'key',
          model: 'model',
        ),
        cwd: '/root',
        prompt: const [
          {'type': 'text', 'text': 'hi'},
        ],
        savedModeId: mode,
      );
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AcpChatSessions>.value(value: sessions),
            ChangeNotifierProvider<ChatService>.value(value: chats),
            ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: AcpModeChip(conversationId: conversation.id)),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('acp-mode-chip')), findsNothing);
      await tester.runAsync(() => sessions.send(turn()).drain<void>());
      await tester.pump();
      expect(find.text('Ask'), findsOneWidget);
      // Register the sheet continuation in the real async zone: saving its
      // result performs database IO after the route has been dismissed.
      await tester.runAsync(() async {
        tester
            .widget<IosTileButton>(find.byKey(const ValueKey('acp-mode-chip')))
            .onTap();
      });
      await tester.pumpAndSettle();
      expect(find.text('Agent mode'), findsOneWidget);
      final saved = (await tester.runAsync(() async => Completer<void>()))!;
      void onChanged() {
        if (chats.getConversation(conversation.id)?.extras[acpModeKey] ==
                'code' &&
            !saved.isCompleted) {
          saved.complete();
        }
      }

      chats.addListener(onChanged);
      addTearDown(() => chats.removeListener(onChanged));
      await tester.tap(find.text('Code'));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => saved.future.timeout(const Duration(seconds: 2)),
      );
      await tester.pumpAndSettle();
      expect(
        chats.getConversation(conversation.id)!.extras[acpModeKey],
        'code',
      );
      expect(
        tester
            .widget<IosTileButton>(find.byKey(const ValueKey('acp-mode-chip')))
            .label,
        'Code',
      );
      expect(
        channel.sent.where((m) => m['method'] == 'session/set_mode'),
        isEmpty,
      );
      await tester.runAsync(
        () => sessions
            .send(
              turn(
                mode:
                    chats.getConversation(conversation.id)!.extras[acpModeKey]
                        as String,
              ),
            )
            .drain<void>(),
      );
      expect(
        channel.sent.singleWhere(
          (m) => m['method'] == 'session/set_mode',
        )['params'],
        {'sessionId': 's1', 'modeId': 'code'},
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test('an agent chat without a folder gets the assistant\'s, made once '
      'and named after the agent', () async {
    final id = await assistants.addAssistant(name: 'OpenCode');
    final assistant = assistants.getById(id)!.copyWith(agentId: 'opencode');
    await assistants.updateAssistant(assistant);
    final first = await chats.createConversation(assistantId: id);
    final second = await chats.createConversation(assistantId: id);

    Future<void> ensure(String conversationId) => AcpChatBridge.ensureWorkspace(
      chats: chats,
      workspaces: workspaces,
      assistants: assistants,
      assistant: assistant,
      conversationId: conversationId,
      name: 'OpenCode',
    );

    await ensure(first.id);
    expect(workspaces.workspaces, hasLength(1));
    final workspace = workspaces.workspaces.single;
    expect(workspace.name, 'OpenCode');
    expect(assistants.getById(id)!.defaultWorkspaceId, workspace.id);
    expect(
      WorkspaceBinding.fromExtras(
        chats.getConversation(first.id)!.extras,
      ).workspaceId,
      workspace.id,
    );

    // The next chat reuses it.
    await ensure(second.id);
    expect(workspaces.workspaces, hasLength(1));
    expect(
      WorkspaceBinding.fromExtras(
        chats.getConversation(second.id)!.extras,
      ).workspaceId,
      workspace.id,
    );
  });

  test('a chat that already has a folder keeps it', () async {
    final id = await assistants.addAssistant(name: 'Codex');
    final own = await workspaces.create(name: 'My project');
    final chat = await chats.createConversation(assistantId: id);
    await chats.updateConversationExtras(
      chat.id,
      WorkspaceBinding(workspaceId: own.id, cwd: own.defaultCwd).applyTo,
    );
    await AcpChatBridge.ensureWorkspace(
      chats: chats,
      workspaces: workspaces,
      assistants: assistants,
      assistant: assistants.getById(id)!,
      conversationId: chat.id,
      name: 'Codex',
    );
    expect(workspaces.workspaces, hasLength(1));
    expect(
      WorkspaceBinding.fromExtras(
        chats.getConversation(chat.id)!.extras,
      ).workspaceId,
      own.id,
    );
    expect(assistants.getById(id)!.defaultWorkspaceId, isNull);
  });
}
