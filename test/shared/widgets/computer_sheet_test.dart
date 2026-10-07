import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:Kelivo/core/database/app_database.dart';
import 'package:Kelivo/core/database/extension_entity_store.dart';
import 'package:Kelivo/core/models/conversation.dart';
import 'package:Kelivo/core/models/workspace.dart';
import 'package:Kelivo/core/models/workspace_binding.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/providers/workspace_provider.dart';
import 'package:Kelivo/core/services/browser/browser_agent_session.dart';
import 'package:Kelivo/core/services/browser/browser_thumbnail_cache.dart';
import 'package:Kelivo/core/services/acp/acp_secret_redactor.dart';
import 'package:Kelivo/core/services/api/tool_display_redaction.dart';
import 'package:Kelivo/core/services/chat/chat_service.dart';
import 'package:Kelivo/core/services/workspace/tool_run_registry.dart';
import 'package:Kelivo/core/services/workspace/workspace_tool_metadata.dart';
import 'package:Kelivo/features/chat/models/computer_step.dart';
import 'package:Kelivo/features/chat/widgets/computer_sheet.dart';
import 'package:Kelivo/features/chat/widgets/computer_step_thumbnail.dart';
import 'package:Kelivo/features/home/services/browser_ask_ai_bridge.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/features/workspace/widgets/preview/file_preview.dart';
import 'package:Kelivo/features/workspace/widgets/preview/code_file_preview.dart';
import 'package:Kelivo/features/workspace/workspace_navigation.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/widgets/custom_bottom_sheet.dart';
import 'package:Kelivo/shared/widgets/snackbar.dart';
import 'package:Kelivo/shared/pages/webview/webview_page.dart';
import 'package:Kelivo/utils/mcp_structured_image.dart';
import 'package:Kelivo/utils/safe_resize_image.dart';

import '../../support/business_test_harness.dart';
import '../../support/fake_webview_platform.dart';

const _previous = ValueKey('computer-previous-step');
const _next = ValueKey('computer-next-step');
const _latest = ValueKey('computer-latest-step');
const _action = ValueKey('computer-header-action');

ComputerStep _step(
  String id, {
  String toolName = 'custom_tool',
  String? content,
  bool loading = false,
  ToolRun? run,
  Map<String, dynamic> arguments = const {},
  Map<String, dynamic>? metadata,
}) => ComputerStep(
  id: id,
  toolName: toolName,
  arguments: arguments,
  content: content ?? 'result-$id',
  metadata: metadata,
  loading: loading,
  run: run,
);

