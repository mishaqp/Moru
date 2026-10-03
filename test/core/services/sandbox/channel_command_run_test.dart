import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/services/sandbox/channel_command_run.dart';
import 'package:Kelivo/core/services/sandbox/workspace_channel.dart';
import 'package:Kelivo/core/services/workspace/workspace_runtime.dart';
import 'sandbox_channel_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SandboxChannelHarness harness;
  setUp(() {
    harness = SandboxChannelHarness()..install();
  });
  tearDown(() => harness.dispose());
  const args = ExecArgs(runId: 'cancel-me', command: 'true', cwd: '/');

  test('cancelled Android command never issues exec', () async {
    final result = runChannelCommand(
      channel: harness.channel,
      request: CommandRequest(
        runId: args.runId,
        command: args.command,
        cwd: args.cwd,
        isCancelled: () => true,
      ),
      args: args,
    );
    await expectLater(result, emitsError(isA<StateError>()));
    expect(harness.methods, isNot(contains('exec')));
  });

  test('cancel is repeated after delayed native registration', () async {
    final entered = Completer<void>();
    final registered = Completer<void>();
    var cancelled = false;
    harness.handler = (call) {
      if (call.method == 'exec') {
        entered.complete();
        return registered.future;
      }
      if (call.method == 'cancel') {
        harness.emit({
          'type': 'exit',
          'runId': args.runId,
          'exitCode': -1,
          'cancelled': true,
        });
        return true;
      }
      return null;
    };
    final result = runChannelCommand(
      channel: harness.channel,
      request: CommandRequest(
        runId: args.runId,
        command: args.command,
        cwd: '/',
        isCancelled: () => cancelled,
      ),
      args: args,
    ).toList();
    await entered.future;
    cancelled = true;
    registered.complete();
    final events = await result.timeout(const Duration(seconds: 3));
    expect(harness.methods, contains('cancel'));
    expect(events.whereType<CommandExited>().single.cancelled, isTrue);
  });
}
