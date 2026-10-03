import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:Kelivo/core/models/workspace.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/features/workspace/pages/workspace_files_page.dart';
import 'package:Kelivo/features/workspace/widgets/files/file_browser.dart';
import 'package:Kelivo/features/workspace/widgets/files/file_browser_ops.dart';
import 'package:Kelivo/features/workspace/widgets/files/workspace_file_thumbnail.dart';
import 'package:Kelivo/features/workspace/widgets/preview/file_preview.dart';
import 'package:Kelivo/features/workspace/widgets/preview/preview_states.dart';
import 'package:Kelivo/icons/lucide_adapter.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/widgets/custom_bottom_sheet.dart';
import 'package:Kelivo/shared/widgets/ios_settings_rows.dart';
import 'package:Kelivo/shared/widgets/ios_tactile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/link.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../../../../support/business_test_harness.dart';
import '../../../../support/fake_webview_platform.dart';

class _PreviewPaths extends PathProviderPlatform {
  _PreviewPaths(this.root);
  final String root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
}

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

class _PreviewLauncher extends UrlLauncherPlatform {
  final launched = Completer<Uri>();
  @override
  LinkDelegate? get linkDelegate => null;
  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.complete(Uri.parse(url));
    return true;
  }
}

Future<void> _flushIo(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 30)),
  );
}

Future<void> _reload(WidgetTester tester) async {
  await _flushIo(tester);
  final state = tester.state<FileBrowserState>(find.byType(FileBrowser));
  await tester.runAsync(state.refreshEntries);
  await tester.pump();
}

Future<void> _finishMutation(
  WidgetTester tester,
  Completer<void> completed,
) async {
  // Native IO returns outside FakeAsync. Pump the queued continuation between
  // real event-loop turns until the runner reports the actual completed write.
  while (!completed.isCompleted) {
    await tester.pump();
    await tester.runAsync(() => Future<void>(() {}));
  }
  await completed.future;
}

Future<void> _pumpUi(WidgetTester tester) async {
  await _flushIo(tester);
  await tester.pump();
  await tester.pumpAndSettle();
}

Future<void> _tapFormConfirm(WidgetTester tester) async {
  final confirm = find
      .descendant(
        of: find.byKey(const ValueKey<String>('workspace-prompt-confirm')),
        matching: find.byType(GestureDetector),
      )
      .last;
  await tester.ensureVisible(confirm);
  await tester.pump();
  await tester.runAsync(() => tester.tap(confirm));
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  final sheetScrollable = find.descendant(
    of: find.byType(BottomSheet),
    matching: find.byType(Scrollable),
  );
  if (sheetScrollable.evaluate().isNotEmpty) {
    await tester.scrollUntilVisible(
      finder,
      80,
      scrollable: sheetScrollable.first,
    );
  } else {
    await tester.ensureVisible(finder);
  }
  await tester.pump();
  await tester.runAsync(() => tester.tap(finder));
  await _pumpUi(tester);
}

