import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/services/chat/chat_service.dart';
import 'package:Kelivo/features/home/services/message_builder_service.dart';

class _FakeBuildContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeChatService extends ChatService {}

void main() {
  MessageBuilderService service() => MessageBuilderService(
    chatService: _FakeChatService(),
    contextProvider: _FakeBuildContext(),
  );

  test('creates a system message when none exists yet', () {
    final apiMessages = <Map<String, dynamic>>[
      {'role': 'user', 'content': 'hi'},
    ];

    service().injectAppContextPrompt(apiMessages);

    expect(apiMessages.first['role'], 'system');
    expect(apiMessages.first['content'], contains('Moru'));
    expect(apiMessages.length, 2);
  });

  test('appends to an existing system message with a blank line', () {
    final apiMessages = <Map<String, dynamic>>[
      {'role': 'system', 'content': 'base prompt'},
      {'role': 'user', 'content': 'hi'},
    ];

    service().injectAppContextPrompt(apiMessages);

    final content = apiMessages.first['content'] as String;
    expect(content, startsWith('base prompt\n\n'));
    expect(content, contains('Moru'));
    expect(apiMessages.length, 2);
  });

  test('unconditional: runs with no assistant or settings involved', () {
    final apiMessages = <Map<String, dynamic>>[];

    service().injectAppContextPrompt(apiMessages);

    expect(apiMessages, hasLength(1));
    expect(apiMessages.single['role'], 'system');
  });
}
