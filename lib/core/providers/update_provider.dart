import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

class UpdateInfo {
  final String app;
  final String version;
  final int? build;
  final DateTime? releasedAt;
  final String? notes;
  final bool mandatory;
  final Map<String, String> downloads;

  const UpdateInfo({
    required this.app,
    required this.version,
    this.build,
    this.releasedAt,
    this.notes,
    this.mandatory = false,
    this.downloads = const {},
  });

  String? bestDownloadUrl() {
    if (Platform.isIOS) {
      return downloads['ios'] ??
          downloads['iosAppStore'] ??
          downloads['universal'];
    }
    if (Platform.isAndroid) {
      return downloads['android'] ?? downloads['universal'];
    }
    if (Platform.isMacOS) {
      return downloads['macos'] ??
          downloads['mac'] ??
          downloads['darwin'] ??
          downloads['universal'];
    }
    if (Platform.isWindows) {
      return downloads['windows'] ?? downloads['win'] ?? downloads['universal'];
    }
    if (Platform.isLinux) {
      return downloads['linux'] ?? downloads['universal'];
    }
    return downloads['universal'] ?? downloads['android'] ?? downloads['ios'];
  }

  /// Only completed, stable Moru releases with the exact arm64 asset qualify.
  /// Never fall back to an upstream feed or a different repository/ABI.
  static UpdateInfo? fromMoruRelease(Map<String, dynamic> json) {
    const repo = 'https://github.com/mishaqp/Moru';
    final tag = json['tag_name'];
    if (tag is! String ||
        !RegExp(r'^v[0-9]+\.[0-9]+\.[0-9]+$').hasMatch(tag) ||
        json['draft'] != false ||
        json['prerelease'] != false ||
        json['html_url'] != '$repo/releases/tag/$tag') {
      return null;
    }
    final assets = json['assets'];
    if (assets is! List) return null;
    final name = 'Moru-$tag-arm64-v8a-release.apk';
    final download = '$repo/releases/download/$tag/$name';
    final matches = assets.whereType<Map>().where(
      (asset) =>
          asset['name'] == name &&
          asset['state'] == 'uploaded' &&
          asset['size'] is num &&
          (asset['size'] as num) > 0 &&
          asset['browser_download_url'] == download,
    );
    if (matches.length != 1) return null;
    return UpdateInfo(
      app: 'Moru',
      version: tag.substring(1),
      releasedAt: DateTime.tryParse(json['published_at']?.toString() ?? ''),
      notes: json['body'] is String ? json['body'] as String : null,
      downloads: {'android': download},
    );
  }

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    final latest = (json['latest'] as Map?) ?? const {};
    final downloads =
        (latest['downloads'] as Map?)?.map(
          (k, v) => MapEntry(k.toString(), v.toString()),
        ) ??
        const {};
    DateTime? released;
    final releasedRaw = latest['releasedAt']?.toString();
    if (releasedRaw != null && releasedRaw.isNotEmpty) {
      try {
        released = DateTime.parse(releasedRaw);
      } catch (_) {}
    }
    return UpdateInfo(
      app: (json['app'] ?? '').toString(),
      version: (latest['version'] ?? '').toString(),
      build: int.tryParse((latest['build'] ?? '').toString()),
      releasedAt: released,
      notes: (latest['notes'] ?? '').toString(),
      mandatory: (latest['mandatory'] as bool?) ?? false,
      downloads: downloads,
    );
  }
}

class UpdateProvider extends ChangeNotifier {
  UpdateInfo? _available;
  UpdateInfo? get available => _available;
  bool _checking = false;
  bool get checking => _checking;
  String? _error;
  String? get error => _error;

  Future<void> checkForUpdates() async {
    if (_checking) return;
    _checking = true;
    _error = null;
    _available = null;
    notifyListeners();
    try {
      final url = Uri.https(
        'api.github.com',
        '/repos/mishaqp/Moru/releases/latest',
      );
      final resp = await http
          .get(
            url,
            headers: {
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'Moru',
            },
          )
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode == 404) return;
      if (resp.statusCode != 200) {
        throw Exception('HTTP ${resp.statusCode}');
      }
      final data =
          jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final info = UpdateInfo.fromMoruRelease(data);
      if (info == null) return;

      final pkg = await PackageInfo.fromPlatform();
      final currentVer = pkg.version; // e.g., 1.0.0

      // Compare by version only; ignore build numbers
      final hasNew = _isRemoteNewer(
        remoteVersion: info.version,
        currentVersion: currentVer,
      );
      _available = hasNew ? info : null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _checking = false;
      notifyListeners();
    }
  }

  bool _isRemoteNewer({
    required String remoteVersion,
    required String currentVersion,
  }) {
    // Compare semantic versions only (ignore internal build numbers)
    List<int> parseVer(String v) {
      final parts = v.split('.');
      final nums = <int>[];
      for (int i = 0; i < 3; i++) {
        nums.add(i < parts.length ? int.tryParse(parts[i]) ?? 0 : 0);
      }
      return nums;
    }

    final a = parseVer(remoteVersion);
    final b = parseVer(currentVersion);
    if (a[0] != b[0]) return a[0] > b[0];
    if (a[1] != b[1]) return a[1] > b[1];
    if (a[2] != b[2]) return a[2] > b[2];
    return false;
  }
}
