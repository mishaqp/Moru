import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/providers/tts_provider.dart';
import 'package:Kelivo/features/chat/widgets/chat_message_widget.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

import '../../../support/business_test_harness.dart';

void main() {
  for (final showToolCards in [false, true]) {
    testWidgets(
      'MCP approval privately collects secrets without Always (cards visible: $showToolCards)',
      (tester) async {
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
        final pending = approvals.requestApproval(
          toolCallId: 'mcp',
          toolName: 'manage_mcp',
          conversationId: 'chat',
          arguments: {
            'action': 'add',
            'server': {
              'name': 'Private fixture',
              'type': 'stdio',
              'enabled': true,
              'command': 'node',
              'args': ['server.js'],
              'env': {
                'API_KEY': {'value_set': false},
                'MEMORY_FILE_PATH': {
                  'value_set': true,
                  'value': '/workspace/x.json',
                },
              },
              'headers': {
                'Authorization': {'value_set': false},
              },
            },
          },
          secretFields: ['env:API_KEY', 'header:Authorization'],
        );
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<SettingsProvider>.value(value: settings),
              ChangeNotifierProvider<TtsProvider>.value(value: tts),
              ChangeNotifierProvider<ToolApprovalService>.value(
                value: approvals,
              ),
            ],
            child: MaterialApp(
              locale: const Locale('ru'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: SingleChildScrollView(
                  child: ChatMessageWidget(
                    message: ChatMessage(
                      id: 'reply',
                      conversationId: 'chat',
                      role: 'assistant',
                      content: '',
                    ),
                    showModelIcon: false,
                    toolParts: const [
                      ToolUIPart(
                        id: 'mcp',
                        toolName: 'manage_mcp',
                        arguments: {'action': 'add'},
                        loading: true,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.textContaining('Private fixture'), findsOneWidget);
        expect(find.textContaining('STDIO'), findsOneWidget);
        expect(find.textContaining('server.js'), findsOneWidget);
        expect(
          find.textContaining('MEMORY_FILE_PATH=/workspace/x.json'),
          findsOneWidget,
        );
        expect(find.textContaining('Всегда разрешать'), findsNothing);
        expect(find.byTooltip('Всегда разрешать'), findsNothing);
        final fields = find.byType(TextField);
        expect(fields, findsNWidgets(2));
        for (final field in tester.widgetList<TextField>(fields)) {
          expect(field.obscureText, isTrue);
          expect(field.enableSuggestions, isFalse);
        }
        await tester.enterText(fields.at(0), 'PRIVATE_INPUT');
        await tester.enterText(fields.at(1), 'Bearer PRIVATE_INPUT');
        await tester.pump();
        expect(
          approvals.pendingRequests.single.arguments.toString(),
          isNot(contains('PRIVATE_INPUT')),
        );
        await tester.ensureVisible(find.text('Разрешить').last);
        await tester.tap(find.text('Разрешить').last);
        await tester.pump();
        expect(approvals.pendingRequests, isEmpty);
        final result = await pending;
        expect(result.approved, isTrue);
        expect(result.takeSecretValues(), {
          'env:API_KEY': 'PRIVATE_INPUT',
          'header:Authorization': 'Bearer PRIVATE_INPUT',
        });
        expect(result.takeSecretValues(), isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }
}
