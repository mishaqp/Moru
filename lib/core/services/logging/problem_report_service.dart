import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../providers/environment_provider.dart';
import '../../providers/settings_provider.dart';
import '../../../utils/app_directories.dart';
import '../acp/acp_secret_redactor.dart';
import '../workspace/workspace_file_access.dart';
import 'flutter_logger.dart';
import 'log_redactor.dart';

/// Private, short-lived diagnostic exports. No chat/database/request-log reads.
class ProblemReportService {
  ProblemReportService({
    Future<Directory> Function()? supportDirectory,
    Future<Directory> Function()? cacheDirectory,
    Future<Map<String, Object?>> Function()? appInfo,
    Future<Map<String, Object?>> Function()? deviceInfo,
  }) : _supportDirectory = supportDirectory ?? getApplicationSupportDirectory,
       _cacheDirectory =
           cacheDirectory ?? AppDirectories.getSystemCacheDirectory,
       _appInfo = appInfo ?? _loadAppInfo,
       _deviceInfo = deviceInfo ?? _loadDeviceInfo;

  static const maxZipBytes = 256 * 1024;
  static const lifetime = Duration(days: 1);
  static final _reportName = RegExp(r'^moru-problem-[0-9a-f-]{36}\.zip$');
  static bool isReportName(String name) => _reportName.hasMatch(name);
  final Future<Directory> Function() _supportDirectory;
  final Future<Directory> Function() _cacheDirectory;
  final Future<Map<String, Object?>> Function() _appInfo;
  final Future<Map<String, Object?>> Function() _deviceInfo;

  static Future<Map<String, Object?>> _loadAppInfo() async {
    final info = await PackageInfo.fromPlatform();
    return {'version': info.version, 'build': info.buildNumber};
  }

  static Future<Map<String, Object?>> _loadDeviceInfo() async =>
      await const MethodChannel(
        'app.device_tools',
      ).invokeMapMethod<String, Object?>('problemReportDeviceInfo') ??
      const {};

  Future<Directory> _directory() async {
    final support = await _supportDirectory();
    await support.create(recursive: true);
    final root = p.join(support.path, 'problem-reports');
    await WorkspaceFileAccess(roots: [support.path]).createDirectory(root);
    return Directory(root);
  }

  static Map<String, Object?> _settings(SettingsProvider settings) => {
    'theme': settings.themeMode.name,
    'locale': settings.effectiveLocale.toLanguageTag(),
    'chatFontScale': settings.chatFontScale,
    'showToolCards': settings.showToolCards,
    'showToolResultSummary': settings.showToolResultSummary,
    'enableMathRendering': settings.enableMathRendering,
    'enableAssistantMarkdown': settings.enableAssistantMarkdown,
    'browserFloatingWindow': settings.browserFloatingWindow,
    'toolAutoApproveAll': settings.toolAutoApproveAll,
    'requestLogEnabled': settings.requestLogEnabled,
    'contextLogEnabled': settings.contextLogEnabled,
    'flutterLogEnabled': settings.flutterLogEnabled,
    'logSaveOutput': settings.logSaveOutput,
    'logElideLargePayloads': settings.logElideLargePayloads,
    'logAutoDeleteDays': settings.logAutoDeleteDays,
    'logMaxSizeMB': settings.logMaxSizeMB,
    'providerCount': settings.providerConfigs.length,
    'providers': [
      for (final provider in settings.providerConfigs.values.take(32))
        {
          'type': provider.providerType?.name ?? 'auto',
          'enabled': provider.enabled,
          'oauth': provider.isOAuth,
          'responsesApi': provider.useResponseApi == true,
          'proxyEnabled': provider.proxyEnabled == true,
          'modelCount': provider.models.length,
        },
    ],
  };

