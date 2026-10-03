import 'dart:io';

import 'package:Kelivo/core/services/workspace/workspace_file_access.dart';
import 'package:Kelivo/utils/app_directories.dart';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

enum FileBrowserSortField { name, modified, size }

class FileBrowserEntry {
  const FileBrowserEntry({
    required this.name,
    required this.hostPath,
    required this.isDirectory,
    required this.size,
    required this.modified,
    this.childCount,
    this.rootPath,
  });

  final String name;
  final String hostPath;
  final bool isDirectory;
  final int size;
  final DateTime modified;

  /// Immediate child count for directories when it was cheap to collect.
  final int? childCount;

  /// Boundary used again when the thumbnail or preview actually reads the file.
  final String? rootPath;
}

/// Host-side mutation routed through [FileBrowser.mutationRunner].
sealed class FileMutation {
  const FileMutation({required this.rootPath, this.readOnlyRoots = const []});

  final String rootPath;
  final List<String> readOnlyRoots;

  FileMutation withReadOnlyRoots(List<String> roots) => switch (this) {
    CreateFolderMutation(:final parentPath, :final name) =>
      CreateFolderMutation(
        rootPath: rootPath,
        parentPath: parentPath,
        name: name,
        readOnlyRoots: roots,
      ),
    CreateFileMutation(:final parentPath, :final name) => CreateFileMutation(
      rootPath: rootPath,
      parentPath: parentPath,
      name: name,
      readOnlyRoots: roots,
    ),
    RenameMutation(:final hostPath, :final newName) => RenameMutation(
      rootPath: rootPath,
      hostPath: hostPath,
      newName: newName,
      readOnlyRoots: roots,
    ),
    MoveMutation(:final hostPath, :final destDirPath) => MoveMutation(
      rootPath: rootPath,
      hostPath: hostPath,
      destDirPath: destDirPath,
      readOnlyRoots: roots,
    ),
    DeleteMutation(:final hostPath) => DeleteMutation(
      rootPath: rootPath,
      hostPath: hostPath,
      readOnlyRoots: roots,
    ),
    CopyIntoMutation(
      :final sourcePath,
      :final destDirPath,
      :final pickedSource,
    ) =>
      CopyIntoMutation(
        rootPath: rootPath,
        sourcePath: sourcePath,
        destDirPath: destDirPath,
        pickedSource: pickedSource,
        readOnlyRoots: roots,
      ),
    ZipDirectoryMutation(
      :final sourcePath,
      :final destPath,
      :final destinationRoot,
    ) =>
      ZipDirectoryMutation(
        rootPath: rootPath,
        sourcePath: sourcePath,
        destPath: destPath,
        destinationRoot: destinationRoot,
        readOnlyRoots: roots,
      ),
  };

  /// Paths modified by this operation; copying only reads the source.
  Iterable<String> get writePaths => switch (this) {
    CreateFolderMutation(:final parentPath, :final name) ||
    CreateFileMutation(
      :final parentPath,
      :final name,
    ) => [p.join(parentPath, name)],
    RenameMutation(:final hostPath, :final newName) => [
      hostPath,
      p.join(p.dirname(hostPath), newName),
    ],
    MoveMutation(:final hostPath, :final destDirPath) => [
      hostPath,
      destDirPath,
    ],
    DeleteMutation(:final hostPath) => [hostPath],
    CopyIntoMutation(:final destDirPath) => [destDirPath],
    ZipDirectoryMutation(:final destPath) => [destPath],
  };
}

final class CreateFolderMutation extends FileMutation {
  const CreateFolderMutation({
    required super.rootPath,
    super.readOnlyRoots,
    required this.parentPath,
    required this.name,
  });

  final String parentPath;
  final String name;
}

final class CreateFileMutation extends FileMutation {
  const CreateFileMutation({
    required super.rootPath,
    super.readOnlyRoots,
    required this.parentPath,
    required this.name,
  });

  final String parentPath;
  final String name;
}

final class RenameMutation extends FileMutation {
  const RenameMutation({
    required super.rootPath,
    super.readOnlyRoots,
    required this.hostPath,
    required this.newName,
  });

