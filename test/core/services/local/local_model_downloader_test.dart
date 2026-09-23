import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/local/local_model_catalog.dart';
import 'package:Kelivo/core/services/local/local_model_downloader.dart';
import 'package:Kelivo/core/services/local/local_model_library.dart';

import '../../../support/business_test_harness.dart';

/// A genuine LiteRT-LM magic-number-prefixed payload of exactly [length]
/// bytes, deterministic so tests can assert on its exact content.
Uint8List _fixturePayload(int length) {
  final magic = 'LITERTLM'.codeUnits;
  final bytes = Uint8List(length);
  for (var i = 0; i < length; i++) {
    bytes[i] = i < magic.length ? magic[i] : (i % 251);
  }
  return bytes;
}

LiteRtCatalogEntry _fixtureEntry({
  required List<int> payload,
  String id = 'fixture-entry',
  String fileName = 'fixture.litertlm',
  Uri? downloadUrl,
}) {
  final digest = sha256.convert(payload).toString();
  return LiteRtCatalogEntry(
    id: id,
    displayName: 'Fixture Model',
    fileName: fileName,
    sizeBytes: payload.length,
    license: 'Apache-2.0',
    contextTokens: 4096,
    repoUrl: Uri.parse('https://example.invalid/fixture-repo'),
    downloadUrl: downloadUrl ?? Uri.parse('https://example.invalid/fixture'),
    sha256: digest,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SettingsProvider settings;
  late Directory tempDir;

  setUp(() async {
    settings = SettingsProvider(createBusinessTestPreferences());
    await settings.loaded;
    tempDir = await Directory.systemTemp.createTemp('litert_downloader_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test(
    'downloads, verifies magic bytes and checksum, and registers the model',
    () async {
      final payload = _fixturePayload(4096);
      final entry = _fixtureEntry(payload: payload);
      final client = MockClient(
        (request) async => http.Response.bytes(payload, HttpStatus.ok),
      );
      final downloader = LiteRtModelDownloader(
        httpClient: client,
        modelsDirectory: tempDir,
      );
      addTearDown(downloader.dispose);
      final events = <LiteRtDownloadProgress>[];

      final installed = await downloader.download(
        entry,
        settings,
        onProgress: events.add,
      );

      expect(installed.displayName, 'Fixture Model');
      expect(await File(installed.filePath).readAsBytes(), payload);
      expect(
        p.basename(installed.filePath),
        '${entry.sha256}_fixture.litertlm',
        reason: 'verified weights need a collision-proof content address',
      );
      expect(events.last.receivedBytes, payload.length);
      expect(events.last.fraction, 1);

      final cfg = settings.providerConfigs[kLocalModelProviderKey];
      expect(cfg, isNotNull);
      expect(cfg!.models, [installed.id]);

      // No stray .part file left behind after a clean success.
      final leftover = await tempDir
          .list()
          .where((e) => e.path.endsWith('.part'))
          .toList();
      expect(leftover, isEmpty);
    },
  );

  test('a checksum mismatch is refused and never registered, even though the '
      'size and magic bytes both look right', () async {
    final payload = _fixturePayload(2048);
    final tamperedButSameSize = Uint8List.fromList(payload);
    // Flip a byte deep in the payload -- magic number and size both
    // still check out, only the content (and thus the hash) differs.
    tamperedButSameSize[1000] ^= 0xFF;
    final entry = _fixtureEntry(payload: payload); // sha256 of the ORIGINAL
    final client = MockClient(
      (request) async =>
          http.Response.bytes(tamperedButSameSize, HttpStatus.ok),
    );
    final downloader = LiteRtModelDownloader(
      httpClient: client,
      modelsDirectory: tempDir,
    );
    addTearDown(downloader.dispose);

    await expectLater(
      downloader.download(entry, settings),
      throwsA(
        isA<LiteRtDownloadFailedException>().having(
          (e) => e.code,
          'code',
          LiteRtDownloadFailureCode.checksumMismatch,
        ),
      ),
    );

    expect(settings.providerConfigs[kLocalModelProviderKey], isNull);
    final leftover = await tempDir.list().toList();
    expect(leftover, isEmpty);
  });

  test(
    'a payload that is not LiteRT-LM format (wrong magic bytes) is refused',
    () async {
      final payload = Uint8List(1024); // all zeros -- no LITERTLM magic
      final entry = _fixtureEntry(payload: payload);
      final client = MockClient(
        (request) async => http.Response.bytes(payload, HttpStatus.ok),
      );
      final downloader = LiteRtModelDownloader(
        httpClient: client,
        modelsDirectory: tempDir,
      );
      addTearDown(downloader.dispose);

      await expectLater(
        downloader.download(entry, settings),
        throwsA(
          isA<LiteRtDownloadFailedException>().having(
            (e) => e.code,
            'code',
            LiteRtDownloadFailureCode.formatMismatch,
          ),
        ),
      );
      expect(settings.providerConfigs[kLocalModelProviderKey], isNull);
    },
  );

  test('a transfer that ends short of the pinned size is refused as '
      'incomplete, not silently accepted', () async {
    final payload = _fixturePayload(4096);
    final entry = _fixtureEntry(payload: payload);
    final client = _StreamingClient(
      (request) async => http.StreamedResponse(
        Stream<List<int>>.fromIterable([payload.sublist(0, 1000)]),
        HttpStatus.ok,
        contentLength: 1000,
      ),
    );
    final downloader = LiteRtModelDownloader(
      httpClient: client,
      modelsDirectory: tempDir,
    );
    addTearDown(downloader.dispose);

    await expectLater(
      downloader.download(entry, settings),
      throwsA(
        isA<LiteRtDownloadFailedException>().having(
          (e) => e.code,
          'code',
          LiteRtDownloadFailureCode.incompleteTransfer,
        ),
      ),
    );
    expect(settings.providerConfigs[kLocalModelProviderKey], isNull);
  });

  test('cancelling mid-download preserves the partial file, and a later call '
      'resumes from that exact byte offset via a Range request', () async {
    final payload = _fixturePayload(8000);
    final entry = _fixtureEntry(payload: payload);
    final firstChunk = payload.sublist(0, 3000);
    // A controller that never closes on its own -- after the first chunk,
    // moveNext() has nothing more to resolve with until the test cancels,
    // so cancellation is guaranteed to be what ends the stream, not a
    // race against the mock naturally running out of data.
    final controller = StreamController<List<int>>();
    addTearDown(controller.close);
    final firstClient = _StreamingClient(
      (request) async => http.StreamedResponse(
        controller.stream,
        HttpStatus.ok,
        contentLength: payload.length,
      ),
    );
    final firstDownloader = LiteRtModelDownloader(
      httpClient: firstClient,
      modelsDirectory: tempDir,
    );
    final token = LiteRtDownloadCancellationToken();
    final cancelHere = Completer<void>();
    final firstAttempt = firstDownloader.download(
      entry,
      settings,
      cancellationToken: token,
      onProgress: (p) {
        if (p.receivedBytes >= firstChunk.length && !cancelHere.isCompleted) {
          cancelHere.complete();
        }
      },
    );
    controller.add(firstChunk);
    await cancelHere.future;
    token.cancel();
    await expectLater(
      firstAttempt,
      throwsA(isA<LiteRtDownloadCancelledException>()),
    );
    firstDownloader.dispose();

    final partFiles = await tempDir
        .list()
        .where((e) => e.path.endsWith('.part'))
        .toList();
    expect(partFiles, hasLength(1));
    expect(await File(partFiles.single.path).length(), firstChunk.length);

    http.BaseRequest? secondRequest;
    final secondClient = _StreamingClient((request) async {
      secondRequest = request;
      final remaining = payload.sublist(firstChunk.length);
      return http.StreamedResponse(
        Stream<List<int>>.fromIterable([remaining]),
        HttpStatus.partialContent,
        contentLength: remaining.length,
        headers: {
          'content-range':
              'bytes ${firstChunk.length}-${payload.length - 1}/${payload.length}',
        },
      );
    });
    final secondDownloader = LiteRtModelDownloader(
      httpClient: secondClient,
      modelsDirectory: tempDir,
    );
    addTearDown(secondDownloader.dispose);

    final installed = await secondDownloader.download(entry, settings);

    expect(secondRequest!.headers['Range'], 'bytes=${firstChunk.length}-');
    expect(await File(installed.filePath).readAsBytes(), payload);
  });

  test('a server that ignores the Range request and resends the full file '
      'from byte 0 does not corrupt the resumed download', () async {
    final payload = _fixturePayload(5000);
    final entry = _fixtureEntry(payload: payload);
    final dir = tempDir;
    // Pre-seed a stale/mismatched partial file, as if an earlier attempt
    // had left behind bytes that don't even form a valid prefix.
    final partFile = File(
      p.join(dir.path, LiteRtModelDownloader.partialFileName(entry)),
    );
    await partFile.writeAsBytes(List<int>.filled(1200, 0xAA));

    final client = _StreamingClient(
      (request) async => http.StreamedResponse(
        Stream<List<int>>.fromIterable([payload]),
        HttpStatus.ok, // ignores Range, sends the whole file
        contentLength: payload.length,
      ),
    );
    final downloader = LiteRtModelDownloader(
      httpClient: client,
      modelsDirectory: dir,
    );
    addTearDown(downloader.dispose);

    final installed = await downloader.download(entry, settings);

    expect(await File(installed.filePath).readAsBytes(), payload);
  });

  test(
    'cancellation that arrives while hashing never installs the model',
    () async {
      final payload = _fixturePayload(4096);
      final entry = _fixtureEntry(payload: payload);
      final token = LiteRtDownloadCancellationToken();
      final client = MockClient(
        (request) async => http.Response.bytes(payload, HttpStatus.ok),
      );
      final downloader = LiteRtModelDownloader(
        httpClient: client,
        modelsDirectory: tempDir,
        sha256OfFile: (file) async {
          token.cancel();
          return sha256.convert(await file.readAsBytes()).toString();
        },
      );
      addTearDown(downloader.dispose);

      await expectLater(
        downloader.download(entry, settings, cancellationToken: token),
        throwsA(isA<LiteRtDownloadCancelledException>()),
      );

      expect(settings.providerConfigs[kLocalModelProviderKey], isNull);
      expect(
        await tempDir
            .list()
            .where((entity) => !entity.path.endsWith('.part'))
            .toList(),
        isEmpty,
      );
    },
  );

  test(
    'different verified contents with the same source name never overwrite',
    () async {
      final firstPayload = _fixturePayload(4096);
      final secondPayload = Uint8List.fromList(_fixturePayload(4097));
      secondPayload[2048] ^= 0x7F;
      final entries = [
        _fixtureEntry(
          payload: firstPayload,
          id: 'first',
          downloadUrl: Uri.parse('https://example.invalid/first'),
        ),
        _fixtureEntry(
          payload: secondPayload,
          id: 'second',
          downloadUrl: Uri.parse('https://example.invalid/second'),
        ),
      ];
      final bodies = <String, List<int>>{
        entries[0].downloadUrl.toString(): firstPayload,
        entries[1].downloadUrl.toString(): secondPayload,
      };
      final client = MockClient((request) async {
        return http.Response.bytes(
          bodies[request.url.toString()]!,
          HttpStatus.ok,
        );
      });
      final downloader = LiteRtModelDownloader(
        httpClient: client,
        modelsDirectory: tempDir,
      );
      addTearDown(downloader.dispose);

      final first = await downloader.download(entries[0], settings);
      final second = await downloader.download(entries[1], settings);

      expect(first.filePath, isNot(second.filePath));
      expect(await File(first.filePath).readAsBytes(), firstPayload);
      expect(await File(second.filePath).readAsBytes(), secondPayload);
    },
  );
}

final class _StreamingClient extends http.BaseClient {
  _StreamingClient(this._handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
  _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _handler(request);
  }
}
