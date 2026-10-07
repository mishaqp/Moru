import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// One real-path boundary for model tools, workspace instructions and Files.
class WorkspaceFileAccessException implements Exception {
  const WorkspaceFileAccessException(this.message);

  final String message;

  @override
  String toString() => 'WorkspaceFileAccessException: $message';
}

class WorkspaceFileAccess {
  WorkspaceFileAccess({
    required Iterable<String> roots,
    Iterable<String> readOnlyRoots = const [],
    @visibleForTesting this.beforeOpen,
  }) : roots = List.unmodifiable(roots),
       readOnlyRoots = List.unmodifiable(readOnlyRoots);

  final List<String> roots;
  final List<String> readOnlyRoots;
  late final Future<List<String>> _realRoots = Future.wait(
    roots.map(resolvePath),
  );
  late final Future<List<String>> _realReadOnlyRoots = Future.wait(
    readOnlyRoots.map(resolvePath),
  );

  /// Allows tests to replace an ancestor between realpath and open.
  final Future<void> Function(String path)? beforeOpen;

  Future<String> resolve(
    String hostPath, {
    bool followFinalLink = true,
    bool write = false,
  }) async {
    final normalized = _normalize(hostPath);
    final real = followFinalLink
        ? await resolvePath(normalized)
        : p.join(
            await resolvePath(p.dirname(normalized)),
            p.basename(normalized),
          );
    await _check(real, write: write);
    // Entering a read-only mount remains read-only even if it points elsewhere.
    if (write &&
        readOnlyRoots.any((root) => _inside(_normalize(root), normalized))) {
      throw const WorkspaceFileAccessException('path is read-only');
    }
    return real;
  }

  Future<void> _check(String real, {bool write = false}) async {
    var allowed = false;
    for (final root in await _realRoots) {
      if (_inside(root, real)) {
        allowed = true;
        break;
      }
    }
    if (!allowed) {
      throw const WorkspaceFileAccessException('path outside allowed roots');
    }
    if (write) await _checkReadOnly(real);
  }

  Future<void> _checkReadOnly(String real) async {
    for (final root in await _realReadOnlyRoots) {
      if (_inside(root, real)) {
        throw const WorkspaceFileAccessException('path is read-only');
      }
    }
  }

  /// Resolves every existing ancestor, and retains missing trailing components.
  /// A dangling/looping/inaccessible link is an error, never a lexical fallback.
  static Future<String> resolvePath(String hostPath) async {
    final normalized = _normalize(hostPath);
    final missing = <String>[];
    var current = normalized;
    while (true) {
      final type = await FileSystemEntity.type(current, followLinks: false);
      if (type != FileSystemEntityType.notFound) {
        final real = p.canonicalize(await File(current).resolveSymbolicLinks());
        return missing.isEmpty
            ? real
            : p.join(real, p.joinAll(missing.reversed));
      }
      final parent = p.dirname(current);
      if (parent == current) {
        throw FileSystemException('Cannot resolve path', normalized);
      }
      missing.add(p.basename(current));
      current = parent;
    }
  }

  Future<WorkspaceFileHandle> openRead(String hostPath) async {
    final real = await resolve(hostPath);
    await beforeOpen?.call(real);
    final descriptor = _PosixFiles.open(
      real,
      _PosixFiles.readOnly | _PosixFiles.nonBlocking,
    );
    try {
      await _verifyDescriptor(descriptor);
      await _requireRegularFile(descriptor);
      final handle = await File(_descriptorPath(descriptor)).open();
      return WorkspaceFileHandle._(real, descriptor, handle);
    } catch (_) {
      _PosixFiles.close(descriptor);
      rethrow;
    }
  }

  Future<WorkspaceFileHandle> openWrite(
    String hostPath, {
    bool append = false,
  }) async {
    final real = await resolve(hostPath, write: true);
    return withParent(real, (anchored) async {
      await beforeOpen?.call(real);
      // A command can move the already-open parent out of the allowed roots.
      // Recheck it immediately before O_CREAT so even an empty file is not
      // created outside the boundary; no await separates this check from open.
      await resolve(p.dirname(anchored), write: true);
      // Do not truncate until the actual opened file has passed the fd guard.
      final descriptor = _PosixFiles.open(
        anchored,
        _PosixFiles.readWrite | _PosixFiles.create | _PosixFiles.nonBlocking,
      );
      try {
        await _verifyDescriptor(descriptor, write: true);
        await _requireRegularFile(descriptor);
        final handle = await File(
          _descriptorPath(descriptor),
        ).open(mode: append ? FileMode.append : FileMode.write);
        return WorkspaceFileHandle._(real, descriptor, handle);
      } catch (_) {
        _PosixFiles.close(descriptor);
        rethrow;
      }
    });
  }

  Future<Uint8List> readBytes(String hostPath, {int? maxBytes}) async {
    final opened = await openRead(hostPath);
    try {
      return await opened.readBytes(maxBytes: maxBytes);
    } finally {
      await opened.close();
    }
  }

  Future<String> readString(
    String hostPath, {
    int? maxBytes,
    Encoding encoding = utf8,
  }) async => encoding.decode(await readBytes(hostPath, maxBytes: maxBytes));