Future<void> _open(
  WidgetTester tester, {
  required List<ComputerStep> steps,
  String? initialStepId,
  Listenable? updates,
  List<ComputerStep> Function()? readSteps,
  bool Function()? readResponseRunning,
  Locale locale = const Locale('en'),
  double scale = 1,
  double keyboard = 0,
  Widget Function(Widget)? wrap,
}) async {
  final settings = SettingsProvider(createBusinessTestPreferences());
  await settings.loaded;
  addTearDown(settings.dispose);
  final app = MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsProvider>.value(value: settings),
      ChangeNotifierProvider(create: (_) => BrowserAskAiBridge()),
      ChangeNotifierProvider(create: (_) => ToolApprovalService()),
    ],
    child: MaterialApp(
      navigatorKey: rootNavigatorKey,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          viewInsets: EdgeInsets.only(bottom: keyboard),
        ),
        child: AppSnackBarOverlay(child: child!),
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showComputerSheet(
              context,
              steps: steps,
              conversationId: 'chat-a',
              initialStepId: initialStepId,
              updates: updates,
              readSteps: readSteps,
              readResponseRunning: readResponseRunning,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpWidget(wrap?.call(app) ?? app);
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    installFakeWebViewPlatform();
    WorkspaceNavigation.onOpenTerminal = null;
  });

  testWidgets('header is centered with a close target on the left', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _open(
      tester,
      steps: [
        _step('shell', toolName: 'shell', arguments: {'command': 'pwd'}),
      ],
      scale: 1.3,
    );
    final title = tester.getCenter(find.text('Computer'));
    final panel = tester.getRect(find.byKey(CustomBottomSheet.panelKey));
    final close = tester.getRect(find.byKey(CustomBottomSheet.closeButtonKey));
    expect(title.dx, closeTo(panel.center.dx, 1));
    expect(close.width, greaterThanOrEqualTo(44));
    expect(close.height, greaterThanOrEqualTo(44));
    expect(close.center.dx, lessThan(title.dx));
    expect(tester.takeException(), isNull);
  });

  testWidgets('long MCP action label stays on one row at 320dp and scale 1.3', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const toolName =
        'mcp__server__tool_with_many_descriptive_words_and_a_very_long_name';
    await _open(
      tester,
      scale: 1.3,
      steps: [_step('long-tool', toolName: toolName)],
    );
    final label = tester.getRect(find.text(toolName));
    final panel = tester.getRect(find.byKey(CustomBottomSheet.panelKey));
    expect(label.left, greaterThanOrEqualTo(panel.left + 16));
    expect(label.right, lessThanOrEqualTo(panel.right - 16));
    expect(label.height, lessThanOrEqualTo(24));
    expect(
      find.byKey(const ValueKey('computer-copy-result')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending update_plan renders the real checklist', (tester) async {
    await _open(
      tester,
      steps: [
        ComputerStep(
          id: 'plan',
          toolName: 'update_plan',
          loading: true,
          arguments: {
            'plan': [
              {'step': 'Inspect', 'status': 'completed'},
              {'step': 'Implement', 'status': 'in_progress'},
              {'step': 'Verify', 'status': 'pending'},
            ],
          },
        ),
      ],
    );
    expect(find.text('Inspect'), findsOneWidget);
    expect(find.text('Implement'), findsOneWidget);
    expect(find.text('Verify'), findsOneWidget);
    expect(find.text('No result yet'), findsNothing);
    expect(
      find.byKey(const ValueKey('computer-plan-checklist')),
      findsOneWidget,
    );
  });

  testWidgets('unknown parameters stay in a filtered collapsed JSON section', (
    tester,
  ) async {
    await _open(
      tester,
      steps: [
        _step(
          'shell',
          toolName: 'shell',
          arguments: {
            'command': 'pwd',
            'cwd': '/workspace',
            'custom': 'only in expanded JSON',
            'access_token': 'private-token',
          },
        ),
      ],
    );
    expect(find.text('Directory'), findsOneWidget);
    expect(find.text('/workspace'), findsOneWidget);
    expect(find.textContaining('only in expanded JSON'), findsNothing);
    await tester.tap(find.text('All parameters (JSON)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('only in expanded JSON'), findsOneWidget);
    expect(find.textContaining('private-token'), findsNothing);
  });

  testWidgets(
    'browser done renders a filtered plain summary without empty JSON',
    (tester) async {
      const secret = 'browser-summary-private-value';
      final redactor = AcpSecretRedactor([secret]);
      final step =
          await ToolDisplayRedaction(
            text: redactor.text,
            value: redactor.value,
          ).run(
            () async => _step(
              'browser-done',
              toolName: 'browser_use',
              arguments: {'action': 'done', 'summary': 'Answer: $secret'},
              content: '{"ok":true,"summary":"Answer: $secret"}',
            ),
          );
      await _open(tester, locale: const Locale('ru'), steps: [step]);
      expect(find.text('Итог'), findsOneWidget);
      final result = tester.widget<Text>(
        find.byKey(const ValueKey('computer-step-result')),
      );
      expect(result.data, 'Answer: [REDACTED]');
      expect(result.style?.fontFamily, isNull);
      expect(find.textContaining(secret), findsNothing);
      expect(find.textContaining('"ok"'), findsNothing);
      expect(find.text('Все параметры (JSON)'), findsNothing);
      expect(find.byKey(_action), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'browser JSON result shows labeled values before raw disclosure',
    (tester) async {
      await _open(
        tester,
        steps: [
          _step(
            'browser-read',
            toolName: 'browser_use',
            arguments: {'action': 'read'},
            content:
                '{"ok":true,"summary":"Page summary","title":"Documentation",'
                '"url":"https://example.com/docs","details":{"count":3}}',
          ),
        ],
      );
      expect(find.text('Status'), findsOneWidget);
      expect(find.text('Success'), findsOneWidget);
      expect(find.text('Yes'), findsNothing);
      expect(find.text('Summary'), findsOneWidget);
      expect(find.text('Page summary'), findsOneWidget);
      expect(find.text('Title'), findsOneWidget);
      expect(find.text('Documentation'), findsOneWidget);
      expect(find.text('URL'), findsOneWidget);
      expect(find.textContaining('"details"'), findsNothing);
      expect(find.textContaining('"ok"'), findsNothing);
      await tester.tap(find.text('All parameters (JSON)'));
      await tester.pumpAndSettle();
      expect(find.textContaining('"details"'), findsOneWidget);
      expect(find.textContaining('"ok"'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final ok in [true, false]) {
    testWidgets('Russian browser status is readable for ok=$ok', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final cache = BrowserThumbnailCache.instance;
      cache.clear();
      addTearDown(cache.clear);
      await _open(
        tester,
        locale: const Locale('ru'),
        scale: 1.3,
        steps: [
          _step(
            'browser-status',
            toolName: 'browser_use',
            arguments: {'action': 'read'},
            content: jsonEncode({
              'ok': ok,
              'url': 'https://example.com/docs',
              if (!ok) 'error': 'Page unavailable',
            }),
          ),
        ],
      );
      final row = find
          .ancestor(of: find.text('Статус'), matching: find.byType(Row))
          .first;
      final status = tester
          .widgetList<Text>(
            find.descendant(of: row, matching: find.byType(Text)),
          )
          .map((text) => text.data)
          .join(': ');
      expect(status, ok ? 'Статус: Успешно' : 'Статус: Ошибка');
      expect(find.text('Да'), findsNothing);
      expect(find.text('Нет'), findsNothing);
      if (!ok) expect(find.text('Page unavailable'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(
        find.byKey(const ValueKey('computer-step-thumbnail:browser-status')),
        findsNothing,
      );
      expect(
        tester.getSize(find.byType(ComputerStepThumbnail)).height,
        lessThanOrEqualTo(48),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'browser sheet keeps saved and same-page images and omits unrelated preview',
    (tester) async {
      final cache = BrowserThumbnailCache.instance;
      cache.clear();
      addTearDown(cache.clear);
      late Directory directory;
      late String source;
      late BrowserThumbnail snapshot;
      await tester.runAsync(() async {
        directory = await Directory.systemTemp.createTemp(
          'computer-sheet-browser',
        );
        final image = img.Image(width: 12, height: 8);
        img.fill(image, color: img.ColorRgb8(70, 150, 200));
        source = (await File(
          '${directory.path}/page.png',
        ).writeAsBytes(img.encodePng(image))).path;
        snapshot = (await cache.capture(
          conversationId: 'chat-a',
          stepId: 'captured-step',
          sourcePath: source,
          sourceDirectory: directory,
          pageUrl: 'https://example.com/docs',
        ))!;
      });
      addTearDown(() => directory.delete(recursive: true));
      final session = BrowserAgentSession.instance;
      final originalCapture = session.captureBytes;
      var nativeCaptures = 0;
      session.captureBytes = (controller) async {
        nativeCaptures++;
        throw StateError('UI must not capture');
      };
      addTearDown(() => session.captureBytes = originalCapture);
      await _open(
        tester,
        initialStepId: 'saved-browser',
        steps: [
          _step(
            'saved-browser',
            toolName: 'browser_use',
            arguments: {'action': 'screenshot'},
            content: jsonEncode({
              'ok': true,
              'url': 'https://example.com/docs',
            }),
            metadata: {
              kMcpResultMetadataKey: mcpResultMetadata([source]),
            },
          ),
          for (final (id, url) in [
            ('same-page', 'https://example.com/docs'),
            ('other-page', 'https://other.example/docs'),
          ])
            _step(
              id,
              toolName: 'browser_use',
              arguments: {'action': 'read', 'url': url},
              content: jsonEncode({'ok': true, 'url': url}),
              metadata: {
                'browser': {'startedAt': '2020-01-01T00:00:00Z'},
              },
            ),
        ],
      );
      for (final id in ['saved-browser', 'same-page']) {
        final thumbnail = find.byKey(ValueKey('computer-step-thumbnail:$id'));
        final image = tester.widget<Image>(
          find.descendant(of: thumbnail, matching: find.byType(Image)),
        );
        expect(
          ((image.image as SafeResizeImage).imageProvider as MemoryImage).bytes,
          same(snapshot.bytes),
        );
        expect(tester.getSize(thumbnail).height, greaterThan(48));
        await tester.tap(find.byKey(_next));
        await tester.pumpAndSettle();
      }
      expect(find.byType(Image), findsNothing);
      expect(
        find.byKey(const ValueKey('computer-step-thumbnail:other-page')),
        findsNothing,
      );
      expect(
        tester.getSize(find.byType(ComputerStepThumbnail)).height,
        lessThanOrEqualTo(48),
      );
      expect(nativeCaptures, 0);
      expect(tester.takeException(), isNull);
    },
  );

  for (final json in ['{}', '[]']) {
    testWidgets('empty browser result $json omits raw JSON and disclosure', (
      tester,
    ) async {
      await _open(
        tester,
        steps: [
          _step(
            'empty-browser-result',
            toolName: 'browser_use',
            arguments: {'action': 'done'},
            content: json,
          ),
        ],
      );
      expect(find.text('No result yet'), findsOneWidget);
      expect(find.text(json), findsNothing);
      expect(find.text('All parameters (JSON)'), findsNothing);
    });
  }

  testWidgets('browser result lists only appear in collapsed JSON', (
    tester,
  ) async {
    await _open(
      tester,
      steps: [
        _step(
          'browser-result-list',
          toolName: 'browser_use',
          arguments: {'action': 'read'},
          content: '[{"title":"List detail"}]',
        ),
      ],
    );
    expect(find.textContaining('List detail'), findsNothing);
    expect(find.text('No result yet'), findsOneWidget);
    await tester.tap(find.text('All parameters (JSON)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('"title"'), findsOneWidget);
    expect(find.textContaining('List detail'), findsOneWidget);
  });

  testWidgets('plain browser result text remains readable', (tester) async {
    await _open(
      tester,
      steps: [
        _step(
          'plain-browser-result',
          toolName: 'browser_use',
          arguments: {'action': 'read'},
          content: 'Legacy page text',
        ),
      ],
    );
    expect(find.text('Legacy page text'), findsOneWidget);
    expect(find.text('All parameters (JSON)'), findsNothing);
  });

  testWidgets('stopped plan never says AI is working', (tester) async {
    await _open(
      tester,
      steps: [
        ComputerStep(
          id: 'stopped',
          toolName: 'update_plan',
          metadata: {
            'computer': {'status': 'stopped'},
          },
          arguments: {
            'plan': [
              {'step': 'Verify', 'status': 'pending'},
            ],
          },
        ),
      ],
    );
    expect(find.text('Stopped'), findsOneWidget);
    expect(find.text('AI is working…'), findsNothing);
    expect(find.text('No result yet'), findsNothing);
  });

  testWidgets('shell output follows the bottom and pauses after scrolling up', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final run = ToolRun(
      toolCallId: 'follow-output',
      toolName: 'shell',
      command: 'npm test',
    );
    addTearDown(run.dispose);
    run.appendStdout(
      utf8.encode(List.generate(100, (n) => 'line $n').join('\n')),
    );
    await _open(
      tester,
      steps: [_step('follow-output', toolName: 'shell', run: run)],
    );
    final scroll = find.byKey(
      const ValueKey('computer-step-body:follow-output'),
    );
    final controller = tester.widget<CustomScrollView>(scroll).controller!;
    expect(controller.offset, closeTo(controller.position.maxScrollExtent, 1));
    final terminal = tester.getRect(
      find.byKey(const ValueKey('computer-terminal-output')),
    );
    final viewport = tester.getRect(scroll);
    expect(terminal.height, greaterThanOrEqualTo(viewport.height - 50));

    await tester.drag(scroll, const Offset(0, 150));
    await tester.pumpAndSettle();
    final pinnedOffset = controller.offset;
    expect(pinnedOffset, lessThan(controller.position.maxScrollExtent - 50));
    run.appendStdout(
      utf8.encode('\n${List.generate(10, (n) => 'more $n').join('\n')}'),
    );
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(pinnedOffset, 1));

    await tester.drag(scroll, const Offset(0, -1500));
    await tester.pumpAndSettle();
    run.appendStdout(utf8.encode('\nlast line'));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(controller.position.maxScrollExtent, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('shell argument stays below the header during output following', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final run = ToolRun(
      toolCallId: 'header-geometry',
      toolName: 'shell',
      command: 'flutter test test/shared',
    );
    addTearDown(run.dispose);
    run.appendStdout(utf8.encode('24 tests passed\nRunning browser checks'));
    await _open(
      tester,
      scale: 1.3,
      steps: [_step('header-geometry', toolName: 'shell', run: run)],
    );
    void expectVisibleArgument() {
      final headerBottom = tester
          .getRect(find.byKey(CustomBottomSheet.closeButtonKey))
          .bottom;
      final argument = tester.getRect(
        find.byKey(const ValueKey('computer-step-action')),
      );
      expect(argument.top, greaterThanOrEqualTo(headerBottom));
      expect(
        find.byKey(const ValueKey('computer-step-action')).hitTestable(),
        findsOneWidget,
      );
    }

    expectVisibleArgument();
    run.appendStdout(
      utf8.encode(
        '\n${List.generate(100, (index) => 'line $index').join('\n')}',
      ),
    );
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pumpAndSettle();
    expectVisibleArgument();
    expect(tester.takeException(), isNull);
  });

  testWidgets('completed response suppresses working status for a live run', (
    tester,
  ) async {
    final run = ToolRun(
      toolCallId: 'finished-response',
      toolName: 'shell',
      command: 'pwd',
    );
    addTearDown(run.dispose);
    await _open(
      tester,
      steps: [_step('finished-response', toolName: 'shell', run: run)],
      readResponseRunning: () => false,
    );
    expect(find.text('AI is working…'), findsNothing);
    expect(find.text('Done'), findsOneWidget);
  });

  testWidgets('shell detail and copy retain over 200 filtered output lines', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });
    const secret = 'private-provider-output';
    final redactor = AcpSecretRedactor([secret]);
    final run =
        await ToolDisplayRedaction(
          text: redactor.text,
          value: redactor.value,
        ).run(
          () async => ToolRun(
            toolCallId: 'long-copy',
            toolName: 'shell',
            command: 'npm test',
          ),
        );
    addTearDown(run.dispose);
    run.appendStdout(
      utf8.encode(
        List.generate(
          250,
          (index) => index == 25 ? 'line $index $secret' : 'line $index',
        ).join('\n'),
      ),
    );
    run.appendStderr(utf8.encode('stderr last $secret'));
    await _open(
      tester,
      steps: [_step('long-copy', toolName: 'shell', run: run)],
    );
    final shown = tester
        .widget<Text>(find.byKey(const ValueKey('computer-step-result')))
        .data!;
    expect(shown, startsWith('line 0\n'));
    expect(shown, contains('line 249'));
    expect(shown, contains('stderr last'));
    expect(shown, isNot(contains(secret)));
    await tester.tap(find.byKey(const ValueKey('computer-copy-result')));
    await tester.pump();
    expect(copied, shown);
  });

  testWidgets(
    'stopped response keeps background output alive without working status',
    (tester) async {
      final run = ToolRun(
        toolCallId: 'background',
        toolName: 'shell',
        command: 'npm run dev',
        background: true,
      );
      addTearDown(run.dispose);
      await _open(
        tester,
        steps: [
          _step(
            'background',
            toolName: 'shell',
            run: run,
            metadata: {
              'computer': {'responseStopped': true},
            },
          ),
        ],
        readResponseRunning: () => false,
      );
      expect(find.text('Stopped'), findsOneWidget);
      expect(find.text('AI is working…'), findsNothing);
      run.appendStdout(utf8.encode('server ready'));
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.text('server ready'), findsOneWidget);
      expect(run.status, ToolRunStatus.running);
      expect(find.byTooltip('Open terminal'), findsOneWidget);
    },
  );

  testWidgets('Russian stopped sheet fits narrow scaled keyboard layout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _open(
      tester,
      locale: const Locale('ru'),
      scale: 1.3,
      keyboard: 100,
      initialStepId: '1',
      steps: [
        _step(
          '1',
          metadata: {
            'computer': {'status': 'stopped', 'responseStopped': true},
          },
        ),
        _step('2'),
      ],
    );
    expect(find.text('Остановлено'), findsOneWidget);
    expect(find.text('ИИ работает…'), findsNothing);
    expect(find.byKey(_previous).hitTestable(), findsOneWidget);
    expect(
      find.byKey(const ValueKey('computer-copy-result')).hitTestable(),
      findsOneWidget,
    );
    expect(find.byKey(_latest).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  tearDown(() async {
    FakeWebViewPlatform.onCreated = null;
    final session = BrowserAgentSession.instance;
    if (session.minimized.value) await session.closeMinimized();
    WorkspaceNavigation.onOpenTerminal = null;
  });

  testWidgets('full-width sheet opens latest and pages every step', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _open(tester, steps: [_step('1'), _step('2'), _step('3')]);

    final panel = find.byKey(CustomBottomSheet.panelKey);
    expect(tester.getSize(panel).width, 400);
    expect(tester.getSize(panel).height, closeTo(680, 1));
    expect(find.text('Computer'), findsOneWidget);
    expect(find.text('3 / 3'), findsOneWidget);
    expect(find.text('result-3'), findsOneWidget);
    await tester.tap(find.byKey(_previous));
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
    expect(find.text('result-2'), findsOneWidget);
    await tester.tap(find.byKey(_previous));
    await tester.pumpAndSettle();
    expect(find.text('1 / 3'), findsOneWidget);
    expect(tester.widget<IconButton>(find.byKey(_previous)).onPressed, isNull);
    await tester.tap(find.byKey(_next));
    await tester.pumpAndSettle();
    expect(find.text('result-2'), findsOneWidget);
    await tester.tap(find.byKey(_latest));
    await tester.pumpAndSettle();
    expect(find.text('3 / 3'), findsOneWidget);
    await tester.tap(find.byKey(CustomBottomSheet.closeButtonKey));
    await tester.pumpAndSettle();
    expect(find.text('Computer'), findsNothing);
  });

  testWidgets('live steps follow newest and respect a pinned running step', (
    tester,
  ) async {
    final changes = ChangeNotifier();
    addTearDown(changes.dispose);
    var steps = [_step('1', loading: true), _step('2', loading: true)];
    await _open(tester, steps: steps, updates: changes, readSteps: () => steps);
    expect(find.text('2 / 2'), findsOneWidget);
    steps = [...steps, _step('3', loading: true)];
    changes.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('3 / 3'), findsOneWidget);
    await tester.tap(find.byKey(_previous));
    await tester.pumpAndSettle();
    steps = [...steps, _step('4', loading: true)];
    changes.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('2 / 4'), findsOneWidget);
    expect(find.text('result-2'), findsOneWidget);
    await tester.tap(find.byKey(_latest));
    await tester.pumpAndSettle();
    expect(find.text('4 / 4'), findsOneWidget);
  });

  testWidgets('initial step id is stable while older steps are inserted', (
    tester,
  ) async {
    final changes = ChangeNotifier();
    addTearDown(changes.dispose);
    var steps = [_step('1', loading: true), _step('2', loading: true)];
    await _open(
      tester,
      steps: steps,
      initialStepId: '1',
      updates: changes,
      readSteps: () => steps,
    );
    expect(find.text('1 / 2'), findsOneWidget);
    steps = [_step('0'), ...steps, _step('3', loading: true)];
    changes.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('2 / 4'), findsOneWidget);
    expect(find.text('result-1'), findsOneWidget);
  });

  testWidgets('run output and terminal action update from the live run', (
    tester,
  ) async {
    final run = ToolRun(
      toolCallId: 'shell-1',
      toolName: 'shell',
      command: 'echo live',
    );
    addTearDown(run.dispose);
    String? capturedCommand;
    WorkspaceNavigation.onOpenTerminal = (context, {command}) {
      // The app-shell callback must receive the actual command.
      capturedCommand = command;
    };
    await _open(
      tester,
      steps: [_step('shell-1', toolName: 'shell', run: run)],
    );
    expect(find.text('AI is working…'), findsOneWidget);
    run.appendStdout(utf8.encode('live output\n'));
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('live output\n'), findsOneWidget);
    run.complete(status: ToolRunStatus.succeeded, exitCode: 0);
    await tester.pumpAndSettle();
    expect(find.text('Done'), findsOneWidget);
    await tester.tap(find.byKey(_action));
    await tester.pumpAndSettle();
    expect(capturedCommand, 'echo live');
  });

  testWidgets('copy and rendered parameters remove credentials and auth URLs', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });
    await _open(
      tester,
      steps: [
        _step(
          'secret',
          arguments: {'access_token': 'private-token', 'query': 'safe query'},
          content:
              '{"access_token":"private-token",'
              '"url":"https://auth.openai.com/authorize?code=auth-secret",'
              '"message":"safe result"}',
        ),
      ],
    );
    expect(find.textContaining('private-token'), findsNothing);
    expect(find.textContaining('auth-secret'), findsNothing);
    expect(find.textContaining('safe query'), findsNothing);
    await tester.tap(find.text('All parameters (JSON)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('safe query'), findsOneWidget);
    expect(find.textContaining('safe result'), findsOneWidget);
    expect(find.byKey(_action), findsNothing);
    await tester.tap(find.byKey(const ValueKey('computer-copy-result')));
    await tester.pump();
    expect(copied, contains('safe result'));
    expect(copied, isNot(contains('private-token')));
    expect(copied, isNot(contains('auth-secret')));
  });

  testWidgets('filtered file references cannot open a substituted path', (
    tester,
  ) async {
    final redactor = AcpSecretRedactor(['private-file']);
    final step =
        await ToolDisplayRedaction(
          text: redactor.text,
          value: redactor.value,
        ).run(
          () async => ComputerStep(
            id: 'file',
            toolName: 'read_file',
            arguments: {'path': '/workspace/private-file.txt'},
            metadata: const WorkspaceToolMetadata(
              tool: 'read_file',
              status: 'ok',
              path: '/workspace/private-file.txt',
              files: [
                WorkspaceToolFile(
                  path: '/workspace/private-file.txt',
                  link: 'kelivo://workspace/private-file.txt',
                ),
              ],
            ).toJson(),
          ),
        );
    await _open(tester, steps: [step]);
    expect(find.textContaining('private-file'), findsNothing);
    expect(tester.widget<IconButton>(find.byKey(_action)).onPressed, isNull);
  });

  testWidgets('failed live run shows error status', (tester) async {
    final run = ToolRun(
      toolCallId: 'failed',
      toolName: 'shell',
      command: 'exit 1',
    );
    addTearDown(run.dispose);
    await _open(
      tester,
      steps: [_step('failed', toolName: 'shell', run: run)],
    );
    run.complete(status: ToolRunStatus.failed, exitCode: 1);
    await tester.pumpAndSettle();
    expect(find.text('Error'), findsOneWidget);
  });

  testWidgets('image and other steps offer copy; browser and file offer open', (
    tester,
  ) async {
    await _open(
      tester,
      steps: [
        _step(
          'browser',
          toolName: 'browser_use',
          arguments: {'action': 'read'},
        ),
        _step(
          'file',
          toolName: 'read_file',
          arguments: {'path': '/workspace/a.txt'},
        ),
        _step('image', toolName: 'image_gen'),
        _step('generic'),
      ],
    );
    expect(find.byTooltip('Copy result'), findsOneWidget);
    await tester.tap(find.byKey(_previous));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Copy result'), findsOneWidget);
    await tester.tap(find.byKey(_previous));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Preview file'), findsOneWidget);
    await tester.tap(find.byKey(_previous));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Open live browser'), findsOneWidget);
  });

  testWidgets('browser action selects the existing tab without a reload', (
    tester,
  ) async {
    await _open(
      tester,
      steps: [
        _step(
          'browser',
          toolName: 'browser_use',
          arguments: {'action': 'read', 'url': 'https://first.example/'},
        ),
      ],
    );
    final created = <FakeWebViewController>[];
    FakeWebViewPlatform.onCreated = created.add;
    rootNavigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const WebViewPage(
          url: 'https://first.example/',
          agentSession: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final session = BrowserAgentSession.instance;
    session.setOwnerConversationId('chat-a');
    final first = session.controller!;
    final originalLoads = (first.platform as FakeWebViewController).loadedUrls;
    await session.newTab(url: 'https://second.example/');
    await tester.pumpAndSettle();
    expect(created, hasLength(2));
    await tester.tap(find.byKey(const ValueKey('browser_minimize')));
    await tester.pumpAndSettle();
    expect(session.minimized.value, isTrue);
    await tester.tap(find.byKey(_action));
    await tester.pumpAndSettle();
    expect(session.controller, same(first));
    expect((first.platform as FakeWebViewController).loadedUrls, originalLoads);
    expect(created, hasLength(2));
    expect(find.byType(WebViewPage), findsOneWidget);
    expect(find.byType(ComputerSheet), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('file action opens checked file preview in the owning chat', (
    tester,
  ) async {
    late Directory fixture;
    late WorkspaceProvider workspaces;
    late AppDatabase database;
    late _Chats chats;
    late PathProviderPlatform oldPaths;
    await tester.runAsync(() async {
      fixture = await Directory.systemTemp.createTemp('computer-sheet-file');
      final files = await Directory('${fixture.path}/files').create();
      await File(
        '${files.path}/note.txt',
      ).writeAsString('checked file content');
      oldPaths = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _Paths(fixture.path);
      database = AppDatabase(NativeDatabase.memory());
      workspaces = WorkspaceProvider(store: ExtensionEntityStore(database));
      await workspaces.loaded;
      final workspace = await workspaces.create(
        name: 'Fixture',
        kind: WorkspaceKind.linked,
        hostPath: files.path,
      );
      chats = _Chats(
        Conversation(
          id: 'chat-a',
          title: 'Fixture chat',
          extras: WorkspaceBinding(workspaceId: workspace.id).applyTo({}),
        ),
      );
    });
    addTearDown(() async {
      chats.dispose();
      workspaces.dispose();
      await database.close();
      PathProviderPlatform.instance = oldPaths;
      await fixture.delete(recursive: true);
    });
    await _open(
      tester,
      steps: [
        _step(
          'file',
          toolName: 'read_file',
          arguments: {'path': '/workspace/note.txt'},
        ),
      ],
      wrap: (child) => MultiProvider(
        providers: [
          ChangeNotifierProvider<WorkspaceProvider>.value(value: workspaces),
          ChangeNotifierProvider<ChatService>.value(value: chats),
        ],
        child: child,
      ),
    );
    await tester.tap(find.byKey(_action));
    for (
      var i = 0;
      i < 100 && find.byType(FilePreviewFrame).evaluate().isEmpty;
      i++
    ) {
      // Let native SQLite/file I/O run; virtual frames alone can exhaust the
      // polling bound before the checked snapshot has completed.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.byType(FilePreviewFrame), findsOneWidget);
    await tester.runAsync(
      () => tester
          .state<CodeFilePreviewState>(find.byType(CodeFilePreview))
          .load(),
    );
    await tester.pumpAndSettle();
    expect(find.byType(FilePreviewFrame), findsOneWidget);
    expect(find.text('note.txt'), findsOneWidget);
    expect(find.byType(ComputerSheet), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'landscape with text scaling and keyboard keeps pager reachable',
    (tester) async {
      tester.view.physicalSize = const Size(740, 420);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _open(
        tester,
        scale: 1.3,
        keyboard: 100,
        steps: [
          _step('1'),
          _step(
            '2',
            arguments: {'long label': List.filled(100, 'parameter').join(' ')},
            content: List.filled(100, 'long result').join('\n'),
          ),
        ],
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(_previous).hitTestable(), findsOneWidget);
      expect(
        find.byKey(CustomBottomSheet.closeButtonKey).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.byKey(_previous));
      await tester.pumpAndSettle();
      expect(find.text('1 / 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('command thumbnail shows sanitized output tail', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ComputerStepThumbnail(
            step: _step(
              'shell',
              toolName: 'shell',
              arguments: {'command': 'echo hello'},
              content: 'first\nsecond\nlast',
            ),
            conversationId: 'chat-a',
          ),
        ),
      ),
    );
    expect(find.textContaining('last'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('image step thumbnails render inline tool image data', (
    tester,
  ) async {
    final image = img.Image(width: 12, height: 8);
    img.fill(image, color: img.ColorRgb8(70, 150, 200));
    final data = 'data:image/png;base64,${base64Encode(img.encodePng(image))}';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ComputerStepThumbnail(
            step: _step(
              'image',
              toolName: 'image_gen',
              content: '![generated]($data)',
            ),
            conversationId: 'chat-a',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('image previews decode at thumbnail size', (tester) async {
    final image = img.Image(width: 1200, height: 600);
    img.fill(image, color: img.ColorRgb8(70, 150, 200));
    final data = 'data:image/png;base64,${base64Encode(img.encodePng(image))}';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ComputerStepThumbnail(
            step: _step(
              'image',
              toolName: 'image_gen',
              content: '![generated]($data)',
            ),
            conversationId: 'chat-a',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final provider = tester.widget<Image>(find.byType(Image)).image;
    final decoded = await tester.runAsync(() async {
      final completer = Completer<ui.Image>();
      final stream = provider.resolve(ImageConfiguration.empty);
      final listener = ImageStreamListener(
        (info, _) => completer.complete(info.image),
      );
      stream.addListener(listener);
      final decoded = await completer.future;
      stream.removeListener(listener);
      return decoded;
    });
    expect(decoded!.width, lessThanOrEqualTo(480));
    expect(decoded.height, lessThanOrEqualTo(480));
  });

  testWidgets('image file steps keep file preview action and image thumbnail', (
    tester,
  ) async {
    final image = img.Image(width: 12, height: 8);
    img.fill(image, color: img.ColorRgb8(70, 150, 200));
    final data = 'data:image/png;base64,${base64Encode(img.encodePng(image))}';
    await _open(
      tester,
      steps: [
        _step(
          'file-image',
          toolName: 'read_file',
          arguments: {'path': '/workspace/plot.png'},
          content: '![generated]($data)',
        ),
      ],
    );
    expect(find.byTooltip('Preview file'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('remote image previews fetch safe URLs and skip auth URLs', (
    tester,
  ) async {
    final image = img.Image(width: 1200, height: 600);
    img.fill(image, color: img.ColorRgb8(70, 150, 200));
    final requested = <Uri>[];
    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Row(
                children: [
                  ComputerStepThumbnail(
                    key: const ValueKey('public-image'),
                    step: _step(
                      'public',
                      toolName: 'image_gen',
                      content:
                          '![generated](https://images.example.com/result.png)',
                    ),
                    conversationId: 'chat-a',
                  ),
                  ComputerStepThumbnail(
                    key: const ValueKey('private-image'),
                    step: _step(
                      'private',
                      toolName: 'image_gen',
                      content:
                          '![generated](https://images.example.com/result.png?access_token=private)',
                    ),
                    conversationId: 'chat-a',
                  ),
                ],
              ),
            ),
          ),
        );
        for (var i = 0; i < 100 && find.byType(Image).evaluate().isEmpty; i++) {
          await tester.runAsync(() => Future<void>(() {}));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.pumpAndSettle();
      },
      () => MockClient((request) async {
        requested.add(request.url);
        return http.Response.bytes(
          img.encodePng(image),
          200,
          headers: {'content-type': 'image/png'},
        );
      }),
    );
    expect(requested, [Uri.parse('https://images.example.com/result.png')]);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('public-image')),
        matching: find.byType(Image),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('private-image')),
        matching: find.byType(Image),
      ),
      findsNothing,
    );
    final provider = tester.widget<Image>(find.byType(Image)).image;
    final decoded = await tester.runAsync(() async {
      final completer = Completer<ui.Image>();
      final stream = provider.resolve(ImageConfiguration.empty);
      final listener = ImageStreamListener(
        (info, _) => completer.complete(info.image),
      );
      stream.addListener(listener);
      final decoded = await completer.future;
      stream.removeListener(listener);
      return decoded;
    });
    expect(decoded!.width, lessThanOrEqualTo(480));
    expect(decoded.height, lessThanOrEqualTo(480));
    expect(tester.takeException(), isNull);
  });

  testWidgets('persisted browser screenshots repopulate the preview cache', (
    tester,
  ) async {
    final cache = BrowserThumbnailCache.instance;
    cache.clear();
    addTearDown(cache.clear);
    final oldPaths = PathProviderPlatform.instance;
    late Directory directory;
    late String source;
    await tester.runAsync(() async {
      directory = await Directory.systemTemp.createTemp(
        'saved-browser-preview',
      );
      final browser = await Directory(
        '${directory.path}/images/browser',
      ).create(recursive: true);
      final image = img.Image(width: 1200, height: 600);
      img.fill(image, color: img.ColorRgb8(70, 150, 200));
      source = (await File(
        '${browser.path}/shot.jpg',
      ).writeAsBytes(img.encodeJpg(image))).path;
      PathProviderPlatform.instance = _Paths(directory.path);
    });
    addTearDown(() async {
      PathProviderPlatform.instance = oldPaths;
      await directory.delete(recursive: true);
    });
    final session = BrowserAgentSession.instance;
    final originalCapture = session.captureBytes;
    var nativeCaptures = 0;
    session.captureBytes = (controller) async {
      nativeCaptures++;
      throw StateError('UI must not capture');
    };
    addTearDown(() => session.captureBytes = originalCapture);
    final savedStep = _step(
      'saved-step',
      toolName: 'browser_use',
      arguments: {'action': 'screenshot'},
      content: jsonEncode({
        'url': 'https://example.com/',
        'screenshot': 'attached',
      }),
      metadata: {
        kMcpResultMetadataKey: mcpResultMetadata([source]),
      },
    );
    expect(savedStep.imagePath, source);
    expect(savedStep.allowsBrowserPreview, isTrue);
    Widget app() => MaterialApp(
      home: Scaffold(
        body: Row(
          children: [
            ComputerStepThumbnail(
              key: const ValueKey('restored-shot'),
              step: savedStep,
              conversationId: 'chat-a',
            ),
            ComputerStepThumbnail(
              key: const ValueKey('restored-auth-shot'),
              step: _step(
                'saved-auth',
                toolName: 'browser_use',
                arguments: {'action': 'screenshot'},
                content: jsonEncode({
                  'url': 'https://auth.openai.com/authorize?code=private',
                  'screenshot': 'attached',
                }),
                metadata: {
                  kMcpResultMetadataKey: mcpResultMetadata([source]),
                },
              ),
              conversationId: 'chat-a',
            ),
          ],
        ),
      ),
    );
    await tester.pumpWidget(app());
    final wait = Stopwatch()..start();
    while (wait.elapsed < const Duration(seconds: 5) &&
        cache.forSource('chat-a', source) == null) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();
    final preview = cache.forSource('chat-a', source);
    expect(preview, isNotNull);
    expect(preview!.width, 480);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('restored-shot')),
        matching: find.byType(Image),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('restored-auth-shot')),
        matching: find.byType(Image),
      ),
      findsNothing,
    );
    expect(cache.forStep('chat-a', 'saved-auth'), isNull);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(cache.forSource('chat-a', source), same(preview));
    expect(nativeCaptures, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'restoring an older browser shot preserves the newer live fallback',
    (tester) async {
      final cache = BrowserThumbnailCache.instance;
      cache.clear();
      addTearDown(cache.clear);
      final oldPaths = PathProviderPlatform.instance;
      late Directory directory;
      late String oldSource;
      late BrowserThumbnail newerPreview;
      await tester.runAsync(() async {
        directory = await Directory.systemTemp.createTemp(
          'browser-preview-order',
        );
        final browser = await Directory(
          '${directory.path}/images/browser',
        ).create(recursive: true);
        final oldImage = img.Image(width: 12, height: 8);
        img.fill(oldImage, color: img.ColorRgb8(200, 70, 70));
        oldSource = (await File(
          '${browser.path}/older.jpg',
        ).writeAsBytes(img.encodeJpg(oldImage))).path;
        final newImage = img.Image(width: 12, height: 8);
        img.fill(newImage, color: img.ColorRgb8(70, 200, 70));
        final newSource = (await File(
          '${browser.path}/newer.jpg',
        ).writeAsBytes(img.encodeJpg(newImage))).path;
        PathProviderPlatform.instance = _Paths(directory.path);
        newerPreview = (await cache.capture(
          conversationId: 'chat-a',
          stepId: 'new-live-shot',
          sourcePath: newSource,
          sourceDirectory: browser,
          pageUrl: 'https://example.com/newer',
        ))!;
      });
      addTearDown(() async {
        PathProviderPlatform.instance = oldPaths;
        await directory.delete(recursive: true);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                ComputerStepThumbnail(
                  key: const ValueKey('older-restored-shot'),
                  step: _step(
                    'old-saved-shot',
                    toolName: 'browser_use',
                    arguments: {'action': 'screenshot'},
                    content: jsonEncode({'url': 'https://example.com/older'}),
                    metadata: {
                      kMcpResultMetadataKey: mcpResultMetadata([oldSource]),
                    },
                  ),
                  conversationId: 'chat-a',
                ),
                ComputerStepThumbnail(
                  key: const ValueKey('newer-fallback-shot'),
                  step: _step(
                    'navigate',
                    toolName: 'browser_use',
                    arguments: {'url': 'https://example.com/newer'},
                    metadata: {
                      'browser': {'startedAt': '2020-01-01T00:00:00Z'},
                    },
                  ),
                  conversationId: 'chat-a',
                ),
              ],
            ),
          ),
        ),
      );
      final wait = Stopwatch()..start();
      while (wait.elapsed < const Duration(seconds: 5) &&
          cache.forSource('chat-a', oldSource) == null) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pumpAndSettle();
      final restored = cache.forSource('chat-a', oldSource);
      expect(restored, isNotNull);
      expect(cache.latestIn('chat-a'), same(newerPreview));
      final oldImage = tester.widget<Image>(
        find.descendant(
          of: find.byKey(const ValueKey('older-restored-shot')),
          matching: find.byType(Image),
        ),
      );
      final fallback = tester.widget<Image>(
        find.descendant(
          of: find.byKey(const ValueKey('newer-fallback-shot')),
          matching: find.byType(Image),
        ),
      );
      expect(
        ((oldImage.image as SafeResizeImage).imageProvider as MemoryImage)
            .bytes,
        same(restored!.bytes),
      );
      expect(
        ((fallback.image as SafeResizeImage).imageProvider as MemoryImage)
            .bytes,
        same(newerPreview.bytes),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reused browser step IDs retain each exact screenshot and latest fallback',
    (tester) async {
      final cache = BrowserThumbnailCache.instance;
      cache.clear();
      addTearDown(cache.clear);
      final oldPaths = PathProviderPlatform.instance;
      late Directory directory;
      late List<String> sources;
      late BrowserThumbnail latest;
      await tester.runAsync(() async {
        directory = await Directory.systemTemp.createTemp('browser-source-id');
        final browser = await Directory(
          '${directory.path}/images/browser',
        ).create(recursive: true);
        sources = [];
        for (var index = 0; index < 4; index++) {
          final image = img.Image(width: 12, height: 8);
          img.fill(image, color: img.ColorRgb8(20 + index * 60, 90, 160));
          sources.add(
            (await File(
              '${browser.path}/shot-$index.jpg',
            ).writeAsBytes(img.encodeJpg(image))).path,
          );
        }
        PathProviderPlatform.instance = _Paths(directory.path);
        await cache.capture(
          conversationId: 'chat-a',
          stepId: 'browser_use-0',
          sourcePath: sources.last,
          sourceDirectory: browser,
          pageUrl: 'https://example.com/stale-reply',
        );
        latest = (await cache.capture(
          conversationId: 'chat-a',
          stepId: 'native-latest',
          sourcePath: sources[2],
          sourceDirectory: browser,
          pageUrl: 'https://example.com/latest',
        ))!;
      });
      addTearDown(() async {
        PathProviderPlatform.instance = oldPaths;
        await directory.delete(recursive: true);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                for (var index = 0; index < 2; index++)
                  ComputerStepThumbnail(
                    key: ValueKey('reused-shot-$index'),
                    step: _step(
                      'browser_use-0',
                      toolName: 'browser_use',
                      arguments: {'action': 'screenshot'},
                      content: jsonEncode({
                        'url': 'https://example.com/$index',
                      }),
                      metadata: {
                        kMcpResultMetadataKey: mcpResultMetadata([
                          sources[index],
                        ]),
                      },
                    ),
                    conversationId: 'chat-a',
                  ),
                ComputerStepThumbnail(
                  key: const ValueKey('reused-latest'),
                  step: _step(
                    'browser_use-0',
                    toolName: 'browser_use',
                    arguments: {'url': 'https://example.com/latest'},
                    metadata: {
                      'browser': {'startedAt': '2020-01-01T00:00:00Z'},
                    },
                  ),
                  conversationId: 'chat-a',
                ),
              ],
            ),
          ),
        ),
      );
      final wait = Stopwatch()..start();
      while (wait.elapsed < const Duration(seconds: 5) &&
          sources
              .take(2)
              .any((source) => cache.forSource('chat-a', source) == null)) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pumpAndSettle();
      for (var index = 0; index < 3; index++) {
        final preview = index < 2
            ? cache.forSource('chat-a', sources[index])
            : latest;
        expect(preview, isNotNull);
        final image = tester.widget<Image>(
          find.descendant(
            of: find.byKey(
              index < 2
                  ? ValueKey('reused-shot-$index')
                  : const ValueKey('reused-latest'),
            ),
            matching: find.byType(Image),
          ),
        );
        expect(
          ((image.image as SafeResizeImage).imageProvider as MemoryImage).bytes,
          same(preview!.bytes),
        );
      }
      expect(cache.latestIn('chat-a'), same(latest));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'browser thumbnail reads same-chat cache without native capture',
    (tester) async {
      final cache = BrowserThumbnailCache.instance;
      cache.clear();
      addTearDown(cache.clear);
      late Directory directory;
      await tester.runAsync(() async {
        directory = await Directory.systemTemp.createTemp('computer-thumbnail');
        final image = img.Image(width: 12, height: 8);
        img.fill(image, color: img.ColorRgb8(70, 150, 200));
        final file = await File(
          '${directory.path}/page.png',
        ).writeAsBytes(img.encodePng(image));
        final thumbnail = await cache.capture(
          conversationId: 'chat-a',
          stepId: 'captured-step',
          sourcePath: file.path,
          sourceDirectory: directory,
          pageUrl: 'https://example.com/',
        );
        expect(thumbnail, isNotNull);
      });
      addTearDown(() => directory.delete(recursive: true));
      final session = BrowserAgentSession.instance;
      final originalCapture = session.captureBytes;
      var nativeCaptures = 0;
      session.captureBytes = (controller) async {
        nativeCaptures++;
        throw StateError('UI must not capture');
      };
      addTearDown(() => session.captureBytes = originalCapture);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                ComputerStepThumbnail(
                  key: const ValueKey('same-chat'),
                  step: _step(
                    'new-step',
                    toolName: 'browser_use',
                    arguments: {'url': 'https://example.com/'},
                    metadata: {
                      'browser': {'startedAt': '2020-01-01T00:00:00Z'},
                    },
                  ),
                  conversationId: 'chat-a',
                ),
                ComputerStepThumbnail(
                  key: const ValueKey('other-chat'),
                  step: _step('new-step', toolName: 'browser_use'),
                  conversationId: 'chat-b',
                ),
                ComputerStepThumbnail(
                  key: const ValueKey('auth-page'),
                  step: _step(
                    'auth-step',
                    toolName: 'browser_use',
                    arguments: {
                      'url': 'https://auth.openai.com/authorize?code=private',
                    },
                  ),
                  conversationId: 'chat-a',
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('same-chat')),
          matching: find.byType(Image),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('other-chat')),
          matching: find.byType(Image),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('auth-page')),
          matching: find.byType(Image),
        ),
        findsNothing,
      );
      expect(nativeCaptures, 0);
      expect(tester.takeException(), isNull);
    },
  );
}

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
}

class _Chats extends ChatService {
  _Chats(this.conversation);
  final Conversation conversation;

  @override
  String? get currentConversationId => 'different-chat';

  @override
  Conversation? getConversation(String id) =>
      id == conversation.id ? conversation : null;
}