  final String hostPath;
  final String newName;
}

final class MoveMutation extends FileMutation {
  const MoveMutation({
    required super.rootPath,
    super.readOnlyRoots,
    required this.hostPath,
    required this.destDirPath,
  });

  final String hostPath;
  final String destDirPath;
}

final class DeleteMutation extends FileMutation {
  const DeleteMutation({
    required super.rootPath,
    super.readOnlyRoots,
    required this.hostPath,
  });

  final String hostPath;
}

final class CopyIntoMutation extends FileMutation {
  const CopyIntoMutation({
    required super.rootPath,
    super.readOnlyRoots,
    required this.sourcePath,
    required this.destDirPath,
    this.pickedSource,
  });

  final String sourcePath;
  final String destDirPath;

  /// A checked, held descriptor granted by the system file picker.
  final WorkspaceFileHandle? pickedSource;
}

final class ZipDirectoryMutation extends FileMutation {
  const ZipDirectoryMutation({
    required super.rootPath,
    super.readOnlyRoots,
    required this.sourcePath,
    required this.destPath,
    this.destinationRoot,
  });

  final String sourcePath;
  final String destPath;

  /// A newly created private export directory, never the whole system temp.
  final String? destinationRoot;
}

/// Path-safe file operations that always stay inside [rootPath].
class FileBrowserOps {
  FileBrowserOps._();

  static String canonicalize(String path) => p.canonicalize(path);

  static WorkspaceFileAccess _access(
    String rootPath, {
    Iterable<String> readOnlyRoots = const [],
  }) => WorkspaceFileAccess(roots: [rootPath], readOnlyRoots: readOnlyRoots);

  static Future<String> resolveRealInsideRoot(
    String rootPath,
    String hostPath, {
    bool followFinalLink = true,
    bool write = false,
  }) => _access(
    rootPath,
  ).resolve(hostPath, followFinalLink: followFinalLink, write: write);

  /// Native preview/share handlers reopen paths later. Give them a private
  /// snapshot copied from the descriptor that passed the realpath check.
  static Future<T> withReadableFile<T>({
    required String rootPath,
    required String hostPath,
    required Future<T> Function(File file) operation,
  }) async {
    final source = await _access(rootPath).openRead(hostPath);
    Directory? temporary;
    try {
      temporary = await createPrivateTemporaryDirectory();
      final snapshotPath = p.join(temporary.path, p.basename(hostPath));
      final destination = await _access(temporary.path).openWrite(snapshotPath);
      try {
        await _copyHandles(source, destination);
      } finally {
        await destination.close();
      }
      return await operation(File(snapshotPath));
    } finally {
      await source.close();
      await temporary?.delete(recursive: true);
    }
  }

  /// Preview/export snapshots are not in the model's writable `/tmp` mount.
  static Future<Directory> createPrivateTemporaryDirectory() async {
    final appData = await AppDirectories.getAppDataDirectory();
    final access = _access(appData.path);
    final root = p.join(appData.path, 'workspace-previews');
    await access.createDirectory(root);
    final name = await access.withDirectory(root, (path) async {
      final directory = await Directory(path).createTemp('snapshot-');
      return p.basename(directory.path);
    });
    return Directory(p.join(root, name));
  }

  static Future<void> _copyHandles(
    WorkspaceFileHandle source,
    WorkspaceFileHandle destination,
  ) async {
    await source.handle.setPosition(0);
    while (true) {
      final bytes = await source.handle.read(64 * 1024);
      if (bytes.isEmpty) break;
      await destination.handle.writeFrom(bytes);
    }
    await destination.handle.flush();
  }

  static bool isWithinRoot(String rootPath, String candidatePath) {
    final root = canonicalize(rootPath);
    final candidate = canonicalize(candidatePath);
    return p.equals(root, candidate) || p.isWithin(root, candidate);
  }

  static String? resolveInsideRoot(String rootPath, String candidatePath) {
    if (candidatePath.contains('\u0000')) return null;
    final candidate = canonicalize(candidatePath);
    return isWithinRoot(rootPath, candidate) ? candidate : null;
  }

