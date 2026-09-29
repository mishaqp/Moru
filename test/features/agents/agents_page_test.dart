import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:Kelivo/core/providers/environment_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/acp/acp_agent_manager.dart';
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
              '__acp_claude-code=0\n__acp_codex=0\n__acp_opencode=1\n',
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

void main() {
  late AcpAgentManager manager;
  late SettingsProvider settings;

  Future<void> pumpPage(WidgetTester tester, Widget page) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: manager),
          ChangeNotifierProvider.value(value: settings),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
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

  tearDown(() => settings.dispose());

  testWidgets('the list explains agents and shows which are installed', (
    tester,
  ) async {
    await tester.runAsync(manager.refresh);
    await pumpPage(tester, const AgentsPage());
    expect(find.textContaining('Coding agents such as Claude Code'), findsOne);
    for (final name in ['Claude Code', 'Codex', 'OpenCode']) {
      expect(find.text(name), findsOneWidget);
    }
    expect(find.text('Installed'), findsOneWidget);
    expect(find.text('Not installed'), findsNWidgets(2));

    await tester.tap(find.text('Codex'));
    await tester.pumpAndSettle();
    expect(find.byType(AgentDetailPage), findsOneWidget);
    expect(find.byKey(AgentDetailPage.installKey), findsOneWidget);
    expect(find.text('Install'), findsOneWidget);
    // Not installed yet: nothing to check or remove.
    expect(find.byKey(AgentDetailPage.checkKey), findsNothing);
    expect(find.byKey(AgentDetailPage.removeKey), findsNothing);
  });

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
    await tester.tap(find.byKey(const ValueKey('agent-add-custom')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('agent-custom-name')),
      'Goose',
    );
    await tester.enterText(
      find.byKey(const ValueKey('agent-custom-command')),
      'goose acp --with-builtin developer',
    );
    await tester.tap(find.text('Save'));
    // The dialog closes, then the preferences write finishes outside the
    // fake clock.
    for (
      var i = 0;
      i < 40 && find.byType(AgentDetailPage).evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
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

    // Loading and saving finish outside the fake clock.
    Future<void> settle() async {
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
    }

    Future<void> choose(String label) async {
      await tester.tap(find.byKey(AssistantAgentCard.rowKey));
      await settle();
      await tester.tap(find.text(label).last);
      await settle();
    }

    await choose('OpenCode');
    expect(assistants.getById(id)!.agentId, 'opencode');
    expect(find.text('OpenCode'), findsOneWidget);

    await choose('None — the model answers');
    expect(assistants.getById(id)!.agentId, isNull);
  });
}
