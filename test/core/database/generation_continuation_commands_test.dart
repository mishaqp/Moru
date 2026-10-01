import 'dart:io';

import 'package:Kelivo/core/database/app_database.dart';
import 'package:Kelivo/core/database/chat_database_repository.dart';
import 'package:Kelivo/core/database/generation_run.dart';
import 'package:Kelivo/core/models/chat_input_data.dart';
import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/models/conversation.dart';
import 'package:Kelivo/core/models/message_part.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late AppDatabase database;
  late ChatDatabaseRepository repository;
  late List<MessagePart> savedParts;
  final conversation = Conversation(id: 'chat', title: 'Recovered tool');
  final partial = ChatMessage(
    id: 'assistant',
    conversationId: 'chat',
    role: 'assistant',
    isStreaming: true,
    reasoningText: 'saved reasoning',
    parts: const [
      TextPart('saved partial'),
      ToolCallPart(
        '{"id":"ask","name":"ask_user","arguments":{},"content":"chosen answer"}',
      ),
    ],
  );

  Future<void> open() async {
    database = AppDatabase(
      NativeDatabase(
        File('${directory.path}/chat.sqlite'),
        setup: (db) => db.execute('PRAGMA foreign_keys = ON;'),
      ),
    );
    repository = ChatDatabaseRepository(database);
    await repository.ensureReady();
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('moru_continuation_');
    await open();
    await repository.beginSendGeneration(
      conversation: conversation,
      userMessage: ChatMessage(
        id: 'user',
        conversationId: 'chat',
        role: 'user',
        content: 'question',
      ),
      assistantMessage: partial,
      runId: 'old-run',
    );
    await repository.resetStaleStreamingState();
    savedParts = (await repository.getMessage('assistant'))!.parts;
    await repository.putQueuedInput(
      const QueuedChatInput(
        id: 'pending',
        conversationId: 'chat',
        input: ChatInputData(text: 'later'),
      ),
    );
  });
  tearDown(() async {
    await repository.close();
    await directory.delete(recursive: true);
  });

  Future<GenerationBeginResult> begin({String runId = 'continued-run'}) =>
      repository.beginContinuationGeneration(
        conversationId: 'chat',
        assistantMessageId: 'assistant',
        runId: runId,
        startedAt: DateTime.now().toUtc(),
        modelId: 'model',
        providerId: 'provider',
      );

  test(
    'explicit recovered continuation creates a new run without another message or lost tool history',
    () async {
      final result = await begin();
      expect(result.run.id, 'continued-run');
      expect(result.run.state, GenerationRunState.preparing);
      expect(result.assistantMessage.isStreaming, isTrue);
      expect(result.assistantMessage.content, 'saved partial');
      expect(result.assistantMessage.parts, savedParts);
      expect(result.assistantMessage.reasoningText, 'saved reasoning');
      expect(result.assistantMessage.modelId, 'model');
      expect(await repository.getMessageCount('chat'), 2);
      expect(
        (await repository.queuedInputsForConversation('chat')).single.id,
        'pending',
      );
      expect(
        (await repository.getGenerationRun('old-run'))!.state,
        GenerationRunState.interrupted,
      );
      expect(
        await repository.getInterruptedRevisionIds(),
        isNot(contains('assistant')),
      );
      await repository.close();
      await open();
      expect(await repository.resetStaleStreamingState(), 1);
      expect(
        (await repository.getGenerationRun('continued-run'))!.state,
        GenerationRunState.interrupted,
      );
      expect(
        await repository.getInterruptedRevisionIds(),
        contains('assistant'),
      );
      expect((await repository.getMessage('assistant'))!.parts, savedParts);
      expect(await repository.getMessageCount('chat'), 2);
    },
  );

  test(
    'continuation run failure rolls back the streaming flag and preserved revision',
    () async {
      await expectLater(begin(runId: 'old-run'), throwsA(anything));
      expect((await repository.getMessage('assistant'))!.isStreaming, isFalse);
      expect((await repository.getMessage('assistant'))!.parts, savedParts);
      expect(await repository.getMessageCount('chat'), 2);
      expect(
        (await repository.queuedInputsForConversation('chat')).single.id,
        'pending',
      );
    },
  );

  test(
    'an active continuation rejects a successor without stealing its target',
    () async {
      await begin();
      await expectLater(begin(runId: 'racing-run'), throwsStateError);
      expect(await repository.getGenerationRun('racing-run'), isNull);
      expect(
        (await repository.getGenerationRun('continued-run'))!.state,
        GenerationRunState.preparing,
      );
      expect((await repository.getMessage('assistant'))!.isStreaming, isTrue);
      expect(await repository.getMessageCount('chat'), 2);
    },
  );
}
