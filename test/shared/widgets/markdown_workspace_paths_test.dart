import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/link.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'package:Kelivo/core/database/app_database.dart';
import 'package:Kelivo/core/database/extension_entity_store.dart';
import 'package:Kelivo/core/models/conversation.dart';
import 'package:Kelivo/core/models/workspace.dart';
import 'package:Kelivo/core/models/workspace_binding.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/providers/workspace_provider.dart';
import 'package:Kelivo/core/services/chat/chat_service.dart';
import 'package:Kelivo/features/workspace/widgets/files/file_browser.dart';
import 'package:Kelivo/features/workspace/widgets/preview/file_preview.dart';
import 'package:Kelivo/features/workspace/widgets/preview/preview_states.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/widgets/markdown_with_highlight.dart';
import 'package:Kelivo/shared/widgets/snackbar.dart';

import '../../support/business_test_harness.dart';
import '../../support/fake_webview_platform.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
}

class _Chats extends ChatService {
  _Chats(this.conversations);
  final Map<String, Conversation> conversations;
  int conversationLookups = 0;
  @override
  String? get currentConversationId => 'unbound';
  @override
  Conversation? getConversation(String id) {
    conversationLookups++;
    return conversations[id];
  }
}

class _Launcher extends UrlLauncherPlatform {
  final launched = <String>[];
  @override
  LinkDelegate? get linkDelegate => null;
  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return true;
  }
}

