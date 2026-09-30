import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

import 'edit_matchers.dart';
import 'unified_diff.dart';
import 'workspace_paths.dart';
import 'workspace_file_access.dart';
import 'workspace_runtime.dart';
import '../../models/external_mount.dart';

class HostFileException implements Exception {
  const HostFileException(this.message);

  final String message;

  @override
  String toString() => 'HostFileException: $message';
}

class ReadFileResult {
  const ReadFileResult({
    this.text,
    this.nextOffset,
    this.binary = false,
    this.hexPreview,
    this.imageBytes,
    this.imageMime,
  });

  /// 1-based numbered lines (`     1|...`). Null when [binary] or image.
  final String? text;

  /// 1-based line to continue from when the 32 KB cap (or [limit]) truncated.
  final int? nextOffset;
  final bool binary;
  final String? hexPreview;
  final Uint8List? imageBytes;
  final String? imageMime;
}

class WriteFileResult {
  const WriteFileResult({required this.bytes, required this.created});

  final int bytes;
  final bool created;
}

class EditFileResult {
  const EditFileResult({
    required this.changed,
    required this.diff,
    required this.replacements,
    required this.strategy,
    required this.updated,
  });

  final bool changed;
  final UnifiedDiff diff;
  final int replacements;
  final String strategy;
  final String updated;
}

class ListDirEntry {
  const ListDirEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.size,
    required this.modified,
  });

  final String name;
  final String path;
  final bool isDirectory;
  final int size;
  final DateTime modified;
}

class ListDirResult {
  const ListDirResult({required this.entries, required this.truncated});

  final List<ListDirEntry> entries;
  final bool truncated;
}

class GlobResult {
  const GlobResult({required this.paths, required this.truncated});

  final List<String> paths;
  final bool truncated;
}

class GrepMatch {
  const GrepMatch({required this.path, required this.line, required this.text});

  final String path;
  final int line;
  final String text;

  String get display => '$path:$line: $text';
}

class GrepResult {
  const GrepResult({required this.matches, required this.truncated});

  final List<GrepMatch> matches;
  final bool truncated;
}

class _CheckedHostPath {
  const _CheckedHostPath(this.resolved, this.access, this.lexicalHostPath);

  final ResolvedPath resolved;
  final WorkspaceFileAccess access;
  final String lexicalHostPath;
  String get hostPath => resolved.hostPath;
  String get modelPath => resolved.modelPath;
}

class HostFileTools {
  HostFileTools(this.paths, {this.checkCancelled});

  final WorkspacePaths paths;
  final void Function()? checkCancelled;

  static const int readCapBytes = 32 * 1024;
  static const int binaryProbeBytes = 8 * 1024;
  static const int listCap = 500;
  static const int globCap = 500;
  static const int defaultGrepLimit = 100;
  static const int defaultMaxFileBytes = 2 * 1024 * 1024;

  static const Set<String> _imageExtensions = {
    '.png',
    '.jpg',
    '.jpeg',
    '.gif',
    '.webp',
    '.bmp',
  };

  Future<ReadFileResult> readFile(
    String path, {
    int? offset,
    int? limit,
    String? cwd,
  }) async {
    final resolved = await _resolve(path, cwd);
    final file = File(resolved.hostPath);
    if (!await file.exists()) {
      throw HostFileException('file not found: ${resolved.modelPath}');
    }
    if (await FileSystemEntity.isDirectory(resolved.hostPath)) {
      throw HostFileException('not a file: ${resolved.modelPath}');
    }

    final opened = await resolved.access.openRead(resolved.hostPath);
    final handle = opened.handle;
    try {
      final mime = _imageMime(resolved.hostPath);
      if (mime != null) {
        return ReadFileResult(
          imageBytes: await opened.readBytes(),
          imageMime: mime,
        );
      }
      final probeLen = (await handle.length()) < binaryProbeBytes
          ? await handle.length()
          : binaryProbeBytes;
      final probe = await handle.read(probeLen);
      if (_containsNul(probe)) {
        return ReadFileResult(binary: true, hexPreview: _hexPreview(probe));
      }
      await handle.setPosition(0);

      final start = (offset ?? 1) < 1 ? 1 : (offset ?? 1);
      final pageLimit = limit == null ? null : (limit < 1 ? 1 : limit);
      final buffer = StringBuffer();
      var encodedBytes = 0;
      var included = 0;
      await for (final line in _readBoundedLines(handle, start)) {
        if (pageLimit != null && included >= pageLimit) {
          return ReadFileResult(
            text: buffer.toString(),
            nextOffset: line.number,
          );
        }
        final prefix = '${line.number.toString().padLeft(6)}|';
        final size = prefix.length + line.bytes.length + 1;
        if (encodedBytes + size > readCapBytes && included > 0) {
          return ReadFileResult(
            text: buffer.toString(),
            nextOffset: line.number,
          );
        }
        const marker = ' [line truncated]';
        final truncated = line.truncated || size > readCapBytes;
        final maxContent =
            readCapBytes - prefix.length - 1 - (truncated ? marker.length : 0);
        var end = line.bytes.length.clamp(0, maxContent);
        // Do not split a UTF-8 code point at the byte cap.
        if (end < line.bytes.length) {
          while (end > 0 && (line.bytes[end] & 0xc0) == 0x80) {
            end--;
          }
        }
        final text = utf8.decode(line.bytes.sublist(0, end));
        final formatted = '$prefix$text${truncated ? marker : ''}\n';
        buffer.write(formatted);
        encodedBytes += utf8.encode(formatted).length;
        included++;
      }
      return ReadFileResult(text: buffer.toString());
    } finally {
      await opened.close();
    }
  }

