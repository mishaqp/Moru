import 'dart:convert';

import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/models/message_part.dart';
import 'package:Kelivo/features/chat/utils/chat_ui_work.dart';
import 'package:Kelivo/features/chat/widgets/chat_message_widget.dart';
import 'package:Kelivo/features/chat/widgets/computer_response_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/long_chat_harness.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    installLongChatPlatformStubs();
  });
  tearDown(() => ChatUiWork.debugObserver = null);

  test('unchanged tool versions share prepared Computer steps', () {
    const part = ToolUIPart(
      id: 'call',
      toolName: 'shell',
      arguments: {'command': 'pwd'},
      content: 'one',
    );
    final first = computerStepsFromToolUi([part]).single;
    expect(computerStepsFromToolUi([part]).single, same(first));
    const changed = ToolUIPart(
      id: 'call',
      toolName: 'shell',
      arguments: {'command': 'pwd'},
      content: 'two',
    );
    final next = computerStepsFromToolUi([changed]).single;
    expect(next, isNot(same(first)));
    expect(next.content, 'two');
    const legacy = ToolUIPart(id: '', toolName: 'shell', arguments: {});
    expect(computerStepsFromToolUi([legacy]).single.id, 'shell-0');
    expect(computerStepsFromToolUi([part, legacy]).last.id, 'shell-1');
  });

  testWidgets('send and stream do not decode historical tool payloads', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2100);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final key = GlobalKey<LongChatHarnessState>();
    await tester.pumpWidget(
      LongChatHarness(key: key, fixture: LongChatFixture()),
    );
    final state = key.currentState!;
    state.goToEnd();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    var decodes = 0;
    final builds = <String>[];
    var projections = 0;
    ChatUiWork.debugObserver = (name, id, _) {
      if (name.endsWith('jsonDecode')) decodes++;
      if (name == 'message.build' && id != null) builds.add(id);
      if (name == 'history.project') projections++;
    };
    state.send();
    await tester.pump();
    state.goToEnd();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      decodes,
      0,
      reason: 'unchanged old parts must keep their decoded payloads',
    );
    expect(
      builds.where((id) => id.startsWith('assistant-')),
      isEmpty,
      reason: 'sending must retain the visible historical message subtrees',
    );

    decodes = 0;
    builds.clear();
    projections = 0;
    for (var chunk = 0; chunk < 3; chunk++) {
      state.streamChunk();
      await tester.pump();
    }
    expect(decodes, 0);
    expect(projections, 0);
    expect(builds, isNotEmpty);
    expect(builds.toSet(), {state.activeId});

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  test(
    'persisted Computer steps reuse unchanged parts and invalidate revisions',
    () {
      var decodes = 0;
      ChatUiWork.debugObserver = (name, _, _) {
        if (name.endsWith('jsonDecode')) decodes++;
      };
      String payload(String result) => jsonEncode({
        'id': 'call',
        'name': 'shell',
        'arguments': {'command': 'pwd'},
        'content': result,
      });
      final part = ToolCallPart(payload('one'));
      final message = ChatMessage(
        id: 'reply',
        version: 2,
        role: 'assistant',
        conversationId: 'chat',
        parts: [const TextPart('text'), part],
        isStreaming: true,
      );
      expect(computerStepsFromMessage(message).single.content, 'one');
      expect(
        computerStepsFromMessage(
          message.copyWith(content: 'more text'),
        ).single.content,
        'one',
      );
      expect(decodes, 1);
      final edited = message.copyWith(parts: [ToolCallPart(payload('two'))]);
      expect(computerStepsFromMessage(edited).single.content, 'two');
      expect(decodes, 2);
      final finished = edited.copyWith(isStreaming: false);
      expect(computerStepsFromMessage(finished).single.loading, isFalse);
      expect(decodes, 2);
    },
  );
}