void main() {
  late Directory fixture;
  late Directory workspace;
  late AppDatabase database;
  late WorkspaceProvider workspaces;
  late SettingsProvider settings;
  late _Chats chats;
  late PathProviderPlatform oldPaths;
  late UrlLauncherPlatform oldLauncher;
  late _Launcher launcher;

  setUp(() async {
    fixture = await Directory(
      p.join(Directory.current.path, '.dart_tool'),
    ).createTemp('markdown_workspace_paths_');
    workspace = await Directory(p.join(fixture.path, 'workspace')).create();
    final documents = await Directory(
      p.join(fixture.path, 'documents'),
    ).create();
    final site = await Directory(p.join(workspace.path, 'site')).create();
    await File(p.join(site.path, 'note.txt')).writeAsString('workspace marker');
    await File(
      p.join(workspace.path, '#note.txt'),
    ).writeAsString('hash marker');
    await File(
      p.join(site.path, 'index.html'),
    ).writeAsString('<h1>Workspace site</h1>');
    await File(
      p.join(site.path, 'hello world.txt'),
    ).writeAsString('space marker');
    await File(
      p.join(fixture.path, 'outside.txt'),
    ).writeAsString('outside marker');
    await Link(
      p.join(site.path, 'escape.txt'),
    ).create(p.join(fixture.path, 'outside.txt'));
    await Link(p.join(workspace.path, 'escape-dir')).create(fixture.path);
    await Link(
      p.join(site.path, 'inside.txt'),
    ).create(p.join(site.path, 'note.txt'));
    oldPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(documents.path);
    oldLauncher = UrlLauncherPlatform.instance;
    launcher = _Launcher();
    UrlLauncherPlatform.instance = launcher;
    database = AppDatabase(NativeDatabase.memory());
    workspaces = WorkspaceProvider(store: ExtensionEntityStore(database));
    await workspaces.loaded;
    final folder = await workspaces.create(
      name: 'Project',
      kind: WorkspaceKind.linked,
      hostPath: workspace.path,
    );
    chats = _Chats({
      'bound': Conversation(
        id: 'bound',
        title: 'Bound',
        extras: WorkspaceBinding(workspaceId: folder.id).applyTo({}),
      ),
      'unbound': Conversation(id: 'unbound', title: 'Unbound'),
    });
    settings = SettingsProvider(createBusinessTestPreferences());
    await settings.loaded;
  });

  tearDown(() async {
    settings.dispose();
    chats.dispose();
    workspaces.dispose();
    await database.close();
    PathProviderPlatform.instance = oldPaths;
    UrlLauncherPlatform.instance = oldLauncher;
    await fixture.delete(recursive: true);
  });

  Future<AppLocalizations> pumpLink(
    WidgetTester tester,
    String source, {
    String conversationId = 'bound',
  }) async {
    addTearDown(() async {
      AppSnackBarManager().dismissAll();
      await tester.pumpAndSettle();
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<WorkspaceProvider>.value(value: workspaces),
          ChangeNotifierProvider<ChatService>.value(value: chats),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (_, child) => AppSnackBarOverlay(child: child!),
          home: Scaffold(
            body: MarkdownWithCodeHighlight(
              text: '[open file]($source)',
              conversationId: conversationId,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return AppLocalizations.of(tester.element(find.byType(Scaffold)))!;
  }

  Future<void> waitFor(WidgetTester tester, bool Function() done) async {
    final deadline = Stopwatch()..start();
    for (
      var iteration = 0;
      iteration < 500 &&
          !done() &&
          deadline.elapsed < const Duration(seconds: 10);
      iteration++
    ) {
      await tester.runAsync(() => Future<void>(() {}));
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
    }
    expect(
      done(),
      isTrue,
      reason: 'Markdown link did not reach the expected UI state',
    );
  }

  for (final id in ['bound', 'unbound']) {
    for (final entry in const {
      'empty': '#',
      'ASCII': '#section',
      'Russian': '#раздел',
      'ZWSP': '\u200B#раздел',
    }.entries) {
      testWidgets('$id Markdown ignores ${entry.key} fragment', (tester) async {
        await pumpLink(tester, entry.value, conversationId: id);
        addTearDown(() => tester.pumpWidget(const SizedBox()));
        final previousLookups = chats.conversationLookups;
        await tester.tap(find.text('open file'));
        // A file lookup starts synchronously. If it occurs, observe its UI
        // result so unfinished real IO cannot masquerade as an ignored link.
        await waitFor(
          tester,
          () =>
              chats.conversationLookups == previousLookups ||
              launcher.launched.isNotEmpty ||
              find.byType(FileBrowser).evaluate().isNotEmpty ||
              find.byType(FilePreviewFrame).evaluate().isNotEmpty ||
              AppSnackBarManager().activeToasts.isNotEmpty,
        );
        expect(chats.conversationLookups, previousLookups);
        expect(launcher.launched, isEmpty);
        expect(find.byType(FileBrowser), findsNothing);
        expect(find.byType(FilePreviewFrame), findsNothing);
        expect(AppSnackBarManager().activeToasts, isEmpty);
        expect(find.text('open file'), findsOneWidget);
        expect(
          Navigator.of(tester.element(find.text('open file'))).canPop(),
          isFalse,
        );
      });
    }
  }

  for (final source in [
    '/workspace/site/note.txt',
    'file:///workspace/site/note.txt',
    'site/note.txt',
    './site/note.txt',
    'site/hello%20world.txt',
    '/workspace/site/inside.txt',
    'site/note.txt#раздел',
    '/workspace/site/note.txt#section',
    'file:///workspace/site/note.txt#раздел',
    '%23note.txt',
  ]) {
    testWidgets('workspace Markdown opens $source with a checked preview', (
      tester,
    ) async {
      await pumpLink(tester, source);
      await tester.tap(find.text('open file'));
      await waitFor(
        tester,
        () =>
            find.byType(FilePreviewFrame).evaluate().isNotEmpty &&
            find.byType(PreviewLoading).evaluate().isEmpty,
      );
      final preview = tester.widget<FilePreviewFrame>(
        find.byType(FilePreviewFrame),
      );
      expect(preview.sourceFile?.path, startsWith(workspace.path));
      expect(preview.accessRoot, workspace.path);
      expect(
        await tester.runAsync(preview.file.readAsString),
        const {
              'site/hello%20world.txt': 'space marker',
              '%23note.txt': 'hash marker',
            }[source] ??
            'workspace marker',
      );
      expect(launcher.launched, isEmpty);
      Navigator.of(tester.element(find.byType(FilePreviewFrame))).pop();
      await waitFor(
        tester,
        () =>
            find.byType(FilePreviewFrame).evaluate().isEmpty &&
            !preview.file.existsSync(),
      );
    });
  }

  for (final source in [
    '/workspace/site/index.html',
    'file:///workspace/site/index.html',
    'site/index.html',
  ]) {
    testWidgets('ACP Markdown opens $source in the HTML preview', (
      tester,
    ) async {
      final previousWebView = WebViewPlatform.instance;
      WebViewPlatform.instance = FakeWebViewPlatform();
      FakeWebViewPlatform.lastCreated = null;
      addTearDown(
        () =>
            WebViewPlatform.instance = previousWebView ?? FakeWebViewPlatform(),
      );
      await pumpLink(tester, source);
      await tester.tap(find.text('open file'));
      await waitFor(
        tester,
        () =>
            find.byType(HtmlFilePreview).evaluate().isNotEmpty &&
            FakeWebViewPlatform.lastCreated?.currentUrlSync?.startsWith(
                  'http://127.0.0.1:',
                ) ==
                true,
      );
      final frame = tester.widget<FilePreviewFrame>(
        find.byType(FilePreviewFrame),
      );
      expect(
        frame.sourceFile?.path,
        p.join(workspace.path, 'site', 'index.html'),
      );
      expect(frame.accessRoot, workspace.path);
      expect(frame.file.path, contains('workspace-previews/snapshot-'));
      expect(launcher.launched, isEmpty);
      final state = tester.state<HtmlFilePreviewState>(
        find.byType(HtmlFilePreview),
      );
      await tester.runAsync(() => tester.pumpWidget(const SizedBox()));
      await tester.runAsync(() => state.serverClosed);
    });
  }

  for (final source in [
    '/etc/passwd',
    'file:///etc/passwd',
    '../outside.txt',
    'site/../../outside.txt',
    '/workspace/../outside.txt',
    'file:///workspace/%2e%2e/outside.txt',
    '%2e%2e/outside.txt',
    '%2e%2e%2foutside.txt',
    '/workspace%2f..%2foutside.txt',
    'file://foreign/workspace/site/note.txt',
    '/workspace/site/escape.txt',
    'escape-dir/outside.txt',
    'kelivo://workspace/%2e%2e/outside.txt',
    '../outside.txt#раздел',
    '%2e%2e/outside.txt#section',
    'file:///workspace/%2e%2e/outside.txt#section',
  ]) {
    testWidgets('workspace Markdown rejects $source in-app', (tester) async {
      final l10n = await pumpLink(tester, source);
      await tester.tap(find.text('open file'));
      await waitFor(
        tester,
        () =>
            find.text(l10n.workspaceFileNotAvailable).evaluate().isNotEmpty ||
            launcher.launched.isNotEmpty,
      );
      expect(find.text(l10n.workspaceFileNotAvailable), findsOneWidget);
      expect(find.byType(FilePreviewFrame), findsNothing);
      expect(launcher.launched, isEmpty);
      await waitFor(tester, () => AppSnackBarManager().activeToasts.isEmpty);
      await tester.pumpAndSettle();
    });
  }

  for (final id in ['bound', 'unbound']) {
    for (final source in [
      'http://example.com/path',
      'https://example.com/path',
      'http://example.com/path#section',
      'https://example.com/path#section',
    ]) {
      testWidgets('$id Markdown retains external $source', (tester) async {
        await pumpLink(tester, source, conversationId: id);
        await tester.tap(find.text('open file'));
        await tester.pump();
        expect(launcher.launched, [source]);
        expect(find.byType(FilePreviewFrame), findsNothing);
      });
    }
  }

  for (final source in [
    'file:///workspace/site/note.txt',
    'site/note.txt',
    '/workspace/site/note.txt',
    'file:///workspace/site/note.txt#section',
    'site/note.txt#section',
  ]) {
    testWidgets('unbound chat retains existing $source behavior', (
      tester,
    ) async {
      await pumpLink(tester, source, conversationId: 'unbound');
      await tester.tap(find.text('open file'));
      await tester.pump();
      expect(launcher.launched, [
        source.startsWith('file:') ? source : 'https://$source',
      ]);
      expect(find.byType(FilePreviewFrame), findsNothing);
    });
  }

  testWidgets('unbound chat retains domain link normalization', (tester) async {
    await pumpLink(tester, 'example.com/path', conversationId: 'unbound');
    await tester.tap(find.text('open file'));
    await tester.pump();
    expect(launcher.launched, ['https://example.com/path']);
  });
}
