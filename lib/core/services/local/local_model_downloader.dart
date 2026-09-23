import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../../utils/app_directories.dart';
import '../../providers/settings_provider.dart';
import 'local_model_catalog.dart';
import 'local_model_import.dart' show fileStartsWithLiteRtLmMagic;
import 'local_model_library.dart';

/// Progress of a catalog download in progress.
final class LiteRtDownloadProgress {
  const LiteRtDownloadProgress({
    required this.entryId,
    required this.receivedBytes,
    required this.totalBytes,
  });

  final String entryId;
  final int receivedBytes;

  /// Null only if neither the server nor the catalog's own pinned
  /// [LiteRtCatalogEntry.sizeBytes] gives a usable total -- practically
  /// never, since every catalog entry always has one.
  final int? totalBytes;

  double? get fraction {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    return (receivedBytes / total).clamp(0, 1).toDouble();
  }
}

typedef LiteRtDownloadProgressCallback =
    void Function(LiteRtDownloadProgress progress);

typedef LiteRtFileSha256 = Future<String> Function(File file);

final class LiteRtDownloadCancellationToken {
  final Completer<void> _cancelledCompleter = Completer<void>();

  bool get isCancelled => _cancelledCompleter.isCompleted;
  Future<void> get whenCancelled => _cancelledCompleter.future;

  void cancel() {
    if (!_cancelledCompleter.isCompleted) _cancelledCompleter.complete();
  }

  void throwIfCancelled() {
    if (isCancelled) throw const LiteRtDownloadCancelledException();
  }
}

final class LiteRtDownloadCancelledException implements Exception {
  const LiteRtDownloadCancelledException();
  @override
  String toString() => 'LiteRT-LM model download was cancelled';
}

/// Why a download did not produce an installed model. [code] is stable
/// (not user-facing text); the UI maps it to a localized message.
enum LiteRtDownloadFailureCode {
  /// The server rejected the request (non-2xx/206 status).
  httpError,

  /// The stream ended with fewer bytes than the catalog's pinned size.
  incompleteTransfer,

  /// A completed download's first bytes are not LiteRT-LM's own magic
  /// number -- the file the server actually sent isn't what the catalog
  /// entry claims it is.
  formatMismatch,

  /// A completed, correctly-sized, correctly-tagged download's sha256
  /// doesn't match the catalog's pinned checksum. This is the final
  /// integrity gate: even a same-size, right-magic file is refused rather
  /// than silently installed if the content doesn't match exactly.
  checksumMismatch,
}

final class LiteRtDownloadFailedException implements Exception {
  const LiteRtDownloadFailedException(this.code, [this.detail]);
  final LiteRtDownloadFailureCode code;
  final String? detail;

  @override
  String toString() => 'LiteRT-LM model download failed: $code ${detail ?? ''}';
}

/// Downloads a [LiteRtCatalogEntry] into the same local-models directory
/// [importLocalModelFile] uses, resuming a previous attempt via an HTTP
/// `Range` request when a `.part` file from it is still on disk, and
/// registers the finished, verified file with [LocalModelLibrary] exactly
/// like a manual import does.
///
/// Unlike [importLocalModelFile] (which deletes its `.part` file on
/// cancellation -- there is nothing to resume when the source was a
/// one-off picked file), cancelling a catalog download deliberately keeps
/// its `.part` file: the whole point of a catalog entry's stable pinned
/// URL is that the next `download` call for the same [LiteRtCatalogEntry]
/// can pick up from that exact byte offset instead of re-fetching what was
/// already received.
///
/// Verification gate, applied only once the full byte count has arrived (a
/// resumed download's early chunks were never re-validated against the
/// magic number, since they may start mid-file): the completed file's first
/// bytes must be LiteRT-LM's own magic number, and its whole-file sha256
/// must match [LiteRtCatalogEntry.sha256] exactly. Either failure deletes
/// the file and throws -- nothing partially-verified is ever registered as
/// an installed model.
final class LiteRtModelDownloader {
  LiteRtModelDownloader({
    http.Client? httpClient,
    Directory? modelsDirectory,
    LiteRtFileSha256? sha256OfFile,
  }) : _httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null,
       _injectedModelsDirectory = modelsDirectory,
       _sha256OfFile = sha256OfFile ?? _defaultSha256OfFile;

  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final Directory? _injectedModelsDirectory;
  final LiteRtFileSha256 _sha256OfFile;
  final Map<String, LiteRtDownloadCancellationToken> _activeTokens = {};

