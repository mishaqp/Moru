import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/models/conversation.dart';
import 'package:Kelivo/core/models/spend_limits.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/providers/tts_provider.dart';
import 'package:Kelivo/core/services/chat/chat_service.dart';
import 'package:Kelivo/features/chat/widgets/chat_message_widget.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/features/home/widgets/spend_warning_hint.dart';
import 'package:Kelivo/features/stats/widgets/spend_limits_settings.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import '../../../support/business_test_harness.dart';

class _UsageChats extends ChatService {
  int tokens = 79;
  int revision = 0;
  @override
  int get statisticsRevision => revision;
  void setTokens(int value) {
    tokens = value;
    revision++;
    notifyListeners();
  }

  @override
  Conversation? getConversation(String id) =>
      Conversation(id: id, title: 'Chat');
  @override
  Future<List<ChatMessage>> loadSpendMessages({
    String? conversationId,
    DateTime? start,
    DateTime? endExclusive,
  }) async => [
    ChatMessage(
      role: 'assistant',
      content: '',
      conversationId: conversationId ?? 'chat',
      promptTokens: tokens,
      completionTokens: 0,
    ),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Widget app(Widget child) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  testWidgets(
    'composer hint appears at threshold and distinguishes optional hard stop',
    (tester) async {
      final settings = SettingsProvider(createBusinessTestPreferences());
      final chats = _UsageChats();
      addTearDown(settings.dispose);
      addTearDown(chats.dispose);
      await settings.loaded;
      await settings.setSpendLimits(const SpendLimits(chatTokens: 100));
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsProvider>.value(value: settings),
            ChangeNotifierProvider<ChatService>.value(value: chats),
          ],
          child: app(const SpendWarningHint(conversationId: 'chat')),
        ),
      );
      await tester.pump();
      expect(find.textContaining('Budget warning'), findsNothing);
      chats.setTokens(80);
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('20 tokens'), findsOneWidget);
      chats.setTokens(100);
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Budget reached'), findsOneWidget);
      expect(find.textContaining('Spending limit reached.'), findsNothing);
      await settings.setSpendLimits(
        const SpendLimits(chatTokens: 100, hardStop: true),
      );
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Spending limit reached.'), findsOneWidget);
      await settings.setSpendLimits(const SpendLimits());
      await tester.pump();
      expect(find.textContaining('Spending limit'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'limit editor saves dollars and tokens and rejects fractional tokens',
    (tester) async {
      final settings = SettingsProvider(createBusinessTestPreferences());
      addTearDown(settings.dispose);
      await settings.loaded;
      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsProvider>.value(
          value: settings,
          child: app(
            Builder(
              builder: (context) => TextButton(
                onPressed: () => showSpendLimitsSettings(context),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      Finder field(String key) => find.descendant(
        of: find.byKey(ValueKey('spend-$key')),
        matching: find.byType(TextField),
      );
      await tester.enterText(field('chat_usd'), '0,5');
      await tester.enterText(field('daily_tokens'), '10.5');
      await tester.scrollUntilVisible(
        find.byType(FilledButton),
        150,
        scrollable: find
            .descendant(
              of: find.byType(SpendLimitsSettings),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(settings.spendLimits.enabled, isFalse);
      expect(
        find.textContaining('Token limits need whole numbers'),
        findsOneWidget,
      );
      await tester.ensureVisible(field('daily_tokens'));
      await tester.enterText(field('daily_tokens'), '10000');
      await tester.scrollUntilVisible(
        find.byType(FilledButton),
        150,
        scrollable: find
            .descendant(
              of: find.byType(SpendLimitsSettings),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.byType(FilledButton));
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      expect(settings.spendLimits.chatUsd, 0.5);
      expect(settings.spendLimits.dailyTokens, 10000);
      expect(settings.spendLimits.warningPercent, 80);
      expect(settings.spendLimits.hardStop, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  for (final summary in [false, true]) {
    for (final action in ['compact', 'set_limits']) {
      testWidgets(
        '$action approval shows readable details without Always (summary=$summary)',
        (tester) async {
          final preferences = createBusinessTestPreferences();
          final settings = SettingsProvider(preferences);
          final tts = TtsProvider(preferences: preferences);
          final approvals = ToolApprovalService();
          addTearDown(settings.dispose);
          addTearDown(tts.dispose);
          addTearDown(approvals.dispose);
          await settings.loaded;
          await settings.setShowToolResultSummary(summary);
          final args = {
            'action': action,
            if (action == 'set_limits') 'clear': ['chat_tokens'],
            if (action == 'set_limits')
              'limits': {
                'chat_usd': 0.5,
                'daily_tokens': 10000,
                'hard_stop': true,
              },
          };
          final pending = approvals.requestApproval(
            toolCallId: 'spend',
            toolName: 'spend_control',
            arguments: args,
            conversationId: 'chat',
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
              child: app(
                SingleChildScrollView(
                  child: ChatMessageWidget(
                    message: ChatMessage(
                      id: 'reply',
                      role: 'assistant',
                      content: '',
                      conversationId: 'chat',
                    ),
                    showModelIcon: false,
                    toolParts: [
                      ToolUIPart(
                        id: 'spend',
                        toolName: 'spend_control',
                        arguments: args,
                        loading: true,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          if (action == 'compact') {
            expect(
              find.textContaining('Compression creates a new chat'),
              findsOneWidget,
            );
          } else {
            expect(find.text('Per chat · USD: 0.5'), findsOneWidget);
            expect(find.text('Per day · tokens: 10000'), findsOneWidget);
            expect(find.text('Hard stop: Enabled'), findsOneWidget);
            expect(find.text('Per chat · tokens: Off'), findsOneWidget);
          }
          expect(find.textContaining('Always allow'), findsNothing);
          expect(find.byTooltip('Always allow'), findsNothing);
          expect(approvals.pendingRequests, hasLength(1));
          approvals.deny('spend', conversationId: 'chat');
          expect((await pending).approved, isFalse);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        },
      );
    }
  }
}
