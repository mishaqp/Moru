import 'dart:convert';
import 'dart:io';

import 'package:Kelivo/core/database/chat_database_repository.dart';
import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/models/conversation.dart';
import 'package:Kelivo/core/models/message_part.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late ChatDatabaseRepository repository;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('tool_decode_isolate_');
    repository = ChatDatabaseRepository.open(
      file: File('${root.path}/chat.db'),
    );
    await repository.ensureReady();
  });
  tearDown(() async {
    ChatDatabaseRepository.debugToolEventDecode = null;
    await repository.close();
    await root.delete(recursive: true);
  });

  Future<void> seed(Map<String, List<String>> payloads) async {
    await repository.putMigrationBatch(
      conversations: [Conversation(id: 'chat', title: 'Decode')],
      messages: [
        for (final (index, entry) in payloads.entries.indexed)
          (
            message: ChatMessage(
              id: entry.key,
              role: 'assistant',
              conversationId: 'chat',
              parts: [for (final payload in entry.value) ToolCallPart(payload)],
            ),
            messageOrder: index,
          ),
      ],
      toolEventsByMessageId: const {},
      geminiSignaturesByMessageId: const {},
    );
  }

  test(
    'large history decodes off the calling isolate with exact raw data',
    () async {
      final expected = <String, List<Map<String, dynamic>>>{
        for (final id in ['answer-a', 'answer-b'])
          id: [
            for (var ordinal = 0; ordinal < 24; ordinal++)
              {
                'id': '$id-$ordinal',
                'name': 'edit_file',
                'arguments': {
                  'path': '/workspace/$ordinal',
                  'token': 'raw-value',
                },
                'content': 'updated $ordinal',
                'metadata': {
                  'workspace': {'diff': '+ changed line\n' * 1600},
                  'nested': [
                    true,
                    null,
                    {'value': ordinal},
                  ],
                },
              },
          ],
      };
      await seed({
        for (final entry in expected.entries)
          entry.key: [for (final event in entry.value) jsonEncode(event)],
      });
      var decodedOnCaller = 0;
      ChatDatabaseRepository.debugToolEventDecode = (payloads, _) {
        decodedOnCaller += payloads;
      };
      final result = await repository.getToolEventsForMessages(expected.keys);
      expect(
        result,
        expected,
        reason: 'provider inputs retain order and every value',
      );
      expect(
        decodedOnCaller,
        0,
        reason: 'large history JSON must not block the UI isolate',
      );
    },
  );

  test('small results remain mutable and ignore non-map JSON roots', () async {
    await seed({
      'answer': ['[]', '{"id":"call","arguments":{"path":"raw"}}'],
    });
    final result = await repository.getToolEventsForMessages(['answer']);
    expect(result, {
      'answer': [
        {
          'id': 'call',
          'arguments': {'path': 'raw'},
        },
      ],
    });
    (result['answer']!.single['arguments'] as Map)['path'] = 'changed';
    expect((await repository.getToolEvents('answer')).single['arguments'], {
      'path': 'raw',
    });
    expect(await repository.getToolEventsForMessages([]), isEmpty);
  });

  test('malformed JSON still fails in a large decode batch', () async {
    await seed({
      'answer': [
        jsonEncode({'content': 'large result' * 20000}),
        '{broken',
      ],
    });
    await expectLater(
      repository.getToolEvents('answer'),
      throwsFormatException,
    );
  });
}