  static Iterable<String> _secrets(
    SettingsProvider settings,
    EnvironmentProvider? environment,
  ) sync* {
    yield settings.globalProxyPassword;
    yield settings.miniAppWebPassword;
    for (final provider in settings.providerConfigs.values) {
      yield provider.apiKey;
      yield provider.proxyPassword ?? '';
      yield provider.oauthCredentials?.accessToken ?? '';
      yield provider.oauthCredentials?.refreshToken ?? '';
      for (final key in provider.apiKeys ?? []) {
        yield key.key;
      }
      for (final header in provider.customHeaders) {
        yield header['value'] ?? '';
      }
    }
    for (final variable in environment?.variables ?? []) {
      yield variable.value;
    }
    for (final service in settings.searchServices) {
      yield service.primaryApiKey;
      yield* service.extraApiKeys;
    }
  }

  Future<Map<String, Object?>> create({
    required SettingsProvider settings,
    EnvironmentProvider? environment,
    void Function()? checkCancelled,
  }) async {
    await cleanup();
    // Device identity is limited to Android release/SDK, manufacturer and model.
    // Never serialize the entire platform response or the settings provider.
    final app = await _appInfo();
    final device = await _deviceInfo();
    checkCancelled?.call();
    final known = AcpSecretRedactor(
      _secrets(settings, environment),
      protectAuthentication: true,
    );
    String safeText(String value) =>
        LogRedactor.redactDiagnosticText(known.text(value));
    Object? safeValue(Object? value) => switch (value) {
      String() => _head(safeText(value), 1024),
      Map() => {
        for (final entry in value.entries)
          entry.key.toString(): safeValue(entry.value),
      },
      List() => value.map(safeValue).toList(),
      _ => value,
    };
    final safeApp = safeValue({
      for (final key in ['version', 'build']) key: app[key],
    });
    final safeDevice = safeValue({
      for (final key in ['android', 'sdk', 'manufacturer', 'model'])
        key: device[key],
    });
    final mode = environment?.rootChroot == true ? 'root' : 'PRoot';
    final log = _tail(
      safeText(FlutterLogger.technicalTail),
      FlutterLogger.technicalTailMaxBytes,
    );
    final logBytes = utf8.encode(log);
    final metadata = {
      'format': 1,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'app': safeApp,
      'device': safeDevice,
      'environment': {'mode': mode, 'privacyMode': environment?.privacyMode},
      'settings': safeValue(_settings(settings)),
      'journal': {
        'scope': 'current_app_run',
        'bytes': logBytes.length,
        'limit_bytes': FlutterLogger.technicalTailMaxBytes,
        'contents':
            'Technical event names, error types and package stack frames. No messages or request/context logs.',
      },
    };
    final metadataBytes = utf8.encode(
      const JsonEncoder.withIndent('  ').convert(metadata),
    );
    if (metadataBytes.length > 32 * 1024) {
      throw StateError('Report metadata exceeds limit');
    }
    final archive = Archive()
      ..addFile(ArchiveFile('report.json', metadataBytes.length, metadataBytes))
      ..addFile(ArchiveFile('events.txt', logBytes.length, logBytes));
    final bytes = ZipEncoder().encode(archive);
    if (bytes.length > maxZipBytes) {
      throw StateError('Report exceeds limit');
    }
    checkCancelled?.call();
    final directory = await _directory();
    final name = 'moru-problem-${const Uuid().v4()}.zip';
    final path = p.join(directory.path, name);
    final access = WorkspaceFileAccess(roots: [directory.path]);
    try {
      await _write(access, path, bytes);
      checkCancelled?.call();
    } catch (_) {
      await access.withParent(path, (anchored) async {
        if (await File(anchored).exists()) await File(anchored).delete();
      });
      rethrow;
    }
    return {
      'ok': true,
      'name': name,
      'path': path,
      'size_bytes': bytes.length,
      'included': [
        'app version/build',
        'Android/device model',
        'PRoot/root mode',
        'allowlisted settings without secrets',
        'technical journal tail (up to 128 KiB)',
      ],
      'expires_at': DateTime.now().toUtc().add(lifetime).toIso8601String(),
      'summary': {
        'app': safeApp,
        'device': safeDevice,
        'environment': mode,
        'recent_events': FlutterLogger.technicalSummary
            .map((event) => _head(safeText(event), 256))
            .toList(),
      },
    };
  }

  static String _head(String value, int limit) =>
      value.length <= limit ? value : '${value.substring(0, limit)}…';

