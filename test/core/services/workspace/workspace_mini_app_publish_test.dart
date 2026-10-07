import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:Kelivo/core/models/workspace.dart';
import 'package:Kelivo/core/models/workspace_binding.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_check.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_store.dart';
import 'package:Kelivo/core/services/workspace/workspace_paths.dart';
import 'package:Kelivo/core/services/workspace/workspace_file_access.dart';
import 'package:Kelivo/core/services/workspace/workspace_runtime.dart';
import 'package:Kelivo/core/services/workspace/workspace_tools_service.dart';
import 'package:Kelivo/utils/mcp_structured_image.dart';

void main() {
  late Directory temp;
  late Directory workspace;
  late MiniAppStore store;
  late WorkspaceToolContext context;
  late WorkspaceToolsService tools;
  late List<String> checked;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mini-app-publish-');
    workspace = Directory(p.join(temp.path, 'workspace'))..createSync();
    final session = Directory(p.join(temp.path, 'session'))..createSync();
    final date = DateTime(2026, 9);
    var tick = 0;
    store = MiniAppStore(
      root: () async => Directory(p.join(temp.path, 'installed')),
      now: () => date.add(Duration(microseconds: tick++)),
    );
    context = WorkspaceToolContext(
      workspace: Workspace(
        id: 'workspace',
        name: 'Build workspace',
        kind: WorkspaceKind.managed,
        createdAt: date,
        updatedAt: date,
      ),
      binding: const WorkspaceBinding(workspaceId: 'workspace', allowAll: true),
      paths: WorkspacePaths.sandboxed(
        workspaceHostRoot: workspace.path,
        sessionHostDir: session.path,
        skillsHostDir: p.join(temp.path, 'skills'),
      ),
      sessionDir: session,
      outputsDir: Directory(p.join(session.path, 'outputs')),
      runtimeStatus: const RuntimeStatus(
        ready: true,
        engine: 'proot',
        sandboxed: true,
      ),
    );
    checked = [];
    tools = WorkspaceToolsService(
      miniApps: store,
      checkMiniApp: (app) async {
        checked.add(app.id);
        return const MiniAppCheckReport(loaded: true, visibleContent: 1);
      },
    );
  });
  tearDown(() => temp.delete(recursive: true));

  Future<File> write(String path, String text) async {
    final file = File(p.join(workspace.path, path));
    await file.parent.create(recursive: true);
    return file.writeAsString(text);
  }

  Future<Map<String, dynamic>> publish(Map<String, dynamic> args) async {
    final raw = await tools.handle(
      context,
      'publish_mini_app',
      args,
      toolCallId: 'publish',
    );
    return jsonDecode(ClientToolResult.fromHandler(raw).content)
        as Map<String, dynamic>;
  }

  Future<void> installOriginal() async {
    await write(
      'original/moru-app.json',
      jsonEncode({
        'id': 'game',
        'name': 'Game',
        'data': 'best: integer',
        'fullscreen': true,
        'server': {'command': 'python3 server.py'},
      }),
    );
    await write('original/index.html', '<head></head><p>original</p>');
    await write('original/main.js', 'window.score = 1;');
    await write('original/style.css', 'body{margin:0}');
    await write('original/server.py', 'print("server")');
    expect((await publish({'path': '/workspace/original'}))['ok'], isTrue);
  }

  test('publishes a Linux build folder without copying a manifest', () async {
    await write(
      'project/dist/pages/index.html',
      '<head></head><script type="module" src="../assets/main.js"></script>',
    );
    await write('project/dist/assets/main.js', 'export const score = 1;');
    final binary = Uint8List(2 * 1024 * 1024 + 7);
    binary[0] = 255;
    binary[binary.length - 1] = 128;
    final file = File(p.join(workspace.path, 'project/dist/assets/level.bin'));
    await file.writeAsBytes(binary);
    final result = await publish({
      'path': '/workspace/project/dist',
      'manifest': {'id': 'built', 'name': 'Built', 'entry': 'pages/index.html'},
    });
    expect(result['ok'], isTrue, reason: '$result');
    expect(result['files'], 3);
    final app = store.byId('built')!;
    expect(await File(app.entryPath).readAsString(), contains('../moru.js'));
    expect(
      await File(p.join(app.codeDirectory, 'assets/level.bin')).readAsBytes(),
      binary,
    );
    expect(
      File(p.join(workspace.path, 'project/dist/moru-app.json')).existsSync(),
      isFalse,
    );
    expect(checked, ['built']);
  });

  test(
    'patches selected files and keeps data, jobs and server files',
    () async {
      await installOriginal();
      final first = store.byId('game')!;
      await store.storageSet('game', 'best', 42);
      await store.updateJobs('game', (jobs) {
        jobs['daily'] = {'run': 'daily', 'time': '09:00'};
      });
      await store.updateReminders('game', (reminders) {
        reminders['daily'] = {'time': '09:00'};
      });
      final serverData = File(p.join(first.directory, 'server-data/save.db'));
      await serverData.create(recursive: true);
      await serverData.writeAsString('persistent server data');
      await write('patch/main.js', 'window.score = 2;');
      await write('patch/style.css', 'body{margin:8px}');
      await write('patch/unselected.txt', 'do not publish');
      final result = await publish({
        'path': '/workspace/patch',
        'app_id': 'game',
        'files': ['main.js', 'style.css'],
        'manifest': {
          'name': 'Updated game',
          'id': null,
          'server': null,
          'fullscreen': null,
          'data': null,
        },
      });
      expect(result['ok'], isTrue, reason: '$result');
      final updated = store.byId('game')!;
      expect(updated.name, 'Updated game');
      expect(updated.fullscreen, isTrue);
      expect(updated.serverCommand, 'python3 server.py');
      expect(
        await File(updated.entryPath).readAsString(),
        contains('original'),
      );
      expect(
        await File(p.join(updated.codeDirectory, 'main.js')).readAsString(),
        'window.score = 2;',
      );
      expect(
        File(p.join(updated.codeDirectory, 'unselected.txt')).existsSync(),
        isFalse,
      );
      expect(await store.storageGet('game', 'best'), 42);
      expect((await store.readJobs('game')).keys, ['daily']);
      expect((await store.readReminders('game')).keys, ['daily']);
      expect(await serverData.readAsString(), 'persistent server data');
      expect(checked, ['game', 'game']);
      final versions = await store.versions('game');
      expect(versions, hasLength(1));
      expect(versions.single.updatedAt, first.updatedAt);
      expect(updated.updatedAt.isAfter(first.updatedAt), isTrue);
      await store.rollback('game', MiniAppStore.versionOf(first));
      expect(
        await File(p.join(first.codeDirectory, 'main.js')).readAsString(),
        'window.score = 1;',
      );
      expect(await store.storageGet('game', 'best'), 42);
    },
  );

  test(
    'rejects invalid partial arguments instead of replacing the app',
    () async {
      await installOriginal();
      await write('patch/moru-app.json', '{"id":"game","name":"Wrong"}');
      await write('patch/index.html', '<p>wrong</p>');
      for (final fields in <Map<String, dynamic>>[
        {'app_id': 'game'},
        {
          'files': ['index.html'],
        },
        {'app_id': 'game', 'files': []},
        {
          'app_id': 'game',
          'files': [42],
        },
        {
          'app_id': 42,
          'files': ['index.html'],
        },
        {'app_id': 'game', 'files': 'index.html'},
        {'manifest': 'not an object'},
      ]) {
        final result = await publish({'path': '/workspace/patch', ...fields});
        expect(result['error'], isNotNull, reason: '$fields: $result');
        expect(store.byId('game')!.name, 'Game');
        expect(
          await File(store.byId('game')!.entryPath).readAsString(),
          contains('original'),
        );
      }
      expect(await store.versions('game'), isEmpty);
    },
  );

  test('an invalid file or metadata patch leaves the old app intact', () async {
    await installOriginal();
    await write('patch/main.js', 'window.score = 2;');
    await write('outside.txt', 'secret');
    await Link(
      p.join(workspace.path, 'patch/link.js'),
    ).create(p.join(workspace.path, 'outside.txt'));
    for (final patch in <Map<String, dynamic>>[
      {
        'files': ['main.js', 'missing.js'],
      },
      {
        'files': ['../outside.txt'],
      },
      {
        'files': ['/workspace/outside.txt'],
      },
      {
        'files': ['link.js'],
      },
      {
        'files': ['moru.js'],
      },
      {
        'files': ['main.js'],
        'manifest': {'id': 'another'},
      },
      {
        'files': ['main.js'],
        'manifest': {'entry': 'missing.html'},
      },
    ]) {
      final result = await publish({
        'path': '/workspace/patch',
        'app_id': 'game',
        ...patch,
      });
      expect(result['error'], isNotNull, reason: '$patch: $result');
      expect(
        await File(
          p.join(store.byId('game')!.codeDirectory, 'main.js'),
        ).readAsString(),
        'window.score = 1;',
      );
    }
    expect(await store.versions('game'), isEmpty);
    expect(store.byId('another'), isNull);
  });

  test('concurrent patches preserve each file and distinct versions', () async {
    await installOriginal();
    await write('patch-a/main.js', 'window.score = 2;');
    await write('patch-b/style.css', 'body{margin:8px}');
    final results = await Future.wait([
      publish({
        'path': '/workspace/patch-a',
        'app_id': 'game',
        'files': ['main.js'],
      }),
      publish({
        'path': '/workspace/patch-b',
        'app_id': 'game',
        'files': ['style.css'],
      }),
    ]);
    expect(results.map((r) => r['ok']), everyElement(isTrue));
    final app = store.byId('game')!;
    expect(
      await File(p.join(app.codeDirectory, 'main.js')).readAsString(),
      'window.score = 2;',
    );
    expect(
      await File(p.join(app.codeDirectory, 'style.css')).readAsString(),
      'body{margin:8px}',
    );
    final versions = await store.versions('game');
    expect(versions, hasLength(2));
    expect(versions.map(MiniAppStore.versionOf).toSet(), hasLength(2));
  });

  for (final partial in [false, true]) {
    test(
      'publication rejects ancestor replacement during ${partial ? 'patch' : 'install'}',
      () async {
        await installOriginal();
        final source = Directory(p.join(workspace.path, 'race'));
        await write('race/index.html', '<p>safe</p>');
        await write('race/main.js', 'safe');
        final outside = Directory(p.join(temp.path, 'private'))..createSync();
        File(
          p.join(outside.path, 'index.html'),
        ).writeAsStringSync('<p>secret</p>');
        File(p.join(outside.path, 'main.js')).writeAsStringSync('secret');
        var replaced = false;
        final grant = WorkspaceFileAccess(
          roots: [workspace.path],
          beforeOpen: (path) async {
            if (replaced) return;
            replaced = true;
            await source.rename('${source.path}-old');
            await Link(source.path).create(outside.path);
          },
        );
        final action = partial
            ? store.updateFiles(
                'game',
                source,
                files: ['main.js'],
                sourceAccess: grant,
              )
            : store.install(
                source,
                manifest: {'id': 'game', 'name': 'Game'},
                sourceAccess: grant,
              );
        await expectLater(action, throwsA(isA<WorkspaceFileAccessException>()));
        expect(replaced, isTrue);
        expect(
          await File(
            p.join(store.byId('game')!.codeDirectory, 'main.js'),
          ).readAsString(),
          'window.score = 1;',
        );
        expect(await store.versions('game'), isEmpty);
      },
    );
  }

  test(
    'partial publication reads an internal symlink through its descriptor',
    () async {
      await installOriginal();
      await write('patch/source.js', 'window.score = 7;');
      await Link(p.join(workspace.path, 'patch/main.js')).create('source.js');
      final result = await publish({
        'path': '/workspace/patch',
        'app_id': 'game',
        'files': ['main.js'],
      });
      expect(result['ok'], isTrue, reason: '$result');
      expect(
        await File(
          p.join(store.byId('game')!.codeDirectory, 'main.js'),
        ).readAsString(),
        'window.score = 7;',
      );
    },
  );

  test(
    'validates the complete patched app against size and file limits',
    () async {
      await installOriginal();
      final app = store.byId('game')!;
      final payload = File(p.join(app.codeDirectory, 'level.bin'));
      // Sparse data is copied as binary; no large string passes through a tool.
      final handle = await payload.open(mode: FileMode.write);
      await handle.truncate(MiniAppStore.maxBytes - 1024);
      await handle.close();
      await write('patch/extra.bin', 'x' * 2048);
      final tooLarge = await publish({
        'path': '/workspace/patch',
        'app_id': 'game',
        'files': ['extra.bin'],
      });
      expect(tooLarge['error'], 'too_large');
      expect(
        File(p.join(app.codeDirectory, 'extra.bin')).existsSync(),
        isFalse,
      );
      expect(await store.versions('game'), isEmpty);
      await payload.delete();
      for (var n = 0; n < MiniAppStore.maxFiles - 4; n++) {
        await File(p.join(app.codeDirectory, 'file-$n.txt')).writeAsString('x');
      }
      final tooMany = await publish({
        'path': '/workspace/patch',
        'app_id': 'game',
        'files': ['extra.bin'],
      });
      expect(tooMany['error'], 'too_many_files');
      expect(await store.versions('game'), isEmpty);
    },
  );
}