  bool isDownloading(String entryId) => _activeTokens.containsKey(entryId);

  void cancel(String entryId) => _activeTokens[entryId]?.cancel();

  void dispose() {
    for (final token in _activeTokens.values) {
      token.cancel();
    }
    if (_ownsHttpClient) _httpClient.close();
  }

  Future<Directory> _modelsDirectory() async {
    final injected = _injectedModelsDirectory;
    if (injected != null) return injected;
    return AppDirectories.getLocalModelsDirectory();
  }

  /// Downloads [entry], verifies it, and registers it as an installed
  /// model. Returns the registered model. Throws
  /// [LiteRtDownloadCancelledException] if [cancellationToken] (or a call
  /// to [cancel]) fires first, or [LiteRtDownloadFailedException] if the
  /// transfer completes but fails verification.
  Future<InstalledLocalModel> download(
    LiteRtCatalogEntry entry,
    SettingsProvider settings, {
    LiteRtDownloadProgressCallback? onProgress,
    LiteRtDownloadCancellationToken? cancellationToken,
  }) async {
    if (!entry.isDownloadable) {
      throw ArgumentError.value(entry.id, 'entry', 'Not downloadable');
    }
    if (_activeTokens.containsKey(entry.id)) {
      throw StateError('Model download is already active: ${entry.id}');
    }

    final token = cancellationToken ?? LiteRtDownloadCancellationToken();
    token.throwIfCancelled();
    _activeTokens[entry.id] = token;

    try {
      final dir = await _modelsDirectory();
      await dir.create(recursive: true);
      final partFile = File(p.join(dir.path, partialFileName(entry)));
      token.throwIfCancelled();
      final receivedBytes = await _downloadToPartFile(
        entry,
        partFile,
        token,
        onProgress: onProgress,
      );
      token.throwIfCancelled();

      if (receivedBytes != entry.sizeBytes) {
        await _deleteFileIfPresent(partFile);
        throw LiteRtDownloadFailedException(
          LiteRtDownloadFailureCode.incompleteTransfer,
          '$receivedBytes/${entry.sizeBytes} bytes',
        );
      }
      if (!await fileStartsWithLiteRtLmMagic(partFile)) {
        await _deleteFileIfPresent(partFile);
        throw const LiteRtDownloadFailedException(
          LiteRtDownloadFailureCode.formatMismatch,
        );
      }
      final actualSha256 = await _sha256OfFile(partFile);
      token.throwIfCancelled();
      if (actualSha256 != entry.sha256) {
        await _deleteFileIfPresent(partFile);
        throw LiteRtDownloadFailedException(
          LiteRtDownloadFailureCode.checksumMismatch,
          actualSha256,
        );
      }

      final finalFile = await _availableFinalFile(dir, entry);
      token.throwIfCancelled();
      await partFile.rename(finalFile.path);

      return _library.registerInstalledModel(
        settings,
        filePath: finalFile.path,
        sizeBytes: entry.sizeBytes,
        displayName: entry.displayName,
        sourceLabel: entry.fileName,
        contentSha256: entry.sha256,
        initialSettings: {
          'localVision': entry.vision,
          'localAudio': entry.audio,
          'localThinking': entry.thinking,
          'localTools': entry.tools,
          if (entry.contextTokens > 0)
            'localMaxNumTokens': entry.contextTokens > 4096
                ? 4096
                : entry.contextTokens,
        },
      );
    } on LiteRtDownloadCancelledException {
      rethrow;
    } finally {
      _activeTokens.remove(entry.id);
    }
  }

  static String partialFileName(LiteRtCatalogEntry entry) {
    final identity = '${entry.id}:${entry.sha256}:${entry.sizeBytes}';
    return '.catalog-${sha256.convert(utf8.encode(identity))}.part';
  }

  static const _library = LocalModelLibrary();

  Future<File> _availableFinalFile(
    Directory directory,
    LiteRtCatalogEntry entry,
  ) async {
    final basename = p.basename(entry.fileName);
    var candidate = File(p.join(directory.path, '${entry.sha256}_$basename'));
    var suffix = 1;
    while (await candidate.exists()) {
      candidate = File(
        p.join(directory.path, '${entry.sha256}-$suffix-$basename'),
      );
      suffix++;
    }
    return candidate;
  }

