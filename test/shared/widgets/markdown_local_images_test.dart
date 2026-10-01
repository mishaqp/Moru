import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/link.dart';

import 'package:Kelivo/core/database/app_database.dart';
import 'package:Kelivo/core/database/extension_entity_store.dart';
import 'package:Kelivo/core/models/conversation.dart';
import 'package:Kelivo/core/models/workspace.dart';
import 'package:Kelivo/core/models/workspace_binding.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/providers/workspace_provider.dart';
import 'package:Kelivo/core/services/chat/chat_service.dart';
import 'package:Kelivo/core/services/workspace/local_image_access.dart';
import 'package:Kelivo/features/chat/pages/image_viewer_page.dart';
import 'package:Kelivo/core/services/workspace/workspace_tool_metadata.dart';
import 'package:Kelivo/features/chat/widgets/produced_files_row.dart';
import 'package:Kelivo/features/chat/widgets/workspace_tool_ui.dart';
import 'package:Kelivo/features/workspace/widgets/files/workspace_file_thumbnail.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/widgets/markdown_with_highlight.dart';
import 'package:Kelivo/utils/sandbox_path_resolver.dart';

import '../../support/business_test_harness.dart';

const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/Kz0AAAAASUVORK5CYII=';
const _dataImage = 'data:image/png;base64,$_png';

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
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

class _Chats extends ChatService {
  _Chats(this.conversation);
  final Conversation conversation;
  @override
  Conversation? getConversation(String id) =>
      id == conversation.id ? conversation : null;
}

MemoryImage? _memoryProvider(ImageProvider provider) => switch (provider) {
  MemoryImage image => image,
  ResizeImage image => _memoryProvider(image.imageProvider),
  _ => null,
};

