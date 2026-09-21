import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Progress while streaming a picked file into the local models directory.
class LocalModelImportProgress {
  const LocalModelImportProgress({
    required this.bytesWritten,
    required this.totalBytes,
  });

  final int bytesWritten;

  /// Null when the source didn't report a size (some content providers
  /// don't) -- callers should show an indeterminate progress indicator
  /// rather than inventing a percentage.
  final int? totalBytes;
}

sealed class LocalModelImportResult {
  const LocalModelImportResult();
}

final class LocalModelImportSuccess extends LocalModelImportResult {
  const LocalModelImportSuccess({
    required this.filePath,
    required this.sizeBytes,
    required this.sha256,
  });

  final String filePath;
  final int sizeBytes;
  final String sha256;
}

/// Why an import did not produce an installed model. [reason] is a stable
/// code (not user-facing text) the UI maps to a localized message.
final class LocalModelImportRejected extends LocalModelImportResult {
  const LocalModelImportRejected(this.reason);

  final LocalModelImportRejectReason reason;
}

final class LocalModelImportCancelled extends LocalModelImportResult {
  const LocalModelImportCancelled();
}

final class _DigestSink implements Sink<Digest> {
  _DigestSink(this.onDigest);

  final void Function(Digest digest) onDigest;

  @override
  void add(Digest data) => onDigest(data);

  @override
  void close() {}
}

enum LocalModelImportRejectReason {
  /// The picked source has no [Stream<List<int>>] to read (should not
  /// happen when the picker was asked for one -- defensive only).
  noReadableStream,

  /// First bytes match GGUF's own magic number ("GGUF") -- a real,
  /// different, unsupported format, not a corrupt LiteRT-LM file.
  ggufNotSupported,

  /// Doesn't start with LiteRT-LM's own magic ("LITERTLM", 8 bytes) --
  /// covers every other non-`.litertlm` file, including a `.litertlm`-
  /// named file that isn't actually one (the extension alone proves
  /// nothing -- see docs/litert-lm-progress.md).
  notLiteRtLmFormat,
}

/// The literal first bytes of a genuine LiteRT-LM file, confirmed by
/// reading the SDK's own `GetFileFormatFromFileContents` (`file_format_
/// util.cc`, `absl::StartsWith(header, "LITERTLM")`) -- not guessed.
const List<int> _liteRtLmMagic = [
  0x4C, 0x49, 0x54, 0x45, 0x52, 0x54, 0x4C, 0x4D, // "LITERTLM"
];

/// GGUF's own magic number (the ASCII bytes "GGUF"), used only to give a
/// clearer rejection reason than "not a supported format" when the file is
/// recognizably a GGUF model rather than something arbitrary.
const List<int> _ggufMagic = [0x47, 0x47, 0x55, 0x46]; // "GGUF"

bool _startsWith(List<int> header, List<int> magic) {
  if (header.length < magic.length) return false;
  for (var i = 0; i < magic.length; i++) {
    if (header[i] != magic[i]) return false;
  }
  return true;
}

/// Whether [file]'s first bytes are LiteRT-LM's own magic number
/// ("LITERTLM"). Reuses the exact same check [importLocalModelFile] applies
/// to a picked file's first chunk -- the catalog downloader in
/// `local_model_downloader.dart` calls this once a download is complete
/// (its own first chunk may be mid-file on a resumed download, so it can't
/// check as it streams the way a fresh import does).
Future<bool> fileStartsWithLiteRtLmMagic(File file) async {
  final raf = await file.open();
  try {
    final header = await raf.read(_liteRtLmMagic.length);
    return _startsWith(header, _liteRtLmMagic);
  } finally {
    await raf.close();
  }
}

