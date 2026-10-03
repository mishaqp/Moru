import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:Kelivo/core/services/workspace/workspace_file_access.dart';

void main() {
  late Directory temporary;
  late Directory root;
  late Directory outside;
  late WorkspaceFileAccess access;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('moru_real_boundary_');
    root = await Directory(p.join(temporary.path, 'workspace')).create();
    outside = await Directory(p.join(temporary.path, 'outside')).create();
    access = WorkspaceFileAccess(roots: [root.path]);
  });

  tearDown(() async => temporary.delete(recursive: true));

  test(
    'reads remain bound to the opened inode after source replacement',
    () async {
      final source = File(p.join(root.path, 'source.txt'));
      await source.writeAsString('original');
      final opened = await access.openRead(source.path);
      try {
        await source.rename(p.join(root.path, 'old.txt'));
        await source.writeAsString('replacement');
        expect(await opened.readBytes(), 'original'.codeUnits);
        expect(await File(opened.path).readAsString(), 'original');
      } finally {
        await opened.close();
      }
    },
  );

  test(
    'opened descriptor rejects an ancestor replaced with an outside link',
    () async {
      final parent = await Directory(p.join(root.path, 'parent')).create();
      await File(p.join(parent.path, 'source.txt')).writeAsString('original');
      await File(p.join(outside.path, 'source.txt')).writeAsString('private');
      access = WorkspaceFileAccess(
        roots: [root.path],
        beforeOpen: (_) async {
          await parent.rename(p.join(root.path, 'original-parent'));
          await Link(parent.path).create(outside.path);
        },
      );
      await expectLater(
        access.readBytes(p.join(parent.path, 'source.txt')),
        throwsA(isA<WorkspaceFileAccessException>()),
      );
      expect(
        await File(p.join(outside.path, 'source.txt')).readAsString(),
        'private',
      );
    },
  );

  test(
    'moving an opened parent outside is rejected before truncating',
    () async {
      final parent = await Directory(p.join(root.path, 'parent')).create();
      await File(p.join(parent.path, 'source.txt')).writeAsString('unchanged');
      final moved = p.join(outside.path, 'moved');
      access = WorkspaceFileAccess(
        roots: [root.path],
        beforeOpen: (_) async => parent.rename(moved),
      );
      await expectLater(
        access.openWrite(p.join(parent.path, 'source.txt')),
        throwsA(isA<WorkspaceFileAccessException>()),
      );
      expect(
        await File(p.join(moved, 'source.txt')).readAsString(),
        'unchanged',
      );
    },
  );

  test('a final link swapped before writing is never followed', () async {
    final source = File(p.join(root.path, 'source.txt'));
    final secret = File(p.join(outside.path, 'secret.txt'));
    await source.writeAsString('original');
    await secret.writeAsString('private');
    access = WorkspaceFileAccess(
      roots: [root.path],
      beforeOpen: (_) async {
        await source.delete();
        await Link(source.path).create(secret.path);
      },
    );
    await expectLater(
      access.openWrite(source.path),
      throwsA(isA<FileSystemException>()),
    );
    expect(await secret.readAsString(), 'private');
  });

  test('moving an opened parent outside cannot create an empty file', () async {
    final parent = await Directory(p.join(root.path, 'parent')).create();
    final moved = p.join(outside.path, 'moved');
    access = WorkspaceFileAccess(
      roots: [root.path],
      beforeOpen: (_) async => parent.rename(moved),
    );
    await expectLater(
      access.openWrite(p.join(parent.path, 'new.txt')),
      throwsA(isA<WorkspaceFileAccessException>()),
    );
    expect(await File(p.join(moved, 'new.txt')).exists(), isFalse);
  });

  test('parent anchoring survives an intermediate link replacement', () async {
    final actual = await Directory(p.join(root.path, 'actual')).create();
    final inside = File(p.join(actual.path, 'delete.txt'));
    final secret = File(p.join(outside.path, 'delete.txt'));
    await inside.writeAsString('delete me');
    await secret.writeAsString('private');
    final link = await Link(p.join(root.path, 'alias')).create(actual.path);
    await access.withParent(p.join(link.path, 'delete.txt'), (anchored) async {
      await link.delete();
      await link.create(outside.path);
      await File(anchored).delete();
    });
    expect(await inside.exists(), isFalse);
    expect(await secret.readAsString(), 'private');
  });

  test(
    'deleting an escaping or dangling final link removes just the link',
    () async {
      final secret = File(p.join(outside.path, 'secret.txt'));
      await secret.writeAsString('private');
      for (final target in [secret.path, p.join(outside.path, 'missing.txt')]) {
        final link = await Link(p.join(root.path, 'link')).create(target);
        await access.withParent(
          link.path,
          (anchored) => Link(anchored).delete(),
          followFinalLink: false,
        );
        expect(
          await FileSystemEntity.type(link.path, followLinks: false),
          FileSystemEntityType.notFound,
        );
      }
      expect(await secret.readAsString(), 'private');
    },
  );

  test(
    'read-only mounts remain read-only through both alias directions',
    () async {
      final readonly = await Directory(p.join(root.path, 'readonly')).create();
      final writable = await Directory(p.join(root.path, 'writable')).create();
      await File(
        p.join(readonly.path, 'source.txt'),
      ).writeAsString('allowed read');
      await Link(p.join(writable.path, 'into-readonly')).create(readonly.path);
      await Link(p.join(readonly.path, 'into-writable')).create(writable.path);
      access = WorkspaceFileAccess(
        roots: [root.path],
        readOnlyRoots: [readonly.path],
      );
      expect(
        await access.readString(
          p.join(writable.path, 'into-readonly/source.txt'),
        ),
        'allowed read',
      );
      await expectLater(
        access.openWrite(p.join(writable.path, 'into-readonly/source.txt')),
        throwsA(isA<WorkspaceFileAccessException>()),
      );
      await expectLater(
        access.openWrite(p.join(readonly.path, 'into-writable/new.txt')),
        throwsA(isA<WorkspaceFileAccessException>()),
      );
      expect(await File(p.join(writable.path, 'new.txt')).exists(), isFalse);
    },
  );

  test('new directory paths resolve existing intermediate links', () async {
    final actual = await Directory(p.join(root.path, 'actual')).create();
    await Link(p.join(root.path, 'alias')).create(actual.path);
    await access.createDirectory(p.join(root.path, 'alias/new/nested'));
    expect(await Directory(p.join(actual.path, 'new/nested')).exists(), isTrue);
    await Link(p.join(root.path, 'escape')).create(outside.path);
    await expectLater(
      access.createDirectory(p.join(root.path, 'escape/new')),
      throwsA(isA<WorkspaceFileAccessException>()),
    );
    expect(await Directory(p.join(outside.path, 'new')).exists(), isFalse);
  });

  test('bounded reads preserve the caller size limit', () async {
    final source = File(p.join(root.path, 'source.txt'));
    await source.writeAsString('abcdef');
    expect(await access.readBytes(source.path, maxBytes: 4), 'abcd'.codeUnits);
    expect(await access.readString(source.path), 'abcdef');
  });

  test('an explicit selected-file root grants only that file', () async {
    final selected = File(p.join(outside.path, 'selected.txt'));
    await selected.writeAsString('selected');
    await File(p.join(outside.path, 'other.txt')).writeAsString('private');
    access = WorkspaceFileAccess(roots: [selected.path]);
    expect(await access.readString(selected.path), 'selected');
    await expectLater(
      access.readString(p.join(outside.path, 'other.txt')),
      throwsA(isA<WorkspaceFileAccessException>()),
    );
  });

  test('named pipes are rejected without blocking a content open', () async {
    final fifo = p.join(root.path, 'fifo');
    final result = await Process.run('mkfifo', [fifo]);
    expect(result.exitCode, 0);
    await expectLater(
      access.readBytes(fifo),
      throwsA(isA<WorkspaceFileAccessException>()),
    );
    await expectLater(
      access.openWrite(fifo),
      throwsA(isA<WorkspaceFileAccessException>()),
    );
  });
}
