import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/models/chat_input_data.dart';
import 'package:Kelivo/features/home/controllers/queued_input_queue.dart';

/// Ordering rules of the pending-message FIFO.
///
/// The queue is what decides which message goes out next once the running
/// reply finishes, so these cases pin down send order, the exclusivity of a
/// claim, and where an edited message goes back.
void main() {
  const a = 'conversation-a';
  const b = 'conversation-b';

  ChatInputData text(String value, {List<String> images = const []}) {
    return ChatInputData(text: value, imagePaths: List<String>.of(images));
  }

  List<String> textsOf(List<QueuedChatInput> items) => [
    for (final item in items) item.input.text,
  ];

  group('QueuedInputQueue', () {
    test('holds one pending message per conversation', () {
      final queue = QueuedInputQueue();
      expect(queue.isEmpty, isTrue);

      queue.enqueue(a, text('first'));

      expect(queue.length, 1);
      expect(queue.headFor(a)?.input.text, 'first');
      expect(queue.headFor(b), isNull);
      expect(textsOf(queue.forConversation(a)), ['first']);
    });

    test('sends pending messages in insertion order', () {
      final queue = QueuedInputQueue();
      queue.enqueue(a, text('one'));
      queue.enqueue(a, text('two'));
      queue.enqueue(a, text('three'));

      expect(textsOf(queue.forConversation(a)), ['one', 'two', 'three']);
      expect(queue.claimHeadFor(a)?.input.text, 'one');
      expect(queue.claimHeadFor(a)?.input.text, 'two');
      expect(queue.claimHeadFor(a)?.input.text, 'three');
      expect(queue.claimHeadFor(a), isNull);
      expect(queue.isEmpty, isTrue);
    });

    test('a claimed message can never be sent twice', () {
      final queue = QueuedInputQueue();
      queue.enqueue(a, text('only'));

      expect(queue.claimHeadFor(a)?.input.text, 'only');
      expect(queue.claimHeadFor(a), isNull);
      expect(queue.isEmpty, isTrue);
    });

    test('each conversation keeps its own order', () {
      final queue = QueuedInputQueue();
      queue.enqueue(a, text('a1'));
      queue.enqueue(b, text('b1'));
      queue.enqueue(a, text('a2'));
      queue.enqueue(b, text('b2'));

      expect(queue.claimHeadFor(b)?.input.text, 'b1');
      expect(queue.claimHeadFor(a)?.input.text, 'a1');
      expect(textsOf(queue.forConversation(a)), ['a2']);
      expect(textsOf(queue.forConversation(b)), ['b2']);
    });

    test('an edited message returns to its own slot', () {
      final queue = QueuedInputQueue();
      queue.enqueue(a, text('one'));
      final middle = queue.enqueue(a, text('two'));
      queue.enqueue(a, text('three'));

      expect(queue.indexOf(middle.id), 1);
      expect(queue.remove(middle.id)?.input.text, 'two');
      expect(queue.indexOf(middle.id), -1);

      expect(
        queue.reinsert(
          id: middle.id,
          conversationId: a,
          index: 1,
          input: text('two edited'),
        ),
        isTrue,
      );
      expect(textsOf(queue.forConversation(a)), ['one', 'two edited', 'three']);
    });

    test('reinserting an already parked message is refused', () {
      final queue = QueuedInputQueue();
      final item = queue.enqueue(a, text('one'));

      expect(
        queue.reinsert(
          id: item.id,
          conversationId: a,
          index: 0,
          input: text('duplicate'),
        ),
        isFalse,
      );
      expect(queue.length, 1);
      expect(textsOf(queue.forConversation(a)), ['one']);
    });

    test('a stale reinsert index is clamped, never dropped', () {
      final queue = QueuedInputQueue();
      queue.enqueue(a, text('one'));
      final two = queue.enqueue(a, text('two'));
      queue.claimHeadFor(a); // 'one' was sent while the edit was open
      queue.remove(two.id);

      queue.reinsert(
        id: two.id,
        conversationId: a,
        index: 0,
        input: text('two edited'),
      );
      expect(textsOf(queue.forConversation(a)), ['two edited']);

      queue.reinsert(
        id: 'queued-late',
        conversationId: a,
        index: 99,
        input: text('late'),
      );
      expect(textsOf(queue.forConversation(a)), ['two edited', 'late']);
    });

    test('the input of a parked message can be replaced in place', () {
      final queue = QueuedInputQueue();
      final item = queue.enqueue(a, text('draft'));

      expect(
        queue.replaceInput(item.id, text('draft edited'))?.input.text,
        'draft edited',
      );
      expect(queue.length, 1);
      expect(queue.replaceInput('queued-missing', text('x')), isNull);
    });

    test('parked input is copied, so later draft edits cannot reach it', () {
      final queue = QueuedInputQueue();
      final mutable = text('original', images: ['/tmp/a.png']);
      final parked = queue.enqueue(a, mutable);

      mutable.imagePaths.add('/tmp/b.png');

      expect(parked.input.imagePaths, ['/tmp/a.png']);
      expect(queue.replaceInput(parked.id, mutable)?.input.imagePaths, [
        '/tmp/a.png',
        '/tmp/b.png',
      ]);
    });

    test('drops pending messages of deleted conversations', () {
      final queue = QueuedInputQueue();
      queue.enqueue(a, text('a1'));
      queue.enqueue(b, text('b1'));

      expect(queue.prune((id) => id == a), isTrue);
      expect(textsOf(queue.items), ['a1']);
      expect(queue.prune((id) => true), isFalse);
    });

    test('clears one conversation without touching the others', () {
      final queue = QueuedInputQueue();
      queue.enqueue(a, text('a1'));
      queue.enqueue(a, text('a2'));
      queue.enqueue(b, text('b1'));

      expect(queue.removeConversation(a), 2);
      expect(textsOf(queue.items), ['b1']);
      expect(queue.removeConversation(a), 0);
    });

    test('clear empties every conversation', () {
      final queue = QueuedInputQueue();
      queue.enqueue(a, text('a1'));
      queue.enqueue(b, text('b1'));

      queue.clear();

      expect(queue.isEmpty, isTrue);
      expect(queue.length, 0);
      expect(queue.claimHeadFor(a), isNull);
    });

    test('every parked message gets a distinct id', () {
      final queue = QueuedInputQueue();
      final ids = {
        for (final value in ['1', '2', '3', '4'])
          queue.enqueue(a, text(value)).id,
      };
      expect(ids, hasLength(4));
    });
  });
}
