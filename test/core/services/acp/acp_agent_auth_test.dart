import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/services/acp/acp_agent_auth.dart';
import 'package:Kelivo/core/services/acp/acp_agent_catalog.dart';
import 'package:Kelivo/core/services/workspace/workspace_runtime.dart';

import '../../../support/fake_workspace_runtime.dart';

CommandExited _exit(int code) => CommandExited(
  exitCode: code,
  timedOut: false,
  cancelled: false,
  interrupted: false,
  duration: Duration.zero,
);

class _AuthRuntime extends FakeWorkspaceRuntime
    implements WorkspaceStdioRuntime {
  bool signedIn = false;
  bool apiKey = false;
  bool statusFailure = false;
  bool logoutFailure = false;
  bool statusWarning = false;
  bool holdShortCommands = false;
  final shortCommands = <String, StreamController<CommandEvent>>{};
  final logins = <String, StreamController<CommandEvent>>{};
  final writes = <String>[];
  final cancelled = <String>[];

  @override
  Stream<CommandEvent> run(CommandRequest request) {
    requests.add(request);
    if (request.keepStdinOpen) {
      final events = StreamController<CommandEvent>();
      logins[request.runId] = events;
      events.add(const CommandStarted());
      return events.stream;
    }
    if (holdShortCommands) {
      final events = StreamController<CommandEvent>();
      shortCommands[request.runId] = events;
      events.add(const CommandStarted());
      return events.stream;
    }
    final claude = request.command.contains("'claude'");
    final logout = request.command.contains("'logout'");
    final code = logout
        ? (logoutFailure ? 1 : 0)
        : statusFailure || !signedIn
        ? 1
        : 0;
    if (logout && code == 0) signedIn = false;
    final output = logout
        ? 'Logged out\n'
        : statusFailure
        ? 'Error loading auth file\n'
        : claude
        ? jsonEncode({
            'loggedIn': signedIn,
            'authMethod': signedIn
                ? (apiKey ? 'api_key' : 'claude.ai')
                : 'none',
            'apiProvider': 'firstParty',
            'email': 'private-account@example.test',
          })
        : signedIn
        ? apiKey
              ? 'Logged in using an API key - private-key\n'
              : 'WARNING: could not update PATH\nLogged in using ChatGPT\n'
        : 'Not logged in\n';
    return Stream.fromIterable([
      const CommandStarted(),
      if (claude && statusWarning)
        CommandOutput(
          OutputStreamKind.stderr,
          Uint8List.fromList(
            utf8.encode('WARNING: native PATH update failed\n'),
          ),
        ),
      CommandOutput(
        claude ? OutputStreamKind.stdout : OutputStreamKind.stderr,
        Uint8List.fromList(utf8.encode(output)),
      ),
      _exit(code),
    ]);
  }

  void output(String text) {
    logins.values.single.add(
      CommandOutput(
        OutputStreamKind.stdout,
        Uint8List.fromList(utf8.encode(text)),
      ),
    );
  }

  Future<void> finishLogin() async {
    signedIn = true;
    final events = logins.values.single;
    events.add(_exit(0));
    await events.close();
    logins.clear();
  }

  @override
  Future<void> writeStdin(String runId, Uint8List data) async {
    writes.add(utf8.decode(data));
  }

  @override
  Future<void> cancel(String runId) async {
    cancelled.add(runId);
    final events = logins.remove(runId) ?? shortCommands.remove(runId);
    if (events != null) {
      events.add(_exit(143));
      await events.close();
    }
  }
}

