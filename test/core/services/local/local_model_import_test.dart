import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/services/local/local_model_import.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('litert_import_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  List<int> liteRtLmBytes(String body) => [
    0x4C, 0x49, 0x54, 0x45, 0x52, 0x54, 0x4C, 0x4D, // "LITERTLM"
    ...body.codeUnits,
  ];

  Stream<List<int>> chunked(List<int> bytes, {int chunkSize = 4}) async* {
    for (var i = 0; i < bytes.length; i += chunkSize) {
      yield bytes.sublist(i, (i + chunkSize).clamp(0, bytes.length));
      // Yield control so a concurrent isCancelled() flip is observable
      // between chunks, matching a real streamed copy.
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('a genuine .litertlm file is copied and renamed atomically', () async {
    final bytes = liteRtLmBytes('fake model weights payload');
    final result = await importLocalModelFile(
      source: chunked(bytes),
      totalBytes: bytes.length,
      targetDirectory: tempDir,
      targetFileName: 'model.litertlm',
    );

    expect(result, isA<LocalModelImportSuccess>());
    final success = result as LocalModelImportSuccess;
    expect(success.sizeBytes, bytes.length);
    expect(success.sha256, sha256.convert(bytes).toString());
    expect(File(success.filePath).existsSync(), isTrue);
    expect(File(success.filePath).readAsBytesSync(), bytes);
    // No leftover .part file.
    expect(File('${tempDir.path}/model.litertlm.part').existsSync(), isFalse);
  });

  test('progress reports monotonically increasing bytesWritten', () async {
    final bytes = liteRtLmBytes('0123456789' * 20);
    final seen = <int>[];
    await importLocalModelFile(
      source: chunked(bytes),
      totalBytes: bytes.length,
      targetDirectory: tempDir,
      targetFileName: 'model.litertlm',
      onProgress: (p) {
        seen.add(p.bytesWritten);
        expect(p.totalBytes, bytes.length);
      },
    );
    expect(seen, isNotEmpty);
    for (var i = 1; i < seen.length; i++) {
      expect(seen[i], greaterThan(seen[i - 1]));
    }
    expect(seen.last, bytes.length);
  });

  test(
    'an unknown totalBytes is reported as null, not a fabricated size',
    () async {
      final bytes = liteRtLmBytes('short');
      var sawNull = false;
      await importLocalModelFile(
        source: chunked(bytes),
        totalBytes: null,
        targetDirectory: tempDir,
        targetFileName: 'model.litertlm',
        onProgress: (p) {
          if (p.totalBytes == null) sawNull = true;
        },
      );
      expect(sawNull, isTrue);
    },
  );

  test(
    'a GGUF file is rejected with a specific reason, not opened as LiteRT',
    () async {
      final ggufBytes = [
        0x47,
        0x47,
        0x55,
        0x46,
        0x03,
        0x00,
        0x00,
        0x00,
        1,
        2,
        3,
      ];
      final result = await importLocalModelFile(
        source: chunked(ggufBytes),
        totalBytes: ggufBytes.length,
        targetDirectory: tempDir,
        targetFileName: 'model.litertlm',
      );

      expect(
        result,
        isA<LocalModelImportRejected>().having(
          (r) => r.reason,
          'reason',
          LocalModelImportRejectReason.ggufNotSupported,
        ),
      );
      expect(await tempDir.list().toList(), isEmpty);
    },
  );

  test('a file with a matching extension but wrong magic bytes is rejected '
      '-- the extension alone proves nothing', () async {
    final notReallyLiteRtLm = 'PK\x03\x04 this is actually a zip'.codeUnits;
    final result = await importLocalModelFile(
      source: chunked(notReallyLiteRtLm),
      totalBytes: notReallyLiteRtLm.length,
      targetDirectory: tempDir,
      targetFileName: 'sneaky.litertlm',
    );

    expect(
      result,
      isA<LocalModelImportRejected>().having(
        (r) => r.reason,
        'reason',
        LocalModelImportRejectReason.notLiteRtLmFormat,
      ),
    );
    expect(await tempDir.list().toList(), isEmpty);
  });

  test(
    'a file shorter than the magic number is rejected, not crashed on',
    () async {
      final result = await importLocalModelFile(
        source: chunked([0x4C, 0x49, 0x54]),
        totalBytes: 3,
        targetDirectory: tempDir,
        targetFileName: 'model.litertlm',
      );
      expect(
        result,
        isA<LocalModelImportRejected>().having(
          (r) => r.reason,
          'reason',
          LocalModelImportRejectReason.notLiteRtLmFormat,
        ),
      );
    },
  );

  test(
    'cancelling mid-copy deletes the partial file and leaves nothing behind',
    () async {
      final bytes = liteRtLmBytes('0123456789' * 50);
      var cancelled = false;
      var chunksSeen = 0;
      final result = await importLocalModelFile(
        source: chunked(bytes),
        totalBytes: bytes.length,
        targetDirectory: tempDir,
        targetFileName: 'model.litertlm',
        onProgress: (_) => chunksSeen++,
        isCancelled: () {
          if (chunksSeen >= 3) cancelled = true;
          return cancelled;
        },
      );

      expect(result, isA<LocalModelImportCancelled>());
      expect(await tempDir.list().toList(), isEmpty);
    },
  );

  test('no readStream at all is rejected cleanly', () async {
    final result = await importLocalModelFile(
      source: null,
      totalBytes: 100,
      targetDirectory: tempDir,
      targetFileName: 'model.litertlm',
    );
    expect(
      result,
      isA<LocalModelImportRejected>().having(
        (r) => r.reason,
        'reason',
        LocalModelImportRejectReason.noReadableStream,
      ),
    );
  });

  test('importing a second file with the same name never leaves a reader '
      'able to observe a half-written final file', () async {
    final first = liteRtLmBytes('first version');
    final second = liteRtLmBytes('second version, different length!!');

    await importLocalModelFile(
      source: chunked(first),
      totalBytes: first.length,
      targetDirectory: tempDir,
      targetFileName: 'model.litertlm',
    );
    final result = await importLocalModelFile(
      source: chunked(second),
      totalBytes: second.length,
      targetDirectory: tempDir,
      targetFileName: 'model.litertlm',
    );

    expect(result, isA<LocalModelImportSuccess>());
    final finalBytes = File('${tempDir.path}/model.litertlm').readAsBytesSync();
    expect(finalBytes, second);
  });

  test('a stream error cleans up the partial file and rethrows', () async {
    final controller = StreamController<List<int>>();
    final future = importLocalModelFile(
      source: controller.stream,
      totalBytes: 100,
      targetDirectory: tempDir,
      targetFileName: 'model.litertlm',
    );
    controller.add(_liteRtLmMagicOnly());
    await Future<void>.delayed(Duration.zero);
    controller.addError(const SocketException('connection reset'));

    await expectLater(future, throwsA(isA<SocketException>()));
    expect(await tempDir.list().toList(), isEmpty);
  });

  test(
    'cleanUpInterruptedLocalModelImports removes stray .part files only',
    () async {
      await File(
        '${tempDir.path}/orphan.litertlm.part',
      ).writeAsBytes([1, 2, 3]);
      await File('${tempDir.path}/installed.litertlm').writeAsBytes([4, 5, 6]);

      await cleanUpInterruptedLocalModelImports(tempDir);

      expect(
        File('${tempDir.path}/orphan.litertlm.part').existsSync(),
        isFalse,
      );
      expect(File('${tempDir.path}/installed.litertlm').existsSync(), isTrue);
    },
  );
}

List<int> _liteRtLmMagicOnly() => [
  0x4C,
  0x49,
  0x54,
  0x45,
  0x52,
  0x54,
  0x4C,
  0x4D,
];