Widget _harness({required Widget child}) {
  return ChangeNotifierProvider(
    create: (_) => SettingsProvider(createBusinessTestPreferences()),
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

FileBrowser _browser(Directory root, {FileMutationRunner? mutationRunner}) {
  return FileBrowser(
    root: root,
    rootLabel: 'Root',
    modelPathOf: (host) => host,
    mutationRunner: mutationRunner,
  );
}

class _PhoneFilesAppBar extends StatefulWidget {
  const _PhoneFilesAppBar({required this.root, required this.workspace});

  final Directory root;
  final Workspace workspace;

  @override
  State<_PhoneFilesAppBar> createState() => _PhoneFilesAppBarState();
}

class _PhoneFilesAppBarState extends State<_PhoneFilesAppBar> {
  final GlobalKey<FileBrowserState> _browserKey = GlobalKey<FileBrowserState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: Tooltip(
          message: 'Back',
          child: IosIconButton(
            icon: Lucide.ArrowLeft,
            size: 22,
            minSize: 44,
            onTap: () {},
          ),
        ),
        title: WorkspaceFilesTitle(workspace: widget.workspace),
        actions: [
          if (_browserKey.currentState != null)
            ...fileBrowserToolbarActions(_browserKey.currentState!),
          const SizedBox(width: 12),
        ],
      ),
      body: FileBrowser(
        key: _browserKey,
        root: widget.root,
        rootLabel: widget.workspace.name,
        showToolbar: false,
        modelPathOf: (host) => host,
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('kelivo_file_browser_');
  });

  Future<void> pumpHarness(WidgetTester tester, {required Widget child}) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_harness(child: child));
  }

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('refuses an escape path', () {
    expect(FileBrowserOps.joinInsideRoot(tempDir.path, '../escape'), isNull);
    expect(FileBrowserOps.joinInsideRoot(tempDir.path, '..'), isNull);
    expect(
      FileBrowserOps.resolveInsideRoot(
        tempDir.path,
        p.join(tempDir.path, '..', 'escape'),
      ),
      isNull,
    );
    expect(
      FileBrowserOps.resolveInsideRoot(
        tempDir.path,
        p.join(tempDir.path, 'inside.txt'),
      ),
      isNotNull,
    );
    expect(FileBrowserOps.isValidFileName('../x'), isFalse);
    expect(FileBrowserOps.isValidFileName('ok.txt'), isTrue);
    expect(FileBrowserOps.isValidRelativePath('../etc'), isFalse);
    expect(FileBrowserOps.isValidRelativePath('src/lib'), isTrue);
  });

  testWidgets('lists directories first then files', (tester) async {
    Directory(p.join(tempDir.path, 'docs')).createSync();
    File(p.join(tempDir.path, 'zebra.txt')).writeAsStringSync('z');
    File(p.join(tempDir.path, 'alpha.txt')).writeAsStringSync('a');

    await pumpHarness(tester, child: _browser(tempDir));
    await _reload(tester);

    expect(find.byKey(FileBrowser.itemKey('docs')), findsOneWidget);
    expect(find.byKey(FileBrowser.itemKey('alpha.txt')), findsOneWidget);
    expect(find.byKey(FileBrowser.itemKey('zebra.txt')), findsOneWidget);

    final names = ['docs', 'alpha.txt', 'zebra.txt'];
    final ys = [
      for (final name in names)
        tester.getTopLeft(find.byKey(FileBrowser.itemKey(name))).dy,
    ];
    expect(ys[0], lessThan(ys[1]));
    expect(ys[1], lessThan(ys[2]));
  });

  testWidgets('HTML from Files serves original page assets within its grant', (
    tester,
  ) async {
    final workspace = Directory(p.join(tempDir.path, 'workspace'))
      ..createSync();
    final pages = Directory(p.join(workspace.path, 'pages'))..createSync();
    final html = File(p.join(pages.path, 'index.html'))
      ..writeAsStringSync(
        '<link rel="stylesheet" href="style.css"><h1>Files</h1>',
      );
    File(
      p.join(pages.path, 'style.css'),
    ).writeAsStringSync('files asset marker');
    File(
      p.join(workspace.path, 'other.css'),
    ).writeAsStringSync('workspace secret');
    final outside = File(p.join(tempDir.path, 'outside.css'))
      ..writeAsStringSync('outside secret');
    Link(p.join(pages.path, 'escape.css')).createSync(outside.path);
    final appData = Directory(p.join(tempDir.path, 'app-data'))..createSync();
    final previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _PreviewPaths(appData.path);
    final previousWebView = WebViewPlatform.instance;
    final platform = _HtmlLoadPlatform();
    WebViewPlatform.instance = platform;
    final previousLauncher = UrlLauncherPlatform.instance;
    final launcher = _PreviewLauncher();
    UrlLauncherPlatform.instance = launcher;
    addTearDown(() {
      PathProviderPlatform.instance = previousPaths;
      WebViewPlatform.instance = previousWebView ?? FakeWebViewPlatform();
      UrlLauncherPlatform.instance = previousLauncher;
    });
    addTearDown(closePreviewFileBrowserServer);

    await pumpHarness(
      tester,
      child: FileBrowser(
        root: pages,
        accessRoot: workspace.path,
        rootLabel: 'Pages',
        modelPathOf: (host) => host,
      ),
    );
    await _reload(tester);
    await tester.runAsync(
      () => tester.tap(find.byKey(FileBrowser.itemKey('index.html'))),
    );
    while (!platform.loaded.isCompleted) {
      // Route construction creates the native HTTP listener. Keep it in the
      // real zone so an actual HTTP request need not wait for FakeAsync pumps.
      await tester.runAsync(
        () => tester.pump(const Duration(milliseconds: 16)),
      );
      await tester.runAsync(() => Future<void>(() {}));
      expect(find.byType(PreviewError), findsNothing);
    }
    final uri = await platform.loaded.future;
    expect(uri.scheme, 'http');
    expect(uri.host, '127.0.0.1');
    final frame = tester.widget<FilePreviewFrame>(
      find.byType(FilePreviewFrame),
    );
    expect(frame.file.path, contains('/workspace-previews/snapshot-'));
    expect(frame.file.path, isNot(html.path));
    expect(frame.sourceFile?.path, html.path);
    expect(frame.accessRoot, workspace.path);
    await tester.runAsync(
      () => HttpOverrides.runWithHttpOverrides(() async {
        final client = HttpClient();
        try {
          final response = await (await client.getUrl(
            uri.resolve('style.css'),
          )).close();
          expect(response.statusCode, HttpStatus.ok);
          expect(
            await response.transform(utf8.decoder).join(),
            'files asset marker',
          );
          for (final resource in ['escape.css', '../other.css']) {
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
    await tester.runAsync(
      () => tester.tap(find.byKey(FilePreviewFrame.openInBrowserActionKey)),
    );
    while (!launcher.launched.isCompleted) {
      await tester.pump();
      await tester.runAsync(() => Future<void>(() {}));
    }
    final browserUri = await launcher.launched.future;
    expect(browserUri.scheme, 'http');
    expect(browserUri.host, '127.0.0.1');
    await tester.runAsync(
      () => HttpOverrides.runWithHttpOverrides(() async {
        final client = HttpClient();
        try {
          final response = await (await client.getUrl(
            browserUri.resolve('style.css'),
          )).close();
          expect(response.statusCode, HttpStatus.ok);
          expect(
            await response.transform(utf8.decoder).join(),
            'files asset marker',
          );
          final denied = await (await client.getUrl(
            browserUri.resolve('escape.css'),
          )).close();
          expect(denied.statusCode, HttpStatus.forbidden);
          await denied.drain<void>();
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

  testWidgets('navigates into a directory and breadcrumb returns', (
    tester,
  ) async {
    Directory(p.join(tempDir.path, 'docs')).createSync();
    File(p.join(tempDir.path, 'docs', 'readme.md')).writeAsStringSync('# hi');

    await pumpHarness(tester, child: _browser(tempDir));
    await _reload(tester);

    await tester.tap(find.byKey(FileBrowser.itemKey('docs')));
    await _pumpUi(tester);
    await _reload(tester);

    expect(find.byKey(FileBrowser.itemKey('readme.md')), findsOneWidget);
    expect(find.byKey(FileBrowser.itemKey('docs')), findsNothing);

    await tester.tap(find.byKey(FileBrowser.breadcrumbKey('Root')));
    await _pumpUi(tester);
    await _reload(tester);

    expect(find.byKey(FileBrowser.itemKey('docs')), findsOneWidget);
    expect(find.byKey(FileBrowser.itemKey('readme.md')), findsNothing);
  });

  testWidgets('hidden toggle shows dotfiles', (tester) async {
    File(p.join(tempDir.path, 'visible.txt')).writeAsStringSync('v');
    File(p.join(tempDir.path, '.secret')).writeAsStringSync('s');

    await pumpHarness(tester, child: _browser(tempDir));
    await _reload(tester);

    expect(find.byKey(FileBrowser.itemKey('visible.txt')), findsOneWidget);
    expect(find.byKey(FileBrowser.itemKey('.secret')), findsNothing);

    await tester.tap(find.byKey(FileBrowser.hiddenToggleKey));
    await _pumpUi(tester);
    await _reload(tester);

    expect(find.byKey(FileBrowser.itemKey('.secret')), findsOneWidget);
  });

  testWidgets('sort menu orders by size', (tester) async {
    File(p.join(tempDir.path, 'small.txt')).writeAsStringSync('a');
    File(p.join(tempDir.path, 'large.txt')).writeAsStringSync('abcdef');

    await pumpHarness(tester, child: _browser(tempDir));
    await _reload(tester);

    await tester.tap(find.byKey(FileBrowser.sortButtonKey));
    await _pumpUi(tester);
    expect(find.text('Size'), findsOneWidget);
    await tester.tap(find.text('Size'));
    await tester.pumpAndSettle();
    await _reload(tester);

    var smallY = tester
        .getTopLeft(find.byKey(FileBrowser.itemKey('small.txt')))
        .dy;
    var largeY = tester
        .getTopLeft(find.byKey(FileBrowser.itemKey('large.txt')))
        .dy;
    expect(smallY, lessThan(largeY));

    await tester.tap(find.byKey(FileBrowser.sortButtonKey));
    await _pumpUi(tester);
    final descending = find.text('Descending').hitTestable();
    expect(descending, findsOneWidget);
    await tester.tap(descending);
    await tester.pumpAndSettle();
    await _reload(tester);

    smallY = tester.getTopLeft(find.byKey(FileBrowser.itemKey('small.txt'))).dy;
    largeY = tester.getTopLeft(find.byKey(FileBrowser.itemKey('large.txt'))).dy;
    expect(largeY, lessThan(smallY));
  });

  testWidgets('new folder rename and delete through the widget', (
    tester,
  ) async {
    File(p.join(tempDir.path, 'keep.txt')).writeAsStringSync('k');

    final completed = List.generate(3, (_) => Completer<void>());
    var operationIndex = 0;
    await pumpHarness(
      tester,
      child: _browser(
        tempDir,
        mutationRunner: (mutation) async {
          await FileBrowserOps.runMutation(mutation);
          completed[operationIndex++].complete();
        },
      ),
    );
    await _reload(tester);

    await tester.runAsync(() => tester.tap(find.byKey(FileBrowser.newKey)));
    await _pumpUi(tester);
    await _tapVisible(tester, find.text('New folder'));
    await tester.enterText(find.byType(TextField), 'created');
    await _tapFormConfirm(tester);
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await _pumpUi(tester);
    await _reload(tester);
    await _reload(tester);
    await _finishMutation(tester, completed[0]);
    await _reload(tester);
    expect(Directory(p.join(tempDir.path, 'created')).existsSync(), isTrue);
    expect(find.byKey(FileBrowser.itemKey('created')), findsOneWidget);

    await tester.longPress(find.byKey(FileBrowser.itemKey('created')));
    await _pumpUi(tester);
    await tester.runAsync(() => tester.tap(find.text('Rename')));
    await _pumpUi(tester);
    await tester.enterText(find.byType(TextField), 'renamed');
    await _tapFormConfirm(tester);
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await _pumpUi(tester);
    await _reload(tester);
    await _reload(tester);
    await _finishMutation(tester, completed[1]);
    await _reload(tester);
    expect(Directory(p.join(tempDir.path, 'renamed')).existsSync(), isTrue);
    expect(Directory(p.join(tempDir.path, 'created')).existsSync(), isFalse);

    await tester.longPress(find.byKey(FileBrowser.itemKey('renamed')));
    await _pumpUi(tester);
    await tester.runAsync(() => tester.tap(find.text('Delete')));
    await _pumpUi(tester);
    await tester.runAsync(
      () => tester.tap(
        find.byKey(const ValueKey<String>('workspace-confirm-accept')),
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await _pumpUi(tester);
    await _reload(tester);
    await _finishMutation(tester, completed[2]);
    expect(Directory(p.join(tempDir.path, 'renamed')).existsSync(), isFalse);
  });

  testWidgets('rename refuses an escape path', (tester) async {
    File(p.join(tempDir.path, 'safe.txt')).writeAsStringSync('ok');

    await pumpHarness(tester, child: _browser(tempDir));
    await _reload(tester);

    await tester.longPress(find.byKey(FileBrowser.itemKey('safe.txt')));
    await _pumpUi(tester);
    await tester.runAsync(() => tester.tap(find.text('Rename')));
    await _pumpUi(tester);
    await tester.enterText(find.byType(TextField), '../escape.txt');
    await _tapFormConfirm(tester);
    await tester.pump();

    expect(File(p.join(tempDir.path, 'safe.txt')).existsSync(), isTrue);
    expect(
      File(p.join(tempDir.path, '..', 'escape.txt')).existsSync(),
      isFalse,
    );
    expect(
      FileBrowserOps.joinInsideRoot(tempDir.path, '../escape.txt'),
      isNull,
    );
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('folder picker lists directories only and reports rel path', (
    tester,
  ) async {
    Directory(p.join(tempDir.path, 'docs')).createSync();
    File(p.join(tempDir.path, 'skip.txt')).writeAsStringSync('x');

    String? picked;
    await pumpHarness(
      tester,
      child: FileBrowser(
        root: tempDir,
        rootLabel: 'Root',
        modelPathOf: (host) => host,
        pickDirectoryMode: true,
        onPickDirectory: (rel) => picked = rel,
      ),
    );
    await _reload(tester);

    expect(find.byKey(FileBrowser.itemKey('docs')), findsOneWidget);
    expect(find.byKey(FileBrowser.itemKey('skip.txt')), findsNothing);

    await tester.tap(find.byKey(FileBrowser.itemKey('docs')));
    await _pumpUi(tester);
    await _reload(tester);

    await tester.tap(find.byKey(FileBrowser.pickDirectoryKey));
    await tester.pump();
    expect(picked, 'docs');
  });

  testWidgets('showWorkspaceFolderPicker returns the chosen folder', (
    tester,
  ) async {
    Directory(p.join(tempDir.path, 'src')).createSync();
    String? picked;

    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _harness(
        child: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () async {
                picked = await showWorkspaceFolderPicker(
                  context,
                  root: tempDir.path,
                  title: 'Pick folder',
                  rootLabel: 'Root',
                );
              },
              child: const Text('open-picker'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('open-picker'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final browser = find.byType(FileBrowser);
    expect(browser, findsOneWidget);
    await tester.runAsync(
      tester.state<FileBrowserState>(browser).refreshEntries,
    );
    await tester.pump();

    await tester.tap(find.byKey(FileBrowser.itemKey('src')));
    await tester.pump();
    await tester.runAsync(
      tester.state<FileBrowserState>(find.byType(FileBrowser)).refreshEntries,
    );
    await tester.pump();

    await tester.tap(find.byKey(FileBrowser.pickDirectoryKey));
    await tester.pump();
    expect(picked, 'src');
  });

  testWidgets('phone AppBar shows sort, new, more and a 12-char title', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const name = 'abcdefghijkl';
    final now = DateTime.utc(2026, 1, 1);
    final workspace = Workspace(
      id: 'ws-phone',
      name: name,
      kind: WorkspaceKind.managed,
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      _harness(
        child: _PhoneFilesAppBar(root: tempDir, workspace: workspace),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(FileBrowser.sortButtonKey), findsOneWidget);
    expect(find.byKey(FileBrowser.newKey), findsOneWidget);
    expect(find.byKey(FileBrowser.moreKey), findsOneWidget);
    expect(find.byKey(FileBrowser.hiddenToggleKey), findsNothing);
    expect(find.byKey(FileBrowser.importKey), findsNothing);
    expect(find.byKey(FileBrowser.exportKey), findsNothing);
    expect(find.byKey(FileBrowser.refreshKey), findsNothing);

    expect(
      find.descendant(
        of: find.byType(WorkspaceFilesTitle),
        matching: find.text(name),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(WorkspaceFilesTitle),
        matching: find.byType(WorkspaceKindBadge),
      ),
      findsNothing,
    );
  });

  testWidgets('narrow embedded toolbar collapses to new and more', (
    tester,
  ) async {
    File(p.join(tempDir.path, 'keep.txt')).writeAsStringSync('k');

    await pumpHarness(
      tester,
      child: SizedBox(width: 300, height: 640, child: _browser(tempDir)),
    );
    await _reload(tester);

    expect(find.byKey(FileBrowser.newKey), findsOneWidget);
    expect(find.byKey(FileBrowser.moreKey), findsOneWidget);
    expect(find.byKey(FileBrowser.sortButtonKey), findsNothing);
    expect(find.byKey(FileBrowser.hiddenToggleKey), findsNothing);
    expect(find.byKey(FileBrowser.importKey), findsNothing);
    expect(find.byKey(FileBrowser.exportKey), findsNothing);
    expect(find.byKey(FileBrowser.refreshKey), findsNothing);
  });

  testWidgets('picker footer pads for viewPadding.bottom', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding = FakeViewPadding.zero;
    tester.view.viewPadding = const FakeViewPadding(bottom: 48);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);

    await tester.pumpWidget(
      _harness(
        child: FileBrowser(
          root: tempDir,
          rootLabel: 'Root',
          modelPathOf: (host) => host,
          pickDirectoryMode: true,
          onPickDirectory: (_) {},
        ),
      ),
    );
    await _reload(tester);

    final padding = tester.widget<Padding>(find.byKey(FileBrowser.pickBarKey));
    expect((padding.padding as EdgeInsets).bottom, 64);
    expect(
      tester.getBottomLeft(find.byKey(FileBrowser.pickDirectoryKey)).dy,
      lessThanOrEqualTo(800 - 48),
    );
    expect(find.text('This folder is empty'), findsOneWidget);
    expect(find.text('Use New folder to add a subfolder'), findsOneWidget);
  });

  testWidgets('file list starts at the top of the card', (tester) async {
    File(p.join(tempDir.path, 'alpha.txt')).writeAsStringSync('a');

    await tester.pumpWidget(
      _harness(
        child: Builder(
          builder: (context) {
            final media = MediaQuery.of(context);
            return MediaQuery(
              data: media.copyWith(padding: const EdgeInsets.only(top: 59)),
              child: _browser(tempDir),
            );
          },
        ),
      ),
    );
    await _reload(tester);

    final listTop = tester.getTopLeft(find.byKey(FileBrowser.listKey)).dy;
    final rowTop = tester
        .getTopLeft(find.byKey(FileBrowser.itemKey('alpha.txt')))
        .dy;
    expect(rowTop - listTop, lessThan(8));
  });

  testWidgets('file rows use a plain icon with no tinted well', (tester) async {
    File(p.join(tempDir.path, 'plain.txt')).writeAsStringSync('a');
    Directory(p.join(tempDir.path, 'docs')).createSync();

    await pumpHarness(tester, child: _browser(tempDir));
    await _reload(tester);

    final fileRow = find.byKey(FileBrowser.itemKey('plain.txt'));
    expect(tester.widget(fileRow), isA<IosNavRow>());
    final fileIcon = tester.widget<Icon>(
      find.descendant(of: fileRow, matching: find.byType(Icon)).first,
    );
    expect(fileIcon.size, 20);
    expect(fileIcon.color?.a, closeTo(0.9, 0.01));
    expect(
      find.descendant(of: fileRow, matching: find.byIcon(Lucide.ChevronRight)),
      findsNothing,
    );

    final leading = tester.widget<SizedBox>(
      find
          .ancestor(
            of: find.byWidget(fileIcon),
            matching: find.byType(SizedBox),
          )
          .first,
    );
    expect(leading.width, 36);
    expect(leading.child, isA<Icon>());

    final folderRow = find.byKey(FileBrowser.itemKey('docs'));
    expect(
      find.descendant(
        of: folderRow,
        matching: find.byIcon(Lucide.ChevronRight),
      ),
      findsNothing,
    );
    expect(find.byKey(FileBrowser.itemMoreKey('plain.txt')), findsOneWidget);
    expect(find.byKey(FileBrowser.itemMoreKey('docs')), findsOneWidget);
  });

  for (final desktop in [false, true]) {
    testWidgets(
      'image rows use thumbnails in ${desktop ? 'desktop' : 'mobile'} lists',
      (tester) async {
        File(p.join(tempDir.path, 'photo.PNG')).createSync();
        File(p.join(tempDir.path, 'notes.txt')).writeAsStringSync('notes');
        Directory(p.join(tempDir.path, 'folder.png')).createSync();
        tester.view.physicalSize = desktop
            ? const Size(1400, 900)
            : const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(_harness(child: _browser(tempDir)));
        await _reload(tester);

        expect(
          find.descendant(
            of: find.byKey(FileBrowser.itemKey('photo.PNG')),
            matching: find.byType(WorkspaceFileThumbnail),
          ),
          findsOneWidget,
        );
        expect(find.byType(WorkspaceFileThumbnail), findsOneWidget);
        expect(
          tester
              .widget<WorkspaceFileThumbnail>(
                find.byType(WorkspaceFileThumbnail),
              )
              .size,
          desktop ? 24 : 32,
        );
        expect(find.byKey(FileBrowser.itemKey('notes.txt')), findsOneWidget);
        expect(find.byKey(FileBrowser.itemKey('folder.png')), findsOneWidget);
        expect(
          tester.getTopLeft(find.text('photo.PNG')).dx,
          tester.getTopLeft(find.text('notes.txt')).dx,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('row more button opens the item action menu', (tester) async {
    File(p.join(tempDir.path, 'notes.txt')).writeAsStringSync('hi');

    await pumpHarness(tester, child: _browser(tempDir));
    await _reload(tester);

    await tester.tap(find.byKey(FileBrowser.itemMoreKey('notes.txt')));
    await _pumpUi(tester);

    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Export'), findsOneWidget);
    expect(find.byKey(FileBrowser.itemKey('notes.txt')), findsOneWidget);
  });

  testWidgets('long-press opens a destructive delete action', (tester) async {
    File(p.join(tempDir.path, 'gone.txt')).writeAsStringSync('x');

    await pumpHarness(tester, child: _browser(tempDir));
    await _reload(tester);

    await tester.longPress(find.byKey(FileBrowser.itemKey('gone.txt')));
    await _pumpUi(tester);

    expect(find.byKey(CustomBottomSheet.panelKey), findsNothing);
    expect(find.text('Delete'), findsOneWidget);
    final error = Theme.of(
      tester.element(find.text('Delete')),
    ).colorScheme.error;
    expect(tester.widget<Text>(find.text('Delete')).style?.color, error);
  });

  testWidgets('more menu opens the workspace terminal', (tester) async {
    var opened = 0;
    File(p.join(tempDir.path, 'keep.txt')).writeAsStringSync('k');

    await pumpHarness(
      tester,
      child: SizedBox(
        width: 300,
        height: 640,
        child: FileBrowser(
          root: tempDir,
          rootLabel: 'Root',
          modelPathOf: (host) => host,
          onOpenTerminal: () => opened++,
        ),
      ),
    );
    await _reload(tester);

    await tester.tap(find.byKey(FileBrowser.moreKey));
    await _pumpUi(tester);
    expect(find.byKey(FileBrowser.terminalKey), findsOneWidget);
    await tester.tap(find.byKey(FileBrowser.terminalKey));
    await _pumpUi(tester);
    expect(opened, 1);
  });

  testWidgets('more menu omits terminal without a callback', (tester) async {
    File(p.join(tempDir.path, 'keep.txt')).writeAsStringSync('k');

    await pumpHarness(
      tester,
      child: SizedBox(width: 300, height: 640, child: _browser(tempDir)),
    );
    await _reload(tester);

    await tester.tap(find.byKey(FileBrowser.moreKey));
    await _pumpUi(tester);
    expect(find.byKey(FileBrowser.terminalKey), findsNothing);
  });

  testWidgets('sort sheet returns the chosen field', (tester) async {
    File(p.join(tempDir.path, 'b.txt')).writeAsStringSync('bb');
    File(p.join(tempDir.path, 'a.txt')).writeAsStringSync('a');

    await pumpHarness(tester, child: _browser(tempDir));
    await _reload(tester);

    await tester.tap(find.byKey(FileBrowser.sortButtonKey));
    await _pumpUi(tester);
    expect(find.text('Size'), findsOneWidget);
    expect(find.text('Name'), findsOneWidget);
    await tester.tap(find.text('Size'));
    await tester.pumpAndSettle();
    await _reload(tester);

    final aY = tester.getTopLeft(find.byKey(FileBrowser.itemKey('a.txt'))).dy;
    final bY = tester.getTopLeft(find.byKey(FileBrowser.itemKey('b.txt'))).dy;
    expect(aY, lessThan(bY));
  });

  testWidgets('a sheet reads the list offset before pulling itself down', (
    tester,
  ) async {
    for (var i = 0; i < 40; i += 1) {
      File(
        p.join(tempDir.path, 'file_${i.toString().padLeft(2, '0')}.txt'),
      ).writeAsStringSync('x');
    }
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late ScrollController listController;

    await tester.pumpWidget(
      _harness(
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () => showCustomBottomSheet<void>(
              context: context,
              title: 'Files',
              partialHeightFactor: 0.9,
              expandedHeightFactor: 0.9,
              builder: (sheetContext, controller) {
                listController = controller;
                return FileBrowser(
                  root: tempDir,
                  rootLabel: 'Root',
                  modelPathOf: (host) => host,
                  scrollController: controller,
                );
              },
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await _reload(tester);
    await tester.pumpAndSettle();

    final panel = find.byKey(CustomBottomSheet.panelKey);
    final sheetTop = tester.getTopLeft(panel).dy;

    await tester.drag(find.byKey(FileBrowser.listKey), const Offset(0, -200));
    await tester.pumpAndSettle();
    final scrolled = listController.offset;
    expect(scrolled, greaterThan(0));
    expect(tester.getTopLeft(panel).dy, sheetTop);

    // Pulling down mid-list scrolls back up; the sheet only follows once the
    // list has nothing left to give.
    await tester.drag(find.byKey(FileBrowser.listKey), const Offset(0, 100));
    await tester.pumpAndSettle();
    expect(listController.offset, lessThan(scrolled));
    expect(tester.getTopLeft(panel).dy, sheetTop);
  });
}
