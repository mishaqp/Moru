import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import 'mini_app_store.dart';

/// Private upgrade bookkeeping, outside versioned app code. The old address
/// is captured before an update can change the entry path. Fresh apps must
/// never read the shared legacy file origin.
class MiniAppBrowserStorageState {
  MiniAppBrowserStorageState._(
    this.app,
    this.legacyUrl,
    this.complete,
    this.originId,
  );

  final MiniApp app;
  final String? legacyUrl;
  final bool complete;
  final String originId;
  static const fileName = '.browser-storage.json';
  Uri get origin =>
      Uri(scheme: 'https', host: 'moru-miniapp-$originId.invalid');

  static String _newOriginId() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  static Future<void> registerLegacy(MiniApp app) async {
    if (await File(p.join(app.directory, fileName)).exists()) return;
    await MiniAppBrowserStorageState._(
      app,
      Uri.file(app.entryPath).toString(),
      false,
      _newOriginId(),
    )._write(false);
  }

  static Future<void> registerFresh(MiniApp app) =>
      MiniAppBrowserStorageState._(
        app,
        null,
        true,
        _newOriginId(),
      )._write(true);

  static Future<MiniAppBrowserStorageState> read(MiniApp app) async {
    final raw = jsonDecode(
      await File(p.join(app.directory, fileName)).readAsString(),
    );
    if (raw is! Map ||
        raw['version'] != 1 ||
        raw['complete'] is! bool ||
        raw['originId'] is! String ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(raw['originId'] as String) ||
        (raw['legacyUrl'] != null && raw['legacyUrl'] is! String)) {
      throw const FormatException('Invalid browser storage migration state.');
    }
    return MiniAppBrowserStorageState._(
      app,
      raw['legacyUrl'] as String?,
      raw['complete'] as bool,
      raw['originId'] as String,
    );
  }

  Future<void> markComplete() => _write(true);

  Future<void> _write(bool done) async {
    final destination = File(p.join(app.directory, fileName));
    await destination.parent.create(recursive: true);
    final staging = File('${destination.path}.tmp');
    await staging.writeAsString(
      jsonEncode({
        'version': 1,
        'legacyUrl': legacyUrl,
        'complete': done,
        'originId': originId,
      }),
      flush: true,
    );
    await staging.rename(destination.path);
  }
}