  static String _tail(String value, int maxBytes) {
    final bytes = utf8.encode(value);
    if (bytes.length <= maxBytes) return value;
    var start = bytes.length - maxBytes;
    // Drop a whole partial line, including any incomplete UTF-8 character.
    while (start < bytes.length && bytes[start] != 10) {
      start++;
    }
    return start == bytes.length ? '' : utf8.decode(bytes.sublist(start + 1));
  }

  static Future<void> _write(
    WorkspaceFileAccess access,
    String path,
    List<int> bytes,
  ) async {
    final output = await access.openWrite(path);
    try {
      await output.handle.writeFrom(bytes);
      await output.handle.flush();
    } finally {
      await output.close();
    }
  }

  Future<WorkspaceFileHandle> _open(String name) async {
    if (!_reportName.hasMatch(name)) throw ArgumentError('Invalid report name');
    final directory = await _directory();
    final path = p.join(directory.path, name);
    final access = WorkspaceFileAccess(roots: [directory.path]);
    final opened = await access.openRead(path);
    try {
      final stat = await File(opened.path).stat();
      if (stat.modified.isBefore(DateTime.now().subtract(lifetime))) {
        await access.withParent(path, (anchored) => File(anchored).delete());
        throw StateError('Report expired');
      }
      if (await opened.handle.length() > maxZipBytes) {
        throw StateError('Report exceeds limit');
      }
      return opened;
    } catch (_) {
      await opened.close();
      rethrow;
    }
  }

  Future<List<int>> readReport(String name) async {
    final opened = await _open(name);
    try {
      return await opened.readBytes(maxBytes: maxZipBytes);
    } finally {
      await opened.close();
    }
  }

  /// Share only a private snapshot copied from the checked, still-open source.
  Future<void> withShareSnapshot(
    String name,
    Future<void> Function(File) share,
  ) async {
    final opened = await _open(name);
    final directory = await _directory();
    final access = WorkspaceFileAccess(roots: [directory.path]);
    String? temporaryPath;
    try {
      final temporaryName = await access.withDirectory(
        directory.path,
        (anchored) async =>
            p.basename((await Directory(anchored).createTemp('share-')).path),
      );
      temporaryPath = p.join(directory.path, temporaryName);
      final snapshot = p.join(temporaryPath, name);
      await _write(
        access,
        snapshot,
        await opened.readBytes(maxBytes: maxZipBytes),
      );
      await share(File(snapshot));
    } finally {
      await opened.close();
      if (temporaryPath != null) {
        await access.withParent(
          temporaryPath,
          (anchored) => Directory(anchored).delete(recursive: true),
        );
      }
    }
  }

  /// Startup removes every owned export; later use also expires day-old files.
  /// share_plus's Android FileProvider copies are private cache files too.
  Future<void> cleanup({bool all = false}) async {
    final directory = await _directory();
    await _cleanupDirectory(directory, all: all, snapshots: true);
    final cache = await _cacheDirectory();
    final shares = Directory(p.join(cache.path, 'share_plus'));
    if (await shares.exists()) await _cleanupDirectory(shares, all: all);
  }

  Future<void> _cleanupDirectory(
    Directory directory, {
    required bool all,
    bool snapshots = false,
  }) async {
    final access = WorkspaceFileAccess(roots: [directory.path]);
    final cutoff = DateTime.now().subtract(lifetime);
    await access.withDirectory(directory.path, (anchored) async {
      await for (final entry in Directory(anchored).list(followLinks: false)) {
        final name = p.basename(entry.path);
        if (!_reportName.hasMatch(name) &&
            !(snapshots && name.startsWith('share-'))) {
          continue;
        }
        if (!all && !(await entry.stat()).modified.isBefore(cutoff)) continue;
        final path = p.join(directory.path, name);
        await access.withParent(path, (child) async {
          final type = await FileSystemEntity.type(child, followLinks: false);
          if (type == FileSystemEntityType.directory) {
            await Directory(child).delete(recursive: true);
          } else if (type == FileSystemEntityType.link) {
            await Link(child).delete();
          } else if (type == FileSystemEntityType.file) {
            await File(child).delete();
          }
        }, followFinalLink: false);
      }
    });
  }
}
