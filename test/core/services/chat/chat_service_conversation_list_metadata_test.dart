import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:Kelivo/core/models/message_part.dart';
import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/models/conversation.dart';
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
  final services = <ChatService>[];

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('chat_list_metadata_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(directory.path);
  });

  tearDown(() async {
    for (final service in services) {
      await service.close();
    }
    services.clear();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  ChatService createService() {
    final service = ChatService();
    services.add(service);
    return service;
  }

  test('cold list reads metadata without loading chat history', () async {
    final writer = createService();
    await writer.init();
    final conversation = await writer.createConversation(title: 'Chat');
    await writer.addMessage(
      conversationId: conversation.id,
      role: 'assistant',
      content: 'Answer',
      modelId: 'answer-model',
      providerId: 'answer-provider',
    );
    final latest = await writer.addMessage(
      conversationId: conversation.id,
      role: 'user',
      content: 'First line\nLater line',
    );
    await writer.close();
    services.remove(writer);

    final reader = createService();
    await reader.init();
    final metadata = reader.getConversationListMetadata(conversation.id);

    expect(metadata, isNotNull);
    expect(metadata!.lastMessageId, latest.id);
    expect(metadata.lastMessagePreview, 'First line');
    expect(metadata.lastAssistantModelId, 'answer-model');
    expect(reader.getMessages(conversation.id), isEmpty);
    expect(reader.getConversation(conversation.id)!.messageIds, isEmpty);
    expect(reader.isMessageCountKnown(conversation.id), isFalse);
    expect(reader.debugHasMessageOrderSkeleton(conversation.id), isFalse);
    expect(reader.getConversationListMetadata(conversation.id), same(metadata));
  });

  test('silent checkpoints update only cached preview metadata', () async {
    final service = createService();
    await service.init();
    final conversation = await service.createConversation(title: 'Chat');
    final message = await service.addMessage(
      conversationId: conversation.id,
      role: 'assistant',
      content: '',
      modelId: 'model',
      providerId: 'provider',
      isStreaming: true,
    );
    final revision = service.conversationListRevision;
    var notifications = 0;
    service.addListener(() => notifications++);

    await service.updateStreamingCheckpointSilent(
      message.copyWith(parts: const [TextPart('First line\nMore text')]),
      const [],
    );

    final metadata = service.getConversationListMetadata(conversation.id);
    expect(metadata, isNotNull);
    expect(metadata!.lastMessagePreview, 'First line');
    expect(metadata.lastAssistantModelId, 'model');
    expect(service.conversationListRevision, revision);
    expect(notifications, 0);

    await service.updateStreamingCheckpointSilent(
      message.copyWith(
        parts: const [TextPart('First line\nMore text appended')],
      ),
      const [],
    );
    expect(
      service.getConversationListMetadata(conversation.id),
      same(metadata),
    );
    expect(notifications, 0);
  });

  test('editing older rows does not replace the latest preview', () async {
    final service = createService();
    await service.init();
    final conversation = await service.createConversation(title: 'Chat');
    final older = await service.addMessage(
      conversationId: conversation.id,
      role: 'user',
      content: 'Old',
    );
    final latest = await service.addMessage(
      conversationId: conversation.id,
      role: 'assistant',
      content: 'Latest',
      modelId: 'model',
      providerId: 'provider',
    );
    await service.updateMessage(older.id, content: 'Old edited');

    final metadata = service.getConversationListMetadata(conversation.id);
    expect(metadata, isNotNull);
    expect(metadata!.lastMessageId, latest.id);
    expect(metadata.lastMessagePreview, 'Latest');
  });

  test('deleting the latest message restores the previous summary', () async {
    final service = createService();
    await service.init();
    final conversation = await service.createConversation(title: 'Chat');
    final answer = await service.addMessage(
      conversationId: conversation.id,
      role: 'assistant',
      content: 'Answer',
      modelId: 'model',
      providerId: 'provider',
    );
    final latest = await service.addMessage(
      conversationId: conversation.id,
      role: 'user',
      content: 'Question',
    );

    await service.deleteMessage(latest.id);
    expect(
      service.getConversationListMetadata(conversation.id)!.lastMessageId,
      answer.id,
    );
    expect(
      service.getConversationListMetadata(conversation.id)!.lastMessagePreview,
      'Answer',
    );

    await service.deleteMessage(answer.id);
    expect(service.getConversationListMetadata(conversation.id), isNull);
  });

  test(
    'duplicate and restore expose summaries without opening chats',
    () async {
      final service = createService();
      await service.init();
      final conversation = await service.createConversation(title: 'Chat');
      await service.addMessage(
        conversationId: conversation.id,
        role: 'assistant',
        content: 'Answer',
        modelId: 'model',
        providerId: 'provider',
      );
      final duplicate = await service.duplicateConversation(conversation.id);
      final duplicateMetadata = service.getConversationListMetadata(
        duplicate!.id,
      );
      expect(duplicateMetadata, isNotNull);
      expect(duplicateMetadata!.lastMessagePreview, 'Answer');
      expect(duplicateMetadata.lastAssistantModelId, 'model');
      expect(service.getMessages(duplicate.id), isEmpty);

      final restored = Conversation(id: 'restored', title: 'Restored');
      await service.restoreConversation(restored, [
        ChatMessage(
          id: 'restored-message',
          conversationId: restored.id,
          role: 'assistant',
          content: 'Restored first line\nRestored later line',
          modelId: 'restored-model',
          providerId: 'restored-provider',
        ),
      ]);
      final restoredMetadata = service.getConversationListMetadata(restored.id);
      expect(restoredMetadata, isNotNull);
      expect(restoredMetadata!.lastMessagePreview, 'Restored first line');
      expect(restoredMetadata.lastAssistantModelId, 'restored-model');
    },
  );

  test(
    'deleting conversations and clearing data drops their metadata',
    () async {
      final service = createService();
      await service.init();
      final first = await service.createConversation(title: 'First');
      final second = await service.createConversation(title: 'Second');
      await service.addMessage(
        conversationId: first.id,
        role: 'user',
        content: 'First preview',
      );
      await service.addMessage(
        conversationId: second.id,
        role: 'user',
        content: 'Second preview',
      );

      await service.deleteConversation(first.id);
      expect(service.getConversationListMetadata(first.id), isNull);
      expect(service.getConversationListMetadata(second.id), isNotNull);

      await service.clearAllData();
      expect(service.getConversationListMetadata(second.id), isNull);
    },
  );

  test('anchored generation keeps later message preview and model', () async {
    final service = createService();
    await service.init();
    final conversation = await service.createConversation(title: 'Chat');
    final anchor = await service.addMessage(
      conversationId: conversation.id,
      role: 'user',
      content: 'Anchor',
    );
    final later = await service.addMessage(
      conversationId: conversation.id,
      role: 'assistant',
      content: 'Later answer',
      modelId: 'later-model',
      providerId: 'later-provider',
    );

    await service.beginAssistantGeneration(
      conversationId: conversation.id,
      modelId: 'earlier-model',
      providerId: 'earlier-provider',
      anchorGroupId: anchor.groupId ?? anchor.id,
      truncateFuture: false,
    );

    final metadata = service.getConversationListMetadata(conversation.id)!;
    expect(metadata.lastMessageId, later.id);
    expect(metadata.lastMessagePreview, 'Later answer');
    expect(metadata.lastAssistantModelId, 'later-model');
  });

  test(
    'anchored generation supplies the last model before a later user',
    () async {
      final service = createService();
      await service.init();
      final conversation = await service.createConversation(title: 'Chat');
      final anchor = await service.addMessage(
        conversationId: conversation.id,
        role: 'user',
        content: 'Anchor',
      );
      final later = await service.addMessage(
        conversationId: conversation.id,
        role: 'user',
        content: 'Later question',
      );

      final result = await service.beginAssistantGeneration(
        conversationId: conversation.id,
        modelId: 'inserted-model',
        providerId: 'inserted-provider',
        anchorGroupId: anchor.groupId ?? anchor.id,
        truncateFuture: false,
      );

      final metadata = service.getConversationListMetadata(conversation.id)!;
      expect(metadata.lastMessageId, later.id);
      expect(metadata.lastMessagePreview, 'Later question');
      expect(metadata.lastAssistantMessageId, result.assistantMessage.id);
      expect(metadata.lastAssistantModelId, 'inserted-model');
    },
  );
}
