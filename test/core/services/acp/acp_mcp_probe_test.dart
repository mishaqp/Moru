import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/services/acp/acp_mcp_probe.dart';

import '../../../support/fake_workspace_runtime.dart';

void main() {
  test(
    'Node in the chosen runtime reaches the authenticated app endpoint',
    () async {
      final runtime = FakeWorkspaceRuntime(useRealProcess: true);
      expect(
        await AcpMcpProbe.check(
          runtime,
          environment: {'PATH': Platform.environment['PATH']!},
        ),
        isTrue,
      );
      final request = runtime.requests.single;
      expect(request.cwd, '/root');
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
