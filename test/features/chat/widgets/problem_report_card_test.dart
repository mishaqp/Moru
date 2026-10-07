import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/providers/tts_provider.dart';
import 'package:Kelivo/features/chat/widgets/chat_message_widget.dart';
import 'package:Kelivo/features/chat/widgets/problem_report_card.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/l10n/app_localizations_ru.dart';

import '../../../support/business_test_harness.dart';

const _name = 'moru-problem-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.zip';

void main() {
  testWidgets('report consent lists all contents without an Always option', (
    tester,
  ) async {
    final preferences = createBusinessTestPreferences();
    final settings = SettingsProvider(preferences);
    final tts = TtsProvider(preferences: preferences);
    final approvals = ToolApprovalService();
    addTearDown(settings.dispose);
    addTearDown(tts.dispose);
    addTearDown(approvals.dispose);
    await settings.loaded;
    await settings.setShowToolResultSummary(false);
    final pending = approvals.requestApproval(
      toolCallId: 'report',
      toolName: 'report_problem',
      arguments: {},
      conversationId: 'chat',
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<TtsProvider>.value(value: tts),
          ChangeNotifierProvider<ToolApprovalService>.value(value: approvals),
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
                    id: 'report',
                    toolName: 'report_problem',
                    arguments: {},
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
    expect(
      find.text(AppLocalizationsRu().problemReportConsent),
      findsOneWidget,
    );
    expect(find.textContaining('Всегда разрешать'), findsNothing);
    expect(find.byTooltip('Всегда разрешать'), findsNothing);
    expect(approvals.pendingRequests, hasLength(1));
    approvals.deny('report', conversationId: 'chat');
    expect((await pending).approved, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('a finished report offers Share even when summaries are hidden', (
    tester,
  ) async {
    final preferences = createBusinessTestPreferences();
    final settings = SettingsProvider(preferences);
    final tts = TtsProvider(preferences: preferences);
    final approvals = ToolApprovalService();
    addTearDown(settings.dispose);
    addTearDown(tts.dispose);
    addTearDown(approvals.dispose);
    await settings.loaded;
    await settings.setShowToolResultSummary(false);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<TtsProvider>.value(value: tts),
          ChangeNotifierProvider<ToolApprovalService>.value(value: approvals),
        ],
        child: MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ChatMessageWidget(
              message: ChatMessage(
                id: 'reply',
                conversationId: 'chat',
                role: 'assistant',
                content: '',
              ),
              showModelIcon: false,
              toolParts: [
                ToolUIPart(
                  id: 'report',
                  toolName: 'report_problem',
                  arguments: {},
                  loading: false,
                  content: jsonEncode({
                    'ok': true,
                    'name': _name,
                    'size_bytes': 2048,
                  }),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text(_name), findsOneWidget);
    expect(find.text('Поделиться'), findsOneWidget);
    expect(find.text('2.0 KB'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  test('forged paths and failed tool results cannot become share cards', () {
    for (final result in [
      {'ok': true, 'name': '../secret.zip', 'size_bytes': 1},
      {'ok': true, 'name': '/etc/passwd', 'size_bytes': 1},
      {'ok': false, 'name': _name, 'size_bytes': 1},
      {'ok': true, 'name': _name, 'size_bytes': 9999999},
    ]) {
      expect(ProblemReportCard.fromContent(jsonEncode(result)), isNull);
    }
  });
}
