import 'dart:io';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late PathProviderPlatform previousPathProvider;
  late AppDatabase database;
  late WorkspaceProvider workspaces;
  late ChatService chats;
  late AssistantProvider assistants;

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
  });

  tearDown(() async {
    await chats.close();
    await Hive.close();
    PathProviderPlatform.instance = previousPathProvider;
    await database.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

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