/// Streams [source] into `<localModelsDir>/[targetFileName]`, validating
/// the real file format (magic bytes, not just the picked file's own
/// extension) before any bytes are trusted. Writes to a `.part` sibling
/// first and only renames to the final name once the full stream has been
/// written -- a reader can never observe a half-written file at the final
/// path. Never loads the whole file into memory.
///
/// [totalBytes] is the size the picker reported for [source] (`0`/absent
/// when unknown -- some content providers don't report it). [isCancelled]
/// is polled between chunks; the moment it returns true the partial
/// `.part` file is deleted and [LocalModelImportCancelled] is returned --
/// the copy has bounded chunk sizes, so the check runs many times over a
/// large file rather than only once at the boundary.
Future<LocalModelImportResult> importLocalModelFile({
  required Stream<List<int>>? source,
  required int? totalBytes,
  required Directory targetDirectory,
  required String targetFileName,
  void Function(LocalModelImportProgress progress)? onProgress,
  bool Function()? isCancelled,
}) async {
  if (source == null) {
    return const LocalModelImportRejected(
      LocalModelImportRejectReason.noReadableStream,
    );
  }
  if (!await targetDirectory.exists()) {
    await targetDirectory.create(recursive: true);
  }
  final partFile = File('${targetDirectory.path}/$targetFileName.part');
  final finalFile = File('${targetDirectory.path}/$targetFileName');
  final sink = partFile.openWrite();
  Digest? contentDigest;
  var hashSinkClosed = false;
  final hashSink = sha256.startChunkedConversion(
    _DigestSink((digest) => contentDigest = digest),
  );

  void closeHashSink() {
    if (hashSinkClosed) return;
    hashSinkClosed = true;
    hashSink.close();
  }

  var written = 0;
  var headerChecked = false;
  final headerBuffer = <int>[];

  Future<LocalModelImportResult> abort(LocalModelImportResult result) async {
    closeHashSink();
    await sink.close();
    if (await partFile.exists()) await partFile.delete();
    return result;
  }

  Future<void> cleanUpAfterError() async {
    closeHashSink();
    await sink.close();
    if (await partFile.exists()) await partFile.delete();
  }

  try {
    await for (final chunk in source) {
      if (isCancelled?.call() ?? false) {
        return await abort(const LocalModelImportCancelled());
      }
      if (!headerChecked) {
        headerBuffer.addAll(chunk);
        if (headerBuffer.length >= _liteRtLmMagic.length) {
          headerChecked = true;
          if (_startsWith(headerBuffer, _ggufMagic)) {
            return await abort(
              const LocalModelImportRejected(
                LocalModelImportRejectReason.ggufNotSupported,
              ),
            );
          }
          if (!_startsWith(headerBuffer, _liteRtLmMagic)) {
            return await abort(
              const LocalModelImportRejected(
                LocalModelImportRejectReason.notLiteRtLmFormat,
              ),
            );
          }
        }
      }
      hashSink.add(chunk);
      sink.add(chunk);
      written += chunk.length;
      onProgress?.call(
        LocalModelImportProgress(
          bytesWritten: written,
          totalBytes: (totalBytes != null && totalBytes > 0)
              ? totalBytes
              : null,
        ),
      );
    }
  } catch (error) {
    await cleanUpAfterError();
    rethrow;
  }

  if (!headerChecked) {
    // Fewer than 8 bytes total -- too small to be a real model under any
    // format, including LiteRT-LM's own magic check.
    return await abort(
      const LocalModelImportRejected(
        LocalModelImportRejectReason.notLiteRtLmFormat,
      ),
    );
  }

  await sink.flush();
  await sink.close();
  closeHashSink();
  if (await finalFile.exists()) await finalFile.delete();
  await partFile.rename(finalFile.path);
  return LocalModelImportSuccess(
    filePath: finalFile.path,
    sizeBytes: written,
    sha256: contentDigest!.toString(),
  );
}

/// Deletes every stray `*.part` file in [directory] -- an import that was
/// killed mid-copy (process death, not a clean cancel) leaves one behind.
/// Safe to call on app start; never touches a finished (non-`.part`) model
/// file.
Future<void> cleanUpInterruptedLocalModelImports(Directory directory) async {
  if (!await directory.exists()) return;
  await for (final entry in directory.list()) {
    if (entry is File && entry.path.endsWith('.part')) {
      try {
        await entry.delete();
      } catch (_) {
        // Best-effort -- a locked/already-gone file is not fatal here.
      }
    }
  }
}
