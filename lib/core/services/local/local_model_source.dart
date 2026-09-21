import 'dart:convert';
import 'package:http/http.dart' as http;
import 'local_model_catalog.dart';

class LiteRtModelSourceException implements Exception {
  const LiteRtModelSourceException(this.code);
  final String code;
}

/// Pins Hugging Face links to an immutable revision with a verified LFS digest.
class LiteRtModelSource {
  LiteRtModelSource({http.Client? client}) : _client = client ?? http.Client(), _ownsClient = client == null;
  final http.Client _client;
  final bool _ownsClient;
  void dispose() { if (_ownsClient) _client.close(); }

  Future<LiteRtCatalogEntry> resolve(String url) async {
    final uri = Uri.tryParse(url.trim());
    final parts = uri?.pathSegments ?? const <String>[];
    if (uri == null || uri.scheme != 'https' || uri.host != 'huggingface.co' || uri.userInfo.isNotEmpty || uri.hasPort || parts.length < 5 || !{'blob', 'resolve'}.contains(parts[2]) || parts.any((p) => p.isEmpty || p == '.' || p == '..' || p.contains('\\')) || !parts.last.toLowerCase().endsWith('.litertlm')) {
      throw const FormatException('Expected an HTTPS Hugging Face .litertlm file link');
    }
    final repo = parts.take(2).join('/');
    final file = parts.skip(4).join('/');
    final api = Uri(scheme: 'https', host: 'huggingface.co', pathSegments: ['api', 'models', ...parts.take(2), 'revision', parts[3]], queryParameters: {'blobs': 'true'});
    final response = await _client.get(api).timeout(const Duration(seconds: 30));
    if (response.statusCode == 401 || response.statusCode == 403) throw const LiteRtModelSourceException('access');
    if (response.statusCode != 200) throw const LiteRtModelSourceException('metadata');
    final dynamic decoded = jsonDecode(response.body);
    if (decoded is! Map) throw const LiteRtModelSourceException('metadata');
    final commit = decoded['sha']?.toString() ?? '';
    if (!RegExp(r'^[a-fA-F0-9]{40}$').hasMatch(commit)) throw const LiteRtModelSourceException('metadata');
    final siblings = decoded['siblings'];
    if (siblings is! List) throw const LiteRtModelSourceException('metadata');
    for (final item in siblings) {
      if (item is! Map || item['rfilename'] != file) continue;
      final lfs = item['lfs'];
      if (lfs is! Map) break;
      final hash = lfs['sha256']?.toString() ?? '';
      final size = lfs['size'];
      if (!RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(hash) || size is! int || size <= 8) break;
      return LiteRtCatalogEntry(id: '$repo/$file@$commit', displayName: parts.last.substring(0, parts.last.length - 9), fileName: parts.last, sizeBytes: size, license: (decoded['cardData'] is Map ? decoded['cardData']['license'] : null)?.toString() ?? '—', contextTokens: 0, repoUrl: Uri.https('huggingface.co', repo), downloadUrl: Uri(scheme: 'https', host: 'huggingface.co', pathSegments: [...parts.take(2), 'resolve', commit, ...parts.skip(4)]), sha256: hash.toLowerCase());
    }
    throw const LiteRtModelSourceException('metadata');
  }
}
