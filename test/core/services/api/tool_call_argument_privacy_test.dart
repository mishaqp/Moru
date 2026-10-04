import 'dart:convert';

import 'package:Kelivo/core/services/api/chat_api_service.dart';
import 'package:Kelivo/core/services/api/generation/spend_round_control.dart';
import 'package:Kelivo/core/services/api/tool_call_argument_privacy.dart';
import 'package:Kelivo/core/services/api/stream/stream_chunk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('spending stop retains its type after privacy redaction', () async {
    final protected = ToolCallArgumentPrivacy.register(
      (name, args, {toolCallId}) async => 'ok',
      (name, args) =>
          (jsonDecode(
                    jsonEncode(args).replaceAll('private-value', '[REDACTED]'),
                  )
                  as Map)
              .cast<String, dynamic>(),
    );
    await expectLater(
      ToolCallArgumentPrivacy.publishStream(
        Stream.error(const SpendLimitExceeded('Stop private-value')),
        protected,
      ).toList(),
      throwsA(
        isA<SpendLimitExceeded>().having(
          (e) => e.message,
          'message',
          'Stop [REDACTED]',
        ),
      ),
    );
  });
  test(
    'name sanitization also supports credentials matching internal copy keys',
    () {
      final registered = ToolCallArgumentPrivacy.register(
        (name, args, {toolCallId}) async => 'ok',
        (name, args) => {'[REDACTED]': args.values.single},
      );
      expect(ToolCallArgumentPrivacy.nameForModel(registered, 'echo'), 'echo');
    },
  );

  ToolCallHandler handler() => ToolCallArgumentPrivacy.register(
    (name, args, {toolCallId}) async => 'ok',
    (name, args) =>
        (jsonDecode(jsonEncode(args).replaceAll('private-value', '[REDACTED]'))
                as Map)
            .cast<String, dynamic>(),
  );

  test(
    'split private tool name is withheld until it can be sanitized',
    () async {
      final chunks = await ToolCallArgumentPrivacy.publishStream(
        Stream.fromIterable([
          const ToolCallStart(id: 'call'),
          const ToolCallDelta(id: 'call', toolNameDelta: 'echo_private-'),
          const ToolCallDelta(
            id: 'call',
            toolNameDelta: 'value',
            inputDelta: '{"city":"Seattle"}',
          ),
          const ToolCallEnd('call'),
        ]),
        handler(),
      ).toList();
      final exposedNames = [
        for (final chunk in chunks)
          if (chunk is ToolCallStart)
            chunk.toolName
          else if (chunk is ToolCallDelta)
            chunk.toolNameDelta,
      ];
      expect(exposedNames.join(), 'mcp_private_tool');
      expect(exposedNames, everyElement(isNot(contains('private-'))));
      expect(
        chunks.whereType<ToolCallDelta>().map((c) => c.inputDelta).join(),
        '{"city":"Seattle"}',
      );
    },
  );

  test('retry diagnostics redact private values', () async {
    final chunks = await ToolCallArgumentPrivacy.publishStream(
      Stream.value(
        const RetryPending(
          attempt: 1,
          maxRetries: 2,
          delay: Duration.zero,
          errorText: 'HTTP error: private-value',
        ),
      ),
      handler(),
    ).toList();
    expect(
      chunks.whereType<RetryPending>().single.errorText,
      'HTTP error: [REDACTED]',
    );
  });

  test(
    'provider failures redact private values before callers persist errors',
    () async {
      await expectLater(
        ToolCallArgumentPrivacy.publishStream(
          Stream.error(StateError('private-value')),
          handler(),
        ).toList(),
        throwsA(
          predicate(
            (Object error) => !error.toString().contains('private-value'),
          ),
        ),
      );
    },
  );

  test('cancellation never publishes incomplete argument fragments', () async {
    final chunks = await ToolCallArgumentPrivacy.publishStream(
      Stream.fromIterable([
        const ToolCallStart(id: 'call', toolName: 'echo'),
        const ToolCallDelta(id: 'call', inputDelta: '{"token":"private-'),
      ]),
      handler(),
    ).toList();
    expect(chunks.whereType<ToolCallDelta>(), isEmpty);
  });
}
