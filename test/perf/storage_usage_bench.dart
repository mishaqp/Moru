import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path/path.dart' as p;

import 'package:Kelivo/core/services/sandbox/rootfs_disk_usage.dart';
import 'package:Kelivo/core/services/storage/storage_usage_service.dart';

// Explicit benchmark; timings are observations, not regression assertions.

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.path);

  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;

  @override
  Future<String?> getApplicationSupportPath() async => path;

  @override
  Future<String?> getApplicationCachePath() async => p.join(path, 'cache');

  @override
  Future<String?> getTemporaryPath() async => p.join(path, 'tmp');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('storage report with 5000 files in app data', () async {
    final root = await Directory.systemTemp.createTemp('storage-bench-');
    final previous = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProviderPlatform(root.path);
    addTearDown(() async {
      PathProviderPlatform.instance = previous;
      await root.delete(recursive: true);
    });
    for (var i = 0; i < 5000; i++) {
      final dir = ['images', 'upload', 'cache/avatars', 'cache/x'][i % 4];
      final file = File(p.join(root.path, dir, 'f$i.png'));
      await file.parent.create(recursive: true);
      file.writeAsBytesSync(List<int>.filled(64, 1));
    }

    final samples = <int>[];
    for (var i = 0; i < 6; i++) {
      final sw = Stopwatch()..start();
      await StorageUsageService.computeReport();
      sw.stop();
      if (i > 0) samples.add(sw.elapsedMilliseconds);
    }
    samples.sort();
    // ignore: avoid_print
    print('STORAGE_REPORT_5000 medianMs=${samples[samples.length ~/ 2]}');
    final sw = Stopwatch()..start();
    final usage = await measureDirectoryUsage(root);
    sw.stop();
    // ignore: avoid_print
    print(
      'SYNC_WALK_IN_ISOLATE files=${usage.fileCount} ms=${sw.elapsedMilliseconds}',
    );
  });
}
