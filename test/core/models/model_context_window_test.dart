import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/models/model_context_window.dart';

ChatMessage _message(String role, {int? prompt, int? completion, int? total}) =>
    ChatMessage(
      role: role,
      content: '',
      conversationId: 'c1',
      promptTokens: prompt,
      completionTokens: completion,
      totalTokens: total,
    );

void main() {
  test('known families get their context window, others stay unknown', () {
    expect(inferContextWindowTokens('claude-sonnet-4-5'), 200000);
    expect(inferContextWindowTokens('anthropic/claude-opus-4'), 200000);
    expect(inferContextWindowTokens('gemini-2.5-pro'), 1048576);
    expect(inferContextWindowTokens('gpt-4.1-mini'), 1047576);
    expect(inferContextWindowTokens('gpt-5'), 400000);
    expect(inferContextWindowTokens('gpt-4o-mini'), 128000);
    expect(inferContextWindowTokens('o3'), 200000);
    expect(inferContextWindowTokens('o4-mini'), 200000);
    expect(inferContextWindowTokens('deepseek-chat'), 128000);
    expect(inferContextWindowTokens('grok-4'), 256000);
    expect(inferContextWindowTokens('qwen3-32b'), isNull);
    expect(inferContextWindowTokens('gemini-pro'), isNull);
    expect(inferContextWindowTokens('omni-large'), isNull);
  });

  test('context tokens come from the latest reply with usage', () {
    expect(latestContextTokens(const []), isNull);
    expect(latestContextTokens([_message('user')]), isNull);
    expect(
      latestContextTokens([
        _message('assistant', prompt: 1000, completion: 200),
        _message('user'),
        _message('assistant', prompt: 5000, completion: 300),
        _message('user'),
      ]),
      5300,
    );
    // A reply still streaming without usage falls back to the one before.
    expect(
      latestContextTokens([
        _message('assistant', total: 900),
        _message('user'),
        _message('assistant'),
      ]),
      900,
    );
  });
}
