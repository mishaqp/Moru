import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/models/message_part.dart';
import 'package:Kelivo/features/home/controllers/chat_actions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an agent reply previews its last text block as plain text', () {
    final message = ChatMessage(
      id: 'm',
      role: 'assistant',
      conversationId: 'c',
      parts: const [
        TextPart('Step 1: reading `main.dart`.'),
        ToolCallPart('{"id":"t1","name":"read_file"}'),
        TextPart('## Done\n\nThe **build** passes: [log](https://e.com).'),
        TextPart('  '),
      ],
    );

    expect(
      ChatActions.replyPreviewText(message),
      'Done The build passes: log.',
    );
  });

  test('a plain reply drops its thinking block', () {
    final message = ChatMessage(
      id: 'm',
      role: 'assistant',
      conversationId: 'c',
      content: '<think>planning</think>Answer here.',
    );

    expect(ChatActions.replyPreviewText(message), 'Answer here.');
  });
}