  /// Keeps at most one page of a line, even for minified or generated files.
  /// Splits bytes before decoding so a single huge line cannot grow a decoder's
  /// line buffer. Lines before the requested offset are scanned without storage.
  static Stream<({int number, List<int> bytes, bool truncated})>
  _readBoundedLines(RandomAccessFile handle, int start) async* {
    var number = 1;
    var bytes = <int>[];
    var truncated = false;
    var hasContent = false;
    var afterCr = false;
    while (true) {
      final chunk = await handle.read(16 * 1024);
      if (chunk.isEmpty) break;
      for (final byte in chunk) {
        if (afterCr && byte == 10) {
          afterCr = false;
          continue;
        }
        afterCr = byte == 13;
        if (byte == 10 || byte == 13) {
          if (number >= start) {
            yield (number: number, bytes: bytes, truncated: truncated);
          }
          number++;
          bytes = <int>[];
          truncated = false;
          hasContent = false;
        } else {
          hasContent = true;
          if (number >= start) {
            if (bytes.length < readCapBytes) {
              bytes.add(byte);
            } else {
              truncated = true;
            }
          }
        }
      }
    }
    if (hasContent && number >= start) {
      yield (number: number, bytes: bytes, truncated: truncated);
    }
  }

  Future<WriteFileResult> writeFile(
    String path,
    String content, {
    String? cwd,
  }) async {
    final resolved = await _resolve(path, cwd);
    if (paths.isReadOnlyPath(resolved.lexicalHostPath)) {
      throw const HostFileException('External mount is read-only');
    }
    final file = File(resolved.hostPath);
    final created = !await file.exists();
    checkCancelled?.call();
    await resolved.access.createDirectory(file.parent.path);
    checkCancelled?.call();
    final opened = await resolved.access.openWrite(resolved.lexicalHostPath);
    try {
      await opened.handle.writeString(content);
    } finally {
      await opened.close();
    }
    return WriteFileResult(
      bytes: utf8.encode(content).length,
      created: created,
    );
  }

  Future<EditFileResult> editFile(
    String path,
    String oldText,
    String newText, {
    bool replaceAll = false,
    String? cwd,
  }) async {
    final resolved = await _resolve(path, cwd);
    if (paths.isReadOnlyPath(resolved.lexicalHostPath)) {
      throw const HostFileException('External mount is read-only');
    }
    final file = File(resolved.hostPath);
    if (!await file.exists()) {
      throw HostFileException('file not found: ${resolved.modelPath}');
    }
    final original = await resolved.access.readString(resolved.hostPath);
    final outcome = applyEdit(
      original: original,
      oldText: oldText,
      newText: newText,
      replaceAll: replaceAll,
    );
    if (outcome is EditFailed) {
      throw HostFileException(outcome.message);
    }
    final applied = outcome as EditApplied;
    checkCancelled?.call();
    final opened = await resolved.access.openWrite(resolved.lexicalHostPath);
    try {
      await opened.handle.writeString(applied.updated);
    } finally {
      await opened.close();
    }
    return EditFileResult(
      changed: original != applied.updated,
      diff: UnifiedDiff.compute(
        original,
        applied.updated,
        path: resolved.modelPath,
      ),
      replacements: applied.replacements,
      strategy: applied.strategy.id,
      updated: applied.updated,
    );
  }

