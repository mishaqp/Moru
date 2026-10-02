import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'package:Kelivo/core/models/agent_auth_mode.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/environment_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/acp/acp_agent_auth.dart';
import 'package:Kelivo/core/services/acp/acp_agent_catalog.dart';
import 'package:Kelivo/core/services/acp/acp_agent_manager.dart';
import 'package:Kelivo/core/services/workspace/workspace_runtime.dart';
import 'package:Kelivo/features/agents/pages/agent_detail_page.dart';
import 'package:Kelivo/features/agents/pages/agent_subscription_page.dart';
import 'package:Kelivo/features/agents/widgets/assistant_agent_card.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/widgets/ios_tile_button.dart';

import '../../support/business_test_harness.dart';
import '../../support/fake_workspace_runtime.dart';

class _ExternalLauncher extends UrlLauncherPlatform {
  final List<(String, PreferredLaunchMode)> launched = [];

  @override
  get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add((url, options.mode));
    return true;
  }
}

class _SubscriptionRuntime extends FakeWorkspaceRuntime
    implements WorkspaceStdioRuntime {
  bool signedIn = false;
  String? cancelledRun;
  final List<String> submittedCodes = [];
  int loginStarts = 0;
  void Function()? beforeLogin;
  StreamController<CommandEvent>? _login;
  String? _loginId;

  static const codexUrl = 'https://auth.openai.com/codex/device';
  static const claudeUrl =
      'https://claude.com/oauth/authorize?state=private-ui-state';

  static CommandOutput _output(String text) => CommandOutput(
    OutputStreamKind.stdout,
    Uint8List.fromList(utf8.encode(text)),
  );

  static CommandExited _exit({int code = 0, bool cancelled = false}) =>
      CommandExited(
        exitCode: code,
        timedOut: false,
        cancelled: cancelled,
        interrupted: false,
        duration: Duration.zero,
      );

  @override
  Stream<CommandEvent> run(CommandRequest request) {
    requests.add(request);
    final claude = request.command.contains("'claude'");
    if (request.command.contains("'status'")) {
      return Stream.fromIterable([
        const CommandStarted(),
        _output(
          claude
              ? jsonEncode({
                  'loggedIn': signedIn,
                  'authMethod': signedIn ? 'claude.ai' : 'none',
                })
              : signedIn
              ? 'Logged in using ChatGPT\n'
              : 'Not logged in\n',
        ),
        _exit(code: signedIn || claude ? 0 : 1),
      ]);
    }
    if (request.command.contains("'logout'")) {
      signedIn = false;
      return Stream.fromIterable([const CommandStarted(), _exit()]);
    }
    beforeLogin?.call();
    loginStarts++;
    _loginId = request.runId;
    _login = StreamController<CommandEvent>();
    _login!
      ..add(const CommandStarted())
      ..add(
        _output(
          claude
              ? 'private native diagnostics\n$claudeUrl\n'
              : 'private native diagnostics\n$codexUrl\n'
                    'Enter this one-time code:\nABCD-EFGH\n',
        ),
      );
    return _login!.stream;
  }

  @override
  Future<void> writeStdin(String runId, Uint8List data) async {
    expect(runId, _loginId);
    submittedCodes.add(utf8.decode(data));
    signedIn = true;
    _login!.add(_exit());
    await _login!.close();
    _login = null;
  }

  @override
  Future<void> cancel(String runId) async {
    cancelledRun = runId;
    if (_login == null) return;
    _login!.add(_exit(code: 130, cancelled: true));
    await _login!.close();
    _login = null;
  }
}

class _AuthUiManager extends AcpAgentManager {
  _AuthUiManager(this.uiAuth, _SubscriptionRuntime runtime)
    : super(
        preferences: createBusinessTestPreferences(),
        runtimeProvider: WorkspaceRuntimeProvider()..register(runtime),
        environment: EnvironmentProvider(
          preferences: createBusinessTestPreferences(),
        ),
      ) {
    uiAuth.addListener(notifyListeners);
  }

  final AcpAgentAuth uiAuth;

  @override
  AcpAgentAuth get auth => uiAuth;

  @override
  AcpInstallState state(String id) => AcpInstallState.installed;

  @override
  AcpNodeIssue? nodeIssueFor(AcpAgentSpec spec) => null;

  @override
  void dispose() {
    uiAuth
      ..removeListener(notifyListeners)
      ..dispose();
    super.dispose();
  }
}

