import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:Kelivo/core/services/sandbox/rootfs_disk_usage.dart';

void main() {
  test('measureDirectorySize sums files including meta.db', () async {
    final root = await Directory.systemTemp.createTemp('kelivo_rootfs_size_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    final meta = File(p.join(root.path, 'meta.db'));
    await meta.writeAsBytes(List<int>.filled(128, 1));
    final nested = File(p.join(root.path, 'data', 'bin', 'ls'));
    await nested.parent.create(recursive: true);
    await nested.writeAsBytes(List<int>.filled(64, 2));
    await File(p.join(root.path, 'data', 'empty.txt')).writeAsBytes(const []);

    expect(await measureDirectorySize(root), 192);
    expect(measureDirectorySizeSync(root.path), 192);
    expect(
      await measureDirectorySize(Directory(p.join(root.path, 'missing'))),
      0,
    );
  });

  test('measureDirectorySizeSync skips unreadable entries', () async {
    final root = await Directory.systemTemp.createTemp('kelivo_rootfs_skip_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final ok = File(p.join(root.path, 'ok.bin'));
    await ok.writeAsBytes(List<int>.filled(32, 1));
    await Link(p.join(root.path, 'loop')).create(root.path);
    expect(measureDirectorySizeSync(root.path), 32);
  });

  test('resolveRootfsUsageDir prefers an explicit rootfsDir', () async {
    final dir = await resolveRootfsUsageDir(rootfsDir: '/tmp/explicit-rootfs');
    expect(dir.path, '/tmp/explicit-rootfs');
  });
}
