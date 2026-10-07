import 'dart:convert';
import 'dart:io';

import '../../../../utils/mcp_structured_image.dart';
import '../../../models/model_types.dart';
import '../../../providers/settings_provider.dart';
import '../chat_api_helpers.dart';

/// An image a client tool returned (a browser screenshot, an MCP image),
/// ready to send back to a model that takes image input.
typedef ToolResultImage = ({String mime, String base64});

extension ToolResultImageDataUrl on ToolResultImage {
  // `this.` because `base64` alone is dart:convert's codec.
  String get dataUrl => 'data:${this.mime};base64,${this.base64}';
}

/// Whether [modelId] of [config] reads images, so tool images go to it.
bool modelTakesImages(ProviderConfig config, String modelId) =>
    effectiveModelInfo(config, modelId).input.contains(Modality.image);

/// At most this many images of one tool result go to the model.
const int maxToolResultImages = 3;

/// Larger files are not sent: a screenshot is far smaller.
const int maxToolResultImageBytes = 5 * 1024 * 1024;

/// Loads the images listed in a tool result's `mcpResult` metadata: data
/// URLs as they are, local files read. Remote URLs, missing files and
/// oversized files are left out.
Future<List<ToolResultImage>> loadToolResultImages(
  Map<String, dynamic>? metadata,
) async {
  final uris = mcpResultImageUris(readMcpResultMetadata(metadata));
  final images = <ToolResultImage>[];
  for (final uri in uris) {
    if (images.length >= maxToolResultImages) break;
    final image = await _load(uri);
    if (image != null) images.add(image);
  }
  return images;
}

Future<ToolResultImage?> _load(String uri) async {
  if (uri.startsWith('data:')) {
    final comma = uri.indexOf(',');
    if (comma < 0 || !uri.substring(0, comma).endsWith(';base64')) {
      return null;
    }
    final data = uri.substring(comma + 1);
    if (data.length * 3 ~/ 4 > maxToolResultImageBytes) return null;
    return (mime: mimeFromDataUrl(uri), base64: data);
  }
  if (uri.startsWith('http://') || uri.startsWith('https://')) return null;
  final path = uri.startsWith('file://') ? Uri.parse(uri).toFilePath() : uri;
  final file = File(path);
  try {
    if (!await file.exists() || await file.length() > maxToolResultImageBytes) {
      return null;
    }
    return (
      mime: mimeFromPath(path),
      base64: base64Encode(await file.readAsBytes()),
    );
  } on FileSystemException {
    return null;
  }
}

/// Anthropic `tool_result` content: the text, followed by the images as
/// image blocks when there are any.
Object claudeToolResultWithImages(String text, List<ToolResultImage> images) {
  final content = text.trim().isEmpty ? '(no output)' : text;
  if (images.isEmpty) return content;
  return [
    {'type': 'text', 'text': content},
    for (final image in images)
      {
        'type': 'image',
        'source': {
          'type': 'base64',
          'media_type': image.mime,
          'data': image.base64,
        },
      },
  ];
}

/// The note that introduces tool images sent as a separate user message,
/// for APIs whose tool results hold only text.
String toolImagesNote(Iterable<String> toolNames) =>
    'Images returned by the tool call${toolNames.length == 1 ? '' : 's'} '
    '(${toolNames.join(', ')}) above:';

/// A Chat Completions user message carrying the images of [results]
/// (tool name, images), or null when there are none. Tool messages there
/// hold only text, so the images follow them.
Map<String, dynamic>? openaiToolImagesMessage(
  List<({String name, List<ToolResultImage> images})> results,
) {
  final withImages = [
    for (final result in results)
      if (result.images.isNotEmpty) result,
  ];
  if (withImages.isEmpty) return null;
  return {
    'role': 'user',
    'content': [
      {
        'type': 'text',
        'text': toolImagesNote([for (final r in withImages) r.name]),
      },
      for (final result in withImages)
        for (final image in result.images)
          {
            'type': 'image_url',
            'image_url': {'url': image.dataUrl},
          },
    ],
  };
}

/// The Responses API counterpart of [openaiToolImagesMessage].
Map<String, dynamic>? responsesToolImagesItem(
  List<({String name, List<ToolResultImage> images})> results,
) {
  final withImages = [
    for (final result in results)
      if (result.images.isNotEmpty) result,
  ];
  if (withImages.isEmpty) return null;
  return {
    'type': 'message',
    'role': 'user',
    'content': [
      {
        'type': 'input_text',
        'text': toolImagesNote([for (final r in withImages) r.name]),
      },
      for (final result in withImages)
        for (final image in result.images)
          {'type': 'input_image', 'image_url': image.dataUrl},
    ],
  };
}

/// Gemini parts for [images], placed after the function responses.
List<Map<String, dynamic>> geminiToolImageParts(List<ToolResultImage> images) =>
    [
      for (final image in images)
        {
          'inlineData': {'mimeType': image.mime, 'data': image.base64},
        },
    ];
