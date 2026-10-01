import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'acp_mcp_server.dart';

/// Correlation-only data captured before ACP display redaction. Arguments are
/// represented by a nonreversible digest; raw maps never reach UI callbacks.
class AcpToolCorrelation {
  const AcpToolCorrelation._({
    required this.id,
    this.name,
    this.argumentsDigest,
    this.status,
  });

  final String id;
  final String? name;
  final String? argumentsDigest;
  final String? status;

  static AcpToolCorrelation? fromUpdate(Map update) {
    final id = update['toolCallId'];
    if (id is! String) return null;
    final raw = update['rawInput'];
    final arguments = raw is Map && raw['server'] == 'moru'
        ? raw['arguments']
        : raw;
    final status = update['status'];
    return AcpToolCorrelation._(
      id: id,
      name: _toolName(update),
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

  static String? _toolName(Map update) {
    final raw = update['rawInput'];
    if (raw is Map &&
        raw['server'] == 'moru' &&
        AcpMcpServer.allowedNames.contains(raw['tool'])) {
      return raw['tool'] as String;
    }
    final meta = update['_meta'];
    final claude = meta is Map ? meta['claudeCode'] : null;
    for (final candidate in [
      update['name'],
      update['title'],
      if (claude is Map) claude['toolName'],
    ]) {
      for (final name in AcpMcpServer.allowedNames) {
        if (candidate == 'mcp__moru__$name' ||
            candidate == 'moru_$name' ||
            candidate == 'Tool: moru/$name') {
          return name;
        }
      }
    }
    return null;
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
