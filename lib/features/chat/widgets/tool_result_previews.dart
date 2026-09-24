import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/services/search/search_tool_service.dart';
import '../../../icons/lucide_adapter.dart';
import '../../home/services/local_tools_service.dart';

/// Tidy previews for tools whose raw result is JSON: web search shows its
/// sources, the shared browser its action and page. Null for any other tool,
/// or when the result cannot be read, so the plain text summary stays.
Widget? structuredToolPreview({
  required String toolName,
  required Map<String, dynamic> arguments,
  required String? content,
  required Color textColor,
  required Color mutedColor,
  required Color errorColor,
}) {
  final result = _decode(content);
  switch (toolName) {
    case SearchToolService.toolName:
      if (result == null) return null;
      return _SearchPreview(
        result: result,
        textColor: textColor,
        mutedColor: mutedColor,
        errorColor: errorColor,
      );
    case LocalToolNames.browserUse:
      return _BrowserPreview(
        arguments: arguments,
        result: result,
        textColor: textColor,
        mutedColor: mutedColor,
        errorColor: errorColor,
      );
    default:
      return null;
  }
}

Map<String, dynamic>? _decode(String? content) {
  if (content == null || content.trim().isEmpty) return null;
  try {
    final decoded = jsonDecode(content);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  } catch (_) {
    return null;
  }
}

String _host(String url) {
  final uri = Uri.tryParse(url);
  final host = uri?.host ?? '';
  return host.startsWith('www.') ? host.substring(4) : host;
}

class _SearchPreview extends StatelessWidget {
  const _SearchPreview({
    required this.result,
    required this.textColor,
    required this.mutedColor,
    required this.errorColor,
  });

  static const int _shown = 3;

  final Map<String, dynamic> result;
  final Color textColor;
  final Color mutedColor;
  final Color errorColor;

  @override
  Widget build(BuildContext context) {
    final error = result['error'];
    if (error != null) {
      return Text(
        error.toString(),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: errorColor),
      );
    }
    final items = [
      for (final item in (result['items'] as List? ?? const []))
        if (item is Map) item,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final item in items.take(_shown))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Icon(Lucide.Globe, size: 12, color: mutedColor),
                const SizedBox(width: 6),
                Text(
                  _host((item['url'] ?? '').toString()),
                  style: TextStyle(fontSize: 11.5, color: mutedColor),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    (item['title'] ?? '').toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: textColor),
                  ),
                ),
              ],
            ),
          ),
        if (items.length > _shown)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '+${items.length - _shown}',
              style: TextStyle(fontSize: 11.5, color: mutedColor),
            ),
          ),
      ],
    );
  }
}

class _BrowserPreview extends StatelessWidget {
  const _BrowserPreview({
    required this.arguments,
    required this.result,
    required this.textColor,
    required this.mutedColor,
    required this.errorColor,
  });

  final Map<String, dynamic> arguments;
  final Map<String, dynamic>? result;
  final Color textColor;
  final Color mutedColor;
  final Color errorColor;

  @override
  Widget build(BuildContext context) {
    final action = (arguments['action'] ?? '').toString();
    final url = (result?['url'] ?? arguments['url'] ?? '').toString();
    final failed = result != null && result!['ok'] == false;
    final message = failed
        ? (result!['message'] ?? result!['error'] ?? '').toString()
        : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (action.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: mutedColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  action,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: textColor,
                  ),
                ),
              ),
            if (url.isNotEmpty)
              Expanded(
                child: Text(
                  url.replaceFirst(RegExp(r'^https?://(www\.)?'), ''),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: mutedColor),
                ),
              ),
          ],
        ),
        if (message.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: errorColor),
            ),
          ),
      ],
    );
  }
}
