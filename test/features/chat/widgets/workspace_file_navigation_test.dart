import 'dart:io';
import 'dart:convert';
import 'dart:async';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:Kelivo/features/chat/widgets/produced_files_row.dart';
import 'package:Kelivo/features/workspace/widgets/files/workspace_file_thumbnail.dart';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'package:Kelivo/core/database/app_database.dart';
import 'package:Kelivo/core/database/extension_entity_store.dart';
import 'package:Kelivo/core/models/conversation.dart';
import 'package:Kelivo/core/models/workspace.dart';
import 'package:Kelivo/core/models/workspace_binding.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/providers/workspace_provider.dart';
import 'package:Kelivo/core/services/chat/chat_service.dart';
import 'package:Kelivo/core/services/workspace/workspace_tool_metadata.dart';
import 'package:Kelivo/features/chat/widgets/workspace_tool_ui.dart';
import 'package:Kelivo/features/workspace/widgets/files/file_browser.dart';
import 'package:Kelivo/features/workspace/widgets/preview/file_preview.dart';
import 'package:Kelivo/features/workspace/widgets/preview/preview_states.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/widgets/markdown_with_highlight.dart';
import 'package:Kelivo/shared/widgets/snackbar.dart';

import '../../../support/business_test_harness.dart';
import '../../../support/fake_webview_platform.dart';

class _HtmlLoadController extends FakeWebViewController {
  _HtmlLoadController(super.params, this.loaded);
  final Completer<Uri> loaded;
  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) async {
    await super.loadHtmlString(html, baseUrl: baseUrl);
    loaded.complete(Uri.parse(baseUrl ?? 'about:blank'));
  }

  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    await super.loadRequest(params);
    loaded.complete(params.uri);
  }
}

class _HtmlLoadPlatform extends FakeWebViewPlatform {
  final loaded = Completer<Uri>();
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) => _HtmlLoadController(params, loaded);
}

class _LiveHttpOverrides extends HttpOverrides {}

class _PathProvider extends PathProviderPlatform {
  _PathProvider(this.root);
  final String root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
}

class _Chat extends ChatService {
  _Chat(this.conversation);
  final Conversation conversation;
  @override
  Conversation? getConversation(String id) =>
      id == conversation.id ? conversation : null;
}