void main() {
  late _SubscriptionRuntime runtime;
  late AcpAgentAuth auth;
  late _AuthUiManager manager;
  late SettingsProvider settings;
  late UrlLauncherPlatform previousLauncher;
  late _ExternalLauncher launcher;

  setUp(() async {
    previousLauncher = UrlLauncherPlatform.instance;
    launcher = _ExternalLauncher();
    UrlLauncherPlatform.instance = launcher;
    runtime = _SubscriptionRuntime();
    auth = AcpAgentAuth(
      prepare: (_) async => AcpAuthContext(
        runtime: runtime,
        launch: const AcpLaunch(command: 'unused'),
      ),
      stopAgents: (_) async {},
    );
    manager = _AuthUiManager(auth, runtime);
    settings = SettingsProvider(createBusinessTestPreferences());
    await settings.loaded;
    await manager.loaded;
  });

  tearDown(() {
    UrlLauncherPlatform.instance = previousLauncher;
    settings.dispose();
    manager.dispose();
  });

  Future<void> pumpAuthUi(
    WidgetTester tester,
    Widget home, {
    AssistantProvider? assistants,
  }) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AcpAgentManager>.value(value: manager),
          ChangeNotifierProvider.value(value: settings),
          if (assistants != null)
            ChangeNotifierProvider.value(value: assistants),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: home,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openSignIn(
    WidgetTester tester,
    String id, {
    AssistantProvider? assistants,
  }) async {
    await pumpAuthUi(
      tester,
      AgentDetailPage(agentId: id),
      assistants: assistants,
    );
    await tester.tap(find.byKey(AgentDetailPage.subscriptionKey));
    await tester.pumpAndSettle();
    expect(find.byType(AgentSubscriptionPage), findsOneWidget);
  }

  Future<void> startSignIn(WidgetTester tester, String id) async {
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('agent-auth-sign-in')));
      await Future.doWhile(() async {
        await Future<void>.delayed(Duration.zero);
        return auth.loginFor(id)?.url == null;
      }).timeout(const Duration(seconds: 5));
    });
    await tester.pump();
  }

  for (final id in [AcpAgentSpec.claudeCodeId, AcpAgentSpec.codexId]) {
    testWidgets('$id Sign In selects subscription for its existing assistant '
        'before native login and keeps API pins', (tester) async {
      late AssistantProvider assistants;
      late String assistantId;
      await tester.runAsync(() async {
        assistants = AssistantProvider(
          preferences: createBusinessTestPreferences(),
        );
        await assistants.loaded;
        assistantId = await assistants.addAssistant(name: 'Saved coder');
        await assistants.updateAssistant(
          assistants
              .getById(assistantId)!
              .copyWith(
                agentId: id,
                chatModelProvider: 'saved-provider',
                chatModelId: 'saved-model',
              ),
        );
      });
      addTearDown(assistants.dispose);
      await openSignIn(tester, id, assistants: assistants);
      expect(
        assistants.getById(assistantId)!.agentAuthMode,
        AgentAuthMode.provider,
      );
      await tester.tap(find.byKey(const ValueKey('agent-auth-check')));
      await tester.pumpAndSettle();
      expect(
        assistants.getById(assistantId)!.agentAuthMode,
        AgentAuthMode.provider,
      );
      expect(runtime.loginStarts, 0);
      AgentAuthMode? modeBeforeLogin;
      runtime.beforeLogin = () =>
          modeBeforeLogin = assistants.getById(assistantId)!.agentAuthMode;

      await startSignIn(tester, id);
      expect(modeBeforeLogin, AgentAuthMode.subscription);
      final assistant = assistants.getById(assistantId)!;
      expect(assistant.agentAuthMode, AgentAuthMode.subscription);
      expect(assistant.chatModelProvider, 'saved-provider');
      expect(assistant.chatModelId, 'saved-model');
      expect(assistants.assistants, hasLength(1));

      Navigator.of(tester.element(find.byType(AgentSubscriptionPage))).pop();
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await Future.doWhile(() async {
          await Future<void>.delayed(Duration.zero);
          return auth.busy(id);
        }).timeout(const Duration(seconds: 5));
      });
      await tester.pump();
      expect(find.text('Subscription'), findsOneWidget);
      expect(
        tester
            .widget<IosTileButton>(find.byKey(AgentDetailPage.chatKey))
            .enabled,
        isTrue,
      );
      expect(
        tester
            .widget<IosTileButton>(find.byKey(AgentDetailPage.checkKey))
            .enabled,
        isTrue,
      );
    });
  }

  testWidgets('opening and checking login does not create an assistant; '
      'explicit Sign In creates a subscription assistant', (tester) async {
    late AssistantProvider assistants;
    await tester.runAsync(() async {
      assistants = AssistantProvider(
        preferences: createBusinessTestPreferences(),
      );
      await assistants.loaded;
    });
    addTearDown(assistants.dispose);
    await openSignIn(tester, AcpAgentSpec.codexId, assistants: assistants);
    expect(assistants.assistants, isEmpty);
    await tester.tap(find.byKey(const ValueKey('agent-auth-check')));
    await tester.pumpAndSettle();
    expect(assistants.assistants, isEmpty);
    expect(runtime.loginStarts, 0);
    var countBeforeLogin = 0;
    AgentAuthMode? modeBeforeLogin;
    runtime.beforeLogin = () {
      countBeforeLogin = assistants.assistants.length;
      modeBeforeLogin = assistants.assistants.firstOrNull?.agentAuthMode;
    };

    await startSignIn(tester, AcpAgentSpec.codexId);
    expect(countBeforeLogin, 1);
    expect(modeBeforeLogin, AgentAuthMode.subscription);
    expect(assistants.assistants.single.agentId, AcpAgentSpec.codexId);
    expect(
      assistants.assistants.single.agentAuthMode,
      AgentAuthMode.subscription,
    );
  });

  testWidgets('assistant card Sign In updates the selected assistant when '
      'another assistant uses the same agent', (tester) async {
    late AssistantProvider assistants;
    late String firstId;
    late String selectedId;
    await tester.runAsync(() async {
      assistants = AssistantProvider(
        preferences: createBusinessTestPreferences(),
      );
      await assistants.loaded;
      firstId = await assistants.addAssistant(name: 'First coder');
      selectedId = await assistants.addAssistant(name: 'Selected coder');
      for (final assistantId in [firstId, selectedId]) {
        await assistants.updateAssistant(
          assistants
              .getById(assistantId)!
              .copyWith(
                agentId: AcpAgentSpec.codexId,
                chatModelProvider: 'saved-provider',
                chatModelId: 'saved-model',
              ),
        );
      }
    });
    addTearDown(assistants.dispose);
    await pumpAuthUi(
      tester,
      Scaffold(
        body: Consumer<AssistantProvider>(
          builder: (_, provider, _) =>
              AssistantAgentCard(assistant: provider.getById(selectedId)!),
        ),
      ),
      assistants: assistants,
    );
    await tester.tap(
      find.byKey(const ValueKey('assistant-agent-subscription')),
    );
    await tester.pumpAndSettle();
    expect(
      assistants.getById(selectedId)!.agentAuthMode,
      AgentAuthMode.provider,
    );
    (AgentAuthMode, AgentAuthMode)? modesBeforeLogin;
    runtime.beforeLogin = () => modesBeforeLogin = (
      assistants.getById(firstId)!.agentAuthMode,
      assistants.getById(selectedId)!.agentAuthMode,
    );

    await startSignIn(tester, AcpAgentSpec.codexId);
    expect(modesBeforeLogin, (
      AgentAuthMode.provider,
      AgentAuthMode.subscription,
    ));
    expect(assistants.getById(firstId)!.agentAuthMode, AgentAuthMode.provider);
    expect(
      assistants.getById(selectedId)!.agentAuthMode,
      AgentAuthMode.subscription,
    );
    expect(assistants.getById(selectedId)!.chatModelProvider, 'saved-provider');
    expect(assistants.getById(selectedId)!.chatModelId, 'saved-model');
    expect(assistants.assistants, hasLength(2));
  });

  testWidgets('Sign In awaits assistant selection and ignores duplicate taps', (
    tester,
  ) async {
    final selected = Completer<void>();
    var selections = 0;
    await pumpAuthUi(
      tester,
      AgentSubscriptionPage(
        agentId: AcpAgentSpec.codexId,
        onSignIn: () {
          selections++;
          return selected.future;
        },
      ),
    );
    final signIn = find.byKey(const ValueKey('agent-auth-sign-in'));
    await tester.tap(signIn);
    await tester.tap(signIn);
    await tester.pump();
    expect(selections, 1);
    expect(runtime.loginStarts, 0);
    expect(tester.widget<IosTileButton>(signIn).enabled, isFalse);
    expect(
      tester
          .widget<IosTileButton>(find.byKey(const ValueKey('agent-auth-check')))
          .enabled,
      isFalse,
    );

    await tester.runAsync(() async {
      selected.complete();
      await Future.doWhile(() async {
        await Future<void>.delayed(Duration.zero);
        return auth.loginFor(AcpAgentSpec.codexId)?.url == null;
      }).timeout(const Duration(seconds: 5));
    });
    await tester.pump();
    expect(runtime.loginStarts, 1);
    expect(find.text('ABCD-EFGH'), findsOneWidget);
  });

  testWidgets('leaving during assistant selection prevents late native login', (
    tester,
  ) async {
    final selected = Completer<void>();
    await pumpAuthUi(
      tester,
      AgentSubscriptionPage(
        agentId: AcpAgentSpec.codexId,
        onSignIn: () => selected.future,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('agent-auth-sign-in')));
    await tester.pump();
    expect(runtime.loginStarts, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.runAsync(() async {
      selected.complete();
      await selected.future;
      await Future<void>.delayed(Duration.zero);
    });
    expect(runtime.loginStarts, 0);
    expect(auth.loginFor(AcpAgentSpec.codexId), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed assistant selection shows a safe failure and can retry', (
    tester,
  ) async {
    var selections = 0;
    await pumpAuthUi(
      tester,
      AgentSubscriptionPage(
        agentId: AcpAgentSpec.codexId,
        onSignIn: () async {
          if (++selections == 1) {
            throw StateError('private assistant storage failure');
          }
        },
      ),
    );
    await tester.tap(find.byKey(const ValueKey('agent-auth-sign-in')));
    await tester.pumpAndSettle();
    const safeFailure =
        'Sign-in could not be completed. Update the agent and try again.';
    expect(find.text(safeFailure), findsOneWidget);
    expect(
      find.textContaining('private assistant storage failure'),
      findsNothing,
    );
    expect(runtime.loginStarts, 0);
    expect(tester.takeException(), isNull);

    await startSignIn(tester, AcpAgentSpec.codexId);
    expect(selections, 2);
    expect(runtime.loginStarts, 1);
    expect(find.text(safeFailure), findsNothing);
  });

  testWidgets('sign-in page checks subscription status and signs out', (
    tester,
  ) async {
    runtime.signedIn = true;
    await openSignIn(tester, AcpAgentSpec.codexId);

    expect(find.text('Signed in'), findsOneWidget);
    expect(find.textContaining('ChatGPT Settings → Security'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('agent-auth-sign-out')));
    await tester.pumpAndSettle();
    expect(find.text('Sign-in required'), findsOneWidget);
    expect(auth.status(AcpAgentSpec.codexId), AcpAuthStatus.signedOut);
  });

  testWidgets('device challenge is confined to the sign-in page and leaving '
      'cancels the login', (tester) async {
    await openSignIn(tester, AcpAgentSpec.codexId);
    await startSignIn(tester, AcpAgentSpec.codexId);

    expect(find.text(_SubscriptionRuntime.codexUrl), findsOneWidget);
    expect(find.text('ABCD-EFGH'), findsOneWidget);
    expect(find.textContaining('private native diagnostics'), findsNothing);
    expect(manager.log, isEmpty);

    await tester.tap(find.byKey(const ValueKey('agent-auth-open-browser')));
    await tester.pump();
    expect(launcher.launched, [
      (_SubscriptionRuntime.codexUrl, PreferredLaunchMode.externalApplication),
    ]);

    final navigator = Navigator.of(
      tester.element(find.text('Sign in with subscription')),
    );
    navigator.pop();
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await Future.doWhile(() async {
        await Future<void>.delayed(Duration.zero);
        return auth.loginFor(AcpAgentSpec.codexId) != null;
      }).timeout(const Duration(seconds: 5));
    });

    expect(runtime.cancelledRun, isNotNull);
    expect(auth.loginFor(AcpAgentSpec.codexId), isNull);
    expect(find.text('ABCD-EFGH'), findsNothing);
    expect(find.text(_SubscriptionRuntime.codexUrl), findsNothing);
    expect(find.textContaining('private native diagnostics'), findsNothing);
    expect(manager.log, isEmpty);
  });

  testWidgets('Claude submits the complete private code and clears the field', (
    tester,
  ) async {
    await openSignIn(tester, AcpAgentSpec.claudeCodeId);
    await startSignIn(tester, AcpAgentSpec.claudeCodeId);
    expect(find.textContaining('including the part after #'), findsOneWidget);
    expect(find.text(_SubscriptionRuntime.claudeUrl), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('agent-auth-code')),
      'complete-private-code#state',
    );
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const ValueKey('agent-auth-submit-code')),
    );
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('agent-auth-submit-code')));
      await Future.doWhile(() async {
        await Future<void>.delayed(Duration.zero);
        return auth.busy(AcpAgentSpec.claudeCodeId);
      }).timeout(const Duration(seconds: 5));
    });
    await tester.pumpAndSettle();

    expect(runtime.submittedCodes, ['complete-private-code#state\n']);
    expect(find.text('Signed in'), findsOneWidget);
    expect(find.text('complete-private-code#state'), findsNothing);
    expect(find.text(_SubscriptionRuntime.claudeUrl), findsNothing);
    expect(manager.log, isEmpty);
  });
}