  Future<int> _downloadToPartFile(
    LiteRtCatalogEntry entry,
    File partFile,
    LiteRtDownloadCancellationToken token, {
    LiteRtDownloadProgressCallback? onProgress,
  }) async {
    var resumeFrom = 0;
    if (await partFile.exists()) {
      resumeFrom = await partFile.length();
      // Never resume past the expected size -- a stray oversized .part
      // (from a different, since-changed server response) is discarded
      // and restarted rather than trusted.
      if (resumeFrom >= entry.sizeBytes) {
        await partFile.delete();
        resumeFrom = 0;
      }
    }

    final request = http.AbortableRequest(
      'GET',
      entry.downloadUrl!,
      abortTrigger: token.whenCancelled,
    );
    if (resumeFrom > 0) {
      request.headers['Range'] = 'bytes=$resumeFrom-';
    }

    late final http.StreamedResponse response;
    try {
      response = await _httpClient.send(request);
    } on http.RequestAbortedException {
      throw const LiteRtDownloadCancelledException();
    }

    var receivedBytes = resumeFrom;
    IOSink sink;
    if (response.statusCode == HttpStatus.partialContent && resumeFrom > 0) {
      final contentRange = response.headers['content-range'] ?? '';
      final match = RegExp(
        r'^bytes (\d+)-(\d+)/(\d+)$',
      ).firstMatch(contentRange);
      if (match == null ||
          int.parse(match[1]!) != resumeFrom ||
          int.parse(match[2]!) != entry.sizeBytes - 1 ||
          int.parse(match[3]!) != entry.sizeBytes) {
        final sub = response.stream.listen((_) {});
        await sub.cancel();
        throw const LiteRtDownloadFailedException(
          LiteRtDownloadFailureCode.incompleteTransfer,
        );
      }
      sink = partFile.openWrite(mode: FileMode.append);
    } else if (response.statusCode == HttpStatus.ok) {
      // Either a fresh download, or the server ignored our Range header
      // and is sending the whole file from byte 0 -- either way, start
      // clean rather than risk appending a full response onto existing
      // bytes.
      receivedBytes = 0;
      sink = partFile.openWrite(mode: FileMode.writeOnly);
    } else {
      final sub = response.stream.listen((_) {});
      await sub.cancel();
      throw LiteRtDownloadFailedException(
        LiteRtDownloadFailureCode.httpError,
        'HTTP ${response.statusCode}',
      );
    }

    final totalBytes = _positiveOrNull(response.contentLength) != null
        ? receivedBytes + response.contentLength!
        : entry.sizeBytes;
    final iterator = StreamIterator<List<int>>(response.stream);
    try {
      onProgress?.call(
        LiteRtDownloadProgress(
          entryId: entry.id,
          receivedBytes: receivedBytes,
          totalBytes: totalBytes,
        ),
      );
      while (await _moveNextOrCancel(iterator, token)) {
        final chunk = iterator.current;
        if (receivedBytes + chunk.length > entry.sizeBytes) {
          throw const LiteRtDownloadFailedException(
            LiteRtDownloadFailureCode.incompleteTransfer,
          );
        }
        sink.add(chunk);
        receivedBytes += chunk.length;
        onProgress?.call(
          LiteRtDownloadProgress(
            entryId: entry.id,
            receivedBytes: receivedBytes,
            totalBytes: totalBytes,
          ),
        );
      }
      token.throwIfCancelled();
      await sink.flush();
      return receivedBytes;
    } finally {
      await iterator.cancel();
      await sink.close();
    }
  }

  Future<bool> _moveNextOrCancel(
    StreamIterator<List<int>> iterator,
    LiteRtDownloadCancellationToken token,
  ) async {
    token.throwIfCancelled();
    late final Object result;
    try {
      result = await Future.any<Object>([
        iterator.moveNext(),
        token.whenCancelled.then<Object>((_) => _cancelledMarker),
      ]);
    } on http.RequestAbortedException {
      throw const LiteRtDownloadCancelledException();
    }
    if (identical(result, _cancelledMarker)) {
      throw const LiteRtDownloadCancelledException();
    }
    return result as bool;
  }
}

const Object _cancelledMarker = Object();

int? _positiveOrNull(int? value) => value != null && value > 0 ? value : null;

Future<void> _deleteFileIfPresent(File file) async {
  if (await file.exists()) await file.delete();
}

Future<String> _defaultSha256OfFile(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();
