import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/database/chat_database_repository.dart';
import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/models/conversation.dart';
import 'package:Kelivo/core/models/message_part.dart';

void main() {
  late Directory directory;
  late ChatDatabaseRepository repository;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('chat_list_metadata_');
    repository = ChatDatabaseRepository.open(
      file: File('${directory.path}/chat.sqlite'),
    );
    await repository.ensureReady();
  });

  tearDown(() async {
    await repository.close();
    await directory.delete(recursive: true);
  });

  test('summary loads bounded preview and the last answering model', () async {
    final assistantAt = DateTime.utc(2026, 10, 1, 12);
    final userAt = assistantAt.add(const Duration(minutes: 1));
    final conversation = Conversation(
      id: 'chat',
      title: 'Chat',
      assistantId: 'assistant',
      chatModelProvider: 'override-provider',
      chatModelId: 'override-model',
      mcpServerIds: const ['second', 'first'],
    );
    final answer = ChatMessage(
      id: 'answer',
      conversationId: conversation.id,
      role: 'assistant',
      content: 'Previous answer',
      timestamp: assistantAt,
      modelId: 'answer-model',
      providerId: 'answer-provider',
    );
    final user = ChatMessage(
      id: 'latest-user',
      conversationId: conversation.id,
      role: 'user',
      timestamp: userAt,
      parts: [
        const ReasoningPart('private reasoning'),
        const ImagePart(uri: 'https://example.com/photo.png'),
        TextPart('  First line\r\n${'large body ' * 100000}'),
        const ToolCallPart('{"secret":"tool arguments"}'),
      ],
    );
    await repository.putMigrationBatch(
      conversations: [conversation],
      messages: [
        (message: answer, messageOrder: 0),
        (message: user, messageOrder: 1),
      ],
      toolEventsByMessageId: const {},
      geminiSignaturesByMessageId: const {},
    );

    final summary = (await repository.getAllConversationSummaries()).single;
    final metadata = summary.listMetadata;

    expect(summary.messageIds, isEmpty);
    expect(summary.assistantId, 'assistant');
    expect(summary.chatModelId, 'override-model');
    expect(summary.mcpServerIds, ['second', 'first']);
    expect(metadata, isNotNull);
    expect(metadata!.lastMessageId, user.id);
    expect(metadata.lastMessageAt.toUtc(), userAt);
    expect(metadata.lastMessagePreview, 'First line');
    expect(metadata.lastMessageModelId, isNull);
    expect(metadata.lastAssistantMessageId, answer.id);
    expect(metadata.lastAssistantModelId, 'answer-model');
    expect(metadata.lastAssistantProviderId, 'answer-provider');

    // List metadata is derived only; backups and restored full bodies stay intact.
    expect(summary.toJson(), isNot(contains('listMetadata')));
    expect((await repository.getMessage(user.id))!.content, user.content);
  });

  test('empty chats and attachment-only messages have no preview', () async {
    final empty = Conversation(id: 'empty', title: 'Empty');
    final image = Conversation(id: 'image-chat', title: 'Image');
    final message = ChatMessage(
      id: 'image-message',
      role: 'user',
      conversationId: image.id,
      parts: const [ImagePart(uri: 'https://example.com/photo.png')],
    );
    await repository.putMigrationBatch(
      conversations: [empty, image],
      messages: [(message: message, messageOrder: 0)],
      toolEventsByMessageId: const {},
      geminiSignaturesByMessageId: const {},
    );

    final summaries = {
      for (final summary in await repository.getAllConversationSummaries())
        summary.id: summary,
    };
    expect(summaries[empty.id]!.listMetadata, isNull);
    expect(summaries[image.id]!.listMetadata!.lastMessageId, message.id);
    expect(summaries[image.id]!.listMetadata!.lastMessagePreview, isEmpty);
    expect(summaries[image.id]!.listMetadata!.lastAssistantModelId, isNull);
  });

  test('preview retains at most 240 characters of plain text', () async {
    final conversation = Conversation(id: 'long', title: 'Long');
    final message = ChatMessage(
      id: 'long-message',
      conversationId: conversation.id,
      role: 'assistant',
      content: 'x' * 1000000,
    );
    await repository.putMigrationBatch(
      conversations: [conversation],
      messages: [(message: message, messageOrder: 0)],
      toolEventsByMessageId: const {},
      geminiSignaturesByMessageId: const {},
    );

    final summary = (await repository.getAllConversationSummaries()).single;
    expect(summary.listMetadata!.lastMessagePreview, 'x' * 240);
  });
}
