import 'dart:async';

import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/providers/tts_provider.dart';
import 'package:Kelivo/core/providers/user_provider.dart';
import 'package:Kelivo/core/services/chat/chat_service.dart';
import 'package:Kelivo/features/chat/utils/chat_ui_work.dart';
import 'package:Kelivo/features/chat/widgets/chat_message_widget.dart';
import 'package:Kelivo/features/chat/widgets/message_more_sheet.dart';
import 'package:Kelivo/features/home/controllers/stream_controller.dart'
    as stream_ctrl;
import 'package:Kelivo/features/home/services/ask_user_interaction_service.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/features/home/widgets/message_list_view.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import '../../../support/business_test_harness.dart';
import '../../../support/long_chat_harness.dart';
import '../../../support/send_long_chat_harness.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    installLongChatPlatformStubs();
    const background = MethodChannel('app.mobile_background');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(background, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(background, null));
    addTearDown(() => ChatUiWork.debugObserver = null);
  });

  testWidgets('sending into a capped real window retains unchanged rows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2100);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final environment = (await tester.runAsync(
      () => SendLongChatEnvironment.create(rounds: 200),
    ))!;
    final key = GlobalKey<SendLongChatHarnessState>();
    try {
      await tester.pumpWidget(environment.app(key: key));
      final state = key.currentState!;
      await tester.runAsync(state.open);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        state.controller.messages,
        hasLength(ChatService.defaultLoadedWindowMax),
      );
      final previousFirst = state.controller.messages.first.id;
      const retainedId = 'user-199';
      final before = _row(tester, retainedId);
      final beforeIndex = state.controller.messages.indexWhere(
        (message) => message.id == retainedId,
      );
      var retainedBuilds = 0;
      ChatUiWork.debugObserver = (name, id, _) {
        if (name == 'message.build' && id == retainedId) retainedBuilds++;
      };
      environment.responseHold = Completer<void>();
      await tester.enterText(find.byType(TextField).first, 'Continue.');
      await tester.pump();
      final send = tester.widget<InkWell>(
        find
            .ancestor(
              of: find.byKey(const ValueKey('send')),
              matching: find.byType(InkWell),
            )
            .first,
      );
      await tester.runAsync(() async => send.onTap!());
      await _driveUntil(tester, () => environment.requests.isNotEmpty);
      expect(
        state.controller.messages,
        hasLength(ChatService.defaultLoadedWindowMax),
      );
      expect(state.controller.messages.first.id, isNot(previousFirst));
      expect(
        state.controller.messages.indexWhere(
          (message) => message.id == retainedId,
        ),
        beforeIndex - 2,
      );
      expect(
        _row(tester, retainedId),
        same(before),
        reason: 'A window-relative index shift does not change this row.',
      );
      expect(retainedBuilds, 0);
    } finally {
      ChatUiWork.debugObserver = null;
      await tester.runAsync(() async => environment.releaseResponse());
      if (key.currentState != null) {
        await _driveUntil(
          tester,
          () => !key.currentState!.controller.isCurrentConversationLoading,
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.runAsync(environment.close);
    }
  });

  for (final action in [
    MessageMoreAction.share,
    MessageMoreAction.selectMessages,
  ]) {
    testWidgets('${action.name} resolves the retained row index after shifts', (
      tester,
    ) async {
      final key = GlobalKey<_RowCacheHarnessState>();
      await tester.pumpWidget(_RowCacheHarness(key: key));
      await tester.pumpAndSettle();
      final state = key.currentState!;
      final retained = _row(tester, 'message-5');
      state.appendPair();
      await tester.pumpAndSettle();
      expect(_row(tester, 'message-5'), same(retained));
      await _chooseAction(tester, retained, action);
      expect(state.actions, [(action, 3, 'message-5')]);

      state.remove('message-3');
      await tester.pumpAndSettle();
      expect(_row(tester, 'message-5'), same(retained));
      await _chooseAction(tester, retained, action);
      expect(state.actions.last, (action, 2, 'message-5'));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('${action.name} ignores a row removed while its menu is open', (
      tester,
    ) async {
      final key = GlobalKey<_RowCacheHarnessState>();
      await tester.pumpWidget(_RowCacheHarness(key: key));
      await tester.pumpAndSettle();
      final state = key.currentState!;
      _row(tester, 'message-5').onMore!();
      await tester.pumpAndSettle();
      state.remove('message-5');
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(MessageListView))).pop(action);
      await tester.pumpAndSettle();
      expect(state.actions, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }

  testWidgets('version and presentation changes invalidate a retained row', (
    tester,
  ) async {
    final key = GlobalKey<_RowCacheHarnessState>();
    await tester.pumpWidget(_RowCacheHarness(key: key));
    await tester.pumpAndSettle();
    final state = key.currentState!;
    final before = _row(tester, 'message-5');
    // A menu opened for the old version must not act on the replacement.
    before.onMore!();
    await tester.pumpAndSettle();
    state.replaceVersion('message-5');
    await tester.pumpAndSettle();
    Navigator.of(
      tester.element(find.byType(MessageListView)),
    ).pop(MessageMoreAction.share);
    await tester.pumpAndSettle();
    expect(state.actions, isEmpty);
    state.listController.jumpToItem(
      index: 5,
      scrollController: state.scrollController,
      alignment: 1,
    );
    await tester.pumpAndSettle();
    final version = _row(tester, 'message-5-v1');
    expect(version, isNot(same(before)));
    expect(version.message.content, 'Revised answer');
    expect(version.versionIndex, 1);
    expect(version.versionCount, 2);
    expect(
      find.textContaining('Revised answer', findRichText: true),
      findsOneWidget,
    );
    await _chooseAction(tester, version, MessageMoreAction.share);
    expect(state.actions.single, (MessageMoreAction.share, 5, 'message-5-v1'));

    state.toggleTokenStats();
    await tester.pumpAndSettle();
    final presentation = _row(tester, 'message-5-v1');
    expect(presentation, isNot(same(version)));
    expect(presentation.showTokenStats, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

ChatMessageWidget _row(WidgetTester tester, String id) =>
    tester.widget<ChatMessageWidget>(
      find.byWidgetPredicate(
        (widget) => widget is ChatMessageWidget && widget.message.id == id,
        skipOffstage: false,
      ),
    );

Future<void> _chooseAction(
  WidgetTester tester,
  ChatMessageWidget row,
  MessageMoreAction action,
) async {
  row.onMore!();
  await tester.pumpAndSettle();
  Navigator.of(tester.element(find.byType(MessageListView))).pop(action);
  await tester.pumpAndSettle();
}

Future<void> _driveUntil(WidgetTester tester, bool Function() done) async {
  for (var attempts = 0; attempts < 300 && !done(); attempts++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(done(), isTrue, reason: 'The real send must finish its async stage.');
}

class _RowCacheHarness extends StatefulWidget {
  const _RowCacheHarness({super.key});

  @override
  State<_RowCacheHarness> createState() => _RowCacheHarnessState();
}

class _RowCacheHarnessState extends State<_RowCacheHarness> {
  final scrollController = ScrollController();
  final listController = ListController();
  final processingFiles = ValueNotifier<String?>(null);
  final actions = <(MessageMoreAction, int, String)>[];
  late List<ChatMessage> messages = List.generate(
    6,
    (index) => ChatMessage(
      id: 'message-$index',
      role: index.isEven ? 'user' : 'assistant',
      content: 'Message $index',
      conversationId: 'row-cache',
    ),
  );
  final versions = <String, List<ChatMessage>>{};
  final versionSelections = <String, int>{};
  bool showTokenStats = false;

  void appendPair() => setState(() {
    messages = [
      ...messages.skip(2),
      ChatMessage(
        id: 'new-user',
        role: 'user',
        content: 'New question',
        conversationId: 'row-cache',
      ),
      ChatMessage(
        id: 'new-assistant',
        role: 'assistant',
        content: 'New answer',
        conversationId: 'row-cache',
      ),
    ];
  });

  void remove(String id) => setState(() {
    messages = messages.where((message) => message.id != id).toList();
  });

  void replaceVersion(String id) => setState(() {
    final index = messages.indexWhere((message) => message.id == id);
    final original = messages[index];
    final replacement = original.copyWith(
      id: '$id-v1',
      version: 1,
      content: 'Revised answer',
    );
    messages = [...messages]..[index] = replacement;
    versions[original.groupId!] = [original, replacement];
    versionSelections[original.groupId!] = 1;
  });

  void toggleTokenStats() => setState(() => showTokenStats = !showTokenStats);

  void record(MessageMoreAction action, int index, List<ChatMessage> current) =>
      actions.add((action, index, current[index].id));

  @override
  Widget build(BuildContext context) => MultiProvider(
    providers: [
      ChangeNotifierProvider(
        create: (_) => SettingsProvider(createBusinessTestPreferences()),
      ),
      ChangeNotifierProvider(
        create: (_) =>
            AssistantProvider(preferences: createBusinessTestPreferences()),
      ),
      ChangeNotifierProvider(
        create: (_) =>
            UserProvider(preferences: createBusinessTestPreferences()),
      ),
      ChangeNotifierProvider(
        create: (_) =>
            TtsProvider(preferences: createBusinessTestPreferences()),
      ),
      ChangeNotifierProvider(create: (_) => AskUserInteractionService()),
      ChangeNotifierProvider(create: (_) => ToolApprovalService()),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: MessageListView(
          scrollController: scrollController,
          listController: listController,
          messages: messages,
          byGroup: versions,
          versionSelections: versionSelections,
          reasoning: const <String, stream_ctrl.ReasoningData>{},
          reasoningSegments:
              const <String, List<stream_ctrl.ReasoningSegmentData>>{},
          contentSplits: const <String, stream_ctrl.ContentSplitData>{},
          toolParts: const {},
          translations: const {},
          selecting: false,
          selectedItems: const {},
          dividerPadding: EdgeInsets.zero,
          showTokenStats: showTokenStats,
          processingFilesMessageId: processingFiles,
          onShareMessage: (index, messages) =>
              record(MessageMoreAction.share, index, messages),
          onSelectMessages: (index, messages) =>
              record(MessageMoreAction.selectMessages, index, messages),
        ),
      ),
    ),
  );

  @override
  void dispose() {
    scrollController.dispose();
    listController.dispose();
    processingFiles.dispose();
    super.dispose();
  }
}
