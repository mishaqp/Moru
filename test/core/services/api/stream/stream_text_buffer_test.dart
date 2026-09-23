import 'package:Kelivo/core/services/api/stream/stream_text_buffer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('many deltas preserve text across reads and replacement', () {
    final buffer = StreamTextBuffer();
    for (var i = 0; i < 1000; i++) {
      buffer.add('x');
    }
    expect(buffer.length, 1000);
    expect(buffer.value, 'x' * 1000);
    expect(buffer.value, 'x' * 1000);
    buffer.add('!');
    expect(buffer.value, '${'x' * 1000}!');
    buffer.value = 'new';
    expect(buffer.value, 'new');
    expect(buffer.length, 3);
  });
}
