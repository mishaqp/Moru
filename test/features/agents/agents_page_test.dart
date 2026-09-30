import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:Kelivo/core/providers/environment_provider.dart';
import 'package:Kelivo/core/models/assistant.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/acp/acp_agent_manager.dart';
import 'package:Kelivo/core/services/acp/acp_agent.dart';
import 'package:Kelivo/core/services/workspace/workspace_runtime.dart';
import 'package:Kelivo/features/agents/pages/agent_detail_page.dart';
import 'package:Kelivo/features/agents/pages/agents_page.dart';
import 'package:Kelivo/features/agents/widgets/assistant_agent_card.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

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
  _CheckedManager(this.available)
    : super(
        preferences: createBusinessTestPreferences(),
        runtimeProvider: WorkspaceRuntimeProvider()..register(_ProbeRuntime()),
        environment: EnvironmentProvider(
          preferences: createBusinessTestPreferences(),
        ),
      );
  final bool available;
  @override
  AcpCheckResult? lastCheck(String id) => AcpCheckResult(
    info: const AcpAgentInfo(name: 'OpenCode', version: '1'),
    moruToolsAvailable: available,
  );
}

void main() {
  late AcpAgentManager manager;
  late SettingsProvider settings;

  Future<void> pumpPage(
    WidgetTester tester,
    Widget page, {
    Locale locale = const Locale('en'),
  }) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: manager),
          ChangeNotifierProvider.value(value: settings),
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
}
