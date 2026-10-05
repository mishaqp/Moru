import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'acp_mcp_server.dart';

/// Correlation-only data captured before ACP display redaction. Arguments are
/// represented by a nonreversible digest; raw maps never reach UI callbacks.
class AcpToolCorrelation {
  const AcpToolCorrelation._({
    required this.id,
    this.name,
    this._toolNameCandidates = const [],
    this.argumentsDigest,
    this.status,
  });

  final String id;
  final String? name;

  /// Unredacted machine names retained only until the binding can check its
  /// live app registry. Capturing a candidate does not authorize that tool.
  final List<String> _toolNameCandidates;
  final String? argumentsDigest;
  final String? status;

  String? resolveToolName({Set<String> miniAppActionNames = const {}}) =>
      _toolNameCandidates
          .where(
            (candidate) =>
                AcpMcpServer.allowedNames.contains(candidate) ||
                (candidate.startsWith('ma_') &&
                    miniAppActionNames.contains(candidate)),
          )
          .firstOrNull;

  static AcpToolCorrelation? fromUpdate(Map update) {
    final id = update['toolCallId'];
    if (id is! String) return null;
    final raw = update['rawInput'];
    final arguments = raw is Map && raw['server'] == 'moru'
        ? raw['arguments']
        : raw;
    final status = update['status'];
    final candidates = _toolNames(update);
    return AcpToolCorrelation._(
      id: id,
      name: candidates.where(AcpMcpServer.allowedNames.contains).firstOrNull,
      toolNameCandidates: candidates,
      argumentsDigest: update.containsKey('rawInput')
          ? digest(arguments)
          : null,
      status:
          const {
            'pending',
            'in_progress',
            'completed',
            'failed',
            'cancelled',
          }.contains(status)
          ? status as String
          : null,
    );
  }

  static List<String> _toolNames(Map update) {
    final names = <String>[];
    final raw = update['rawInput'];
    if (raw is Map && raw['server'] == 'moru' && raw['tool'] is String) {
      names.add(raw['tool'] as String);
    }
    final meta = update['_meta'];
    final claude = meta is Map ? meta['claudeCode'] : null;
    for (final candidate in [
      update['name'],
      update['title'],
      if (claude is Map) claude['toolName'],
    ]) {
      if (candidate is! String) continue;
      for (final prefix in ['mcp__moru__', 'moru_', 'Tool: moru/']) {
        if (candidate.startsWith(prefix)) {
          names.add(candidate.substring(prefix.length));
          break;
        }
      }
    }
    return List.unmodifiable(names);
  }

  static String digest(Object? input) {
    Object? sorted(Object? value) {
      if (value is Map) {
        final keys = value.keys.cast<String>().toList()..sort();
        return {for (final key in keys) key: sorted(value[key])};
      }
      if (value is List) return value.map(sorted).toList();
      return value;
    }

    return sha256.convert(utf8.encode(jsonEncode(sorted(input)))).toString();
  }
}
