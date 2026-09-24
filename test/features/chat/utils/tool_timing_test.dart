import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/features/chat/utils/tool_timing.dart';

void main() {
  test('a result keeps the start mark and adds the finish mark', () {
    final start = DateTime.fromMillisecondsSinceEpoch(1000);
    final end = DateTime.fromMillisecondsSinceEpoch(21500);
    final call = withToolStart({'google': 'sig'}, start);
    final result = withToolFinish(
      {'tool': 'shell', 'exitCode': 0},
      started: call,
      now: end,
    );

    expect(call['google'], 'sig');
    expect(result['tool'], 'shell');
    expect(toolTimeOf(result, kToolStartedAtMsKey), start);
    expect(toolTimeOf(result, kToolFinishedAtMsKey), end);
  });

  test('a result without a recorded start has only its finish mark', () {
    final result = withToolFinish(
      null,
      started: null,
      now: DateTime.fromMillisecondsSinceEpoch(5),
    );
    expect(result.containsKey(kToolStartedAtMsKey), isFalse);
    expect(toolTimeOf(result, kToolStartedAtMsKey), isNull);
  });
}
