import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/models/assistant.dart';
import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/models/memory_entry.dart';
import 'package:Kelivo/core/services/memory/memory_block_builder.dart';
import 'package:Kelivo/core/services/memory/memory_extractor.dart';
import 'package:Kelivo/core/services/memory/memory_gatekeeper.dart';
import 'package:Kelivo/core/services/memory/memory_pipeline.dart';
import 'package:Kelivo/core/services/memory/memory_prompts.dart';
import 'package:Kelivo/core/services/memory/memory_tools.dart';

// Explicit benchmark: sizes of what memory adds, in characters (~4 per token
// for English, fewer for Russian).
void main() {
  test('memory token budget', () {
    const lang = MemoryPromptLang.en;
    final tools = MemoryTools.buildDefinitions(
      lang: lang,
      writeScope: MemoryWriteScope.alwaysGlobal,
      enableMemory: true,
      allowPastConversationRecall: true,
    );
    final now = DateTime(2026, 9, 1);
    final entries = [
      for (var i = 0; i < 40; i++)
        MemoryEntry(
          id: 'm$i',
          scope: MemoryScope.global,
          type: MemoryType.values[i % 4],
          content: 'The user prefers concise answers with examples number $i.',
          source: MemorySource.manual,
          status: MemoryStatus.active,
          createdAt: now,
          updatedAt: now,
        ),
    ];
    final block = MemoryBlockBuilder.buildMemoryBlock(
      visible: entries,
      totalByType: {for (final t in MemoryType.values) t: 10},
      lang: lang,
      maxItems: 10,
    );
    final prefix = MemoryBlockBuilder.buildFullSnapshotPrefix('', block, lang);
    final user = 'I work as a nurse in Kazan and I like short answers. ' * 3;
    final assistant = 'Here is a detailed explanation. ' * 80;
    final window = [
      for (var i = 0; i < 3; i++) ...[
        ChatMessage(role: 'user', content: user, conversationId: 'c'),
        ChatMessage(role: 'assistant', content: assistant, conversationId: 'c'),
      ],
    ];
    final conversation = MemoryPipelineService.buildConversationText(
      window,
      lang,
    );
    final gate = MemoryGatekeeper.buildPrompt(
      lang: lang,
      conversation: conversation,
    );
    final extract = MemoryExtractor.buildPrompt(
      lang: lang,
      conversation: conversation,
      existingMemory: block,
      writeScope: MemoryWriteScope.alwaysGlobal,
    );
    // ignore: avoid_print
    print(
      'MEMORY_BUDGET toolsChars=${jsonEncode(tools).length} '
      'rulesChars=${MemoryPrompts.rulesEn.length} '
      'snapshot40Chars=${prefix.length} '
      'conversationChars=${conversation.length} '
      'gateChars=${gate.length} extractChars=${extract.length}',
    );
  });
}