  Future<ListDirResult> listDir(
    String path, {
    int depth = 1,
    String? cwd,
  }) async {
    await paths.refreshExternalMounts();
    if (paths.sandboxed && p.posix.normalize(path) == ExternalMount.root) {
      final access = paths.fileAccess;
      final entries = <ListDirEntry>[];
      var truncated = false;
      for (final mount in paths.externalMounts) {
        final dir = Directory(mount.host);
        final stat = await access.stat(dir.path);
        entries.add(
          ListDirEntry(
            name: p.posix.basename(mount.guest),
            path: mount.guest,
            isDirectory: true,
            size: 0,
            modified: stat.modified,
          ),
        );
        if (depth > 1) {
          truncated = await _walkDir(dir, depth - 1, entries, access);
          if (truncated) break;
        }
      }
      return ListDirResult(entries: entries, truncated: truncated);
    }
    final resolved = await _resolve(path.isEmpty ? '.' : path, cwd);
    final dir = Directory(resolved.hostPath);
    if (!await dir.exists()) {
      throw HostFileException('directory not found: ${resolved.modelPath}');
    }
    if (!await FileSystemEntity.isDirectory(resolved.hostPath)) {
      throw HostFileException('not a directory: ${resolved.modelPath}');
    }
    final entries = <ListDirEntry>[];
    final truncated = await _walkDir(
      dir,
      depth < 1 ? 1 : depth,
      entries,
      resolved.access,
    );
    return ListDirResult(entries: entries, truncated: truncated);
  }

  Future<GlobResult> glob(String pattern, {String? path, String? cwd}) async {
    final resolved = await _resolve(path ?? paths.modelRoot, cwd);
    final root = Directory(resolved.hostPath);
    if (!await root.exists()) {
      return const GlobResult(paths: [], truncated: false);
    }
    final skipDotDirs = !pattern.startsWith('.');
    final glob = Glob(
      pattern,
      context: p.Context(style: p.Style.posix, current: '.'),
    );
    final matches = <String>[];
    var truncated = false;
    if (await FileSystemEntity.isFile(resolved.hostPath)) {
      final name = p.basename(resolved.hostPath);
      if (!_isL2s(name) &&
          (glob.matches(name) ||
              glob.matches(p.basename(resolved.modelPath)))) {
        return GlobResult(paths: [resolved.modelPath], truncated: false);
      }
      return const GlobResult(paths: [], truncated: false);
    }
    await for (final entity in _walkEntities(
      root,
      access: resolved.access,
      skipDotDirs: skipDotDirs,
    )) {
      final name = p.basename(entity.path);
      if (_isL2s(name)) continue;
      final rel = p
          .relative(entity.path, from: root.path)
          .replaceAll('\\', '/');
      if (glob.matches(rel)) {
        matches.add(paths.toModelPath(entity.path));
        if (matches.length >= globCap) {
          truncated = true;
          break;
        }
      }
    }
    matches.sort();
    return GlobResult(paths: matches, truncated: truncated);
  }

  Future<GrepResult> grep(
    String pattern, {
    String? path,
    String? cwd,
    bool ignoreCase = false,
    int limit = defaultGrepLimit,
    int maxFileBytes = defaultMaxFileBytes,
  }) async {
    final resolved = await _resolve(path ?? paths.modelRoot, cwd);
    final regex = _compilePattern(pattern, ignoreCase);
    final matches = <GrepMatch>[];
    var truncated = false;

    Future<bool> scanFile(File file) async {
      final opened = await resolved.access.openRead(file.path);
      late Uint8List bytes;
      try {
        if (await opened.handle.length() > maxFileBytes) return false;
        bytes = await opened.readBytes(maxBytes: maxFileBytes + 1);
        if (bytes.length > maxFileBytes) return false;
      } finally {
        await opened.close();
      }
      if (_containsNul(
        bytes.length > binaryProbeBytes
            ? bytes.sublist(0, binaryProbeBytes)
            : bytes,
      )) {
        return false;
      }
      final text = utf8.decode(bytes, allowMalformed: true);
      final lines = const LineSplitter().convert(text);
      final modelPath = paths.toModelPath(file.path);
      for (var i = 0; i < lines.length; i++) {
        if (!regex.hasMatch(lines[i])) continue;
        matches.add(GrepMatch(path: modelPath, line: i + 1, text: lines[i]));
        if (matches.length >= limit) return true;
      }
      return false;
    }

    if (await FileSystemEntity.isFile(resolved.hostPath)) {
      truncated = await scanFile(File(resolved.hostPath));
      return GrepResult(matches: matches, truncated: truncated);
    }
    final root = Directory(resolved.hostPath);
    if (!await root.exists()) {
      return const GrepResult(matches: [], truncated: false);
    }
    await for (final entity in _walkEntities(
      root,
      access: resolved.access,
      skipDotDirs: true,
    )) {
      if (entity is! File) continue;
      if (_isL2s(p.basename(entity.path))) continue;
      if (await scanFile(entity)) {
        truncated = true;
        break;
      }
    }
    return GrepResult(matches: matches, truncated: truncated);
  }