  Future<FileStat> stat(String hostPath) async {
    final real = await resolve(hostPath);
    final descriptor = _PosixFiles.open(
      real,
      _PosixFiles.readOnly | _PosixFiles.nonBlocking,
    );
    try {
      await _verifyDescriptor(descriptor);
      final stat = await File(_descriptorPath(descriptor)).stat();
      if (stat.type != FileSystemEntityType.directory &&
          (stat.mode & 0xf000) != 0x8000) {
        throw const WorkspaceFileAccessException(
          'not a regular file or directory',
        );
      }
      return stat;
    } finally {
      _PosixFiles.close(descriptor);
    }
  }

  Future<void> _requireRegularFile(int descriptor) async {
    final stat = await File(_descriptorPath(descriptor)).stat();
    if ((stat.mode & 0xf000) != 0x8000) {
      throw const WorkspaceFileAccessException('not a regular file');
    }
  }

  /// Holds a checked directory fd while listing it; an ancestor replacement
  /// cannot redirect the operation into another directory.
  Future<T> withDirectory<T>(
    String hostPath,
    Future<T> Function(String anchoredPath) operation,
  ) async {
    final real = await resolve(hostPath);
    await beforeOpen?.call(real);
    final descriptor = _PosixFiles.open(
      real,
      _PosixFiles.readOnly | _PosixFiles.directory,
    );
    try {
      await _verifyDescriptor(descriptor);
      return await operation(_descriptorPath(descriptor));
    } finally {
      _PosixFiles.close(descriptor);
    }
  }

  /// Keeps the parent inode fixed for unlink, rename and directory creation.
  /// For content writes use [openWrite], which also prevents a final-link race.
  Future<T> withParent<T>(
    String hostPath,
    Future<T> Function(String anchoredPath) operation, {
    bool followFinalLink = true,
    bool write = true,
  }) async {
    final real = await resolve(
      hostPath,
      followFinalLink: followFinalLink,
      write: write,
    );
    final parent = p.dirname(real);
    final descriptor = _PosixFiles.open(
      parent,
      _PosixFiles.readOnly | _PosixFiles.directory,
    );
    try {
      await _verifyDescriptor(descriptor, write: write);
      return await operation(
        p.join(_descriptorPath(descriptor), p.basename(real)),
      );
    } finally {
      _PosixFiles.close(descriptor);
    }
  }

  Future<void> createDirectory(String hostPath, {bool recursive = true}) async {
    final real = await resolve(hostPath, write: true);
    if (await Directory(real).exists()) return;
    if (recursive && !await Directory(p.dirname(real)).exists()) {
      await createDirectory(p.dirname(real));
    }
    await withParent(real, (anchored) => Directory(anchored).create());
    await resolve(real, write: true);
  }

  Future<void> _verifyDescriptor(int descriptor, {bool write = false}) async {
    // Mirrors WorkspaceDocumentsProvider: inspect the opened inode, not merely
    // the name checked before open(). No data is read/truncated before this.
    final opened = await Link(_descriptorPath(descriptor)).target();
    if (opened.endsWith(' (deleted)')) {
      throw const WorkspaceFileAccessException('opened file no longer exists');
    }
    await _check(p.canonicalize(opened), write: write);
  }

  static String _descriptorPath(int descriptor) => '/proc/self/fd/$descriptor';

  static bool _inside(String root, String candidate) =>
      p.equals(root, candidate) || p.isWithin(root, candidate);

  static String _normalize(String path) {
    if (path.contains('\u0000')) {
      throw const WorkspaceFileAccessException('path contains NUL');
    }
    return p.canonicalize(path);
  }
}

/// The native fd remains open until its Dart handle and any anchored stream are
/// finished. [path] is only for IO during this lifetime, never UI/metadata.
class WorkspaceFileHandle {
  WorkspaceFileHandle._(this.hostPath, this._descriptor, this.handle);

  final String hostPath;
  final int _descriptor;
  final RandomAccessFile handle;
  bool _closed = false;

  String get path {
    if (_closed) throw StateError('Workspace file handle is closed');
    return WorkspaceFileAccess._descriptorPath(_descriptor);
  }

  Future<Uint8List> readBytes({int? maxBytes}) async {
    final length = await handle.length();
    return handle.read(maxBytes == null ? length : length.clamp(0, maxBytes));
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await handle.close();
    } finally {
      _PosixFiles.close(_descriptor);
    }
  }
}

/// Android and Linux use the same flags. Linux is the deterministic test host;
/// Moru ships only Android, where these symbols are provided by bionic.
abstract final class _PosixFiles {
  static const readOnly = 0;
  static const readWrite = 2;
  static const create = 0x40;
  static const nonBlocking = 0x800;
  static const directory = 0x10000;
  static const _noFollow = 0x20000;
  static const _closeOnExec = 0x80000;

  static final _open = DynamicLibrary.process()
      .lookupFunction<
        Int32 Function(Pointer<Utf8>, Int32, Uint32),
        int Function(Pointer<Utf8>, int, int)
      >('open');
  static final _close = DynamicLibrary.process()
      .lookupFunction<Int32 Function(Int32), int Function(int)>('close');

  static int open(String path, int flags) {
    final native = path.toNativeUtf8();
    try {
      final descriptor = _open(native, flags | _noFollow | _closeOnExec, 0x180);
      if (descriptor < 0) {
        throw FileSystemException('Cannot safely open file', path);
      }
      return descriptor;
    } finally {
      calloc.free(native);
    }
  }

  static void close(int descriptor) => _close(descriptor);
}