void main() {
  late _AuthRuntime runtime;
  late AcpAgentAuth auth;
  late List<String> stopped;
  late int cleaned;
  final claude = AcpAgentSpec.byId(AcpAgentSpec.claudeCodeId)!;
  final codex = AcpAgentSpec.byId(AcpAgentSpec.codexId)!;

  setUp(() {
    runtime = _AuthRuntime();
    stopped = [];
    cleaned = 0;
    auth = AcpAgentAuth(
      prepare: (spec) async => AcpAuthContext(
        runtime: runtime,
        launch: AcpLaunch(
          command: spec.command,
          environment: const {'HOME': '/root'},
          cleanup: () async {
            cleaned++;
          },
        ),
      ),
      stopAgents: (id) async {
        stopped.add(id);
      },
    );
    addTearDown(auth.dispose);
  });

  test('status distinguishes subscription credentials from API keys', () async {
    for (final spec in [claude, codex]) {
      expect(await auth.check(spec), AcpAuthStatus.signedOut);
      runtime.signedIn = true;
      expect(await auth.check(spec), AcpAuthStatus.signedIn);
      runtime.apiKey = true;
      expect(await auth.check(spec), AcpAuthStatus.signedOut);
      runtime.signedIn = runtime.apiKey = false;
    }
    expect(cleaned, 6);
  });

  test('failed status is unknown and never reported as signed out', () async {
    runtime.statusFailure = true;
    expect(await auth.check(claude), AcpAuthStatus.unknown);
    expect(auth.failure(claude.id), AcpAuthFailure.start);
  });

  test('Claude status JSON remains valid with stderr warnings', () async {
    runtime
      ..signedIn = true
      ..statusWarning = true;
    expect(await auth.check(claude), AcpAuthStatus.signedIn);
  });

  for (final logout in [false, true]) {
    test(
      'dispose cancels a running ${logout ? 'logout' : 'status'} command',
      () async {
        runtime.holdShortCommands = true;
        final operation = logout ? auth.signOut(codex) : auth.check(codex);
        await pumpEventQueue();
        expect(runtime.shortCommands, hasLength(1));
        auth.dispose();
        await pumpEventQueue();
        expect(runtime.cancelled, hasLength(1));
        expect(runtime.shortCommands, isEmpty);
        await operation;
        expect(cleaned, 1);
      },
    );
  }

  test(
    'uninstall cancellation during logout preparation prevents launch',
    () async {
      final prepared = Completer<AcpAuthContext>();
      final delayed = AcpAgentAuth(
        prepare: (_) => prepared.future,
        stopAgents: (_) async {},
      );
      final logout = delayed.signOut(codex);
      await pumpEventQueue();
      final cancellation = delayed.cancelOperations(codex.id);
      prepared.complete(
        AcpAuthContext(
          runtime: runtime,
          launch: AcpLaunch(
            command: 'codex-acp',
            cleanup: () async {
              cleaned++;
            },
          ),
        ),
      );
      await cancellation;
      await logout;
      expect(runtime.requests, isEmpty);
      expect(cleaned, 1);
      delayed.dispose();
    },
  );

  test(
    'device challenge is private, handles ANSI and fragmented output',
    () async {
      final started = Completer<void>();
      auth.addListener(() {
        if (runtime.logins.isNotEmpty && !started.isCompleted) {
          started.complete();
        }
      });
      final login = auth.signIn(codex);
      await started.future;
      runtime.output('1. Open this URL in your browser\n\x1b[3');
      runtime.output('4mhttps://auth.openai.com/codex/device\x1b[0m\n\n');
      runtime.output(
        '2. Enter this one-time code (expires in 15 minutes)\n\nABCD',
      );
      runtime.output('-EFGH\n');
      await pumpEventQueue();
      final attempt = auth.loginFor(codex.id)!;
      expect(attempt.url.toString(), 'https://auth.openai.com/codex/device');
      expect(attempt.deviceCode, 'ABCD-EFGH');
      expect(attempt.awaitingUser, isTrue);
      expect(stopped, [codex.id]);
      await runtime.finishLogin();
      await login;
      expect(auth.status(codex.id), AcpAuthStatus.signedIn);
      expect(auth.loginFor(codex.id), isNull);
      expect(attempt.url, isNull);
      expect(attempt.deviceCode, isNull);
    },
  );

  test('only trusted complete authorization URLs reach the login UI', () async {
    final login = auth.signIn(claude);
    await pumpEventQueue();
    runtime.output('https://evil.test/oauth/authorize?state=private\n');
    runtime.output('https://claude.ai/oauth/authorize?state=private');
    await pumpEventQueue();
    expect(auth.loginFor(claude.id)!.url, isNull);
    runtime.output('&code_challenge=private\n');
    await pumpEventQueue();
    expect(auth.loginFor(claude.id)!.url!.host, 'claude.ai');
    await auth.submitCode(claude.id, 'user-only-code');
    expect(runtime.writes, ['user-only-code\n']);
    final attempt = auth.loginFor(claude.id)!;
    await auth.cancel(claude.id);
    await login;
    expect(attempt.url, isNull);
    expect(auth.loginFor(claude.id), isNull);
    expect(runtime.cancelled, hasLength(1));
  });

  test(
    'logout stops processes and removes sign-in state only on success',
    () async {
      runtime.signedIn = true;
      await auth.check(codex);
      runtime.logoutFailure = true;
      await auth.signOut(codex);
      expect(auth.status(codex.id), AcpAuthStatus.signedIn);
      expect(auth.failure(codex.id), AcpAuthFailure.start);
      runtime.logoutFailure = false;
      await auth.signOut(codex);
      expect(auth.status(codex.id), AcpAuthStatus.signedOut);
      expect(stopped, [codex.id, codex.id]);
    },
  );

  test('cancellation during preparation prevents late native launch', () async {
    final prepared = Completer<AcpAuthContext>();
    final delayed = AcpAgentAuth(
      prepare: (_) => prepared.future,
      stopAgents: (_) async {},
    );
    final signingIn = delayed.signIn(codex);
    await pumpEventQueue();
    final cancellation = delayed.cancel(codex.id);
    prepared.complete(
      AcpAuthContext(
        runtime: runtime,
        launch: AcpLaunch(
          command: 'codex-acp',
          cleanup: () async {
            cleaned++;
          },
        ),
      ),
    );
    await cancellation;
    await signingIn;
    expect(runtime.requests, isEmpty);
    expect(cleaned, 1);
    delayed.dispose();
  });

  test('sign out waits for a login to stop before removing tokens', () async {
    final login = auth.signIn(codex);
    await pumpEventQueue();
    await auth.signOut(codex);
    await login;
    expect(runtime.cancelled, hasLength(1));
    expect(auth.status(codex.id), AcpAuthStatus.signedOut);
  });
}
