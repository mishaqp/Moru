import 'dart:io';
import 'dart:async';

import 'package:Kelivo/core/models/conversation.dart';

import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:Kelivo/core/database/chat_database_repository.dart';
import 'package:Kelivo/core/services/chat/chat_service.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late PathProviderPlatform previousPathProvider;
  late ChatDatabaseRepository repository;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'kelivo_chat_service_repository_ownership_',
    );
    previousPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProviderPlatform(directory.path);
    repository = ChatDatabaseRepository.open(
      file: File('${directory.path}/kelivo.db'),
    );
    await repository.ensureReady();
  });

  tearDown(() async {
    PathProviderPlatform.instance = previousPathProvider;
    await repository.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  ChatService service({Set<String>? Function()? live, Future<void>? ready}) {
    final chat = ChatService(existingRepository: repository);
    if (live != null) {
      chat.bindMcpServers(liveMcpServerIds: live, mcpServersLoaded: ready);
    }
    addTearDown(chat.close);
    return chat;
  }

  test('read ignores dead ids without rewriting stored selections', () async {
    await repository.putConversation(
      Conversation(
        id: 'old',
        title: 'Old',
        mcpServerIds: ['live', 'dead', 'disabled'],
      ),
    );
    final chat = service(live: () => {'live', 'disabled'});
    await chat.init();
    expect(chat.getConversationMcpServers('old'), ['live', 'disabled']);
    expect(chat.getConversation('old')!.mcpServerIds, ['live', 'disabled']);
    expect(chat.getCompleteConversation('old')!.mcpServerIds, [
      'live',
      'disabled',
    ]);
    expect(chat.getAllConversations().single.mcpServerIds, [
      'live',
      'disabled',
    ]);
    expect((await repository.getConversation('old'))!.mcpServerIds, [
      'live',
      'dead',
      'disabled',
    ]);
    await chat.renameConversation('old', 'Renamed');
    expect((await repository.getConversation('old'))!.mcpServerIds, [
      'live',
      'disabled',
    ]);
  });

  test(
    'extras saves and duplicate prune old selections without changing source history',
    () async {
      await repository.putConversation(
        Conversation(
          id: 'old',
          title: 'Old',
          mcpServerIds: ['live', 'dead'],
          extras: const {'existing': 'kept'},
        ),
      );
      final chat = service(live: () => {'live'});
      await chat.init();
      final copy = (await chat.duplicateConversation('old'))!;
      expect(copy.mcpServerIds, ['live']);
      expect((await repository.getConversation(copy.id))!.mcpServerIds, [
        'live',
      ]);
      expect((await repository.getConversation('old'))!.mcpServerIds, [
        'live',
        'dead',
      ]);
      await chat.updateConversationExtras(
        'old',
        (extras) => {...extras, 'new': 'value'},
      );
      final saved = (await repository.getConversation('old'))!;
      expect(saved.mcpServerIds, ['live']);
      expect(saved.extras, {'existing': 'kept', 'new': 'value'});
    },
  );

  test('generation and backup replacement prune saved selections', () async {
    await repository.putConversation(
      Conversation(id: 'old', title: 'Old', mcpServerIds: ['live', 'dead']),
    );
    final chat = service(live: () => {'live'});
    final result = await chat.beginSendGeneration(
      conversationId: 'old',
      userParts: const [],
      modelId: 'model',
      providerId: 'provider',
    );
    expect(result.conversation.mcpServerIds, ['live']);
    expect((await repository.getConversation('old'))!.mcpServerIds, ['live']);
    await chat.replaceAllDataFromBackup(
      conversations: [
        Conversation(
          id: 'backup',
          title: 'Backup',
          mcpServerIds: ['live', 'dead'],
        ),
      ],
      messages: const [],
      toolEventsByMessageId: const {},
      geminiSignaturesByMessageId: const {},
    );
    expect((await repository.getConversation('backup'))!.mcpServerIds, [
      'live',
    ]);
  });

  for (final action in ['folder', 'archive', 'move']) {
    test('$action saves prune a previously stored dead selection', () async {
      await repository.putConversation(
        Conversation(id: 'old', title: 'Old', mcpServerIds: ['live', 'dead']),
      );
      final chat = service(live: () => {'live'});
      await chat.init();
      switch (action) {
        case 'folder':
          await chat.setConversationsFolder(['old'], 'folder');
        case 'archive':
          await chat.setConversationsArchived(['old'], true);
        case 'move':
          await chat.moveConversationToAssistant(
            conversationId: 'old',
            assistantId: 'new',
          );
      }
      expect((await repository.getConversation('old'))!.mcpServerIds, ['live']);
    });
  }

  test('saving an empty live MCP list clears only old selections', () async {
    await repository.putConversation(
      Conversation(id: 'old', title: 'Old', mcpServerIds: ['dead']),
    );
    final chat = service(live: () => <String>{});
    await chat.init();
    await chat.renameConversation('old', 'Renamed');
    expect((await repository.getConversation('old'))!.mcpServerIds, isEmpty);
  });

  test('saving a message prunes stored dead ids', () async {
    await repository.putConversation(
      Conversation(id: 'old', title: 'Old', mcpServerIds: ['live', 'dead']),
    );
    final chat = service(live: () => {'live'});
    await chat.addMessage(
      conversationId: 'old',
      role: 'user',
      content: 'hello',
    );
    expect((await repository.getConversation('old'))!.mcpServerIds, ['live']);
  });

  test('draft persistence and restore prune dead ids', () async {
    final chat = service(live: () => {'live'});
    final draft = await chat.createDraftConversation();
    await chat.setConversationMcpServers(draft.id, ['live', 'dead']);
    expect(chat.getConversationMcpServers(draft.id), ['live']);
    await chat.addMessage(
      conversationId: draft.id,
      role: 'user',
      content: 'hello',
    );
    expect((await repository.getConversation(draft.id))!.mcpServerIds, [
      'live',
    ]);
    await chat.restoreConversation(
      Conversation(
        id: 'restored',
        title: 'Restored',
        mcpServerIds: ['live', 'dead'],
      ),
      const [],
    );
    expect((await repository.getConversation('restored'))!.mcpServerIds, [
      'live',
    ]);
  });

  test('explicit removal covers stored uncached chats and drafts', () async {
    final chat = service();
    await chat.init();
    // Simulates a stored record not in the service's already loaded summary cache.
    await repository.putConversation(
      Conversation(
        id: 'unloaded',
        title: 'Unloaded',
        mcpServerIds: ['removed', 'kept'],
        extras: const {'preserve': 'value'},
        summary: 'summary',
      ),
    );
    final cached = await chat.createConversation(title: 'Cached');
    await chat.setConversationMcpServers(cached.id, ['removed', 'kept']);
    final draft = await chat.createDraftConversation(temporary: true);
    await chat.setConversationMcpServers(draft.id, ['removed', 'kept']);
    await chat.removeMcpServerId('removed');
    expect(chat.getConversationMcpServers(cached.id), ['kept']);
    expect(chat.getConversationMcpServers(draft.id), ['kept']);
    final unloaded = (await repository.getConversation('unloaded'))!;
    expect(unloaded.mcpServerIds, ['kept']);
    expect(unloaded.extras, {'preserve': 'value'});
    expect(unloaded.summary, 'summary');
    expect(await repository.getConversation(draft.id), isNull);
    final restarted = service();
    await restarted.init();
    expect(restarted.getConversationMcpServers('unloaded'), ['kept']);
    expect(restarted.getConversationMcpServers(cached.id), ['kept']);
  });

  test(
    'save waits for live list readiness without losing selected live ids',
    () async {
      await repository.putConversation(
        Conversation(id: 'old', title: 'Old', mcpServerIds: ['live', 'dead']),
      );
      final ready = Completer<void>();
      Set<String>? live;
      final chat = service(live: () => live, ready: ready.future);
      await chat.init();
      expect(chat.getConversationMcpServers('old'), ['live', 'dead']);
      var saved = false;
      final saving = chat
          .renameConversation('old', 'Renamed')
          .then((_) => saved = true);
      await Future<void>.delayed(Duration.zero);
      expect(saved, isFalse);
      live = {'live'};
      ready.complete();
      await saving;
      expect((await repository.getConversation('old'))!.mcpServerIds, ['live']);
    },
  );
}
