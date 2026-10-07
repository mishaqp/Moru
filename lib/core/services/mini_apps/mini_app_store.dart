import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../utils/app_directories.dart';
import '../skills/skill_archive.dart' show safeZipEntryName;
import '../workspace/workspace_file_access.dart';
import 'mini_app_browser_storage_state.dart';

/// A mini app the agent built and published: a small web app with its own
/// data, opened inside Moru or from a home screen shortcut.
@immutable
class MiniApp {
  const MiniApp({
    required this.id,
    required this.name,
    required this.directory,
    this.description = '',
    this.entry = 'index.html',
    this.icon,
    this.dataHelp = '',
    this.network = const [],
    this.permissions = const {},
    this.fullscreen = false,
    this.orientation = MiniAppOrientation.any,
    this.keepAwake = false,
    this.serverCommand,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String description;

  /// What the app keeps in `moru.storage`, from `data` in the manifest, so the
  /// chat can read and change it.
  final String dataHelp;

  /// Hosts `moru.fetch` may reach, from `network` in the manifest. An entry
  /// `*.example.com` also allows every subdomain.
  final List<String> network;

  /// Device features the app asked for in `permissions`, e.g. `calendar`.
  final Set<String> permissions;

  /// Hides Moru's app bar and the system bars, e.g. for games.
  final bool fullscreen;

  /// Screen orientation while the app is open.
  final MiniAppOrientation orientation;

  /// Keeps the screen on while the app is open.
  final bool keepAwake;

  /// Shell command of the app's server, from `server.command`: Moru runs it
  /// in the Linux environment while the app is open (see MiniAppServers).
  final String? serverCommand;

  /// Folder of the installed copy (manifest, app/ and data).
  final String directory;

  /// Entry page, relative to [codeDirectory].
  final String entry;

  /// SVG icon relative to [codeDirectory], or null for the letter icon.
  final String? icon;
  final DateTime updatedAt;

  String get codeDirectory => p.join(directory, 'app');
  String get entryPath => p.join(codeDirectory, entry);
  String? get iconPath => icon == null ? null : p.join(codeDirectory, icon);

  /// Opens the app from a chat reply.
  String get link => MiniAppStore.linkFor(id);

  factory MiniApp.fromJson(
    String directory,
    Map<String, dynamic> json,
  ) => MiniApp(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String? ?? '',
    entry: json['entry'] as String? ?? 'index.html',
    icon: json['icon'] as String?,
    dataHelp: json['data'] as String? ?? '',
    network: [for (final host in json['network'] as List? ?? const []) '$host'],
    permissions: {
      for (final name in json['permissions'] as List? ?? const []) '$name',
    },
    fullscreen: json['fullscreen'] == true,
    orientation:
        MiniAppOrientation.parse(json['orientation']) ?? MiniAppOrientation.any,
    keepAwake: json['keepAwake'] == true,
    serverCommand: json['server'] is Map
        ? (json['server'] as Map)['command'] as String?
        : null,
    directory: directory,
    updatedAt: DateTime.fromMillisecondsSinceEpoch(
      json['updatedAt'] as int? ?? 0,
    ),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (description.isNotEmpty) 'description': description,
    'entry': entry,
    'icon': ?icon,
    if (dataHelp.isNotEmpty) 'data': dataHelp,
    if (network.isNotEmpty) 'network': network,
    if (permissions.isNotEmpty) 'permissions': permissions.toList()..sort(),
    if (fullscreen) 'fullscreen': true,
    if (orientation != MiniAppOrientation.any) 'orientation': orientation.name,
    if (keepAwake) 'keepAwake': true,
    if (serverCommand != null) 'server': {'command': serverCommand},
    'updatedAt': updatedAt.millisecondsSinceEpoch,
  };
}

enum MiniAppOrientation {
  any,
  portrait,
  landscape;

  /// The value of `orientation` in moru-app.json, or null when it is not
  /// one of these names.
  static MiniAppOrientation? parse(Object? raw) {
    for (final value in values) {
      if (value.name == raw) return value;
    }
    return null;
  }
}

/// One line of an app's error journal. Repeats of the last message only
/// raise [count].
@immutable
class MiniAppLogEntry {
  const MiniAppLogEntry({
    required this.at,
    required this.message,
    this.count = 1,
  });

  final DateTime at;
  final String message;
  final int count;

  factory MiniAppLogEntry.fromJson(Map<String, dynamic> json) =>
      MiniAppLogEntry(
        at: DateTime.fromMillisecondsSinceEpoch(json['at'] as int? ?? 0),
        message: '${json['message'] ?? ''}',
        count: json['count'] as int? ?? 1,
      );

  Map<String, dynamic> toJson() => {
    'at': at.millisecondsSinceEpoch,
    'message': message,
    if (count > 1) 'count': count,
  };
}

class MiniAppException implements Exception {
  const MiniAppException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

/// Installed mini apps under the app data directory:
///
/// ```
/// mini_apps/<id>/manifest.json   what Moru knows about the app
/// mini_apps/<id>/app/            copy of the published files
/// mini_apps/<id>/data.json       moru.storage, kept across republishing
/// mini_apps/<id>/errors.json     error journal of the current code
/// mini_apps/<id>/versions/<ms>/  earlier manifest.json and app/, named by
///                                their updatedAt
/// ```
class MiniAppStore extends ChangeNotifier {
  MiniAppStore({Future<Directory> Function()? root, DateTime Function()? now})
    : _root = root ?? _defaultRoot,
      _now = now ?? DateTime.now;

  static final MiniAppStore instance = MiniAppStore();

  static const String manifestFile = 'moru-app.json';
  static const String bridgeFile = 'moru.js';
  static const int maxFiles = 500;
  static const int maxBytes = 20 * 1024 * 1024;
  static const int maxDataBytes = 5 * 1024 * 1024;
  static const int maxKeyLength = 200;

  /// Folders a build leaves behind that never belong in the published app.
  static const Set<String> skippedDirectories = {
    'node_modules',
    '.git',
    '__pycache__',
    // Virtualenvs of a server; it installs its dependencies into /data.
    '.venv',
    'venv',
  };

  static final RegExp _idPattern = RegExp(r'^[a-z0-9][a-z0-9-]{0,39}$');

  final Future<Directory> Function() _root;
  final DateTime Function() _now;
  List<MiniApp> _apps = const [];
  bool _loaded = false;
  Future<void>? _loading;
  final Map<String, Future<void>> _writes = {};
  Future<void> _codeWrites = Future<void>.value();
  final StreamController<({String appId, String key})> _changes =
      StreamController.broadcast();
  final List<Future<void> Function(String id)> _deleteHooks = [];

  /// Data written from outside the app itself, e.g. by the chat, so an open
  /// app can redraw.
  Stream<({String appId, String key})> get changes => _changes.stream;

  /// Runs before an app is deleted, e.g. to cancel its reminders.
  void addDeleteHook(Future<void> Function(String id) hook) =>
      _deleteHooks.add(hook);

  static Future<Directory> _defaultRoot() async {
    final base = await AppDirectories.getAppDataDirectory();
    return Directory(p.join(base.path, 'mini_apps'));
  }

  static String linkFor(String id) => 'kelivo://app/$id';

  /// The app id in a `kelivo://app/<id>` link, or null for other links.
  static String? idFromLink(String url) {
    final match = RegExp(
      r'^kelivo://app/([a-z0-9][a-z0-9-]{0,39})/?$',
      caseSensitive: false,
    ).firstMatch(url.trim());
    return match?.group(1)?.toLowerCase();
  }

  /// Installed apps, most recently updated first.
  List<MiniApp> get apps => _apps;
  bool get loaded => _loaded;

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final root = await _root();
    final apps = <MiniApp>[];
    if (await root.exists()) {
      await for (final entry in root.list()) {
        // Staging folders of an interrupted install or rollback.
        if (entry is! Directory || p.basename(entry.path).startsWith('.')) {
          continue;
        }
        final manifest = File(p.join(entry.path, 'manifest.json'));
        if (!await manifest.exists()) continue;
        try {
          final app = MiniApp.fromJson(
            entry.path,
            jsonDecode(await manifest.readAsString()) as Map<String, dynamic>,
          );
          await MiniAppBrowserStorageState.registerLegacy(app);
          apps.add(app);
        } catch (e) {
          debugPrint('[MiniApps] skipping ${entry.path}: $e');
        }
      }
    }
    _apps = _sorted(apps);
    _loaded = true;
    notifyListeners();
  }

  MiniApp? byId(String id) {
    for (final app in _apps) {
      if (app.id == id) return app;
    }
    return null;
  }

  /// Installs or updates the app in [sourceDir], which holds
  /// `moru-app.json`. Returns the app and whether it replaced an older copy.
  /// Stored data survives an update.
  Future<({MiniApp app, bool updated, int files, int bytes})> install(
    Directory sourceDir, {
    Map<String, dynamic>? manifest,
    WorkspaceFileAccess? sourceAccess,
  }) => _mutateCode(
    () => _install(sourceDir, manifest: manifest, sourceAccess: sourceAccess),
  );

  Future<({MiniApp app, bool updated, int files, int bytes})> _install(
    Directory sourceDir, {
    Map<String, dynamic>? manifest,
    WorkspaceFileAccess? sourceAccess,
  }) async {
    final access = WorkspaceFileAccess(roots: [sourceDir.path]);
    await access.resolve(sourceDir.path);
    await load();
    if (manifest == null) {
      final manifestSource = File(p.join(sourceDir.path, manifestFile));
      if (!await manifestSource.exists()) {
        throw const MiniAppException(
          'missing_manifest',
          'The folder has no $manifestFile. Supply manifest when publishing a build folder.',
        );
      }
      try {
        final opened = await _openSource(manifestSource, access, sourceAccess);
        final String text;
        try {
          text = utf8.decode(await opened.readBytes(maxBytes: maxBytes + 1));
          if (text.length > maxBytes) {
            throw const MiniAppException(
              'too_large',
              'The manifest is too large.',
            );
          }
        } finally {
          await opened.close();
        }
        manifest = Map<String, dynamic>.from(jsonDecode(text) as Map);
      } catch (e) {
        throw MiniAppException('invalid_manifest', '$manifestFile: $e');
      }
    }
    final id = '${manifest['id'] ?? ''}'.trim();
    final name = '${manifest['name'] ?? ''}'.trim();
    if (!_idPattern.hasMatch(id)) {
      throw const MiniAppException(
        'invalid_id',
        '"id" must be 1-40 lowercase letters, digits or dashes, '
            'starting with a letter or digit.',
      );
    }
    if (name.isEmpty || name.length > 40) {
      throw const MiniAppException(
        'invalid_name',
        '"name" must be 1-40 characters.',
      );
    }
    final entry = _relative(manifest['entry'], fallback: 'index.html')!;
    final network = _hosts(manifest['network']);
    final permissions = _permissions(manifest['permissions']);
    final icon = _relative(manifest['icon'], fallback: null);
    final orientation = manifest['orientation'] == null
        ? MiniAppOrientation.any
        : MiniAppOrientation.parse(manifest['orientation']);
    if (orientation == null) {
      throw const MiniAppException(
        'invalid_orientation',
        '"orientation" must be "any", "portrait" or "landscape".',
      );
    }
    final serverCommand = _serverCommand(manifest['server']);
    for (final flag in const ['fullscreen', 'keepAwake']) {
      if (manifest[flag] != null && manifest[flag] is! bool) {
        throw MiniAppException(
          'invalid_manifest',
          '"$flag" must be a boolean.',
        );
      }
    }

    final files = await _collect(sourceDir, access: access);
    final names = files.map((f) => f.relative).toSet();
    if (!names.contains(entry)) {
      throw MiniAppException('missing_entry', 'Entry file "$entry" not found.');
    }
    if (icon != null && !names.contains(icon)) {
      throw MiniAppException('missing_icon', 'Icon file "$icon" not found.');
    }
    if (icon != null && p.extension(icon).toLowerCase() != '.svg') {
      throw const MiniAppException('invalid_icon', 'The icon must be an SVG.');
    }
    var bytes = 0;

    final root = await _root();
    final directory = Directory(p.join(root.path, id));
    final previous = byId(id);
    // Build the new copy beside the old one so a failure keeps the old app.
    final staging = Directory(p.join(root.path, '.$id.staging'));
    if (await staging.exists()) await staging.delete(recursive: true);
    final code = Directory(p.join(staging.path, 'app'));
    await code.create(recursive: true);
    for (final file in files) {
      final target = File(p.join(code.path, file.relative));
      await target.parent.create(recursive: true);
      bytes += await _copySource(
        file.file,
        target,
        access,
        sourceAccess,
        maxBytes - bytes,
      );
    }
    await File(p.join(code.path, bridgeFile)).writeAsString(moruBridgeScript);
    final entryFile = File(p.join(code.path, entry));
    if (_isHtml(entry)) {
      await entryFile.writeAsString(
        withBridgeScript(await entryFile.readAsString(), entry),
      );
    }

    final app = MiniApp(
      id: id,
      name: name,
      description: '${manifest['description'] ?? ''}'.trim(),
      entry: entry,
      icon: icon,
      dataHelp: _limited('${manifest['data'] ?? ''}'.trim(), 2000),
      network: network,
      permissions: permissions,
      fullscreen: manifest['fullscreen'] == true,
      orientation: orientation,
      keepAwake: manifest['keepAwake'] == true,
      serverCommand: serverCommand,
      directory: directory.path,
      updatedAt: await _publicationTime(previous),
    );
    await File(
      p.join(staging.path, 'manifest.json'),
    ).writeAsString(jsonEncode(app.toJson()));

    await directory.create(recursive: true);
    final oldCode = Directory(p.join(directory.path, 'app'));
    if (previous != null) {
      await _keepVersion(previous);
    } else if (await oldCode.exists()) {
      await oldCode.delete(recursive: true);
    }
    await code.rename(oldCode.path);
    if (previous == null) await MiniAppBrowserStorageState.registerFresh(app);
    await File(
      p.join(staging.path, 'manifest.json'),
    ).rename(p.join(directory.path, 'manifest.json'));
    await staging.delete(recursive: true);
    if (previous != null) await clearErrors(id);

    _apps = _sorted([
      for (final other in _apps)
        if (other.id != id) other,
      app,
    ]);
    notifyListeners();
    return (
      app: app,
      updated: previous != null,
      files: files.length,
      bytes: bytes,
    );
  }

  /// Replaces only [files] from [sourceDir]. Metadata is inherited unless
  /// supplied in [manifest]; data, jobs and the remaining code are retained.
  /// The complete result is validated before the installed copy is changed.
  Future<({MiniApp app, bool updated, int files, int bytes})> updateFiles(
    String id,
    Directory sourceDir, {
    required List<String> files,
    Map<String, dynamic>? manifest,
    WorkspaceFileAccess? sourceAccess,
  }) => _mutateCode(() async {
    final access = WorkspaceFileAccess(roots: [sourceDir.path]);
    await access.resolve(sourceDir.path);
    await load();
    final app = _require(id);
    if (files.isEmpty || files.length > maxFiles) {
      throw const MiniAppException(
        'invalid_files',
        'files must contain 1-$maxFiles relative file paths.',
      );
    }
    if (manifest != null && manifest['id'] != null && manifest['id'] != id) {
      throw const MiniAppException(
        'invalid_id',
        'A partial update cannot change the app id.',
      );
    }
    final selected = <String, File>{};
    final sourceRoot = await sourceDir.resolveSymbolicLinks();
    for (final raw in files) {
      final name = _relative(raw, fallback: null);
      if (name == null ||
          name == manifestFile ||
          name == bridgeFile ||
          p.posix
              .split(name)
              .any(
                (part) =>
                    part.startsWith('.') || skippedDirectories.contains(part),
              ) ||
          selected.containsKey(name)) {
        throw MiniAppException('invalid_path', 'Cannot patch "$raw".');
      }
      final file = File(p.joinAll([sourceRoot, ...p.posix.split(name)]));
      if (!await file.exists()) {
        throw MiniAppException('missing_file', 'File "$raw" not found.');
      }
      selected[name] = file;
    }
    final root = await _root();
    final staging = await root.createTemp('.$id.patch-');
    try {
      final installedAccess = WorkspaceFileAccess(roots: [app.codeDirectory]);
      var bytes = 0;
      for (final file in await _collect(Directory(app.codeDirectory))) {
        final target = File(p.join(staging.path, file.relative));
        await target.parent.create(recursive: true);
        bytes += await _copySource(
          file.file,
          target,
          installedAccess,
          null,
          maxBytes - bytes,
        );
      }
      for (final file in selected.entries) {
        final target = File(p.join(staging.path, file.key));
        await target.parent.create(recursive: true);
        if (await target.exists()) bytes -= await target.length();
        bytes += await _copySource(
          file.value,
          target,
          access,
          sourceAccess,
          maxBytes - bytes,
        );
      }
      return await _install(
        staging,
        manifest: {
          ...app.toJson()..remove('updatedAt'),
          // Strict tool schemas emit null for unspecified optional fields.
          for (final entry
              in manifest?.entries ?? const <MapEntry<String, dynamic>>[])
            if (entry.value != null) entry.key: entry.value,
        },
      );
    } finally {
      await staging.delete(recursive: true);
    }
  });

  /// Publish, patch, rollback and delete share staging folders and history.
  /// Serializing them also makes two concurrent patches compose correctly.
  Future<T> _mutateCode<T>(Future<T> Function() action) {
    final next = _codeWrites.then((_) => action());
    _codeWrites = next.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return next;
  }

  Future<DateTime> _publicationTime(MiniApp? previous) async {
    var time = _now();
    if (previous == null) return time;
    // Version folders use milliseconds, even when the clock has microseconds.
    // The clock can also repeat or move backwards, including after rollback.
    for (final version in [previous, ...await _versions(previous)]) {
      if (time.millisecondsSinceEpoch <=
          version.updatedAt.millisecondsSinceEpoch) {
        time = version.updatedAt.add(const Duration(milliseconds: 1));
      }
    }
    return time;
  }

  /// Removes the app, its files and its data.
  Future<void> delete(String id) => _mutateCode(() => _delete(id));

  Future<void> _delete(String id) async {
    await load();
    final app = byId(id);
    if (app == null) return;
    for (final hook in _deleteHooks) {
      await hook(id);
    }
    await _writes[id];
    await _writes[_journal(id)]?.catchError((_) {});
    for (final name in ['jobs.json', 'reminders.json']) {
      await _writes[_mapKey(id, name)]?.catchError((_) {});
    }
    final directory = Directory(app.directory);
    if (await directory.exists()) await directory.delete(recursive: true);
    _apps = [
      for (final other in _apps)
        if (other.id != id) other,
    ];
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // .moruapp files
  // ---------------------------------------------------------------------------

  static const String archiveExtension = '.moruapp';

  /// Stored data inside a `.moruapp`, beside the app's own files.
  static const String archiveDataFile = '.moru-data.json';

  /// Packs [id] into `<into>/<id>.moruapp`: its files and moru-app.json, and
  /// its data when [withData]. Reminders stay on this device.
  Future<File> exportArchive(
    String id, {
    required bool withData,
    required Directory into,
  }) async {
    await load();
    final app = _require(id);
    await _writes[id];
    final archive = Archive();
    final manifest = app.toJson()..remove('updatedAt');
    archive.addFile(
      ArchiveFile.bytes(manifestFile, utf8.encode(jsonEncode(manifest))),
    );
    final code = Directory(app.codeDirectory);
    await for (final entity in code.list(recursive: true)) {
      if (entity is! File) continue;
      final relative = p.posix.joinAll(
        p.split(p.relative(entity.path, from: code.path)),
      );
      if (relative == bridgeFile) continue;
      archive.addFile(ArchiveFile.bytes(relative, await entity.readAsBytes()));
    }
    if (withData) {
      final data = await _readData(app);
      if (data.isNotEmpty) {
        archive.addFile(
          ArchiveFile.bytes(archiveDataFile, utf8.encode(jsonEncode(data))),
        );
      }
    }
    await into.create(recursive: true);
    final file = File(p.join(into.path, '$id$archiveExtension'));
    await file.writeAsBytes(ZipEncoder().encodeBytes(archive), flush: true);
    return file;
  }

  /// Installs the app packed in [file]. Its data is used only when the app
  /// has no data here yet, so importing never overwrites what is stored.
  Future<({MiniApp app, bool updated, bool dataRestored})> importArchive(
    File file,
  ) async {
    await load();
    if (await file.length() > maxBytes + maxDataBytes) {
      throw const MiniAppException('too_large', 'The file is too large.');
    }
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(await file.readAsBytes());
    } catch (_) {
      throw const MiniAppException(
        'invalid_archive',
        'This is not a Moru app file.',
      );
    }
    final root = await _root();
    await root.create(recursive: true);
    final staging = await root.createTemp('.import-');
    try {
      var files = 0;
      var bytes = 0;
      for (final entry in archive) {
        if (!entry.isFile || entry.isSymbolicLink) continue;
        final String? name;
        try {
          name = safeZipEntryName(entry.name);
        } on FormatException {
          throw const MiniAppException(
            'invalid_archive',
            'The file has unsafe paths.',
          );
        }
        if (name == null) continue;
        files++;
        bytes += entry.size;
        if (files > maxFiles + 2 || bytes > maxBytes + maxDataBytes) {
          throw const MiniAppException('too_large', 'The app is too large.');
        }
        final target = File(p.join(staging.path, name));
        await target.parent.create(recursive: true);
        await target.writeAsBytes(entry.readBytes() ?? const []);
      }
      if (!await File(p.join(staging.path, manifestFile)).exists()) {
        throw const MiniAppException(
          'invalid_archive',
          'This is not a Moru app file.',
        );
      }
      Map<String, dynamic>? data;
      final dataFile = File(p.join(staging.path, archiveDataFile));
      if (await dataFile.exists()) {
        try {
          data = Map<String, dynamic>.from(
            jsonDecode(await dataFile.readAsString()) as Map,
          );
        } catch (_) {
          throw const MiniAppException(
            'invalid_archive',
            'The app data in the file is damaged.',
          );
        }
        await dataFile.delete();
      }
      final installed = await install(staging);
      final id = installed.app.id;
      var restored = false;
      if (data != null && data.isNotEmpty) {
        await _update(id, (current) {
          if (current.isNotEmpty) return;
          current.addAll(data!);
          restored = true;
        });
      }
      return (
        app: installed.app,
        updated: installed.updated,
        dataRestored: restored,
      );
    } finally {
      await staging.delete(recursive: true);
    }
  }

  // ---------------------------------------------------------------------------
  // moru.storage
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> _readData(MiniApp app) async {
    final file = File(p.join(app.directory, 'data.json'));
    if (!await file.exists()) return <String, dynamic>{};
    return Map<String, dynamic>.from(
      jsonDecode(await file.readAsString()) as Map,
    );
  }

  Future<Object?> storageGet(String id, String key) async =>
      (await _readData(_require(id)))[key];

  Future<List<String>> storageKeys(String id) async =>
      (await _readData(_require(id))).keys.toList();

  /// All stored values of the app.
  Future<Map<String, dynamic>> storageAll(String id) => _readData(_require(id));

  /// [fromApp] marks the app's own writes; other writes reach [changes].
  Future<void> storageSet(
    String id,
    String key,
    Object? value, {
    bool fromApp = false,
  }) async {
    if (key.isEmpty || key.length > maxKeyLength) {
      throw const MiniAppException(
        'invalid_key',
        'Keys must be 1-$maxKeyLength characters.',
      );
    }
    await _update(id, (data) => data[key] = value);
    if (!fromApp) _changes.add((appId: id, key: key));
  }

  Future<void> storageRemove(
    String id,
    String key, {
    bool fromApp = false,
  }) async {
    await _update(id, (data) => data.remove(key));
    if (!fromApp) _changes.add((appId: id, key: key));
  }

  // ---------------------------------------------------------------------------
  // Reminders and background jobs, kept with the app
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> readReminders(String id) =>
      _readMap(id, 'reminders.json');

  /// Reads, changes and writes the reminders as one step (see [updateJobs]).
  Future<T> updateReminders<T>(
    String id,
    FutureOr<T> Function(Map<String, dynamic> reminders) change,
  ) => _updateMap(id, 'reminders.json', change);

  /// Background jobs set with `moru.jobs` (scheduled by MiniAppJobs).
  Future<Map<String, dynamic>> readJobs(String id) => _readMap(id, 'jobs.json');

  /// Reads, changes and writes the jobs as one step, one call after
  /// another: a page that does not await each `moru.jobs.set` must not have
  /// one call overwrite another or both write the same temporary file. A
  /// [change] that throws writes nothing.
  Future<T> updateJobs<T>(
    String id,
    FutureOr<T> Function(Map<String, dynamic> jobs) change,
  ) => _updateMap(id, 'jobs.json', change);

  Future<T> _updateMap<T>(
    String id,
    String name,
    FutureOr<T> Function(Map<String, dynamic> map) change,
  ) => _queued(_mapKey(id, name), () async {
    final map = await _readMap(id, name);
    final result = await change(map);
    await _writeMap(id, name, map);
    return result;
  });

  static String _mapKey(String id, String name) => '$id\u0000$name';

  Future<Map<String, dynamic>> _readMap(String id, String name) async {
    final file = File(p.join(_require(id).directory, name));
    if (!await file.exists()) return <String, dynamic>{};
    return Map<String, dynamic>.from(
      jsonDecode(await file.readAsString()) as Map,
    );
  }

  Future<void> _writeMap(
    String id,
    String name,
    Map<String, dynamic> map,
  ) async => _writeAtomically(
    File(p.join(_require(id).directory, name)),
    jsonEncode(map),
  );

  // ---------------------------------------------------------------------------
  // Error journal
  // ---------------------------------------------------------------------------

  static const int maxLogEntries = 50;

  static String _journal(String id) => '$id/errors';

  File _errorsFile(MiniApp app) => File(p.join(app.directory, 'errors.json'));

  /// The journal of the current code, oldest first.
  Future<List<MiniAppLogEntry>> readErrors(String id) async {
    await load();
    final app = _require(id);
    await _writes[_journal(id)]?.catchError((_) {});
    return _readErrors(app);
  }

  Future<List<MiniAppLogEntry>> _readErrors(MiniApp app) async {
    final file = _errorsFile(app);
    if (!await file.exists()) return [];
    try {
      return [
        for (final entry in jsonDecode(await file.readAsString()) as List)
          MiniAppLogEntry.fromJson(Map<String, dynamic>.from(entry as Map)),
      ];
    } on FormatException {
      return [];
    }
  }

  /// Adds [message] to the journal, keeping the last [maxLogEntries].
  Future<void> logError(String id, String message) async {
    final app = _require(id);
    return _queued(_journal(id), () async {
      final entries = await _readErrors(app);
      final last = entries.isEmpty ? null : entries.last;
      if (last != null && last.message == message) {
        entries.last = MiniAppLogEntry(
          at: _now(),
          message: message,
          count: last.count + 1,
        );
      } else {
        entries.add(MiniAppLogEntry(at: _now(), message: message));
      }
      final kept = entries.length > maxLogEntries
          ? entries.sublist(entries.length - maxLogEntries)
          : entries;
      await _writeAtomically(
        _errorsFile(app),
        jsonEncode([for (final entry in kept) entry.toJson()]),
      );
    });
  }

  Future<void> clearErrors(String id) async {
    final app = _require(id);
    return _queued(_journal(id), () async {
      final file = _errorsFile(app);
      if (await file.exists()) await file.delete();
    });
  }

  // ---------------------------------------------------------------------------
  // Versions
  // ---------------------------------------------------------------------------

  static const int maxVersions = 5;
  static final RegExp _versionPattern = RegExp(r'^\d{1,16}$');

  /// Earlier copies of the app's code, newest first. [MiniApp.updatedAt]
  /// tells when each was published; [versionOf] names it for [rollback].
  Future<List<MiniApp>> versions(String id) async {
    await load();
    return _versions(_require(id));
  }

  static String versionOf(MiniApp version) =>
      '${version.updatedAt.millisecondsSinceEpoch}';

  Future<List<MiniApp>> _versions(MiniApp app) async {
    final root = Directory(p.join(app.directory, 'versions'));
    if (!await root.exists()) return [];
    final found = <MiniApp>[];
    await for (final entry in root.list()) {
      if (entry is! Directory ||
          !_versionPattern.hasMatch(p.basename(entry.path))) {
        continue;
      }
      try {
        found.add(
          MiniApp.fromJson(
            entry.path,
            jsonDecode(
                  await File(
                    p.join(entry.path, 'manifest.json'),
                  ).readAsString(),
                )
                as Map<String, dynamic>,
          ),
        );
      } catch (e) {
        debugPrint('[MiniApps] skipping version ${entry.path}: $e');
      }
    }
    return _sorted(found);
  }

  /// Moves the current code of [app] into `versions/` and drops the oldest
  /// copies beyond [maxVersions]. The manifest stays until it is replaced.
  Future<void> _keepVersion(MiniApp app) async {
    final target = Directory(p.join(app.directory, 'versions', versionOf(app)));
    if (await target.exists()) await target.delete(recursive: true);
    await target.create(recursive: true);
    final code = Directory(app.codeDirectory);
    if (await code.exists()) {
      await code.rename(p.join(target.path, 'app'));
    }
    await File(
      p.join(app.directory, 'manifest.json'),
    ).copy(p.join(target.path, 'manifest.json'));
    final kept = await _versions(app);
    for (final old in kept.skip(maxVersions)) {
      await Directory(old.directory).delete(recursive: true);
    }
  }

  /// Puts back the code of [version] (see [versions]). The current code
  /// becomes a version itself, so a rollback can be undone. Stored data and
  /// reminders stay as they are.
  Future<MiniApp> rollback(String id, String version) =>
      _mutateCode(() => _rollback(id, version));

  Future<MiniApp> _rollback(String id, String version) async {
    await load();
    final current = _require(id);
    final source = Directory(p.join(current.directory, 'versions', version));
    if (!_versionPattern.hasMatch(version) ||
        !await File(p.join(source.path, 'manifest.json')).exists() ||
        !await Directory(p.join(source.path, 'app')).exists()) {
      throw MiniAppException('not_found', 'No version "$version" of "$id".');
    }
    // Move it aside first so pruning while keeping the current code cannot
    // delete it.
    final picked = Directory(
      p.join(p.dirname(current.directory), '.$id.rollback'),
    );
    if (await picked.exists()) await picked.delete(recursive: true);
    await source.rename(picked.path);
    final manifest = File(p.join(picked.path, 'manifest.json'));
    final restored = MiniApp.fromJson(
      current.directory,
      jsonDecode(await manifest.readAsString()) as Map<String, dynamic>,
    );
    await _keepVersion(current);
    await Directory(p.join(picked.path, 'app')).rename(restored.codeDirectory);
    await manifest.rename(p.join(current.directory, 'manifest.json'));
    await picked.delete(recursive: true);
    await refreshBridge(restored);
    await clearErrors(id);
    _apps = _sorted([
      for (final other in _apps)
        if (other.id != id) other,
      restored,
    ]);
    notifyListeners();
    return restored;
  }

  /// Rewrites `moru.js` of an app installed by an older Moru, so it gets the
  /// current bridge without being republished.
  Future<void> refreshBridge(MiniApp app) async {
    final file = File(p.join(app.codeDirectory, bridgeFile));
    if (await file.exists() && await file.readAsString() == moruBridgeScript) {
      return;
    }
    await file.writeAsString(moruBridgeScript);
  }

  /// Writes are queued per app so two quick saves cannot overwrite each other.
  Future<void> _update(String id, void Function(Map<String, dynamic>) change) {
    final app = _require(id);
    return _queued(id, () async {
      final data = await _readData(app);
      change(data);
      final encoded = jsonEncode(data);
      if (utf8.encode(encoded).length > maxDataBytes) {
        throw const MiniAppException(
          'storage_full',
          'App data may not exceed 5 MB.',
        );
      }
      await _writeAtomically(File(p.join(app.directory, 'data.json')), encoded);
    });
  }

  Future<T> _queued<T>(String key, Future<T> Function() action) {
    final previous = _writes[key] ?? Future<void>.value();
    final next = previous.catchError((_) {}).then((_) => action());
    // What waits on the queue only needs it done; the caller gets the error.
    _writes[key] = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  static Future<void> _writeAtomically(File file, String text) async {
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(text, flush: true);
    await temp.rename(file.path);
  }

  MiniApp _require(String id) {
    final app = byId(id);
    if (app == null) {
      throw MiniAppException('not_found', 'No mini app "$id".');
    }
    return app;
  }

  static List<MiniApp> _sorted(List<MiniApp> apps) =>
      apps..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  static const int maxHosts = 20;
  static const Set<String> knownPermissions = {'calendar'};
  static final RegExp _hostPattern = RegExp(
    r'^(\*\.)?([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$',
  );

  static List<String> _hosts(Object? raw) {
    if (raw == null) return const [];
    if (raw is! List || raw.length > maxHosts) {
      throw const MiniAppException(
        'invalid_network',
        '"network" must be a list of at most $maxHosts host names.',
      );
    }
    final hosts = <String>{};
    for (final item in raw) {
      final host = '$item'.trim().toLowerCase();
      if (!_hostPattern.hasMatch(host)) {
        throw MiniAppException(
          'invalid_network',
          '"$item" is not a host name. Use e.g. "api.example.com" or '
              '"*.example.com", without scheme, port or path.',
        );
      }
      hosts.add(host);
    }
    return hosts.toList();
  }

  static const int maxServerCommandLength = 500;

  static String? _serverCommand(Object? raw) {
    if (raw == null) return null;
    final command = raw is Map ? raw['command'] : null;
    if (command is! String ||
        command.trim().isEmpty ||
        command.length > maxServerCommandLength ||
        command.contains('\u0000')) {
      throw const MiniAppException(
        'invalid_server',
        '"server" must be {"command": "..."} with a shell command of at most '
            '$maxServerCommandLength characters.',
      );
    }
    return command.trim();
  }

  static Set<String> _permissions(Object? raw) {
    if (raw == null) return const {};
    final names = raw is List ? raw.map((e) => '$e'.trim()).toSet() : null;
    if (names == null || !names.every(knownPermissions.contains)) {
      throw MiniAppException(
        'invalid_permissions',
        '"permissions" must be a list of: ${knownPermissions.join(', ')}.',
      );
    }
    return names;
  }

  /// Whether `moru.fetch` from [app] may reach [host].
  static bool allowsHost(MiniApp app, String host) {
    final name = host.toLowerCase();
    return app.network.any(
      (allowed) => allowed.startsWith('*.')
          ? name.endsWith(allowed.substring(1)) || name == allowed.substring(2)
          : name == allowed,
    );
  }

  static String _limited(String text, int max) =>
      text.length <= max ? text : text.substring(0, max);

  static bool _isHtml(String path) =>
      const {'.html', '.htm'}.contains(p.extension(path).toLowerCase());

  /// A safe relative path from the manifest, or [fallback] when absent.
  static String? _relative(Object? raw, {required String? fallback}) {
    if (raw != null && raw is! String) {
      throw const MiniAppException('invalid_path', 'A path must be a string.');
    }
    final value = raw == null ? '' : '$raw'.trim();
    if (value.isEmpty) return fallback;
    final normalized = p.posix.normalize(value.replaceAll(r'\', '/'));
    if (p.posix.isAbsolute(normalized) ||
        normalized == '..' ||
        normalized.startsWith('../')) {
      throw MiniAppException('invalid_path', '"$value" leaves the app folder.');
    }
    return normalized;
  }

  static Future<List<({File file, String relative, int size})>> _collect(
    Directory sourceDir, {
    WorkspaceFileAccess? access,
  }) async {
    access ??= WorkspaceFileAccess(roots: [sourceDir.path]);
    final checked = access;
    await checked.resolve(sourceDir.path);
    final files = <({File file, String relative, int size})>[];
    var bytes = 0;
    Future<void> walk(Directory dir) async {
      await checked.withDirectory(dir.path, (anchored) async {
        await for (final child in Directory(
          anchored,
        ).list(followLinks: false)) {
          final entry = child is Directory
              ? Directory(p.join(dir.path, p.basename(child.path)))
              : child is File
              ? File(p.join(dir.path, p.basename(child.path)))
              : child;
          final name = p.basename(entry.path);
          if (name.startsWith('.')) continue;
          if (entry is Directory) {
            if (!skippedDirectories.contains(name)) await walk(entry);
            continue;
          }
          if (entry is! File) continue;
          final relative = p.posix.joinAll(
            p.split(p.relative(entry.path, from: sourceDir.path)),
          );
          if (relative == manifestFile || relative == bridgeFile) continue;
          final size = (await checked.stat(child.path)).size;
          bytes += size;
          files.add((file: entry, relative: relative, size: size));
          if (files.length > maxFiles) {
            throw const MiniAppException(
              'too_many_files',
              'A mini app may have at most $maxFiles files.',
            );
          }
          if (bytes > maxBytes) {
            throw const MiniAppException(
              'too_large',
              'A mini app may be at most 20 MB.',
            );
          }
        }
      });
    }

    await walk(sourceDir);
    return files;
  }

  static Future<WorkspaceFileHandle> _openSource(
    File file,
    WorkspaceFileAccess access,
    WorkspaceFileAccess? grant,
  ) async {
    // The selected folder and the model's original grant must both contain
    // the actual descriptor, including after an ancestor is replaced.
    await access.resolve(file.path);
    final opened = await (grant ?? access).openRead(file.path);
    try {
      await access.resolve(opened.path);
      return opened;
    } catch (_) {
      await opened.close();
      rethrow;
    }
  }

  static Future<int> _copySource(
    File source,
    File target,
    WorkspaceFileAccess access,
    WorkspaceFileAccess? grant,
    int limit,
  ) async {
    final opened = await _openSource(source, access, grant);
    RandomAccessFile? output;
    try {
      if (await opened.handle.length() > limit) {
        throw const MiniAppException(
          'too_large',
          'A mini app may be at most 20 MB.',
        );
      }
      output = await target.open(mode: FileMode.write);
      var bytes = 0;
      while (true) {
        final chunk = await opened.handle.read(
          (limit - bytes + 1).clamp(1, 64 * 1024),
        );
        if (chunk.isEmpty) return bytes;
        bytes += chunk.length;
        if (bytes > limit) {
          throw const MiniAppException(
            'too_large',
            'A mini app may be at most 20 MB.',
          );
        }
        await output.writeFrom(chunk);
      }
    } finally {
      await output?.close();
      await opened.close();
    }
  }

  /// [html] with the bridge script loaded before any app script, unless the
  /// page already includes it.
  static String withBridgeScript(String html, String entry) {
    if (html.contains(bridgeFile)) return html;
    final depth = p.posix.split(entry).length - 1;
    final src = '${'../' * depth}$bridgeFile';
    final tag = '<script src="$src"></script>';
    final head = RegExp(r'<head[^>]*>', caseSensitive: false).firstMatch(html);
    if (head != null) {
      return html.replaceRange(head.end, head.end, tag);
    }
    return '$tag$html';
  }

  /// `window.moru` for the page. Calls go through the `MoruBridge` channel
  /// as `{id, method, args}` and resolve when Moru calls `__moruReply`.
  static const String moruBridgeScript = r'''
(function () {
  if (window.moru) return;
  var assetCatalog = window.__moruAssetCatalog || {};
  var bridgeScript = document.currentScript && document.currentScript.src;
  var assetBase = bridgeScript ? new URL('__moru_assets/', bridgeScript).href : null;
  var assetLoads = {};
  function assetUrl(name) {
    var asset = assetCatalog[name];
    if (!asset || !assetBase) throw new Error('Unknown bundled Moru asset: ' + name);
    return new URL(asset.file, assetBase).href;
  }
  function loadAsset(name) {
    if (assetLoads[name]) return assetLoads[name];
    var asset = assetCatalog[name];
    if (!asset || !/\.(js|css)$/.test(asset.file)) {
      return Promise.reject(new Error('Use moru.assets.url for a binary asset: ' + name));
    }
    var promise = Promise.all((asset.dependencies || []).map(loadAsset)).then(function () {
      return new Promise(function (resolve, reject) {
        var css = /\.css$/.test(asset.file);
        var tag = document.createElement(css ? 'link' : 'script');
        if (css) { tag.rel = 'stylesheet'; tag.href = assetUrl(name); }
        else { tag.src = assetUrl(name); }
        tag.onload = function () { resolve(); };
        tag.onerror = function () { reject(new Error('Failed to load Moru asset: ' + name)); };
        document.head.appendChild(tag);
      });
    });
    assetLoads[name] = promise.catch(function (error) { delete assetLoads[name]; throw error; });
    return assetLoads[name];
  }
  var pending = {};
  var next = 0;
  // Problems go to Moru, which shows them to the agent after publishing.
  function report(kind, message) {
    try {
      MoruBridge.postMessage(JSON.stringify({
        method: '__report', args: { kind: kind, message: String(message).slice(0, 500) }
      }));
    } catch (e) {}
  }
  window.addEventListener('error', function (e) {
    var target = e.target;
    if (target && target !== window && (target.src || target.href)) {
      report('resource', 'Failed to load ' + (target.src || target.href).split('/app/').pop());
    } else {
      var where = e.filename ? ' (' + e.filename.split('/app/').pop() + ':' + e.lineno + ')' : '';
      report('error', (e.message || 'Script error') + where);
    }
  }, true);
  window.addEventListener('unhandledrejection', function (e) {
    var reason = e.reason;
    report('promise', reason && reason.message ? reason.message : String(reason));
  });
  function call(method, args) {
    return new Promise(function (resolve, reject) {
      var id = ++next;
      pending[id] = { resolve: resolve, reject: reject };
      MoruBridge.postMessage(JSON.stringify({ id: id, method: method, args: args || {} }));
    });
  }
  window.__moruReply = function (id, ok, value) {
    var request = pending[id];
    if (!request) return;
    delete pending[id];
    if (ok) request.resolve(value);
    else request.reject(new Error(value));
  };
  window.__moruChanged = function (key) {
    window.dispatchEvent(new CustomEvent('moru:storage', { detail: { key: key } }));
  };
  window.moru = {
    assets: { url: assetUrl, load: loadAsset },
    theme: window.__moruTheme || {
      dark: !!(window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches),
      colors: window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches ? {
        bg: '#1a1b21', surface: '#25262d', text: '#f1f0f7', muted: '#c6c6d0',
        accent: '#b6c4ff', 'on-accent': '#1d2d61', border: '#45464f'
      } : {
        bg: '#fefbff', surface: '#ffffff', text: '#1a1b21', muted: '#45464f',
        accent: '#4d5c92', 'on-accent': '#ffffff', border: '#c6c6d0'
      },
      insets: { top: 0, right: 0, bottom: 0, left: 0 }
    },
    storage: {
      get: function (key) { return call('storage.get', { key: key }); },
      set: function (key, value) { return call('storage.set', { key: key, value: value }); },
      remove: function (key) { return call('storage.remove', { key: key }); },
      keys: function () { return call('storage.keys'); }
    },
    ai: {
      ask: function (prompt, options) {
        return call('ai.ask', { prompt: prompt, system: (options || {}).system });
      }
    },
    notify: function (title, body) {
      return call('notify', { title: title, body: body });
    },
    reminders: {
      set: function (id, reminder) { return call('reminders.set', { id: id, reminder: reminder }); },
      remove: function (id) { return call('reminders.remove', { id: id }); },
      list: function () { return call('reminders.list'); }
    },
    jobs: {
      set: function (id, job) { return call('jobs.set', { id: id, job: job }); },
      remove: function (id) { return call('jobs.remove', { id: id }); },
      list: function () { return call('jobs.list'); }
    },
    fetch: function (url, options) {
      options = options || {};
      return call('fetch', {
        url: url, method: options.method, headers: options.headers, body: options.body
      }).then(function (response) {
        response.json = function () { return JSON.parse(response.body); };
        response.text = function () { return response.body; };
        return response;
      });
    },
    server: {
      fetch: function (path, options) {
        options = options || {};
        return call('server.fetch', {
          path: path, method: options.method, headers: options.headers, body: options.body
        }).then(function (response) {
          response.json = function () { return JSON.parse(response.body); };
          response.text = function () { return response.body; };
          return response;
        });
      },
      url: function (path) { return call('server.url', { path: path || '/' }); }
    },
    calendar: {
      list: function (query) { return call('calendar.list', query); },
      add: function (event) { return call('calendar.add', event); }
    },
    vibrate: function (pattern) { return call('vibrate', { pattern: pattern }); },
    haptic: function (kind) { return call('haptic', { kind: kind }); },
    app: {
      info: function () { return call('app.info'); },
      close: function () { return call('app.close'); }
    }
  };
})();
''';
}