  Future<_CheckedHostPath> _resolve(String path, String? cwd) async {
    await paths.refreshExternalMounts();
    final access = paths.fileAccess;
    final lexical = paths.resolve(path, cwd: paths.normalizeCwd(cwd));
    final resolved = await paths.resolveReal(
      path,
      cwd: paths.normalizeCwd(cwd),
    );
    if (resolved.zone == WorkspaceZone.outside) {
      throw const PathResolutionException('path outside allowed roots');
    }
    try {
      await access.resolve(resolved.hostPath);
    } on WorkspaceFileAccessException catch (error) {
      throw PathResolutionException(error.message);
    }
    return _CheckedHostPath(resolved, access, lexical.hostPath);
  }

  Future<bool> _walkDir(
    Directory dir,
    int remainingDepth,
    List<ListDirEntry> out,
    WorkspaceFileAccess access,
  ) async {
    final entities = await access.withDirectory(dir.path, (anchored) async {
      final children = <({String name, FileStat stat})>[];
      await for (final entity in Directory(anchored).list(followLinks: false)) {
        final name = p.basename(entity.path);
        if (_isL2s(name)) continue;
        try {
          children.add((
            name: name,
            stat: await access.stat(p.join(dir.path, name)),
          ));
        } on WorkspaceFileAccessException {
          // Escaping links are not exposed, just as in DocumentsProvider.
        } on FileSystemException {
          // A running command may remove an entry while listing it.
        }
      }
      return children;
    });
    entities.sort((a, b) {
      final aDir = a.stat.type == FileSystemEntityType.directory;
      final bDir = b.stat.type == FileSystemEntityType.directory;
      if (aDir != bDir) return aDir ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    var truncated = false;
    for (final entity in entities) {
      if (out.length >= listCap) return true;
      final name = entity.name;
      final stat = entity.stat;
      final isDir = stat.type == FileSystemEntityType.directory;
      out.add(
        ListDirEntry(
          name: name,
          path: paths.toModelPath(p.join(dir.path, name)),
          isDirectory: isDir,
          size: isDir ? 0 : stat.size,
          modified: stat.modified,
        ),
      );
      if (isDir && remainingDepth > 1 && !name.startsWith('.')) {
        truncated =
            await _walkDir(
              Directory(p.join(dir.path, name)),
              remainingDepth - 1,
              out,
              access,
            ) ||
            truncated;
      }
    }
    return truncated || out.length >= listCap;
  }

  Stream<FileSystemEntity> _walkEntities(
    Directory root, {
    required WorkspaceFileAccess access,
    required bool skipDotDirs,
  }) async* {
    final stack = <Directory>[root];
    final visited = <String>{};
    while (stack.isNotEmpty) {
      final dir = stack.removeLast();
      final real = await access.resolve(dir.path);
      if (!visited.add(real)) continue;
      final children = await access.withDirectory(
        dir.path,
        (anchored) async =>
            (await Directory(anchored).list(followLinks: false).toList())
                .map((entity) => p.basename(entity.path))
                .toList(),
      );
      for (final name in children) {
        if (_isL2s(name)) continue;
        final child = p.join(dir.path, name);
        late FileStat stat;
        try {
          stat = await access.stat(child);
        } on WorkspaceFileAccessException {
          continue;
        } on FileSystemException {
          continue;
        }
        if (stat.type == FileSystemEntityType.directory) {
          if (skipDotDirs && name.startsWith('.')) continue;
          final directory = Directory(child);
          stack.add(directory);
          yield directory;
        } else {
          yield File(child);
        }
      }
    }
  }

  static bool _isL2s(String name) => name.startsWith('.l2s.');

  static bool _containsNul(List<int> bytes) {
    for (final byte in bytes) {
      if (byte == 0) return true;
    }
    return false;
  }

  static String _hexPreview(List<int> bytes) {
    final take = bytes.length < 256 ? bytes.length : 256;
    final buffer = StringBuffer();
    for (var i = 0; i < take; i++) {
      if (i > 0) buffer.write(' ');
      buffer.write(bytes[i].toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  static String? _imageMime(String hostPath) {
    final ext = p.extension(hostPath).toLowerCase();
    if (!_imageExtensions.contains(ext)) return null;
    switch (ext) {
      case '.png':
        return 'image/png';
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.gif':
        return 'image/gif';
      case '.webp':
        return 'image/webp';
      case '.bmp':
        return 'image/bmp';
      default:
        return null;
    }
  }

  static RegExp _compilePattern(String pattern, bool ignoreCase) {
    try {
      return RegExp(pattern, caseSensitive: !ignoreCase);
    } on FormatException {
      return RegExp(RegExp.escape(pattern), caseSensitive: !ignoreCase);
    }
  }
}
