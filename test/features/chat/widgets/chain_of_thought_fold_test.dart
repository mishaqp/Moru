import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/providers/tts_provider.dart';
import 'package:Kelivo/core/providers/user_provider.dart';
import 'package:Kelivo/features/chat/utils/tool_timing.dart';
import 'package:Kelivo/features/chat/widgets/chat_message_widget.dart';
import 'package:Kelivo/features/home/services/ask_user_interaction_service.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

import '../../../support/business_test_harness.dart';

const _summary = ValueKey<String>('chain-of-thought-summary');
const _t0 = 1700000000000;

Future<void> _pump(
  WidgetTester tester, {
  required bool collapse,
  required bool streaming,
  List<ToolUIPart>? tools,
}) async {
  tester.view.physicalSize = const Size(1170, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final settings = SettingsProvider(createBusinessTestPreferences());
  await settings.loaded;
  await settings.setCollapseThinkingSteps(collapse);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ChangeNotifierProvider(
          create: (_) =>
              AssistantProvider(preferences: createBusinessTestPreferences()),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              TtsProvider(preferences: createBusinessTestPreferences()),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              UserProvider(preferences: createBusinessTestPreferences()),
        ),
        ChangeNotifierProvider(create: (_) => AskUserInteractionService()),
        ChangeNotifierProvider(create: (_) => ToolApprovalService()),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ChatMessageWidget(
            message: ChatMessage(
              id: 'm1',
              role: 'assistant',
              content: 'Done.',
              conversationId: 'c1',
              isStreaming: streaming,
              // The text-only generation time must not stand in for it.
              durationMs: 2100,
            ),
            showModelIcon: false,
            toolParts:
                tools ??
                [
                  for (var i = 0; i < 4; i++)
                    ToolUIPart(
                      id: 't$i',
                      toolName: 'search',
                      arguments: {'q': 'step $i'},
                      content: 'ok $i',
                      // Four steps spread over 12.4 s of wall time.
                      metadata: {
                        kToolStartedAtMsKey: _t0 + i * 3000,
                        kToolFinishedAtMsKey: _t0 + i * 3000 + 3400,
                      },
                    ),
                ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

List<String> _toolKeys(WidgetTester tester) => [
  for (final element
      in find
          .byWidgetPredicate(
            (widget) =>
                widget.key is ValueKey<String> &&
                (widget.key! as ValueKey<String>).value.startsWith('tool-'),
          )
          .evaluate())
    (element.widget.key! as ValueKey<String>).value,
];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a finished reply folds its steps into one line', (tester) async {
    await _pump(tester, collapse: true, streaming: false);

    expect(find.byKey(_summary), findsOneWidget);
    expect(find.text('Processed · 12 s'), findsOneWidget);
    expect(_toolKeys(tester), isEmpty);

    await tester.tap(find.byKey(_summary));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(_toolKeys(tester), hasLength(4));

    await tester.tap(find.byKey(_summary));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(_toolKeys(tester), isEmpty);
  });

  testWidgets('a streaming reply keeps its latest steps visible', (
    tester,
  ) async {
    await _pump(tester, collapse: true, streaming: true);
    expect(find.byKey(_summary), findsNothing);
    expect(_toolKeys(tester), hasLength(2));
  });

  testWidgets('steps stay open when the setting is off', (tester) async {
    await _pump(tester, collapse: false, streaming: false);
    expect(find.byKey(_summary), findsNothing);
    expect(_toolKeys(tester), hasLength(4));
  });

  testWidgets('an unanswered question never hides behind the fold', (
    tester,
  ) async {
    await _pump(
      tester,
      collapse: true,
      streaming: false,
      tools: [
        ToolUIPart(
          id: 'ask',
          toolName: AskUserToolNames.askUser,
          arguments: {
            'questions': [
              {
                'question': 'Which one?',
                'options': ['A', 'B'],
              },
            ],
          },
        ),
      ],
    );
    expect(find.byKey(_summary), findsNothing);
    expect(find.text('Which one?'), findsOneWidget);
  });

  testWidgets('steps without time marks show their count', (tester) async {
    await _pump(
      tester,
      collapse: true,
      streaming: false,
      tools: [
        for (var i = 0; i < 3; i++)
          ToolUIPart(
            id: 'old$i',
            toolName: 'search',
            arguments: {'q': 'old $i'},
            content: 'ok',
          ),
      ],
    );
    expect(find.text('Processed · 3 steps'), findsOneWidget);
  });
}
