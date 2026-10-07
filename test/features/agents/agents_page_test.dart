import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:Kelivo/core/providers/environment_provider.dart';
import 'package:Kelivo/core/models/assistant.dart';
import 'package:Kelivo/core/models/agent_auth_mode.dart';
import 'package:Kelivo/core/models/conversation.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/acp/acp_agent_manager.dart';
import 'package:Kelivo/core/services/acp/acp_agent.dart';
import 'package:Kelivo/core/services/acp/acp_agent_catalog.dart';
import 'package:Kelivo/core/services/acp/acp_agent_auth.dart';
import 'package:Kelivo/core/services/chat/chat_service.dart';
import 'package:Kelivo/core/services/notification_service.dart';
import 'package:Kelivo/core/services/workspace/workspace_runtime.dart';
import 'package:Kelivo/features/agents/pages/agent_detail_page.dart';
import 'package:Kelivo/features/agents/pages/agents_page.dart';
import 'package:Kelivo/features/agents/agent_chat_start.dart';
import 'package:Kelivo/features/agents/widgets/assistant_agent_card.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/widgets/ios_tile_button.dart';

import '../../support/business_test_harness.dart';
import '../../support/fake_workspace_runtime.dart';

class _ProbeRuntime extends FakeWorkspaceRuntime
    implements WorkspaceStdioRuntime {
  @override
  Stream<CommandEvent> run(CommandRequest request) {
    requests.add(request);
    return Stream.fromIterable([
      const CommandStarted(),
      if (request.command.contains('__acp_'))
        CommandOutput(
          OutputStreamKind.stdout,
          Uint8List.fromList(
            utf8.encode(
              '__moru_node=v18.19.1\n__acp_claude-code=0\n__acp_codex=0\n__acp_opencode=1\n__acp_kimi-code=0\n__acp_deepseek-harness=0\n',
            ),
          ),
        ),
      const CommandExited(
        exitCode: 0,
        timedOut: false,
        cancelled: false,
        interrupted: false,
        duration: Duration.zero,
      ),
    ]);
  }

  @override
  Future<void> writeStdin(String runId, Uint8List data) async {}
}

class _CheckedManager extends AcpAgentManager {
  _CheckedManager(this.available, {this.result})
    : super(
        preferences: createBusinessTestPreferences(),
        runtimeProvider: WorkspaceRuntimeProvider()..register(_ProbeRuntime()),
        environment: EnvironmentProvider(
          preferences: createBusinessTestPreferences(),
        ),
      );
  final bool available;
  final AcpCheckResult? result;
  @override
  AcpCheckResult? lastCheck(String id) =>
      result ??
      AcpCheckResult(
        info: const AcpAgentInfo(name: 'OpenCode', version: '1'),
        moruToolsAvailable: available,
      );
}

class _InstalledSubscriptionManager extends AcpAgentManager {
  _InstalledSubscriptionManager()
    : super(
        preferences: createBusinessTestPreferences(),
        runtimeProvider: WorkspaceRuntimeProvider()..register(_ProbeRuntime()),
        environment: EnvironmentProvider(
          preferences: createBusinessTestPreferences(),
        ),
      );

  @override
  AcpInstallState state(String id) =>
      id == AcpAgentSpec.claudeCodeId || id == AcpAgentSpec.codexId
      ? AcpInstallState.installed
      : super.state(id);

  @override
  AcpNodeIssue? nodeIssueFor(AcpAgentSpec spec) => null;

  AgentAuthMode? checkedMode;
  AcpProviderInput? checkedProvider;
  AcpCheckResult? _checkResult;

  @override
  AcpCheckResult? lastCheck(String id) => _checkResult;

  @override
  Future<AcpCheckResult> check(
    AcpAgentSpec spec,
    AcpProviderInput? provider, {
    AgentAuthMode authMode = AgentAuthMode.provider,
  }) async {
    checkedMode = authMode;
    checkedProvider = provider;
    final result = AcpCheckResult(
      info: AcpAgentInfo(name: spec.name, version: 'test'),
      authStatus: AcpAuthStatus.signedIn,
    );
    _checkResult = result;
    notifyListeners();
    return result;
  }
}

class _AgentChatService extends ChatService {
  final List<Conversation> created = [];

  @override
  Future<Conversation> createConversation({
    String? title,
    String? assistantId,
    bool activate = true,
  }) async {
    final conversation = Conversation(
      title: title ?? '',
      assistantId: assistantId,
    );
    created.add(conversation);
    return conversation;
  }
}

