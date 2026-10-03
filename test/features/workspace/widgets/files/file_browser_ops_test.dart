import 'dart:io';

import 'package:Kelivo/features/workspace/widgets/files/file_browser_ops.dart';
import 'package:Kelivo/core/services/workspace/workspace_file_access.dart';
import 'package:Kelivo/core/services/workspace/workspace_paths.dart';
import 'package:Kelivo/core/services/workspace/workspace_runtime.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _PrivatePaths extends PathProviderPlatform {
  _PrivatePaths(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  late Directory temporary;
  late Directory workspace;
  late Directory outside;
  late PathProviderPlatform previousPaths;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('file_browser_boundary_');
    workspace = Directory(p.join(temporary.path, 'workspace'))..createSync();
    outside = Directory(p.join(temporary.path, 'outside'))..createSync();
    final appData = Directory(p.join(temporary.path, 'private-app-data'))
      ..createSync();
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _PrivatePaths(appData.path);
    File(
      p.join(outside.path, 'secret.txt'),
    ).writeAsStringSync('outside marker');
    Link(p.join(workspace.path, 'escape')).createSync(outside.path);
    Link(
      p.join(workspace.path, 'secret-link.txt'),
    ).createSync(p.join(outside.path, 'secret.txt'));
  });

  tearDown(() {
    PathProviderPlatform.instance = previousPaths;
    temporary.deleteSync(recursive: true);
  });

  Future<List<FileBrowserEntry>> list(String path) => FileBrowserOps.listDir(
    Directory(path),
    rootPath: workspace.path,
    showHidden: true,
    sort: FileBrowserSortField.name,
    ascending: true,
  );

  test('listing refuses a directory symlink to an outside folder', () async {
    await expectLater(
      list(p.join(workspace.path, 'escape')),
      throwsA(anything),
    );
  });

  test('listing hides outside file and directory symlink targets', () async {
    final entries = await list(workspace.path);
    expect(entries, isEmpty);
  });

  for (final operation in [
    'create folder',
    'create file',
    'rename',
    'move',
    'delete',
  ]) {
    test(
      '$operation refuses an outside symlink in the middle of the path',
      () async {
        final path = p.join(workspace.path, 'escape', 'secret.txt');
        final action = switch (operation) {
          'create folder' => FileBrowserOps.createFolder(
            rootPath: workspace.path,
            parent: Directory(p.join(workspace.path, 'escape')),
            name: 'created',
          ),
          'create file' => FileBrowserOps.createFile(
            rootPath: workspace.path,
            parent: Directory(p.join(workspace.path, 'escape')),
            name: 'created.txt',
          ),
          'rename' => FileBrowserOps.renameEntry(
            rootPath: workspace.path,
            hostPath: path,
            newName: 'renamed.txt',
          ),
          'move' => FileBrowserOps.moveEntry(
            rootPath: workspace.path,
            hostPath: path,
            destDir: workspace,
          ),
          _ => FileBrowserOps.deleteEntry(
            rootPath: workspace.path,
            hostPath: path,
          ),
        };
        await expectLater(action, throwsA(anything));
        expect(
          File(p.join(outside.path, 'secret.txt')).readAsStringSync(),
          'outside marker',
        );
        expect(
          Directory(p.join(outside.path, 'created')).existsSync(),
          isFalse,
        );
        expect(File(p.join(outside.path, 'created.txt')).existsSync(), isFalse);
        expect(File(p.join(outside.path, 'renamed.txt')).existsSync(), isFalse);
      },
    );
  }

  test('copy refuses an outside file symlink as its source', () async {
    await expectLater(
      FileBrowserOps.copyInto(
        rootPath: workspace.path,
        source: File(p.join(workspace.path, 'secret-link.txt')),
        destDir: workspace,
      ),
      throwsA(anything),
    );
    expect(
      File(p.join(workspace.path, 'secret-link (2).txt')).existsSync(),
      isFalse,
    );
  });

  test(
    'copy refuses a destination redirected by a directory symlink',
    () async {
      final source = File(p.join(workspace.path, 'source.txt'))
        ..writeAsStringSync('source');
      await expectLater(
        FileBrowserOps.copyInto(
          rootPath: workspace.path,
          source: source,
          destDir: Directory(p.join(workspace.path, 'escape')),
        ),
        throwsA(anything),
      );
      expect(File(p.join(outside.path, 'source.txt')).existsSync(), isFalse);
    },
  );

  test('rename refuses an outside file symlink target', () async {
    await expectLater(
      FileBrowserOps.renameEntry(
        rootPath: workspace.path,
        hostPath: p.join(workspace.path, 'secret-link.txt'),
        newName: 'renamed.txt',
      ),
      throwsA(anything),
    );
  });

  test('zip refuses an outside directory symlink as its source', () async {
    final zip = File(p.join(workspace.path, 'archive.zip'));
    await expectLater(
      FileBrowserOps.zipDirectory(
        rootPath: workspace.path,
        source: Directory(p.join(workspace.path, 'escape')),
        dest: zip,
      ),
      throwsA(anything),
    );
    expect(zip.existsSync(), isFalse);
  });

  test(
    'directory export keeps the original workspace boundary after a link retargets',
    () async {
      final folder = Directory(p.join(workspace.path, 'folder'))..createSync();
      File(p.join(folder.path, 'inside.txt')).writeAsStringSync('inside');
      final openedDirectory = Link(p.join(workspace.path, 'opened-directory'))
        ..createSync(folder.path);
      expect((await list(openedDirectory.path)).single.name, 'inside.txt');
      await openedDirectory.update(outside.path);
      final privateExport =
          await FileBrowserOps.createPrivateTemporaryDirectory();
      try {
        await expectLater(
          FileBrowserOps.runMutation(
            ZipDirectoryMutation(
              rootPath: workspace.path,
              sourcePath: openedDirectory.path,
              destPath: p.join(privateExport.path, 'archive.zip'),
              destinationRoot: privateExport.path,
            ),
          ),
          throwsA(isA<WorkspaceFileAccessException>()),
        );
        expect(
          File(p.join(privateExport.path, 'archive.zip')).existsSync(),
          isFalse,
        );
      } finally {
        await privateExport.delete(recursive: true);
      }
    },
  );

  test(
    'zip refuses an outside target behind its destination symlink',
    () async {
      Link(
        p.join(workspace.path, 'archive.zip'),
      ).createSync(p.join(outside.path, 'secret.txt'));
      await expectLater(
        FileBrowserOps.zipDirectory(
          rootPath: workspace.path,
          source: workspace,
          dest: File(p.join(workspace.path, 'archive.zip')),
        ),
        throwsA(anything),
      );
      expect(
        File(p.join(outside.path, 'secret.txt')).readAsStringSync(),
        'outside marker',
      );
    },
  );

  test('deleting an outside symlink removes only that link', () async {
    await FileBrowserOps.deleteEntry(
      rootPath: workspace.path,
      hostPath: p.join(workspace.path, 'escape'),
    );
    expect(Link(p.join(workspace.path, 'escape')).existsSync(), isFalse);
    expect(
      File(p.join(outside.path, 'secret.txt')).readAsStringSync(),
      'outside marker',
    );
  });

  test(
    'read-only target and dangling links can be unlinked without following',
    () async {
      await FileBrowserOps.runMutation(
        DeleteMutation(
          rootPath: workspace.path,
          hostPath: p.join(workspace.path, 'secret-link.txt'),
          readOnlyRoots: [outside.path],
        ),
      );
      final dangling = Link(p.join(workspace.path, 'dangling'))
        ..createSync(p.join(outside.path, 'missing'));
      await FileBrowserOps.runMutation(
        DeleteMutation(
          rootPath: workspace.path,
          hostPath: dangling.path,
          readOnlyRoots: [outside.path],
        ),
      );
      expect(
        FileSystemEntity.typeSync(dangling.path, followLinks: false),
        FileSystemEntityType.notFound,
      );
      expect(
        File(p.join(outside.path, 'secret.txt')).readAsStringSync(),
        'outside marker',
      );
    },
  );

  test('read-only policy applies through an internal alias', () async {
    final readonly = Directory(p.join(workspace.path, 'readonly'))
      ..createSync();
    final alias = Link(p.join(workspace.path, 'readonly-alias'))
      ..createSync(readonly.path);
    await expectLater(
      FileBrowserOps.runMutation(
        CreateFileMutation(
          rootPath: workspace.path,
          parentPath: alias.path,
          name: 'blocked.txt',
          readOnlyRoots: [readonly.path],
        ),
      ),
      throwsA(isA<WorkspaceFileAccessException>()),
    );
    expect(File(p.join(readonly.path, 'blocked.txt')).existsSync(), isFalse);
  });

  test(
    'picker grant copies the selected descriptor even if its filename changes',
    () async {
      final selected = File(p.join(outside.path, 'secret.txt'));
      final opened = await WorkspaceFileAccess(
        roots: [selected.path],
      ).openRead(selected.path);
      try {
        await selected.rename(p.join(outside.path, 'original.txt'));
        await selected.writeAsString('replacement');
        await FileBrowserOps.copyInto(
          rootPath: workspace.path,
          source: selected,
          destDir: workspace,
          pickedSource: opened,
        );
      } finally {
        await opened.close();
      }
      expect(
        File(p.join(workspace.path, 'secret.txt')).readAsStringSync(),
        'outside marker',
      );
    },
  );

  test(
    'preview snapshot stays private and stable until its callback finishes',
    () async {
      final source = File(p.join(workspace.path, 'preview.txt'))
        ..writeAsStringSync('inside preview');
      final runtimeTmp = Directory(p.join(temporary.path, 'runtime-tmp'))
        ..createSync();
      String? snapshotPath;
      final paths = IOOverrides.runZoned(
        () => WorkspacePaths.native(
          workspaceHostRoot: workspace.path,
          sessionHostDir: p.join(temporary.path, 'session'),
          skillsHostDir: p.join(temporary.path, 'skills'),
        ),
        getSystemTempDirectory: () => runtimeTmp,
      );
      expect(paths.tmpHostRoot, runtimeTmp.path);
      await FileBrowserOps.withReadableFile<void>(
        rootPath: workspace.path,
        hostPath: source.path,
        operation: (snapshot) async {
          snapshotPath = snapshot.path;
          expect(
            snapshot.path,
            contains('/private-app-data/workspace-previews/snapshot-'),
          );
          expect(
            (await paths.resolveReal(snapshot.path, cwd: '/workspace')).zone,
            WorkspaceZone.outside,
          );
          await expectLater(
            paths.fileAccess.openWrite(snapshot.path),
            throwsA(isA<WorkspaceFileAccessException>()),
          );
          await source.delete();
          await Link(source.path).create(p.join(outside.path, 'secret.txt'));
          expect(await snapshot.readAsString(), 'inside preview');
        },
      );
      expect(snapshotPath, isNotNull);
      expect(File(snapshotPath!).existsSync(), isFalse);
    },
  );

  test(
    'preview refuses a stale file entry replaced by an outside symlink',
    () async {
      final source = File(p.join(workspace.path, 'preview.txt'))
        ..writeAsStringSync('inside preview');
      await source.delete();
      await Link(source.path).create(p.join(outside.path, 'secret.txt'));
      var called = false;
      await expectLater(
        FileBrowserOps.withReadableFile<void>(
          rootPath: workspace.path,
          hostPath: source.path,
          operation: (_) async {
            called = true;
          },
        ),
        throwsA(isA<WorkspaceFileAccessException>()),
      );
      expect(called, isFalse);
    },
  );

  test('ordinary symlinks inside the workspace remain usable', () async {
    final folder = Directory(p.join(workspace.path, 'folder'))..createSync();
    final original = File(p.join(folder.path, 'original.txt'))
      ..writeAsStringSync('inside marker');
    Link(p.join(workspace.path, 'inside')).createSync(folder.path);
    Link(p.join(workspace.path, 'inside-file.txt')).createSync(original.path);
    expect(
      (await list(p.join(workspace.path, 'inside'))).single.name,
      'original.txt',
    );
    await FileBrowserOps.createFile(
      rootPath: workspace.path,
      parent: Directory(p.join(workspace.path, 'inside')),
      name: 'created.txt',
    );
    expect(File(p.join(folder.path, 'created.txt')).existsSync(), isTrue);
    final copies = Directory(p.join(workspace.path, 'copies'))..createSync();
    await FileBrowserOps.copyInto(
      rootPath: workspace.path,
      source: File(p.join(workspace.path, 'inside-file.txt')),
      destDir: copies,
    );
    expect(
      File(p.join(copies.path, 'inside-file.txt')).readAsStringSync(),
      'inside marker',
    );
    final zipped = await FileBrowserOps.zipDirectory(
      rootPath: workspace.path,
      source: Directory(p.join(workspace.path, 'inside')),
      dest: File(p.join(workspace.path, 'archive.zip')),
    );
    expect(
      ZipDecoder()
          .decodeBytes(await zipped.readAsBytes())
          .files
          .any((f) => f.name == 'original.txt'),
      isTrue,
    );
  });
}