void main() {
  late Directory fixture;
  late Directory workspace;
  late Directory documents;
  late Directory outside;
  late AppDatabase database;
  late WorkspaceProvider workspaces;
  late SettingsProvider settings;
  late _Chats chats;
  late PathProviderPlatform oldPaths;

  setUp(() async {
    // Linux's system temp is an allowed model zone. Put unrelated app/private
    // fixtures outside it so they do not accidentally become authorized tmp.
    fixture = await Directory(
      p.join(Directory.current.path, '.dart_tool'),
    ).createTemp('markdown_image_boundary_');
    workspace = await Directory(p.join(fixture.path, 'workspace')).create();
    documents = await Directory(p.join(fixture.path, 'documents')).create();
    outside = await Directory(p.join(fixture.path, 'outside')).create();
    oldPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(documents.path);
    SandboxPathResolver.debugSetDirs(
      docsDir: documents.path,
      supportDir: documents.path,
    );
    database = AppDatabase(NativeDatabase.memory());
    workspaces = WorkspaceProvider(store: ExtensionEntityStore(database));
    await workspaces.loaded;
    final folder = await workspaces.create(
      name: 'Project',
      kind: WorkspaceKind.linked,
      hostPath: workspace.path,
    );
    chats = _Chats(
      Conversation(
        id: 'chat',
        title: 'Test',
        extras: WorkspaceBinding(workspaceId: folder.id).applyTo({}),
      ),
    );
    settings = SettingsProvider(createBusinessTestPreferences());
    await settings.loaded;
    await File(
      p.join(workspace.path, 'inside.png'),
    ).writeAsBytes(base64Decode(_png));
    await File(
      p.join(outside.path, 'outside.png'),
    ).writeAsBytes(base64Decode(_png));
    await File(
      p.join(documents.path, 'private-config.png'),
    ).writeAsBytes(base64Decode(_png));
  });

  tearDown(() async {
    settings.dispose();
    chats.dispose();
    workspaces.dispose();
    await database.close();
    PathProviderPlatform.instance = oldPaths;
    SandboxPathResolver.debugSetDirs(docsDir: null, supportDir: null);
    await fixture.delete(recursive: true);
  });

  Widget container(Widget child) => MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsProvider>.value(value: settings),
      ChangeNotifierProvider<WorkspaceProvider>.value(value: workspaces),
      ChangeNotifierProvider<ChatService>.value(value: chats),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );

  Widget harness(String markdown, {String conversationId = 'chat'}) =>
      container(
        MarkdownWithCodeHighlight(
          text: markdown,
          conversationId: conversationId,
        ),
      );

  Future<void> completeReads(WidgetTester tester) async {
    final reads = tester
        .widgetList<FutureBuilder<Uint8List?>>(
          find.byType(FutureBuilder<Uint8List?>),
        )
        .map((builder) => builder.future)
        .whereType<Future<Uint8List?>>()
        .toList();
    var remaining = reads.length;
    for (final read in reads) {
      read.whenComplete(() => remaining--);
    }
    final deadline = Stopwatch()..start();
    for (
      var iteration = 0;
      iteration < 500 &&
          remaining > 0 &&
          deadline.elapsed < const Duration(seconds: 10);
      iteration++
    ) {
      // Flush widget-zone continuations between actual IO event boundaries.
      // Neither sleeps nor a fixed number of frames decide readiness.
      await tester.runAsync(() => Future<void>(() {}));
      await tester.pump();
    }
    expect(remaining, 0, reason: 'checked image reads did not finish');
  }

  Future<void> completeViewer(WidgetTester tester) async {
    final deadline = Stopwatch()..start();
    for (
      var iteration = 0;
      iteration < 500 &&
          find.byType(ImageViewerPage).evaluate().isEmpty &&
          deadline.elapsed < const Duration(seconds: 10);
      iteration++
    ) {
      await tester.runAsync(() => Future<void>(() {}));
      await tester.pump();
    }
    expect(find.byType(ImageViewerPage), findsOneWidget);
    await tester.pumpAndSettle();
  }

  for (final mode in ['outside', 'private', 'file-link', 'middle-link']) {
    testWidgets('local markdown rejects $mode image paths', (tester) async {
      final source = switch (mode) {
        'outside' => p.join(outside.path, 'outside.png'),
        'private' => p.join(documents.path, 'private-config.png'),
        'file-link' => p.join(workspace.path, 'escape.png'),
        _ => p.join(workspace.path, 'escape-dir', 'outside.png'),
      };
      if (mode == 'file-link') {
        await tester.runAsync(
          () => Link(source).create(p.join(outside.path, 'outside.png')),
        );
      } else if (mode == 'middle-link') {
        await tester.runAsync(
          () => Link(p.dirname(source)).create(outside.path),
        );
      }
      await tester.pumpWidget(harness('![24x24]($source)'));
      await completeReads(tester);

      expect(find.byType(Image), findsNothing);
      expect(find.byType(ImageViewerPage), findsNothing);
    });
  }

  for (final mode in [
    'host',
    'guest',
    'file-guest',
    'relative',
    'dot-relative',
    'inside-link',
    'kelivo-link',
  ]) {
    testWidgets('local markdown keeps $mode images as checked bytes', (
      tester,
    ) async {
      final source = switch (mode) {
        'host' => p.join(workspace.path, 'inside.png'),
        'guest' => '/workspace/inside.png',
        'file-guest' => 'file:///workspace/inside.png',
        'relative' => 'inside.png',
        'dot-relative' => './inside.png',
        'inside-link' => p.join(workspace.path, 'alias.png'),
        _ => 'kelivo://workspace/inside.png',
      };
      if (mode == 'inside-link') {
        await tester.runAsync(
          () => Link(source).create(p.join(workspace.path, 'inside.png')),
        );
      }
      await tester.pumpWidget(harness('![24x24]($source)'));
      await completeReads(tester);

      final image = tester.widget<Image>(find.byType(Image));
      expect(_memoryProvider(image.image)?.bytes, base64Decode(_png));
    });
  }

  for (final source in [
    '/workspace/../workspace/inside.png',
    'file:///workspace/%2e%2e/workspace/inside.png',
    '../workspace/inside.png',
    '%2e%2e/workspace/inside.png',
    '/workspace/escape.png',
    'escape-dir/outside.png',
  ]) {
    testWidgets('local Markdown rejects guest/relative escape $source', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await Link(
          p.join(workspace.path, 'escape.png'),
        ).create(p.join(outside.path, 'outside.png'));
        await Link(p.join(workspace.path, 'escape-dir')).create(outside.path);
      });
      await tester.pumpWidget(harness('![24x24]($source)'));
      await completeReads(tester);
      expect(find.byType(Image), findsNothing);
    });
  }

  for (final source in [
    '/workspace/inside.png',
    'file:///workspace/inside.png',
    'inside.png',
  ]) {
    testWidgets('unbound Markdown cannot resolve workspace image $source', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness('![24x24]($source)', conversationId: 'unbound'),
      );
      await completeReads(tester);
      expect(find.byType(Image), findsNothing);
    });
  }

  for (final source in [
    'site/images/logo.png',
    '/workspace/images/logo.png',
    'file:///workspace/images/logo.png',
  ]) {
    testWidgets(
      'unbound colliding Markdown image $source cannot use app artifacts',
      (tester) async {
        final previousLauncher = UrlLauncherPlatform.instance;
        final launcher = _Launcher();
        UrlLauncherPlatform.instance = launcher;
        addTearDown(() => UrlLauncherPlatform.instance = previousLauncher);
        await tester.runAsync(() async {
          for (final path in [
            p.join(documents.path, 'images', 'logo.png'),
            p.join(workspace.path, 'images', 'logo.png'),
            p.join(workspace.path, 'site', 'images', 'logo.png'),
          ]) {
            final file = File(path);
            await file.parent.create(recursive: true);
            await file.writeAsBytes(base64Decode(_png));
          }
        });
        await tester.pumpWidget(
          harness('![24x24]($source)', conversationId: 'unbound'),
        );
        await completeReads(tester);
        final bytes = await tester.runAsync(
          () => readLocalImageBytes(
            source,
            conversationId: 'unbound',
            workspaces: workspaces,
          ),
        );
        expect(bytes, isNull);
        expect(find.byType(Image), findsNothing);
        expect(find.byType(ImageViewerPage), findsNothing);
        expect(launcher.launched, isEmpty);
      },
    );
  }

  for (final mode in [
    'relative',
    'guest',
    'file-guest',
    'host',
    'artifact-host',
    'artifact-file',
  ]) {
    test(
      'Markdown image $mode keeps its source when an artifact has the same name',
      () async {
        final workspaceFile = File(
          p.join(workspace.path, 'site', 'images', 'logo.png'),
        );
        final artifactFile = File(p.join(documents.path, 'images', 'logo.png'));
        await workspaceFile.parent.create(recursive: true);
        await artifactFile.parent.create(recursive: true);
        final workspaceBytes = base64Decode(_png);
        final artifactBytes = [...workspaceBytes, 42];
        await workspaceFile.writeAsBytes(workspaceBytes);
        await artifactFile.writeAsBytes(artifactBytes);
        final source = switch (mode) {
          'relative' => 'site/images/logo.png',
          'guest' => '/workspace/site/images/logo.png',
          'file-guest' => 'file:///workspace/site/images/logo.png',
          'host' => workspaceFile.path,
          'artifact-host' => artifactFile.path,
          _ => artifactFile.uri.toString(),
        };
        final bytes = await readLocalImageBytes(
          source,
          conversationId: 'chat',
          binding: WorkspaceBinding.fromExtras(chats.conversation.extras),
          workspaces: workspaces,
        );
        expect(
          bytes,
          mode.startsWith('artifact') ? artifactBytes : workspaceBytes,
        );
      },
    );
  }

  testWidgets('known upload and session artifacts still load', (tester) async {
    for (final directory in [
      p.join(documents.path, 'upload'),
      p.join(documents.path, 'sessions', 'chat', 'attachments'),
      p.join(documents.path, 'sessions', 'chat', 'outputs'),
    ]) {
      final source = p.join(directory, 'artifact.png');
      await tester.runAsync(() async {
        await Directory(directory).create(recursive: true);
        await File(source).writeAsBytes(base64Decode(_png));
      });
      await tester.pumpWidget(harness('![24x24]($source)'));
      await completeReads(tester);
      final image = tester.widget<Image>(find.byType(Image));
      expect(_memoryProvider(image.image)?.bytes, base64Decode(_png));
    }
  });

  testWidgets('data URI viewer excludes unchecked sibling local paths', (
    tester,
  ) async {
    final private = p.join(documents.path, 'private-config.png');
    await tester.pumpWidget(
      harness('![24x24]($_dataImage)\n\n![24x24]($private)'),
    );
    await completeReads(tester);
    await tester.runAsync(() => tester.tap(find.byType(Image).first));
    await completeViewer(tester);

    final viewer = tester.widget<ImageViewerPage>(find.byType(ImageViewerPage));
    expect(viewer.images, [_dataImage]);
  });

  for (final mode in ['host', 'kelivo']) {
    testWidgets('opening $mode preview keeps bytes after path replacement', (
      tester,
    ) async {
      final path = p.join(workspace.path, 'inside.png');
      final source = mode == 'host' ? path : 'kelivo://workspace/inside.png';
      await tester.pumpWidget(harness('![24x24]($source)'));
      await completeReads(tester);
      await tester.runAsync(() async {
        await File(path).delete();
        await Link(path).create(p.join(outside.path, 'outside.png'));
      });
      await tester.runAsync(() => tester.tap(find.byType(Image)));
      await completeViewer(tester);

      final viewer = tester.widget<ImageViewerPage>(
        find.byType(ImageViewerPage),
      );
      expect(viewer.images, hasLength(1));
      expect(viewer.images.single, startsWith('data:image/'));
      expect(
        base64Decode(viewer.images.single.split(',').last),
        base64Decode(_png),
      );
    });
  }

  testWidgets('produced image thumbnails retain their owning root', (
    tester,
  ) async {
    await tester.pumpWidget(
      container(
        ProducedFilesRow(
          conversationId: 'chat',
          parts: [
            WorkspaceToolPart(
              id: 'created-image',
              toolName: 'write_file',
              metadata: const WorkspaceToolMetadata(
                tool: 'write_file',
                status: 'ok',
                files: [
                  WorkspaceToolFile(
                    path: '/workspace/inside.png',
                    link: 'kelivo://workspace/inside.png',
                    role: WorkspaceFileRole.created,
                  ),
                ],
              ).toJson(),
            ),
          ],
        ),
      ),
    );
    final deadline = Stopwatch()..start();
    for (
      var iteration = 0;
      iteration < 500 &&
          find.byType(WorkspaceFileThumbnail).evaluate().isEmpty &&
          deadline.elapsed < const Duration(seconds: 10);
      iteration++
    ) {
      await tester.runAsync(() => Future<void>(() {}));
      await tester.pump();
    }
    final thumbnail = tester.widget<WorkspaceFileThumbnail>(
      find.byType(WorkspaceFileThumbnail),
    );
    expect(thumbnail.entry.rootPath, workspace.path);
    expect(thumbnail.entry.hostPath, p.join(workspace.path, 'inside.png'));
  });
}
