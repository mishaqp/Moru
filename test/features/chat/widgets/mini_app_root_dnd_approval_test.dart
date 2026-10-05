import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/providers/tts_provider.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_runtime.dart';
import 'package:Kelivo/features/chat/widgets/chat_message_widget.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/l10n/app_localizations_en.dart';
import 'package:Kelivo/l10n/app_localizations_ru.dart';

import '../../../support/business_test_harness.dart';

final _actionName = MiniAppRuntime.toolNameFor('focus', 'start');

Map<String, dynamic> _rootDndArguments(String mode) => {
  'app_id': 'focus',
  'app': 'Focus',
  'action': 'start',
  'description': 'Start focus',
  'danger': 'root',
  'permissions': ['device.audio.write', 'device.root.dnd'],
  'arguments': {
    'operations': [
      {
        'handler': 'device.root.dnd.set',
        'args': {'mode': mode},
      },
    ],
  },
  'root_dnd_operations': [
    {
      'handler': 'device.root.dnd.set',
      'args': {'mode': mode},
    },
  ],
};

Future<ToolApprovalService> _pumpApproval(
  WidgetTester tester, {
  required bool showToolCards,
  required Map<String, dynamic> pendingArguments,
  String? partToolName,
  String? pendingToolName,
  Map<String, dynamic> modelArguments = const {},
  Locale locale = const Locale('en'),
  double width = 400,
  double textScale = 1,
}) async {
  final preferences = createBusinessTestPreferences();
  final settings = SettingsProvider(preferences);
  final tts = TtsProvider(preferences: preferences);
  final approvals = ToolApprovalService();
  addTearDown(settings.dispose);
  addTearDown(tts.dispose);
  addTearDown(approvals.dispose);
  await settings.loaded;
  await settings.setShowToolResultSummary(false);
  await settings.setShowToolCards(showToolCards);
  approvals.requestApproval(
    toolCallId: 'dnd',
    toolName: pendingToolName ?? _actionName,
    conversationId: 'chat',
    arguments: pendingArguments,
  );
  addTearDown(() {
    approvals.deny('dnd', conversationId: 'chat');
  });
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ChangeNotifierProvider<TtsProvider>.value(value: tts),
        ChangeNotifierProvider<ToolApprovalService>.value(value: approvals),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: SingleChildScrollView(
                  child: ChatMessageWidget(
                    message: ChatMessage(
                      id: 'reply',
                      conversationId: 'chat',
                      role: 'assistant',
                      content: '',
                    ),
                    showModelIcon: false,
                    toolParts: [
                      ToolUIPart(
                        id: 'dnd',
                        toolName: partToolName ?? _actionName,
                        arguments: modelArguments,
                        loading: true,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return approvals;
}

void main() {
  final en = AppLocalizationsEn();
  final modes = {
    'all': en.phonePanelDndAll,
    'priority': en.phonePanelDndPriority,
    'alarms': en.phonePanelDndAlarms,
    'none': en.phonePanelDndNone,
  };
  for (final showToolCards in [false, true]) {
    for (final mode in modes.entries) {
      testWidgets(
        'root DND preset consent shows ${mode.key} with summaries hidden (cards: $showToolCards)',
        (tester) async {
          final approvals = await _pumpApproval(
            tester,
            showToolCards: showToolCards,
            pendingArguments: _rootDndArguments(mode.key),
          );
          expect(find.text(en.miniAppsNativeRootWarning), findsOneWidget);
          expect(
            find.text('${en.phonePanelDnd}: ${mode.value}'),
            findsOneWidget,
          );
          expect(find.textContaining('Always allow'), findsNothing);
          expect(find.byTooltip('Always allow'), findsNothing);
          expect(approvals.pendingRequests, hasLength(1));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        },
      );
    }

    testWidgets(
      'mini_apps invoke consent uses selected host operations, not model JSON or version (cards: $showToolCards)',
      (tester) async {
        final ru = AppLocalizationsRu();
        await _pumpApproval(
          tester,
          showToolCards: showToolCards,
          pendingArguments: _rootDndArguments('alarms'),
          partToolName: 'mini_apps',
          modelArguments: {
            'action': 'invoke',
            'app_id': 'focus',
            'action_name': 'start',
            'arguments': jsonEncode({'mode': 'none'}),
            'version': jsonEncode(_rootDndArguments('all')),
          },
          locale: const Locale('ru'),
          width: 320,
          textScale: 1.3,
        );
        expect(find.text(ru.miniAppsNativeRootWarning), findsOneWidget);
        expect(
          find.text('${ru.phonePanelDnd}: ${ru.phonePanelDndAlarms}'),
          findsOneWidget,
        );
        expect(
          find.text('${ru.phonePanelDnd}: ${ru.phonePanelDndNone}'),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );

    testWidgets(
      'ordinary DND does not show a root warning for model supplied operations (cards: $showToolCards)',
      (tester) async {
        final arguments = _rootDndArguments('none')
          ..remove('root_dnd_operations')
          ..['danger'] = 'write'
          ..['permissions'] = ['device.audio.write'];
        await _pumpApproval(
          tester,
          showToolCards: showToolCards,
          pendingArguments: arguments,
          modelArguments: _rootDndArguments('none'),
        );
        expect(find.text(en.miniAppsNativeRootWarning), findsNothing);
        expect(
          find.text('${en.phonePanelDnd}: ${en.phonePanelDndNone}'),
          findsNothing,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }
}
