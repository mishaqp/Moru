import 'package:Kelivo/core/services/api/stream/sse_event.dart';
import 'package:Kelivo/core/services/api/stream/stream_chunk.dart';
import 'package:Kelivo/core/services/api/stream/stream_chunk_decoder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';

void main() {
  test('decoder diagnostic omits malformed response source and event name', () {
    final messages = <String>[];
    final previous = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) messages.add(message);
    };
    try {
      logDecoderParseError(
        provider: 'OpenAI',
        eventType: 'configured-private-value',
        error: const FormatException(
          'bad json',
          '{"query":"configured-private-value"}',
        ),
      );
      expect(messages.single, isNot(contains('configured-private-value')));
      expect(messages.single, contains('FormatException'));
    } finally {
      debugPrint = previous;
    }
  });

  test('DecodeResult defaults to no chunks and not completed', () {
    const result = DecodeResult();
    expect(result.chunks, isEmpty);
    expect(result.completed, isFalse);
  });

  test('onClosed and an explicit Finish are mutually idempotent', () {
    final decoder = _TerminalDecoder();

    final accepted = decoder.accept(const SseEvent(data: '[DONE]'));
    expect(accepted.completed, isTrue);
    expect(accepted.chunks.whereType<Finish>(), hasLength(1));
    expect(decoder.onClosed(), isEmpty);

    final closedOnly = _TerminalDecoder();
    final flushed = closedOnly.onClosed();
    expect(flushed.whereType<Finish>(), hasLength(1));
    expect(closedOnly.onClosed(), isEmpty);
  });
}

class _TerminalDecoder implements StreamChunkDecoder {
  bool _finished = false;

  @override
  DecodeResult accept(SseEvent event) {
    if (event.data == '[DONE]') {
      return DecodeResult(chunks: _finishOnce(), completed: true);
    }
    return const DecodeResult();
  }

  @override
  List<StreamChunk> onClosed() => _finishOnce();

  List<StreamChunk> _finishOnce() {
    if (_finished) return const <StreamChunk>[];
    _finished = true;
    return const <StreamChunk>[Finish(finishReason: 'stop')];
  }
}