void main() {
  late AcpAgentManager manager;
  late SettingsProvider settings;

  Future<void> pumpPage(
    WidgetTester tester,
    Widget page, {
    Locale locale = const Locale('en'),
    AssistantProvider? assistants,
    ChatService? chats,
  }) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: manager),
          ChangeNotifierProvider.value(value: settings),
          if (assistants != null)
            ChangeNotifierProvider.value(value: assistants),
          if (chats != null) ChangeNotifierProvider.value(value: chats),
        ],
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: page,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() async {
    manager = AcpAgentManager(
      preferences: createBusinessTestPreferences(),
      runtimeProvider: WorkspaceRuntimeProvider()..register(_ProbeRuntime()),
      environment: EnvironmentProvider(
        preferences: createBusinessTestPreferences(),
      ),
    );
    settings = SettingsProvider(createBusinessTestPreferences());
    await settings.loaded;
  });

  testWidgets('subscription settings are explicit and opening them creates no '
      'assistant', (tester) async {
    manager.dispose();
    late AssistantProvider assistants;
    await tester.runAsync(() async {
      manager = _InstalledSubscriptionManager();
      assistants = AssistantProvider(
        preferences: createBusinessTestPreferences(),
      );
      await assistants.loaded;
      await manager.loaded;
    });
    addTearDown(assistants.dispose);

    await pumpPage(
      tester,
      const AgentDetailPage(agentId: AcpAgentSpec.codexId),
      assistants: assistants,
    );

    expect(find.text('Authentication'), findsOneWidget);
    expect(find.text('Sign in with subscription'), findsOneWidget);
    expect(find.text('API provider'), findsOneWidget);
    expect(assistants.assistants, isEmpty);
  });

  for (final agentId in [AcpAgentSpec.claudeCodeId, AcpAgentSpec.codexId]) {
    testWidgets('$agentId subscription enables chat and check without an API '
        'provider', (tester) async {
      manager.dispose();
      late AssistantProvider assistants;
      final chats = _AgentChatService();
      addTearDown(chats.dispose);
      await tester.runAsync(() async {
        manager = _InstalledSubscriptionManager();
        assistants = AssistantProvider(
          preferences: createBusinessTestPreferences(),
        );
        await assistants.loaded;
        await manager.loaded;
      });
      addTearDown(assistants.dispose);
      await pumpPage(
        tester,
        AgentDetailPage(agentId: agentId),
        assistants: assistants,
        chats: chats,
      );

      await tester.runAsync(() => tester.tap(find.text('Authentication')));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Subscription').last);
        await Future.doWhile(() async {
          await Future<void>.delayed(Duration.zero);
          return assistants.assistants.isEmpty ||
              assistants.assistants.single.toJson()['agentAuthMode'] !=
                  'subscription';
        }).timeout(const Duration(seconds: 5));
      });
      await tester.pumpAndSettle();

      expect(assistants.assistants.single.agentId, agentId);
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
      expect(find.textContaining('Choose a default chat model'), findsNothing);

      await tester.ensureVisible(find.byKey(AgentDetailPage.checkKey));
      await tester.tap(find.byKey(AgentDetailPage.checkKey));
      await tester.pumpAndSettle();
      final checkedManager = manager as _InstalledSubscriptionManager;
      expect(checkedManager.checkedMode, AgentAuthMode.subscription);
      expect(checkedManager.checkedProvider, isNull);
      expect(find.text('Signed in'), findsOneWidget);

      await tester.ensureVisible(find.byKey(AgentDetailPage.chatKey));
      await tester.runAsync(() async {
        final opened = NotificationService.conversationTaps.first;
        await tester.tap(find.byKey(AgentDetailPage.chatKey));
        expect(
          await opened.timeout(const Duration(seconds: 5)),
          chats.created.single.id,
        );
      });
      await tester.pumpAndSettle();
      expect(chats.created.single.assistantId, assistants.assistants.single.id);
      expect(assistants.currentAssistantId, assistants.assistants.single.id);
      expect(
        assistants.assistants.single.agentAuthMode,
        AgentAuthMode.subscription,
      );
    });
  }

  tearDown(() {
    settings.dispose();
    manager.dispose();
  });

  const codexWarning =
      'Codex работает только с провайдерами, которые поддерживают OpenAI Responses API. Включите его в настройках провайдера или выберите другого агента';

  Future<void> configureProvider(String id, bool responses) async {
    await settings.setProviderConfig(
      id,
      ProviderConfig(
        id: id,
        enabled: true,
        name: id,
        apiKey: 'test-key',
        baseUrl: 'https://api.example.com/v1',
        providerType: ProviderKind.openai,
        useResponseApi: responses,
      ),
    );
  }

  testWidgets('Codex detail warns only for a provider without Responses API', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await manager.loaded;
      await configureProvider('custom', false);
      await settings.setCurrentModel('custom', 'model');
    });
    await pumpPage(
      tester,
      const AgentDetailPage(agentId: 'codex'),
      locale: const Locale('ru'),
    );
    expect(find.text(codexWarning), findsOneWidget);
    expect(tester.widget<Text>(find.text(codexWarning)).maxLines, isNull);

    await tester.runAsync(() => configureProvider('custom', true));
    await tester.pumpAndSettle();
    expect(find.text(codexWarning), findsNothing);

    await tester.runAsync(() => configureProvider('custom', false));
    await pumpPage(
      tester,
      const AgentDetailPage(agentId: 'opencode'),
      locale: const Locale('ru'),
    );
    expect(find.text(codexWarning), findsNothing);

    await tester.runAsync(settings.resetCurrentModel);
    await pumpPage(
      tester,
      const AgentDetailPage(agentId: 'codex'),
      locale: const Locale('ru'),
    );
    expect(find.text(codexWarning), findsNothing);
  });

  testWidgets('failed agent check keeps technical details collapsed', (
    tester,
  ) async {
    manager.dispose();
    manager = _CheckedManager(
      false,
      result: const AcpCheckResult(
        error: 'Internal error',
        errorDetails: 'safe check data\n\nstderr explanation',
      ),
    );
    await tester.runAsync(() => manager.loaded);
    await pumpPage(tester, const AgentDetailPage(agentId: 'opencode'));

    expect(find.textContaining('Internal error'), findsOneWidget);
    expect(find.text('safe check data\n\nstderr explanation'), findsNothing);
    expect(find.text('Show details'), findsOneWidget);
    await tester.tap(find.text('Show details'));
    await tester.pumpAndSettle();
    expect(find.text('safe check data\n\nstderr explanation'), findsOneWidget);
    await tester.tap(find.text('Hide details'));
    await tester.pumpAndSettle();
    expect(find.text('safe check data\n\nstderr explanation'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('assistant agent picker warns using the assistant provider', (
    tester,
  ) async {
    late AssistantProvider assistants;
    await tester.runAsync(() async {
      assistants = AssistantProvider(
        preferences: createBusinessTestPreferences(),
      );
      await assistants.loaded;
      await manager.loaded;
      await configureProvider('default', true);
      await configureProvider('assistant', false);
      await settings.setCurrentModel('default', 'model');
    });
    addTearDown(assistants.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: manager),
          ChangeNotifierProvider.value(value: assistants),
          ChangeNotifierProvider.value(value: settings),
        ],
        child: MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: AssistantAgentCard(
              assistant: Assistant(
                id: 'coder',
                name: 'Coder',
                chatModelProvider: 'assistant',
                chatModelId: 'model',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => tester.tap(find.byKey(AssistantAgentCard.rowKey)),
    );
    await tester.pumpAndSettle();
    expect(find.text(codexWarning), findsOneWidget);
    expect(tester.widget<Text>(find.text(codexWarning)).maxLines, isNull);

    Navigator.of(tester.element(find.text(codexWarning))).pop();
    await tester.pumpAndSettle();
    await tester.runAsync(() => configureProvider('assistant', true));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => tester.tap(find.byKey(AssistantAgentCard.rowKey)),
    );
    await tester.pumpAndSettle();
    expect(find.text(codexWarning), findsNothing);
  });

  for (final available in [true, false]) {
    testWidgets(
      'agent check shows Moru tools ${available ? 'available' : 'unavailable'}',
      (tester) async {
        final checked = (await tester.runAsync(
          () async => _CheckedManager(available),
        ))!;
        manager = checked;
        await tester.runAsync(manager.refresh);
        await pumpPage(tester, const AgentDetailPage(agentId: 'opencode'));
        expect(
          find.text('Moru tools: ${available ? 'available' : 'unavailable'}'),
          findsOneWidget,
        );
        expect(find.text('It works: OpenCode 1 answered.'), findsOneWidget);
      },
    );
  }

  testWidgets('the list explains agents and shows which are installed', (
    tester,
  ) async {
    await tester.runAsync(manager.refresh);
    await pumpPage(tester, const AgentsPage());
    expect(find.textContaining('Coding agents such as Claude Code'), findsOne);
    for (final name in [
      'Claude Code',
      'Codex',
      'OpenCode',
      'Kimi Code',
      'DeepSeek Harness',
    ]) {
      expect(find.text(name), findsOneWidget);
    }
    expect(find.text('Installed'), findsOneWidget);
    expect(find.text('Not installed'), findsNWidgets(4));

    await tester.tap(find.text('Codex'));
    await tester.pumpAndSettle();
    expect(find.byType(AgentDetailPage), findsOneWidget);
    expect(find.byKey(AgentDetailPage.installKey), findsOneWidget);
    expect(find.text('Install'), findsOneWidget);
    // Not installed yet: nothing to check or remove.
    expect(find.byKey(AgentDetailPage.checkKey), findsNothing);
    expect(find.byKey(AgentDetailPage.removeKey), findsNothing);
  });

  testWidgets(
    'new agent card explains incompatible Node and upgrade; OpenCode offers Web UI',
    (tester) async {
      await tester.runAsync(manager.refresh);
      await pumpPage(
        tester,
        const AgentDetailPage(agentId: 'deepseek-harness'),
      );
      expect(
        find.textContaining('Detected in the Linux environment: v18.19.1'),
        findsOneWidget,
      );
      expect(find.textContaining('No verified upgrade method'), findsOneWidget);
      await pumpPage(tester, const AgentDetailPage(agentId: 'opencode'));
      expect(find.byKey(AgentDetailPage.webOpenKey), findsOneWidget);
      expect(find.text('Open web interface'), findsOneWidget);
    },
  );

  testWidgets('an installed agent offers update, check and remove; the check '
      'needs a default model first', (tester) async {
    await tester.runAsync(manager.refresh);
    await pumpPage(tester, const AgentDetailPage(agentId: 'opencode'));
    expect(find.text('Update'), findsOneWidget);
    expect(find.byKey(AgentDetailPage.checkKey), findsOneWidget);
    expect(find.byKey(AgentDetailPage.removeKey), findsOneWidget);
    expect(find.textContaining('Choose a default chat model'), findsOneWidget);
  });

  testWidgets('your own agent is added by its command line', (tester) async {
    await tester.runAsync(() => manager.loaded);
    await pumpPage(tester, const AgentsPage());
    await tester.ensureVisible(find.byKey(const ValueKey('agent-add-custom')));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => tester.tap(find.byKey(const ValueKey('agent-add-custom'))),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('agent-custom-name')),
      'Goose',
    );
    await tester.enterText(
      find.byKey(const ValueKey('agent-custom-command')),
      'goose acp --with-builtin developer',
    );
    await tester.runAsync(() async {
      await tester.tap(find.text('Save'));
      await Future.doWhile(() async {
        await Future<void>.delayed(Duration.zero);
        return manager.customAgents.isEmpty;
      });
    });
    await tester.pumpAndSettle();
    final spec = manager.customAgents.single;
    expect(spec.name, 'Goose');
    expect(spec.command, 'goose');
    expect(spec.arguments, ['acp', '--with-builtin', 'developer']);
    // It opens right away, ready to check.
    expect(find.byType(AgentDetailPage), findsOneWidget);
    expect(find.text('goose acp --with-builtin developer'), findsWidgets);
  });

  testWidgets('an assistant is given an agent and set back to the model', (
    tester,
  ) async {
    // Created outside the fake clock, where its loading can finish.
    late AssistantProvider assistants;
    late String id;
    await tester.runAsync(() async {
      assistants = AssistantProvider(
        preferences: createBusinessTestPreferences(),
      );
      await assistants.loaded;
      id = await assistants.addAssistant(name: 'Coder');
      await manager.loaded;
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: manager),
          ChangeNotifierProvider.value(value: assistants),
          ChangeNotifierProvider.value(value: settings),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Consumer<AssistantProvider>(
              builder: (_, provider, _) =>
                  AssistantAgentCard(assistant: provider.getById(id)!),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('None — the model answers'), findsOneWidget);

    Future<void> choose(String label, String? expectedId) async {
      await tester.runAsync(
        () => tester.tap(find.byKey(AssistantAgentCard.rowKey)),
      );
      await tester.runAsync(() => manager.loaded);
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text(label).last);
        await Future.doWhile(() async {
          await Future<void>.delayed(Duration.zero);
          return assistants.getById(id)!.agentId != expectedId;
        });
      });
      await tester.pumpAndSettle();
    }

    await choose('OpenCode', 'opencode');
    expect(assistants.getById(id)!.agentId, 'opencode');
    expect(find.text('OpenCode'), findsOneWidget);

    await choose('None — the model answers', null);
    expect(assistants.getById(id)!.agentId, isNull);
  });

  test(
    'agent assistant reuse preserves an explicit mode until selected again',
    () async {
      final assistants = AssistantProvider(
        preferences: createBusinessTestPreferences(),
      );
      addTearDown(assistants.dispose);
      final spec = manager.agent(AcpAgentSpec.codexId)!;
      final subscribed = await assistantForAgent(
        assistants,
        spec,
        authMode: AgentAuthMode.subscription,
      );
      await assistants.updateAssistant(
        subscribed.copyWith(
          chatModelProvider: 'saved-provider',
          chatModelId: 'saved-model',
        ),
      );

      final reused = await assistantForAgent(assistants, spec);
      expect(reused.id, subscribed.id);
      expect(reused.agentAuthMode, AgentAuthMode.subscription);

      final restored = await assistantForAgent(
        assistants,
        spec,
        authMode: AgentAuthMode.provider,
      );
      expect(restored.id, subscribed.id);
      expect(restored.chatModelProvider, 'saved-provider');
      expect(restored.chatModelId, 'saved-model');
      expect(restored.agentAuthMode, AgentAuthMode.provider);
      expect(assistants.assistants, hasLength(1));
    },
  );

  testWidgets('assistant subscription mode is reversible and preserves API '
      'settings', (tester) async {
    late AssistantProvider assistants;
    late String id;
    await tester.runAsync(() async {
      assistants = AssistantProvider(
        preferences: createBusinessTestPreferences(),
      );
      await assistants.loaded;
      id = await assistants.addAssistant(name: 'Coder');
      await assistants.updateAssistant(
        assistants
            .getById(id)!
            .copyWith(
              agentId: AcpAgentSpec.codexId,
              chatModelProvider: 'saved-provider',
              chatModelId: 'saved-model',
            ),
      );
      await configureProvider('saved-provider', false);
    });
    addTearDown(assistants.dispose);
    await pumpPage(
      tester,
      Scaffold(
        body: Consumer<AssistantProvider>(
          builder: (_, provider, _) =>
              AssistantAgentCard(assistant: provider.getById(id)!),
        ),
      ),
      assistants: assistants,
    );
    expect(find.textContaining('Responses API'), findsOneWidget);

    Future<void> chooseMode(String label, AgentAuthMode mode) async {
      await tester.runAsync(
        () => tester.tap(find.byKey(AssistantAgentCard.authModeKey)),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text(label).last);
        await Future.doWhile(() async {
          await Future<void>.delayed(Duration.zero);
          return assistants.getById(id)!.agentAuthMode != mode;
        }).timeout(const Duration(seconds: 5));
      });
      await tester.pumpAndSettle();
    }

    await chooseMode('Subscription', AgentAuthMode.subscription);
    expect(find.textContaining('Responses API'), findsNothing);
    expect(assistants.getById(id)!.chatModelProvider, 'saved-provider');
    expect(assistants.getById(id)!.chatModelId, 'saved-model');
    expect(settings.getProviderConfig('saved-provider').apiKey, 'test-key');

    await chooseMode('API provider', AgentAuthMode.provider);
    expect(find.textContaining('Responses API'), findsOneWidget);
    expect(assistants.getById(id)!.chatModelProvider, 'saved-provider');
    expect(assistants.getById(id)!.chatModelId, 'saved-model');
  });

  testWidgets('selecting an agent without subscription uses API mode', (
    tester,
  ) async {
    late AssistantProvider assistants;
    late String id;
    await tester.runAsync(() async {
      assistants = AssistantProvider(
        preferences: createBusinessTestPreferences(),
      );
      await assistants.loaded;
      id = await assistants.addAssistant(name: 'Coder');
      await assistants.updateAssistant(
        assistants
            .getById(id)!
            .copyWith(
              agentId: AcpAgentSpec.codexId,
              agentAuthMode: AgentAuthMode.subscription,
            ),
      );
      await manager.loaded;
    });
    addTearDown(assistants.dispose);
    await pumpPage(
      tester,
      Scaffold(
        body: Consumer<AssistantProvider>(
          builder: (_, provider, _) =>
              AssistantAgentCard(assistant: provider.getById(id)!),
        ),
      ),
      assistants: assistants,
    );

    await tester.runAsync(
      () => tester.tap(find.byKey(AssistantAgentCard.rowKey)),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('OpenCode').last);
      await Future.doWhile(() async {
        await Future<void>.delayed(Duration.zero);
        return assistants.getById(id)!.agentId != AcpAgentSpec.openCodeId;
      }).timeout(const Duration(seconds: 5));
    });
    await tester.pumpAndSettle();
    expect(assistants.getById(id)!.agentAuthMode, AgentAuthMode.provider);
    expect(find.byKey(AssistantAgentCard.authModeKey), findsNothing);
  });
}
