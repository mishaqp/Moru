import 'dart:convert';
import 'dart:io';

import 'package:Kelivo/core/database/chat_database_repository.dart';
import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/models/conversation.dart';
import 'package:Kelivo/core/models/message_part.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

// Explicit benchmark. SQL audit triggers count logical payload writes, not
// filesystem bytes or physical flash wear. Correctness has separate tests.
void main() {
  test('checkpoint write amplification', () async {
    final root = await Directory.systemTemp.createTemp('checkpoint-bench-');
    final file = File('${root.path}/chat.db');
    final repository = ChatDatabaseRepository.open(file: file);
    await repository.ensureReady();
    final message = ChatMessage(
      id: 'reply',
      role: 'assistant',
      conversationId: 'conversation',
      isStreaming: true,
      parts: [
        ReasoningPart(List.filled(65536, '思').join()),
        const TextPart(''),
      ],
    );
    await repository.putMigrationBatch(
      conversations: [
        Conversation(
          id: 'conversation',
          title: 'Bench',
          messageIds: const ['reply'],
        ),
      ],
      messages: [(message: message, messageOrder: 0)],
      toolEventsByMessageId: const {},
      geminiSignaturesByMessageId: const {},
    );
    final raw = sqlite.sqlite3.open(file.path);
    try {
      raw.execute(
        'CREATE TABLE part_write_audit(operation TEXT, bytes INTEGER)',
      );
      for (final operation in ['INSERT', 'UPDATE', 'DELETE']) {
        final value = operation == 'DELETE' ? 'old' : 'new';
        raw.execute('''CREATE TRIGGER audit_${operation.toLowerCase()}
          AFTER $operation ON message_part_rows BEGIN
          INSERT INTO part_write_audit VALUES('$operation', length(CAST($value.payload AS BLOB)));
          END''');
      }
      final watch = Stopwatch()..start();
      for (var i = 1; i <= 48; i++) {
        await repository.updateStreamingCheckpoint(
          message.copyWith(
            parts: [
              message.parts.first,
              TextPart(List.filled(i * 512, '文').join()),
            ],
          ),
          const [],
        );
      }
      watch.stop();
      final writes = raw.select(
        'SELECT operation, count(*) AS count, sum(bytes) AS bytes FROM part_write_audit GROUP BY operation',
      );
      // ignore: avoid_print
      print(
        'CHECKPOINT_BENCH ${jsonEncode({'elapsedUs': watch.elapsedMicroseconds, 'checkpoints': 48, 'writes': writes.map((r) => Map<String, Object?>.from(r)).toList()})}',
      );
    } finally {
      raw.close();
      await repository.close();
      await root.delete(recursive: true);
    }
  });

  test('checkpoint cost of a long agent reply', () async {
    final root = await Directory.systemTemp.createTemp('checkpoint-bench-');
    final file = File('${root.path}/chat.db');
    final repository = ChatDatabaseRepository.open(file: file);
    await repository.ensureReady();
    const tools = 80;
    final output = List.generate(
      150,
      (l) => 'line $l of output for a step with some text',
    ).join('\n');
    final parts = <MessagePart>[
      for (var i = 0; i < tools; i++) ...[
        TextPart('Step $i text. '),
        ToolCallPart(
          jsonEncode({
            'id': 'call_$i',
            'name': 'read_file',
            'arguments': {'path': 'lib/a$i.dart'},
          }),
        ),
      ],
    ];
    final events = [
      for (var i = 0; i < tools; i++)
        {
          'id': 'call_$i',
          'name': 'read_file',
          'arguments': {'path': 'lib/a$i.dart'},
          'content': output,
          'metadata': {'stdoutPreview': output.substring(0, 4000)},
        },
    ];
    final message = ChatMessage(
      id: 'reply',
      role: 'assistant',
      conversationId: 'conversation',
      isStreaming: true,
      parts: parts,
    );
    await repository.putMigrationBatch(
      conversations: [
        Conversation(
          id: 'conversation',
          title: 'Bench',
          messageIds: const ['reply'],
        ),
      ],
      messages: [(message: message, messageOrder: 0)],
      toolEventsByMessageId: const {},
      geminiSignaturesByMessageId: const {},
    );
    try {
      final samples = <int>[];
      for (var i = 1; i <= 40; i++) {
        final watch = Stopwatch()..start();
        await repository.updateStreamingCheckpoint(
          message.copyWith(
            parts: [...parts, TextPart(List.filled(i * 64, 'a').join())],
          ),
          // Each checkpoint receives shallow copies, as ChatActions sends.
          [for (final e in events) Map<String, dynamic>.from(e)],
        );
        watch.stop();
        if (i > 5) samples.add(watch.elapsedMicroseconds);
      }
      samples.sort();
      // ignore: avoid_print
      print(
        'AGENT_CHECKPOINT tools=$tools medianUs=${samples[samples.length ~/ 2]} '
        'p95Us=${samples[(samples.length * .95).floor()]}',
      );
    } finally {
      await repository.close();
      await root.delete(recursive: true);
    }
  });
}
