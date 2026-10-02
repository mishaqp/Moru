import 'package:Kelivo/core/services/workspace/tool_run_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('allIn includes finished jobs only from the exact conversation', () {
    final registry = ToolRunRegistry();
    addTearDown(registry.dispose);
    final first = registry.start('first', 'shell', conversationId: 'a');
    final other = registry.start('other', 'shell', conversationId: 'b');
    final unscoped = registry.start('unscoped', 'shell');
    final newest = registry.start('newest', 'shell', conversationId: 'a');
    for (final run in [first, other, unscoped, newest]) {
      addTearDown(run.dispose);
    }
    first.complete(status: ToolRunStatus.succeeded, exitCode: 0);
    expect(registry.allIn('a'), [first, newest]);
    expect(registry.allIn('b'), [other]);
    expect(registry.allIn(null), [unscoped]);
    expect(registry.allIn('unknown'), isEmpty);
    expect(registry.runningIn('a'), [newest]);
  });
}
