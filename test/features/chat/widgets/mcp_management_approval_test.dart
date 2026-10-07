import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/providers/tts_provider.dart';
import 'package:Kelivo/features/chat/widgets/chat_message_widget.dart';
import 'package:Kelivo/features/chat/widgets/mcp_management_approval.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

import '../../../support/business_test_harness.dart';

void main() {
  for (final showToolCards in [false, true]) {
    for (final trustMode in ['ordinary', 'trusted', 'toggle']) {
      testWidgets(
        'MCP approval privately collects secrets without Always (cards: $showToolCards, trust: $trustMode)',
        (tester) async {
          final preferences = createBusinessTestPreferences();
          final settings = SettingsProvider(preferences);
          final tts = TtsProvider(preferences: preferences);
          final approvals = ToolApprovalService();
          if (trustMode == 'trusted') approvals.setAutoApproveAll(true);
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
          final details = trustMode == 'trusted'
              ? findsNothing
              : findsOneWidget;
          expect(find.textContaining('Private fixture'), details);
          expect(find.textContaining('STDIO'), details);
          expect(find.textContaining('server.js'), details);
          expect(
            find.textContaining('MEMORY_FILE_PATH=/workspace/x.json'),
            details,
          );
          expect(find.textContaining('Всегда разрешать'), findsNothing);
          expect(find.byTooltip('Всегда разрешать'), findsNothing);
          if (trustMode == 'trusted') {
            expect(find.text('Сохранить'), findsOneWidget);
            expect(find.text('Отмена'), findsOneWidget);
            expect(find.text('Разрешить'), findsNothing);
            expect(find.textContaining('Private fixture'), findsNothing);
            expect(find.text('Запретить'), findsNothing);
            expect(find.text('Ожидание подтверждения'), findsNothing);
          }
          final fields = find.byType(TextField);
          expect(fields, findsNWidgets(2));
          for (final field in tester.widgetList<TextField>(fields)) {
            expect(field.obscureText, isTrue);
            expect(field.enableSuggestions, isFalse);
          }
          await tester.enterText(fields.at(0), 'PRIVATE_INPUT');
          await tester.enterText(fields.at(1), 'Bearer PRIVATE_INPUT');
          await tester.pump();
          if (trustMode == 'toggle') {
            approvals.setAutoApproveAll(true);
            await tester.pump();
            expect(find.text('Сохранить'), findsOneWidget);
            expect(find.text('Отмена'), findsOneWidget);
            expect(find.text('Разрешить'), findsNothing);
            final inputs = tester.widgetList<TextField>(fields).toList();
            expect(inputs[0].controller!.text, 'PRIVATE_INPUT');
            expect(inputs[1].controller!.text, 'Bearer PRIVATE_INPUT');
            approvals.setAutoApproveAll(false);
            await tester.pump();
            expect(find.text('Разрешить'), findsOneWidget);
            expect(find.text('Сохранить'), findsNothing);
            approvals.setAutoApproveAll(true);
            await tester.pump();
          }
          expect(
            approvals.pendingRequests.single.arguments.toString(),
            isNot(contains('PRIVATE_INPUT')),
          );
          final saveLabel = trustMode == 'ordinary' ? 'Разрешить' : 'Сохранить';
          await tester.ensureVisible(find.text(saveLabel).last);
          await tester.tap(find.text(saveLabel).last);
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

  testWidgets(
    'input-only Cancel discards private values without a denial dialog',
    (tester) async {
      final approvals = ToolApprovalService()..setAutoApproveAll(true);
      addTearDown(approvals.dispose);
      final pending = approvals.requestApproval(
        toolCallId: 'mcp',
        toolName: 'manage_mcp',
        conversationId: 'chat',
        arguments: const {'action': 'add'},
        secretFields: const ['env:API_KEY'],
        secretInputOnly: true,
      );
      var denialDialogOpened = false;
      await tester.pumpWidget(
        ChangeNotifierProvider<ToolApprovalService>.value(
          value: approvals,
          child: MaterialApp(
            locale: const Locale('ru'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: McpManagementApproval(
                request: approvals.pendingRequests.single,
                onDeny: () => denialDialogOpened = true,
              ),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'PRIVATE_INPUT');
      await tester.tap(find.text('Отмена'));
      await tester.pump();
      final result = await pending;
      expect(result.approved, isFalse);
      expect(result.denyReason, 'cancelled');
      expect(result.takeSecretValues(), isEmpty);
      expect(denialDialogOpened, isFalse);
      expect(approvals.pendingRequests, isEmpty);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  final cases = <String, ({Map<String, dynamic> arguments, List<String> text})>{
    'select': (
      arguments: {
        'assistant_id': 'assistant-id',
        'assistant_name': 'My assistant',
      },
      text: ['Select MCP server for assistant', 'Assistant Name: My assistant'],
    ),
    'unselect': (
      arguments: {'assistant_id': 'assistant-id'},
      text: [
        'Unselect MCP server for assistant',
        'Assistant Name: assistant-id',
      ],
    ),
    'set_tool': (
      arguments: {
        'tool_settings': {
          'name': 'search',
          'enabled': false,
          'needs_approval': true,
        },
      },
      text: [
        'Configure MCP tool',
        'Tools: search',
        'Disabled',
        'Require approval: Yes',
      ],
    ),
    'set_timeout': (
      arguments: {'timeout_seconds': 45},
      text: ['Tool call timeout', 'Tool call timeout (seconds): 45'],
    ),
    'refresh': (arguments: {}, text: ['Sync Tools']),
    'reconnect': (arguments: {}, text: ['Reconnect']),
    'import': (
      arguments: {
        'servers': [
          {'name': 'Imported one', 'type': 'stdio', 'enabled': true},
          {'name': 'Imported two', 'type': 'http', 'enabled': false},
        ],
      },
      text: ['Import', 'Imported one · STDIO', 'Imported two · HTTP'],
    ),
  };
  for (final entry in cases.entries) {
    testWidgets('ordinary consent describes MCP ${entry.key}', (tester) async {
      final approvals = ToolApprovalService();
      addTearDown(approvals.dispose);
      final pending = approvals.requestApproval(
        toolCallId: 'mcp',
        toolName: 'manage_mcp',
        conversationId: 'chat',
        arguments: {'action': entry.key, ...entry.value.arguments},
      );
      await tester.pumpWidget(
        ChangeNotifierProvider<ToolApprovalService>.value(
          value: approvals,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: McpManagementApproval(
                request: approvals.pendingRequests.single,
                onDeny: () => approvals.deny('mcp', conversationId: 'chat'),
              ),
            ),
          ),
        ),
      );
      expect(find.text(entry.value.text.first), findsOneWidget);
      for (final text in entry.value.text.skip(1)) {
        expect(find.textContaining(text), findsOneWidget);
      }
      expect(find.text('Approve'), findsOneWidget);
      expect(find.text('Save'), findsNothing);
      await tester.tap(find.text('Approve'));
      await tester.pump();
      expect((await pending).approved, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