void main() {
  late Directory root;
  late PathProviderPlatform previousPaths;
  late AppDatabase db;
  late WorkspaceProvider workspaces;
  late Conversation conversation;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('kelivo_file_navigation_');
    previousPaths = PathProviderPlatform.instance;
    final appData = Directory(p.join(root.path, 'private-app-data'))
      ..createSync();
    PathProviderPlatform.instance = _PathProvider(appData.path);
    File(p.join(root.path, 'note.txt')).writeAsStringSync('preview content');
    Directory(p.join(root.path, 'folder')).createSync();
    File(p.join(root.path, 'folder', 'child.txt')).writeAsStringSync('child');
    db = AppDatabase(NativeDatabase.memory());
    workspaces = WorkspaceProvider(store: ExtensionEntityStore(db));
    await workspaces.loaded;
    final workspace = await workspaces.create(
      name: 'Files',
      kind: WorkspaceKind.linked,
      hostPath: root.path,
    );
    conversation = Conversation(
      id: 'c1',
      title: 'Test',
      extras: WorkspaceBinding(workspaceId: workspace.id).applyTo({}),
    );
  });

  tearDown(() async {
    PathProviderPlatform.instance = previousPaths;
    workspaces.dispose();
    await db.close();
    root.deleteSync(recursive: true);
  });

  Widget harness(Widget child) => MultiProvider(
    providers: [
      ChangeNotifierProvider(
        create: (_) => SettingsProvider(createBusinessTestPreferences()),
      ),
      ChangeNotifierProvider<WorkspaceProvider>.value(value: workspaces),
      ChangeNotifierProvider<ChatService>(create: (_) => _Chat(conversation)),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (_, child) => AppSnackBarOverlay(child: child!),
      home: Scaffold(body: child),
    ),
  );

  Future<void> settle(WidgetTester tester, bool Function() done) async {
    for (var attempt = 0; attempt < 500 && !done(); attempt++) {
      await tester.pump(const Duration(milliseconds: 16));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      expect(tester.takeException(), isNull);
    }
    expect(done(), isTrue, reason: 'Expected UI state after 500 iterations');
  }

  testWidgets(
    'search file chips open the file preview',
    (tester) async {
      await tester.pumpWidget(
        harness(
          WorkspaceToolCardBody(
            part: WorkspaceToolPart(
              id: 'grep',
              toolName: 'grep',
              metadata: const WorkspaceToolMetadata(
                tool: 'grep',
                status: 'ok',
                files: [
                  WorkspaceToolFile(
                    path: '/workspace/note.txt',
                    link: 'kelivo://workspace/note.txt',
                  ),
                ],
              ).toJson(),
            ),
            conversationId: 'c1',
          ),
        ),
      );
      await tester.runAsync(() => tester.tap(find.text('note.txt')));
      await settle(
        tester,
        () =>
            find.byType(FilePreviewFrame).evaluate().isNotEmpty &&
            find.byType(PreviewLoading).evaluate().isEmpty,
      );
      expect(find.byType(FilePreviewFrame), findsOneWidget);
      final previewFile = tester
          .widget<FilePreviewFrame>(find.byType(FilePreviewFrame))
          .file;
      expect(p.basename(previewFile.path), 'note.txt');
      expect(previewFile.path, contains('/workspace-previews/snapshot-'));
      expect(
        await tester.runAsync(previewFile.readAsString),
        'preview content',
      );
      Navigator.of(tester.element(find.byType(FilePreviewFrame))).pop();
      await settle(
        tester,
        () =>
            find.byType(FilePreviewFrame).evaluate().isEmpty &&
            !previewFile.existsSync(),
      );
      expect(previewFile.existsSync(), isFalse);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({TargetPlatform.android}),
  );

  testWidgets(
    'directory chips and markdown links open a read-only file browser',
    (tester) async {
      for (final markdown in [false, true]) {
        await tester.pumpWidget(
          harness(
            markdown
                ? const MarkdownWithCodeHighlight(
                    text: '[folder](kelivo://workspace/folder)',
                    conversationId: 'c1',
                  )
                : const WorkspaceFileChip(
                    path: '/workspace/folder',
                    link: 'kelivo://workspace/folder',
                    isDirectory: true,
                    conversationId: 'c1',
                  ),
          ),
        );
        await tester.runAsync(() => tester.tap(find.text('folder').first));
        await settle(
          tester,
          () =>
              find.byType(FileBrowser).evaluate().isNotEmpty &&
              find.text('child.txt').evaluate().isNotEmpty,
        );
        expect(find.byType(FileBrowser), findsOneWidget);
        final browser = tester.widget<FileBrowser>(find.byType(FileBrowser));
        expect(browser.readOnly, isTrue);
        expect(browser.root.path, p.join(root.path, 'folder'));
        expect(
          browser.modelPathOf(p.join(root.path, 'folder', 'child.txt')),
          p.join(root.path, 'folder', 'child.txt'),
        );
        expect(find.text('child.txt'), findsOneWidget);
        Navigator.of(tester.element(find.byType(FileBrowser))).pop();
        await settle(tester, () => find.byType(FileBrowser).evaluate().isEmpty);
      }
    },
    variant: TargetPlatformVariant({TargetPlatform.android}),
  );

  testWidgets('linked HTML serves original page assets within its grant', (
    tester,
  ) async {
    final pages = Directory(p.join(root.path, 'pages'))..createSync();
    final html = File(p.join(pages.path, 'index.html'))
      ..writeAsStringSync('<script src="app.js"></script><h1>Linked</h1>');
    File(p.join(pages.path, 'app.js')).writeAsStringSync('linked asset marker');
    File(p.join(root.path, 'other.js')).writeAsStringSync('workspace secret');
    final outside = Directory.systemTemp.createTempSync('html_link_outside_');
    addTearDown(() => outside.deleteSync(recursive: true));
    final secret = File(p.join(outside.path, 'secret.js'))
      ..writeAsStringSync('outside secret');
    Link(p.join(pages.path, 'escape.js')).createSync(secret.path);
    final previousWebView = WebViewPlatform.instance;
    final platform = _HtmlLoadPlatform();
    WebViewPlatform.instance = platform;
    addTearDown(
      () => WebViewPlatform.instance = previousWebView ?? FakeWebViewPlatform(),
    );
    await tester.pumpWidget(
      harness(
        const WorkspaceFileChip(
          path: '/workspace/pages/index.html',
          link: 'kelivo://workspace/pages/index.html',
          conversationId: 'c1',
        ),
      ),
    );
    await tester.runAsync(() => tester.tap(find.text('index.html')));
    for (
      var attempt = 0;
      attempt < 500 &&
          (!platform.loaded.isCompleted ||
              find.byType(FilePreviewFrame).evaluate().isEmpty);
      attempt++
    ) {
      // Route construction creates the native HTTP listener. Keep it in the
      // real zone so an actual HTTP request need not wait for FakeAsync pumps.
      await tester.runAsync(
        () => tester.pump(const Duration(milliseconds: 16)),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      expect(find.byType(PreviewError), findsNothing);
    }
    expect(
      platform.loaded.isCompleted,
      isTrue,
      reason: 'Expected HTML load after 500 iterations',
    );
    expect(find.byType(FilePreviewFrame), findsOneWidget);
    final uri = await platform.loaded.future;
    expect(uri.scheme, 'http');
    expect(uri.host, '127.0.0.1');
    final frame = tester.widget<FilePreviewFrame>(
      find.byType(FilePreviewFrame),
    );
    expect(frame.file.path, contains('/workspace-previews/snapshot-'));
    expect(frame.file.path, isNot(html.path));
    expect(frame.sourceFile?.path, html.path);
    expect(frame.accessRoot, root.path);
    await tester.runAsync(
      () => HttpOverrides.runWithHttpOverrides(() async {
        final client = HttpClient();
        try {
          final response = await (await client.getUrl(
            uri.resolve('app.js'),
          )).close();
          expect(response.statusCode, HttpStatus.ok);
          expect(
            await response.transform(utf8.decoder).join(),
            'linked asset marker',
          );
          for (final resource in ['escape.js', '../other.js']) {
            final denied = await (await client.getUrl(
              uri.resolve(resource),
            )).close();
            expect(denied.statusCode, HttpStatus.forbidden);
            expect(
              await denied.transform(utf8.decoder).join(),
              isNot(contains('secret')),
            );
          }
        } finally {
          client.close(force: true);
        }
      }, _LiveHttpOverrides()),
    );
    final htmlState = tester.state<HtmlFilePreviewState>(
      find.byType(HtmlFilePreview),
    );
    await tester.runAsync(() => tester.pumpWidget(const SizedBox()));
    await tester.runAsync(() => htmlState.serverClosed);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shell images use the bounded shared thumbnail loader', (
    tester,
  ) async {
    final imageFile = File(p.join(root.path, 'plot.png'));
    await tester.runAsync(
      () => imageFile.writeAsBytes(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/Kz0AAAAASUVORK5CYII=',
        ),
      ),
    );
    await tester.runAsync(
      () => tester.pumpWidget(
        harness(
          ProducedFilesRow(
            conversationId: 'c1',
            parts: [
              WorkspaceToolPart(
                id: 'shell-image',
                toolName: 'shell',
                metadata: const WorkspaceToolMetadata(
                  tool: 'shell',
                  status: 'ok',
                  files: [
                    WorkspaceToolFile(
                      path: '/workspace/plot.png',
                      link: 'kelivo://workspace/plot.png',
                      role: WorkspaceFileRole.created,
                    ),
                  ],
                ).toJson(),
              ),
            ],
          ),
        ),
      ),
    );
    await settle(
      tester,
      () => find.byType(WorkspaceFileThumbnail).evaluate().isNotEmpty,
    );
    expect(find.byType(WorkspaceFileThumbnail), findsOneWidget);
    expect(
      tester
          .widget<WorkspaceFileThumbnail>(find.byType(WorkspaceFileThumbnail))
          .entry
          .hostPath,
      imageFile.path,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'missing files report their state instead of silently doing nothing',
    (tester) async {
      await tester.pumpWidget(
        harness(
          const WorkspaceFileChip(
            path: 'missing.txt',
            link: 'kelivo://workspace/missing.txt',
            conversationId: 'c1',
          ),
        ),
      );
      await tester.runAsync(() => tester.tap(find.text('missing.txt')));
      await settle(
        tester,
        () => find.text('File no longer exists').evaluate().isNotEmpty,
      );
      expect(find.text('File no longer exists'), findsOneWidget);
      expect(find.byType(FilePreviewFrame), findsNothing);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    },
  );
}
