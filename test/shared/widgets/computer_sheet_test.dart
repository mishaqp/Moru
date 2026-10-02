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
      locale: const Locale('en'),
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
    expect(find.text('live output'), findsOneWidget);
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
    expect(find.textContaining('safe query'), findsOneWidget);
    expect(find.textContaining('safe result'), findsOneWidget);
    await tester.tap(find.byKey(_action));
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
      await tester.runAsync(() => Future<void>(() {}));
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
                  step: _step('navigate', toolName: 'browser_use'),
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
                  step: _step('browser_use-0', toolName: 'browser_use'),
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
                  step: _step('new-step', toolName: 'browser_use'),
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
