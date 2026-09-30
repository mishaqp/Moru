import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/services/acp/acp_mcp_probe.dart';
import 'package:Kelivo/core/services/workspace/workspace_runtime.dart';

import '../../../support/fake_workspace_runtime.dart';

/// Guest /root belongs to the Android Linux environment, not to the CI host.
/// Execute the same command in an accessible host directory while retaining
/// the original guest request for assertions.
class _GuestRuntime extends FakeWorkspaceRuntime {
  _GuestRuntime(this.hostRoot) : super(useRealProcess: true);
  final String hostRoot;
  final guestRequests = <CommandRequest>[];
  @override
  Stream<CommandEvent> run(CommandRequest request) {
    guestRequests.add(request);
    return super.run(
      CommandRequest(
        runId: request.runId,
        command: request.command,
        cwd: hostRoot,
        timeout: request.timeout,
        env: request.env,
        mounts: request.mounts,
        isCancelled: request.isCancelled,
        keepStdinOpen: request.keepStdinOpen,
      ),
    );
  }
}

void main() {
  test(
    'Node in the chosen runtime reaches the authenticated app endpoint',
    () async {
      try {
        final node = await Process.run('node', ['--version']);
        expect(
          node.exitCode,
          0,
          reason:
              'Node.js must run from PATH for the real MCP probe test: ${node.stderr}',
        );
      } on ProcessException catch (error) {
        fail(
          'Node.js is required in PATH for the real MCP probe test: ${error.message}',
        );
      }
      final host = Directory.systemTemp.createTempSync('moru-mcp-probe-');
      addTearDown(() => host.deleteSync(recursive: true));
      final runtime = _GuestRuntime(host.path);
      expect(
        await AcpMcpProbe.check(
          runtime,
          environment: {'PATH': Platform.environment['PATH']!},
        ),
        isTrue,
      );
      final request = runtime.guestRequests.single;
      expect(request.cwd, '/root');
      expect(runtime.requests.single.cwd, host.path);
      expect(request.timeout, const Duration(seconds: 12));
      final token = request.env['MORU_MCP_TOKEN']!;
      expect(token, isNotEmpty);
      expect(request.command, isNot(contains(token)));
      final url = Uri.parse(request.env['MORU_MCP_URL']!);
      expect(url.host, '127.0.0.1');
      await expectLater(
        Socket.connect(url.host, url.port),
        throwsA(isA<SocketException>()),
      );
    },
  );

  test('exit without an authenticated response reports unavailable', () async {
    final runtime = FakeWorkspaceRuntime();
    expect(await AcpMcpProbe.check(runtime, environment: {}), isFalse);
    final url = Uri.parse(runtime.requests.single.env['MORU_MCP_URL']!);
    await expectLater(
      Socket.connect(url.host, url.port),
      throwsA(isA<SocketException>()),
    );
  });
}