  /// Join [relative] onto [rootPath]. Returns null if the result would escape.
  static String? joinInsideRoot(String rootPath, String relative) {
    if (relative.contains('\u0000')) return null;
    final posix = relative.replaceAll('\\', '/');
    if (posix.startsWith('/') || posix.contains(':')) return null;
    final normalized = p.posix.normalize(posix);
    if (normalized == '..' || normalized.startsWith('../')) return null;
    if (normalized.split('/').contains('..')) return null;
    if (normalized == '.' || normalized.isEmpty) {
      return canonicalize(rootPath);
    }
    final hostRel = normalized.split('/').join(p.separator);
    return resolveInsideRoot(rootPath, p.join(rootPath, hostRel));
  }

  static String? posixRelative(String rootPath, String hostPath) {
    final resolved = resolveInsideRoot(rootPath, hostPath);
    if (resolved == null) return null;
    final root = canonicalize(rootPath);
    if (p.equals(root, resolved)) return '';
    return p.relative(resolved, from: root).replaceAll('\\', '/');
  }

  static bool isHiddenName(String name) => name.startsWith('.');

  static bool isValidFileName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == '.' || trimmed == '..') return false;
    if (trimmed.contains('\u0000')) return false;
    if (trimmed.contains('/') || trimmed.contains('\\')) return false;
    return true;
  }

  /// Empty string is allowed (workspace root). Otherwise a relative path
  /// without `..` or absolute segments.
  static bool isValidRelativePath(String path) {
    if (path.isEmpty) return true;
    if (path.contains('\u0000')) return false;
    final posix = path.trim().replaceAll('\\', '/');
    if (posix.startsWith('/')) return false;
    final normalized = p.posix.normalize(posix);
    if (normalized == '..' || normalized.startsWith('../')) return false;
    return !normalized.split('/').contains('..');
  }

  static String uniqueName(Directory dir, String desiredName) {
    if (!_exists(p.join(dir.path, desiredName))) {
      return desiredName;
    }
    final ext = p.extension(desiredName);
    final stem = ext.isEmpty
        ? desiredName
        : desiredName.substring(0, desiredName.length - ext.length);
    var n = 2;
    while (true) {
      final candidate = '$stem ($n)$ext';
      if (!_exists(p.join(dir.path, candidate))) {
        return candidate;
      }
      n += 1;
    }
  }

  static bool _exists(String path) {
    return FileSystemEntity.typeSync(path, followLinks: false) !=
        FileSystemEntityType.notFound;
  }

  static Future<List<FileBrowserEntry>> listDir(
    Directory dir, {
    required String rootPath,
    required bool showHidden,
    required FileBrowserSortField sort,
    required bool ascending,
    bool foldersFirst = true,
    bool directoriesOnly = false,
    String? excludePath,
  }) async {
    final access = _access(rootPath);
    await access.resolve(dir.path);
    final exclude = excludePath == null
        ? null
        : resolveInsideRoot(rootPath, excludePath);
    final names = await access.withDirectory(
      dir.path,
      (anchoredPath) async => [
        await for (final entity in Directory(
          anchoredPath,
        ).list(followLinks: false))
          p.basename(entity.path),
      ],
    );
    final entries = <FileBrowserEntry>[];
    for (final name in names) {
      if (!showHidden && isHiddenName(name)) continue;
      final entityPath = resolveInsideRoot(rootPath, p.join(dir.path, name));
      if (entityPath == null) continue;
      if (exclude != null &&
          (p.equals(entityPath, exclude) || p.isWithin(exclude, entityPath))) {
        continue;
      }
      FileStat stat;
      try {
        stat = await access.stat(entityPath);
      } on WorkspaceFileAccessException {
        // An escaped or replaced link must not disclose its target's metadata.
        continue;
      } on FileSystemException {
        continue;
      }
      final isDirectory = stat.type == FileSystemEntityType.directory;
      if (directoriesOnly && !isDirectory) continue;
      entries.add(
        FileBrowserEntry(
          name: name,
          hostPath: entityPath,
          isDirectory: isDirectory,
          size: stat.size,
          modified: stat.modified,
          rootPath: rootPath,
        ),
      );
    }
    entries.sort((a, b) {
      if (foldersFirst && a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      final int cmp;
      switch (sort) {
        case FileBrowserSortField.name:
          cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case FileBrowserSortField.modified:
          cmp = a.modified.compareTo(b.modified);
        case FileBrowserSortField.size:
          cmp = a.size.compareTo(b.size);
      }
      return ascending ? cmp : -cmp;
    });
    return entries;
  }

  /// Default host `dart:io` runner used when [FileBrowser.mutationRunner] is null.
  static Future<void> runMutation(FileMutation mutation) async {
    await validateMutation(mutation);
    switch (mutation) {
      case CreateFolderMutation(
        :final rootPath,
        :final parentPath,
        :final name,
      ):
        await createFolder(
          rootPath: rootPath,
          readOnlyRoots: mutation.readOnlyRoots,
          parent: Directory(parentPath),
          name: name,
        );
      case CreateFileMutation(:final rootPath, :final parentPath, :final name):
        await createFile(
          rootPath: rootPath,
          readOnlyRoots: mutation.readOnlyRoots,
          parent: Directory(parentPath),
          name: name,
        );
      case RenameMutation(:final rootPath, :final hostPath, :final newName):
        await renameEntry(
          rootPath: rootPath,
          readOnlyRoots: mutation.readOnlyRoots,
          hostPath: hostPath,
          newName: newName,
        );
      case MoveMutation(:final rootPath, :final hostPath, :final destDirPath):
        await moveEntry(
          rootPath: rootPath,
          readOnlyRoots: mutation.readOnlyRoots,
          hostPath: hostPath,
          destDir: Directory(destDirPath),
        );
      case DeleteMutation(:final rootPath, :final hostPath):
        await deleteEntry(
          rootPath: rootPath,
          readOnlyRoots: mutation.readOnlyRoots,
          hostPath: hostPath,
        );
      case CopyIntoMutation(
        :final rootPath,
        :final sourcePath,
        :final destDirPath,
        :final pickedSource,
      ):
        await copyInto(
          rootPath: rootPath,
          readOnlyRoots: mutation.readOnlyRoots,
          source: File(sourcePath),
          destDir: Directory(destDirPath),
          pickedSource: pickedSource,
        );
      case ZipDirectoryMutation(
        :final rootPath,
        :final sourcePath,
        :final destPath,
        :final destinationRoot,
      ):
        await zipDirectory(
          rootPath: rootPath,
          readOnlyRoots: mutation.readOnlyRoots,
          source: Directory(sourcePath),
          dest: File(destPath),
          destinationRoot: destinationRoot,
        );
    }
  }

  /// Run this before user-supplied runners too; callbacks cannot waive the
  /// browser's boundary. Actual I/O checks again while holding descriptors.
  static Future<void> validateMutation(FileMutation mutation) async {
    final access = _access(
      mutation.rootPath,
      readOnlyRoots: mutation.readOnlyRoots,
    );
    switch (mutation) {
      case CreateFolderMutation(:final parentPath, :final name) ||
          CreateFileMutation(:final parentPath, :final name):
        if (!isValidFileName(name)) throw ArgumentError('invalid name');
        await access.resolve(p.join(parentPath, name), write: true);
      case RenameMutation(:final hostPath, :final newName):
        if (!isValidFileName(newName)) throw ArgumentError('invalid name');
        await access.resolve(hostPath, write: true);
        await access.resolve(p.join(p.dirname(hostPath), newName), write: true);
      case MoveMutation(:final hostPath, :final destDirPath):
        await access.resolve(hostPath, write: true);
        await access.resolve(destDirPath, write: true);
      case DeleteMutation(:final hostPath):
        await access.resolve(hostPath, followFinalLink: false, write: true);
      case CopyIntoMutation(
        :final sourcePath,
        :final destDirPath,
        :final pickedSource,
      ):
        if (pickedSource == null) await access.resolve(sourcePath);
        await access.resolve(destDirPath, write: true);
      case ZipDirectoryMutation(
        :final sourcePath,
        :final destPath,
        :final destinationRoot,
      ):
        await access.resolve(sourcePath);
        await _access(
          destinationRoot ?? mutation.rootPath,
          readOnlyRoots: mutation.readOnlyRoots,
        ).resolve(destPath, write: true);
    }
  }

  static Future<int> directorySize(
    Directory dir, {
    required String rootPath,
  }) async {
    var total = 0;
    final access = _access(rootPath);
    await for (final path in _walkFiles(access, dir.path)) {
      final file = await access.openRead(path);
      try {
        total += await file.handle.length();
      } finally {
        await file.close();
      }
    }
    return total;
  }

  static Future<void> createFolder({
    required String rootPath,
    Iterable<String> readOnlyRoots = const [],
    required Directory parent,
    required String name,
  }) async {
    if (!isValidFileName(name)) throw ArgumentError('invalid name');
    final dest = p.join(parent.path, name);
    await _access(
      rootPath,
      readOnlyRoots: readOnlyRoots,
    ).createDirectory(dest, recursive: false);
  }

  static Future<void> createFile({
    required String rootPath,
    Iterable<String> readOnlyRoots = const [],
    required Directory parent,
    required String name,
  }) async {
    if (!isValidFileName(name)) throw ArgumentError('invalid name');
    final access = _access(rootPath, readOnlyRoots: readOnlyRoots);
    final dest = p.join(parent.path, name);
    await access.resolve(dest, write: true);
    // File.create preserves an existing file. Opening without truncation does
    // the same while verifying the descriptor before any change.
    final file = await access.openWrite(dest, append: true);
    await file.close();
  }

  static Future<void> renameEntry({
    required String rootPath,
    Iterable<String> readOnlyRoots = const [],
    required String hostPath,
    required String newName,
  }) async {
    if (!isValidFileName(newName)) throw ArgumentError('invalid name');
    final access = _access(rootPath, readOnlyRoots: readOnlyRoots);
    final source = await access.resolve(hostPath, write: true);
    final realRoot = await access.resolve(rootPath);
    if (p.equals(realRoot, source)) throw StateError('cannot rename root');
    final dest = p.join(p.dirname(hostPath), newName);
    await access.resolve(dest, write: true);
    await _movePath(access, hostPath, dest);
  }

  static Future<void> moveEntry({
    required String rootPath,
    Iterable<String> readOnlyRoots = const [],
    required String hostPath,
    required Directory destDir,
  }) async {
    final access = _access(rootPath, readOnlyRoots: readOnlyRoots);
    final source = await access.resolve(hostPath, write: true);
    final destDirPath = await access.resolve(destDir.path, write: true);
    if (p.equals(await access.resolve(rootPath), source)) {
      throw StateError('cannot move root');
    }
    if (p.equals(source, destDirPath) || p.isWithin(source, destDirPath)) {
      throw StateError('invalid move');
    }
    final name = await access.withDirectory(
      destDir.path,
      (path) async => uniqueName(Directory(path), p.basename(hostPath)),
    );
    final dest = p.join(destDir.path, name);
    await access.resolve(dest, write: true);
    if (p.equals(source, await access.resolve(dest))) return;
    await _movePath(access, hostPath, dest);
  }

  static Future<void> deleteEntry({
    required String rootPath,
    Iterable<String> readOnlyRoots = const [],
    required String hostPath,
  }) async {
    final access = _access(rootPath, readOnlyRoots: readOnlyRoots);
    final source = await access.resolve(
      hostPath,
      followFinalLink: false,
      write: true,
    );
    if (p.equals(await access.resolve(rootPath), source)) {
      throw StateError('cannot delete root');
    }
    await access.withParent(hostPath, (path) async {
      final type = await FileSystemEntity.type(path, followLinks: false);
      if (type == FileSystemEntityType.link) {
        await Link(path).delete();
      } else if (type == FileSystemEntityType.directory) {
        await Directory(path).delete(recursive: true);
      } else {
        await File(path).delete();
      }
    }, followFinalLink: false);
  }

  static Future<void> copyInto({
    required String rootPath,
    Iterable<String> readOnlyRoots = const [],
    required File source,
    required Directory destDir,
    WorkspaceFileHandle? pickedSource,
  }) async {
    final access = _access(rootPath, readOnlyRoots: readOnlyRoots);
    final input = pickedSource ?? await access.openRead(source.path);
    try {
      final name = await access.withDirectory(
        destDir.path,
        (path) async => uniqueName(Directory(path), p.basename(source.path)),
      );
      final output = await access.openWrite(p.join(destDir.path, name));
      try {
        await _copyHandles(input, output);
      } finally {
        await output.close();
      }
    } finally {
      if (pickedSource == null) await input.close();
    }
  }

  static Stream<String> _walkFiles(
    WorkspaceFileAccess access,
    String directory,
  ) async* {
    final children = await access.withDirectory(
      directory,
      (path) async => [
        await for (final entity in Directory(path).list(followLinks: false))
          (
            name: p.basename(entity.path),
            directory: entity is Directory,
            file: entity is File,
          ),
      ],
    );
    for (final child in children) {
      final path = p.join(directory, child.name);
      if (child.directory) {
        yield* _walkFiles(access, path);
      } else if (child.file) {
        await access.resolve(path);
        yield path;
      }
    }
  }

  static Future<File> zipDirectory({
    required String rootPath,
    Iterable<String> readOnlyRoots = const [],
    required Directory source,
    required File dest,
    String? destinationRoot,
  }) async {
    final access = _access(rootPath, readOnlyRoots: readOnlyRoots);
    final destinationAccess = _access(
      destinationRoot ?? rootPath,
      readOnlyRoots: readOnlyRoots,
    );
    await access.resolve(source.path);
    await destinationAccess.resolve(dest.path, write: true);
    final archive = Archive();
    await for (final filePath in _walkFiles(access, source.path)) {
      // Never include an old archive at the output path in its own contents.
      if (p.equals(canonicalize(filePath), canonicalize(dest.path))) continue;
      final rel = p.relative(filePath, from: source.path).replaceAll('\\', '/');
      archive.addFile(ArchiveFile.bytes(rel, await access.readBytes(filePath)));
    }
    await destinationAccess.createDirectory(dest.parent.path);
    final out = await destinationAccess.openWrite(dest.path);
    try {
      await out.handle.writeFrom(ZipEncoder().encodeBytes(archive));
      await out.handle.flush();
    } finally {
      await out.close();
    }
    return dest;
  }

  static Future<void> _movePath(
    WorkspaceFileAccess access,
    String source,
    String dest,
  ) async {
    // Follow links for the policy check above, then rename the directory entry
    // itself. Held parent descriptors prevent an ancestor from changing target.
    await access.withParent(source, (anchoredSource) async {
      await access.withParent(dest, (anchoredDest) async {
        final type = await FileSystemEntity.type(
          anchoredSource,
          followLinks: false,
        );
        if (type == FileSystemEntityType.directory) {
          await Directory(anchoredSource).rename(anchoredDest);
        } else if (type == FileSystemEntityType.link) {
          await Link(anchoredSource).rename(anchoredDest);
        } else {
          await File(anchoredSource).rename(anchoredDest);
        }
      }, followFinalLink: false);
    }, followFinalLink: false);
  }
}

class WorkspaceModelPaths {
  WorkspaceModelPaths._();

  static bool get useGuestPaths => Platform.isAndroid;

  static String workspaceFile(String hostPath, String workspaceRoot) {
    if (!useGuestPaths) return hostPath;
    final rel = FileBrowserOps.posixRelative(workspaceRoot, hostPath);
    if (rel == null || rel.isEmpty) return '/workspace';
    return '/workspace/$rel';
  }

  static String chatFile(String hostPath, String zoneRoot, String zone) {
    if (!useGuestPaths) return hostPath;
    final rel = FileBrowserOps.posixRelative(zoneRoot, hostPath);
    if (rel == null || rel.isEmpty) return '/chat/$zone';
    return '/chat/$zone/$rel';
  }
}
