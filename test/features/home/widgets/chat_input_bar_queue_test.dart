import "../../../support/business_test_harness.dart";
import 'package:Kelivo/core/models/chat_input_data.dart';
import 'package:Kelivo/features/home/utils/model_display_helper.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/features/home/widgets/chat_input_bar.dart';
import 'package:Kelivo/icons/lucide_adapter.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildHarness({
    required TextEditingController controller,
    required FocusNode focusNode,
    required Future<ChatInputSubmissionResult> Function(ChatInputData input)
    onSend,
    SettingsProvider? settingsProvider,
    AssistantProvider? assistantProvider,
    ChatInputBarController? mediaController,
    bool loading = false,
    List<QueuedChatInput> queuedInputs = const <QueuedChatInput>[],
    void Function(QueuedChatInput item)? onEditQueuedInput,
    void Function(String id)? onRemoveQueuedInput,
    String? conversationId,
    String? sendButtonTooltip,
    ThemeData? theme,
    bool backgroundImageActive = false,
    double inputBackgroundOpacityLight = 0.8236,
    double inputBackgroundOpacityDark = 0.7396,
  }) {
    final settings =
        settingsProvider ?? SettingsProvider(createBusinessTestPreferences());
    final assistants =
        assistantProvider ??
        AssistantProvider(preferences: createBusinessTestPreferences());
    // In the app, HomePage resolves the chat model (conversation override ->
    // assistant -> global default) and passes it down; mirror that here.
    final chatModel = resolveChatModel(
      settings,
      assistant: assistants.currentAssistant,
    );
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: assistants),
      ],
      child: MaterialApp(
        theme: theme,
        darkTheme: theme,
        themeMode: theme?.brightness == Brightness.dark
            ? ThemeMode.dark
            : ThemeMode.light,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ChatInputBar(
            chatModelProviderKey: chatModel.providerKey,
            chatModelId: chatModel.modelId,
            controller: controller,
            focusNode: focusNode,
            mediaController: mediaController,
            onSend: onSend,
            loading: loading,
            queuedInputs: queuedInputs,
            onEditQueuedInput: onEditQueuedInput,
            onRemoveQueuedInput: onRemoveQueuedInput,
            conversationId: conversationId,
            sendButtonTooltip: sendButtonTooltip,
            backgroundImageActive: backgroundImageActive,
            inputBackgroundOpacityLight: inputBackgroundOpacityLight,
            inputBackgroundOpacityDark: inputBackgroundOpacityDark,
          ),
        ),
      ),
    );
  }

  testWidgets('提交结果 queued 时会清空输入', (tester) async {
    final controller = TextEditingController(text: 'queued message');
    final focusNode = FocusNode();
    ChatInputData? submitted;

    await tester.pumpWidget(
      buildHarness(
        controller: controller,
        focusNode: focusNode,
        onSend: (input) async {
          submitted = input;
          return ChatInputSubmissionResult.queued;
        },
      ),
    );

    await tapSendButton(tester);

    expect(submitted?.text, 'queued message');
    expect(controller.text, isEmpty);

    controller.dispose();
    focusNode.dispose();
  });

  testWidgets('提交结果 rejected 时保留输入内容', (tester) async {
    final controller = TextEditingController(text: 'keep me');
    final focusNode = FocusNode();

    await tester.pumpWidget(
      buildHarness(
        controller: controller,
        focusNode: focusNode,
        onSend: (_) async => ChatInputSubmissionResult.rejected,
      ),
    );

    await tapSendButton(tester);

    expect(controller.text, 'keep me');

    controller.dispose();
    focusNode.dispose();
  });

  testWidgets('发送按钮可显示编辑态保存并发送提示', (tester) async {
    final controller = TextEditingController(text: 'edited message');
    final focusNode = FocusNode();

    await tester.pumpWidget(
      buildHarness(
        controller: controller,
        focusNode: focusNode,
        sendButtonTooltip: 'Save & Send',
        onSend: (_) async => ChatInputSubmissionResult.rejected,
      ),
    );

    expect(find.byTooltip('Save & Send'), findsOneWidget);

    controller.dispose();
    focusNode.dispose();
  });

  group('pending queue', () {
    QueuedChatInput queued(String id, String text) {
      return QueuedChatInput(
        id: id,
        conversationId: 'conversation-a',
        input: ChatInputData(text: text),
      );
    }

    testWidgets('lists every pending message in send order', (tester) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();

      await tester.pumpWidget(
        buildHarness(
          controller: controller,
          focusNode: focusNode,
          queuedInputs: [
            queued('queued-1', 'first follow-up'),
            queued('queued-2', 'second follow-up'),
            queued('queued-3', 'third follow-up'),
          ],
          onSend: (_) async => ChatInputSubmissionResult.rejected,
        ),
      );

      expect(find.text('Queued to send'), findsOneWidget);
      expect(find.text('first follow-up'), findsOneWidget);
      expect(find.text('second follow-up'), findsOneWidget);
      expect(find.text('third follow-up'), findsOneWidget);
      // Positions are 1-based and follow the send order.
      expect(find.text('1'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);

      controller.dispose();
      focusNode.dispose();
    });

    testWidgets('a long queue shows the newest items and the total count', (
      tester,
    ) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();

      await tester.pumpWidget(
        buildHarness(
          controller: controller,
          focusNode: focusNode,
          queuedInputs: [
            queued('queued-1', 'one'),
            queued('queued-2', 'two'),
            queued('queued-3', 'three'),
            queued('queued-4', 'four'),
          ],
          onSend: (_) async => ChatInputSubmissionResult.rejected,
        ),
      );

      expect(find.text('one'), findsNothing);
      expect(find.text('two'), findsOneWidget);
      expect(find.text('four'), findsOneWidget);
      // The total is only shown when the list is trimmed, and the position
      // numbers make a bare "4" ambiguous, so it is addressed by key.
      expect(find.byKey(const ValueKey('queued-input-count')), findsOneWidget);

      controller.dispose();
      focusNode.dispose();
    });

    testWidgets('each pending message can be edited', (tester) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();
      final edited = <String>[];

      await tester.pumpWidget(
        buildHarness(
          controller: controller,
          focusNode: focusNode,
          queuedInputs: [
            queued('queued-1', 'first follow-up'),
            queued('queued-2', 'second follow-up'),
          ],
          onEditQueuedInput: (item) => edited.add(item.id),
          onSend: (_) async => ChatInputSubmissionResult.rejected,
        ),
      );

      await tester.tap(find.byTooltip('Edit queued message').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit queued message').last);
      await tester.pumpAndSettle();

      expect(edited, ['queued-1', 'queued-2']);

      controller.dispose();
      focusNode.dispose();
    });

    testWidgets('each pending message can be removed', (tester) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();
      final removed = <String>[];

      await tester.pumpWidget(
        buildHarness(
          controller: controller,
          focusNode: focusNode,
          queuedInputs: [
            queued('queued-1', 'first follow-up'),
            queued('queued-2', 'second follow-up'),
          ],
          onRemoveQueuedInput: removed.add,
          onSend: (_) async => ChatInputSubmissionResult.rejected,
        ),
      );

      await tester.tap(find.byTooltip('Remove queued message').last);
      await tester.pumpAndSettle();

      expect(removed, ['queued-2']);

      controller.dispose();
      focusNode.dispose();
    });

    testWidgets('the composer stays editable while messages are pending', (
      tester,
    ) async {
      // The draft is set up front because the composer derives its send
      // button from the controller during build, exactly as in the app.
      final controller = TextEditingController(text: 'second follow-up');
      final focusNode = FocusNode();
      ChatInputData? submitted;

      await tester.pumpWidget(
        buildHarness(
          controller: controller,
          focusNode: focusNode,
          queuedInputs: [queued('queued-1', 'first follow-up')],
          onSend: (input) async {
            submitted = input;
            return ChatInputSubmissionResult.rejected;
          },
        ),
      );

      // Queueing another message must not require waiting for the first.
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.readOnly, isFalse);

      await tapSendButton(tester);

      expect(submitted?.text, 'second follow-up');

      controller.dispose();
      focusNode.dispose();
    });

    testWidgets('no panel is drawn without pending messages', (tester) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();

      await tester.pumpWidget(
        buildHarness(
          controller: controller,
          focusNode: focusNode,
          onSend: (_) async => ChatInputSubmissionResult.rejected,
        ),
      );

      expect(find.text('Queued to send'), findsNothing);
      expect(find.byTooltip('Edit queued message'), findsNothing);

      controller.dispose();
      focusNode.dispose();
    });
  });

  testWidgets('绘图模式胶囊可关闭并传递聊天接口路由', (tester) async {
    final controller = TextEditingController(text: 'draw a cat');
    final focusNode = FocusNode();
    final mediaController = ChatInputBarController();
    final settings = SettingsProvider(createBusinessTestPreferences());
    await settings.setProviderConfig(
      'OpenAITest',
      ProviderConfig(
        id: 'OpenAITest',
        enabled: true,
        name: 'OpenAITest',
        apiKey: 'test-key',
        baseUrl: 'https://example.com/v1',
        providerType: ProviderKind.openai,
      ),
    );
    await settings.setCurrentModel('OpenAITest', 'gpt-image-2');
    ChatInputData? submitted;

    await tester.pumpWidget(
      buildHarness(
        controller: controller,
        focusNode: focusNode,
        mediaController: mediaController,
        settingsProvider: settings,
        onSend: (input) async {
          submitted = input;
          return ChatInputSubmissionResult.rejected;
        },
      ),
    );

    expect(find.text('Image mode'), findsOneWidget);

    await tester.tap(find.byIcon(Lucide.X));
    await tester.pumpAndSettle();

    expect(find.text('Image mode'), findsNothing);
    expect(mediaController.allowImagesApiRouting, isFalse);

    await tapSendButton(tester);

    expect(submitted?.text, 'draw a cat');
    expect(submitted?.allowImagesApiRouting, isFalse);

    controller.dispose();
    focusNode.dispose();
  });

  testWidgets('绘图模式关闭后切换对话会重新显示', (tester) async {
    final controller = TextEditingController(text: 'draw a cat');
    final focusNode = FocusNode();
    final settings = SettingsProvider(createBusinessTestPreferences());
    await settings.setProviderConfig(
      'OpenAITest',
      ProviderConfig(
        id: 'OpenAITest',
        enabled: true,
        name: 'OpenAITest',
        apiKey: 'test-key',
        baseUrl: 'https://example.com/v1',
        providerType: ProviderKind.openai,
      ),
    );
    await settings.setCurrentModel('OpenAITest', 'gpt-image-2');

    await tester.pumpWidget(
      buildHarness(
        controller: controller,
        focusNode: focusNode,
        settingsProvider: settings,
        conversationId: 'conversation-a',
        onSend: (_) async => ChatInputSubmissionResult.rejected,
      ),
    );

    expect(find.text('Image mode'), findsOneWidget);

    await tester.tap(find.byIcon(Lucide.X));
    await tester.pumpAndSettle();

    expect(find.text('Image mode'), findsNothing);

    await tester.pumpWidget(
      buildHarness(
        controller: controller,
        focusNode: focusNode,
        settingsProvider: settings,
        conversationId: 'conversation-b',
        onSend: (_) async => ChatInputSubmissionResult.rejected,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Image mode'), findsOneWidget);

    controller.dispose();
    focusNode.dispose();
  });

  testWidgets('非绘图模型保持默认路由许可', (tester) async {
    final controller = TextEditingController(text: 'hello');
    final focusNode = FocusNode();
    ChatInputData? submitted;

    await tester.pumpWidget(
      buildHarness(
        controller: controller,
        focusNode: focusNode,
        onSend: (input) async {
          submitted = input;
          return ChatInputSubmissionResult.rejected;
        },
      ),
    );

    expect(find.text('Image mode'), findsNothing);

    await tapSendButton(tester);

    expect(submitted?.allowImagesApiRouting, isTrue);

    controller.dispose();
    focusNode.dispose();
  });

  testWidgets('输入框在亮色主题下有稳定底色', (tester) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();

    await tester.pumpWidget(
      buildHarness(
        controller: controller,
        focusNode: focusNode,
        theme: ThemeData.light(),
        onSend: (_) async => ChatInputSubmissionResult.rejected,
      ),
    );

    final decoration = _mainInputDecoration(tester);
    expect(decoration.color?.a, greaterThanOrEqualTo(0.70));

    controller.dispose();
    focusNode.dispose();
  });

  testWidgets('输入框在暗色主题下不是纯透明毛玻璃', (tester) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();

    await tester.pumpWidget(
      buildHarness(
        controller: controller,
        focusNode: focusNode,
        theme: ThemeData.dark(),
        onSend: (_) async => ChatInputSubmissionResult.rejected,
      ),
    );

    final decoration = _mainInputDecoration(tester);
    expect(decoration.color?.a, greaterThanOrEqualTo(0.60));

    controller.dispose();
    focusNode.dispose();
  });

  testWidgets('输入框在背景图模式下降低纯色覆盖', (tester) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();

    await tester.pumpWidget(
      buildHarness(
        controller: controller,
        focusNode: focusNode,
        theme: ThemeData.light(),
        backgroundImageActive: true,
        onSend: (_) async => ChatInputSubmissionResult.rejected,
      ),
    );

    final decoration = _mainInputDecoration(tester);
    expect(decoration.color?.a, inExclusiveRange(0.35, 0.70));

    controller.dispose();
    focusNode.dispose();
  });

  testWidgets('输入框背景透明度按当前主题选择实际 alpha', (tester) async {
    final lightController = TextEditingController();
    final lightFocusNode = FocusNode();

    await tester.pumpWidget(
      buildHarness(
        controller: lightController,
        focusNode: lightFocusNode,
        theme: ThemeData.light(),
        inputBackgroundOpacityLight: 0.35,
        inputBackgroundOpacityDark: 0.75,
        onSend: (_) async => ChatInputSubmissionResult.rejected,
      ),
    );

    final light = _mainInputDecoration(tester).color;
    expect(light?.a, closeTo(0.35, 0.0001));

    await tester.pumpWidget(const SizedBox.shrink());

    lightController.dispose();
    lightFocusNode.dispose();

    final darkController = TextEditingController();
    final darkFocusNode = FocusNode();

    await tester.pumpWidget(
      buildHarness(
        controller: darkController,
        focusNode: darkFocusNode,
        theme: ThemeData.dark(),
        inputBackgroundOpacityLight: 0.35,
        inputBackgroundOpacityDark: 0.75,
        onSend: (_) async => ChatInputSubmissionResult.rejected,
      ),
    );

    final dark = _mainInputDecoration(tester).color;
    expect(dark?.a, closeTo(0.75, 0.0001));

    darkController.dispose();
    darkFocusNode.dispose();
  });

  testWidgets('背景图模式同样遵循输入框背景透明度设置', (tester) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();

    await tester.pumpWidget(
      buildHarness(
        controller: controller,
        focusNode: focusNode,
        theme: ThemeData.dark(),
        backgroundImageActive: true,
        inputBackgroundOpacityDark: 0.7396,
        onSend: (_) async => ChatInputSubmissionResult.rejected,
      ),
    );

    final decoration = _mainInputDecoration(tester);
    expect(decoration.color?.a, closeTo(0.545, 0.0001));

    controller.dispose();
    focusNode.dispose();
  });

  testWidgets('图片和文件预览显示在主输入框内部顶部', (tester) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    final mediaController = ChatInputBarController();

    await tester.pumpWidget(
      buildHarness(
        controller: controller,
        focusNode: focusNode,
        mediaController: mediaController,
        onSend: (_) async => ChatInputSubmissionResult.rejected,
      ),
    );

    mediaController
      ..addFiles(const [
        DocumentAttachment(
          path: '/tmp/draft.pdf',
          fileName: 'draft.pdf',
          mime: 'application/pdf',
        ),
      ])
      ..addImages(['missing-draft-image.png']);
    await tester.pump();

    final surfaceFinder = _mainInputSurfaceFinder();
    expect(surfaceFinder, findsOneWidget);
    expect(
      find.descendant(of: surfaceFinder, matching: find.text('draft.pdf')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: surfaceFinder, matching: find.byType(Image)),
      findsOneWidget,
    );
    final imagePreviewsFinder = find.byKey(
      const ValueKey('chat-input-image-previews'),
    );
    final documentPreviewsFinder = find.byKey(
      const ValueKey('chat-input-document-previews'),
    );
    expect(imagePreviewsFinder, findsOneWidget);
    expect(documentPreviewsFinder, findsOneWidget);

    final imagePreviewsRect = tester.getRect(imagePreviewsFinder);
    final documentPreviewsRect = tester.getRect(documentPreviewsFinder);
    expect(
      imagePreviewsRect.right,
      lessThanOrEqualTo(documentPreviewsRect.left),
    );

    final imageRect = tester.getRect(find.byType(Image));
    final removeButtonRect = tester.getRect(
      find.byKey(const ValueKey('chat-input-image-remove:0')),
    );
    expect(imageRect.contains(removeButtonRect.topLeft), isTrue);
    expect(imageRect.contains(removeButtonRect.bottomRight), isTrue);
    expect(removeButtonRect.width, lessThan(22));
    expect(removeButtonRect.height, lessThan(22));
    expect(
      find.descendant(of: imagePreviewsFinder, matching: find.byType(InkWell)),
      findsNothing,
    );
    expect(
      find.descendant(
        of: documentPreviewsFinder,
        matching: find.byType(InkWell),
      ),
      findsNothing,
    );

    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);

    controller.dispose();
    focusNode.dispose();
  });

  testWidgets('输入框外层底部留白只下移一点', (tester) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();

    await tester.pumpWidget(
      buildHarness(
        controller: controller,
        focusNode: focusNode,
        onSend: (_) async => ChatInputSubmissionResult.rejected,
      ),
    );

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Padding &&
            widget.padding == const EdgeInsets.fromLTRB(12, 4, 12, 8),
      ),
      findsOneWidget,
    );

    controller.dispose();
    focusNode.dispose();
  });
}

Future<void> tapSendButton(WidgetTester tester) async {
  await tester.tap(find.byIcon(Lucide.ArrowUp));
  await tester.pumpAndSettle();
}

Finder _mainInputSurfaceFinder() {
  return find.byWidgetPredicate(
    (widget) =>
        widget is Container &&
        widget.decoration is BoxDecoration &&
        (widget.decoration! as BoxDecoration).borderRadius ==
            BorderRadius.circular(20),
  );
}

BoxDecoration _mainInputDecoration(WidgetTester tester) {
  final candidates = tester
      .widgetList<Container>(_mainInputSurfaceFinder())
      .map((widget) => widget.decoration)
      .whereType<BoxDecoration>()
      .toList();

  expect(candidates, hasLength(1));
  return candidates.single;
}
