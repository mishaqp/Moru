import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/models/conversation.dart';
import 'package:Kelivo/core/models/spend_limits.dart';
import 'package:Kelivo/core/models/token_usage.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/providers/tts_provider.dart';
import 'package:Kelivo/core/services/chat/chat_service.dart';
import 'package:Kelivo/features/chat/widgets/chat_message_widget.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/features/home/services/spend_control_service.dart';
import 'package:Kelivo/features/home/widgets/spend_warning_hint.dart';
import 'package:Kelivo/features/stats/widgets/spend_limits_settings.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import '../../../support/business_test_harness.dart';

class _UsageChats extends ChatService {
  int tokens = 79;
  int cached = 0;
  int output = 0;
  @override
  String? get currentConversationId => 'chat';
  int revision = 0;
  @override
  int get statisticsRevision => revision + super.statisticsRevision;
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
      completionTokens: output,
      cachedTokens: cached,
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
    'completed round refreshes the composer before the reply finishes',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 800);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final settings = SettingsProvider(createBusinessTestPreferences());
      final chats = _UsageChats()
        ..tokens = 72
        ..cached = 54;
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
      final service = SpendControlService(chats: chats, settings: settings);
      final session = service.beginResponse(
        message: ChatMessage(
          id: 'live-round',
          role: 'assistant',
          content: '',
          conversationId: 'chat',
          isStreaming: true,
        ),
        stopMessage: 'Reply stopped',
        onRoundCompleted: chats.notifySpendUsageChanged,
      );
      addTearDown(() => service.endResponse(session));
      final revisionBefore = chats.statisticsRevision;
      session.control.recordInitialUsage(
        const TokenUsage(promptTokens: 8, cachedTokens: 6),
      );
      await tester.pump();
      await tester.pump();
      expect(chats.statisticsRevision, revisionBefore + 1);
      final hint = find.textContaining('Budget warning');
      expect(hint, findsOneWidget);
      expect(find.textContaining('20 tokens left · Cache 75%'), findsOneWidget);
      expect(tester.getSize(hint).height, lessThan(24));
      final status = await service.status('chat', includeContext: false);
      expect(
        status.toJson()['current_response'],
        containsPair('completed_requests', 1),
      );
      expect(
        status.toJson()['current_response'],
        containsPair('accounting', 'partial'),
      );
      expect(session.baseline.isStreaming, isTrue);
      expect(tester.takeException(), isNull);
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

  for (final layout in [
    (width: 800.0, scale: 1.0, showCache: true),
    (width: 240.0, scale: 1.0, showCache: false),
    (width: 320.0, scale: 1.3, showCache: false),
  ]) {
    testWidgets('cache share keeps composer and limit labels stable '
        '(width=${layout.width}, scale=${layout.scale})', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(layout.width, 1400);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final settings = SettingsProvider(createBusinessTestPreferences());
      final chats = _UsageChats()
        ..tokens = 80
        ..output = 20
        ..cached = 60;
      addTearDown(settings.dispose);
      addTearDown(chats.dispose);
      await settings.loaded;
      await settings.setSpendLimits(const SpendLimits(chatTokens: 125));
      Widget surface(Widget child, {bool withChats = true}) => MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          if (withChats)
            ChangeNotifierProvider<ChatService>.value(value: chats),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(layout.scale)),
            child: child!,
          ),
          home: Scaffold(body: child),
        ),
      );
      await tester.pumpWidget(
        surface(const SpendWarningHint(conversationId: 'chat')),
      );
      await tester.pump();
      final warning = find.textContaining('Budget warning');
      expect(warning, findsOneWidget);
      expect(find.textContaining('25 tokens left'), findsOneWidget);
      expect(
        find.textContaining('Cache 75%'),
        layout.showCache ? findsOneWidget : findsNothing,
      );
      final warningHeight = tester.getSize(warning).height;
      chats.cached = 0;
      chats.setTokens(0);
      chats.output = 100;
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Cache'), findsNothing);
      expect(tester.getSize(warning).height, warningHeight);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(
        surface(SpendLimitsSettings(settings: settings), withChats: false),
      );
      await tester.pump();
      final field = find.byKey(const ValueKey('spend-chat_tokens'));
      final fieldBefore = tester.getRect(field);
      chats.tokens = 80;
      chats.output = 20;
      chats.cached = 60;
      await tester.pumpWidget(surface(SpendLimitsSettings(settings: settings)));
      await tester.pump();
      await tester.pump();
      expect(
        find.textContaining('Per chat · tokens · Cache 75%'),
        layout.showCache ? findsOneWidget : findsNothing,
      );
      expect(
        find.textContaining('Per day · tokens · Cache 75%'),
        layout.showCache ? findsOneWidget : findsNothing,
      );
      expect(tester.getRect(field), fieldBefore);
      chats.cached = 40;
      chats.setTokens(80);
      await tester.pump();
      await tester.pump();
      expect(
        find.textContaining('Per chat · tokens · Cache 50%'),
        layout.showCache ? findsOneWidget : findsNothing,
      );
      expect(tester.getRect(field), fieldBefore);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }

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
