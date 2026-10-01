import 'dart:io';

import 'package:Kelivo/core/database/app_database.dart';
import 'package:Kelivo/core/database/chat_database_repository.dart';
import 'package:Kelivo/core/database/generation_run.dart';
import 'package:Kelivo/core/models/chat_input_data.dart';
import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/models/conversation.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late AppDatabase database;
  late ChatDatabaseRepository repository;
  final conversation = Conversation(id: 'chat', title: 'Recovery');
  const first = QueuedChatInput(
    id: 'ad21c9fa-2c48-42a0-9807-c3a35fcae9fb',
    conversationId: 'chat',
    input: ChatInputData(
      text: 'next',
      imagePaths: ['data:image/png;base64,aA=='],
      documents: [
        DocumentAttachment(
          path: '/private/report.txt',
          fileName: 'report.txt',
          mime: 'text/plain',
        ),
      ],
      allowImagesApiRouting: false,
    ),
  );
  const second = QueuedChatInput(
    id: 'a46b3a66-2525-4c24-b6e6-fda1b2ccfa89',
    conversationId: 'chat',
    input: ChatInputData(text: 'after'),
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
    directory = await Directory.systemTemp.createTemp('moru_queue_recovery_');
    await open();
    await repository.putConversation(conversation);
  });
  tearDown(() async {
    await repository.close();
    await directory.delete(recursive: true);
  });

  Future<GenerationBeginResult> begin({
    String run = 'run',
    String? queuedId = 'ad21c9fa-2c48-42a0-9807-c3a35fcae9fb',
  }) => repository.beginSendGeneration(
    conversation: conversation,
    userMessage: ChatMessage(
      id: 'user-$run',
      conversationId: 'chat',
      role: 'user',
      content: first.input.text,
    ),
    assistantMessage: ChatMessage(
      id: 'assistant-$run',
      conversationId: 'chat',
      role: 'assistant',
      content: '',
      isStreaming: true,
    ),
    runId: run,
    queuedInputId: queuedId,
  );

  test(
    'a pending edit survives a closed database with its original slot and attachments',
    () async {
      await repository.putQueuedInput(first);
      await repository.putQueuedInput(second);
      await repository.setQueuedInputEditing('chat', first.id, true);
      await repository.close();
      await open();
      final items = await repository.queuedInputsForConversation('chat');
      expect(items.map((item) => item.id), [first.id, second.id]);
      expect(items.first.isEditing, isTrue);
      expect(items.first.input.text, 'next');
      expect(items.first.input.imagePaths, first.input.imagePaths);
      expect(items.first.input.documents.single.fileName, 'report.txt');
      expect(items.first.input.allowImagesApiRouting, isFalse);
    },
  );

  test(
    'failed begin retains the queued input and rolls back every new send row',
    () async {
      await repository.putQueuedInput(first);
      await begin();
      await repository.putQueuedInput(second);
      await expectLater(begin(queuedId: second.id), throwsA(anything));
      expect(
        (await repository.queuedInputsForConversation('chat')).single.id,
        second.id,
      );
      expect(await repository.getMessageCount('chat'), 2);
    },
  );

  test(
    'failure after pair insertion rolls back queue consumption and survives reopening',
    () async {
      await repository.putQueuedInput(first);
      await database.customStatement(
        "CREATE TRIGGER reject_generation_run BEFORE INSERT ON generation_run_rows BEGIN SELECT RAISE(ABORT, 'run insert failed'); END",
      );
      await expectLater(begin(), throwsA(anything));
      await repository.close();
      await open();
      expect(
        (await repository.queuedInputsForConversation('chat')).single.id,
        first.id,
      );
      expect(await repository.getMessageCount('chat'), 0);
      expect(await repository.getGenerationRun('run'), isNull);
      await database.customStatement('DROP TRIGGER reject_generation_run');
      await begin();
      await repository.close();
      await open();
      expect(await repository.queuedInputsForConversation('chat'), isEmpty);
      expect(await repository.getMessageCount('chat'), 2);
    },
  );

  test(
    'death after begin preserves an interrupted run and consumes the input exactly once',
    () async {
      await repository.putQueuedInput(first);
      await repository.putQueuedInput(second);
      await begin();
      await repository.close();
      await open();
      expect(await repository.resetStaleStreamingState(), 1);
      expect(
        (await repository.getGenerationRun('run'))!.state,
        GenerationRunState.interrupted,
      );
      expect(
        await repository.getInterruptedRevisionIds(),
        contains('assistant-run'),
      );
      expect(
        (await repository.queuedInputsForConversation(
          'chat',
        )).map((item) => item.id),
        [second.id],
      );
      await expectLater(
        begin(run: 'duplicate', queuedId: first.id),
        throwsStateError,
      );
      expect(await repository.getMessage('user-duplicate'), isNull);
    },
  );

  test(
    'interrupted queue remains held across starts until an explicit acknowledgement',
    () async {
      await repository.putQueuedInput(first);
      await begin();
      await repository.resetStaleStreamingState();
      expect(await repository.unacknowledgedInterruptedConversationIds(), [
        'chat',
      ]);
      await repository.acknowledgeInterruptedConversation('chat');
      await repository.close();
      await open();
      expect(
        await repository.unacknowledgedInterruptedConversationIds(),
        isEmpty,
      );
      expect(
        await repository.getInterruptedRevisionIds(),
        contains('assistant-run'),
      );
    },
  );

  test('conversation deletion removes its durable queued input', () async {
    await repository.putQueuedInput(first);
    await repository.deleteConversation('chat');
    expect(await repository.allQueuedInputs(), isEmpty);
  });

  test(
    'runtime Stop durably holds a cancelled FIFO without inventing interruption',
    () async {
      await repository.putQueuedInput(first);
      final started = await begin();
      await repository.putQueuedInput(second);
      await repository.holdQueuedInputsAfterRuntimeStop('chat');
      await repository.finalizeGenerationRun(
        message: started.assistantMessage.copyWith(isStreaming: false),
        toolEvents: const [],
        generationRunId: started.run.id,
        expectedState: started.run.state,
        expectedStateRevision: started.run.stateRevision,
        terminalState: GenerationRunState.cancelled,
      );
      await repository.close();
      await open();
      expect(await repository.resetStaleStreamingState(), 0);
      expect(await repository.unacknowledgedInterruptedConversationIds(), [
        'chat',
      ]);
      expect(await repository.getInterruptedRevisionIds(), isEmpty);
      expect(
        (await repository.getGenerationRun('run'))!.state,
        GenerationRunState.cancelled,
      );
      expect(
        (await repository.queuedInputsForConversation('chat')).single.id,
        second.id,
      );
      await repository.acknowledgeInterruptedConversation('chat');
      await repository.close();
      await open();
      expect(
        await repository.unacknowledgedInterruptedConversationIds(),
        isEmpty,
      );
      expect(
        (await repository.getGenerationRun('run'))!.state,
        GenerationRunState.cancelled,
      );
    },
  );

  test(
    'bulk replacement clears pending input without erasing the migration receipt',
    () async {
      await repository.markMigrationComplete();
      await repository.putQueuedInput(first);
      await repository.clearAllData();
      expect(await repository.allQueuedInputs(), isEmpty);
      expect(await repository.isMigrationComplete(), isTrue);
    },
  );

  for (final document in [false, true]) {
    test(
      'pending ${document ? 'document' : 'image'} prevents an existing asset GC claim after reopening',
      () async {
        const path = '/private/queued "attachment".png';
        final now = DateTime.utc(2026, 10, 1);
        await repository.registerAsset(
          id: 'queued-asset',
          contentHash: List.filled(64, 'a').join(),
          path: path,
          byteSize: 1,
          createdAt: now,
        );
        await repository.scheduleUnreferencedAssetGc(notBefore: now);
        final claim = (await repository.claimAssetGc(now: now)).single;
        expect(await repository.isAssetGcClaimStillValid(claim), isTrue);
        await repository.putQueuedInput(
          first.withInput(
            ChatInputData(
              text: 'with attachment',
              imagePaths: document ? const [] : const [path],
              documents: document
                  ? const [
                      DocumentAttachment(
                        path: path,
                        fileName: 'attachment.png',
                        mime: 'image/png',
                      ),
                    ]
                  : const [],
            ),
          ),
        );
        expect(await repository.isAssetGcClaimStillValid(claim), isFalse);
        expect(
          await repository.completeAssetGc(
            assetId: claim.assetId,
            expectedGeneration: claim.generation,
            path: claim.path,
          ),
          isFalse,
        );
        expect(await repository.claimAssetGc(now: now), isEmpty);
        await repository.close();
        await open();
        expect(await repository.isAssetGcClaimStillValid(claim), isFalse);
        await repository.removeQueuedInput('chat', first.id);
        final reclaim = (await repository.claimAssetGc(
          now: now.add(const Duration(hours: 7)),
        )).single;
        expect(
          await repository.completeAssetGc(
            assetId: reclaim.assetId,
            expectedGeneration: reclaim.generation,
            path: reclaim.path,
          ),
          isTrue,
        );
      },
    );
  }
}
