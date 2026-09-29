import '../api/chat_api_helpers.dart'
    show tryEncodeBase64File, mimeFromDataUrl, mimeFromPath;

/// The newest user message as ACP text blocks, and the chat before it as
/// plain text, taken from the chat's request messages.
///
/// System prompts are left out: an agent has its own instructions, and the
/// workspace notes Moru adds for its models describe tools the agent does
/// not have.
({List<Map<String, Object?>> prompt, String history}) acpPromptFromMessages(
  List<Map<String, dynamic>> apiMessages, {
  int historyLimit = 16000,
}) {
  var last = -1;
  for (var i = apiMessages.length - 1; i >= 0; i--) {
    if (apiMessages[i]['role'] == 'user') {
      last = i;
      break;
    }
  }
  final text = last < 0 ? '' : _text(apiMessages[last]['content']);
  final lines = <String>[];
  for (var i = 0; i < (last < 0 ? 0 : last); i++) {
    final role = apiMessages[i]['role'];
    if (role != 'user' && role != 'assistant') continue;
    final body = _text(apiMessages[i]['content']).trim();
    if (body.isEmpty) continue;
    lines.add('${role == 'user' ? 'User' : 'Assistant'}: $body');
  }
  var history = lines.join('\n\n');
  if (history.length > historyLimit) {
    // The latest part matters most.
    history = '…${history.substring(history.length - historyLimit)}';
  }
  return (
    prompt: [
      if (text.trim().isNotEmpty) {'type': 'text', 'text': text},
    ],
    history: history,
  );
}

String _text(Object? content) {
  if (content is String) return content;
  if (content is List) {
    return [
      for (final part in content)
        if (part is Map && part['type'] == 'text' && part['text'] is String)
          part['text'] as String,
    ].join('\n');
  }
  return '';
}

/// Attach only this turn's images, after initialize has advertised support.
/// Reuse Moru's local-path resolver; never fetch a remote URL here.
Future<List<Map<String, Object?>>> acpImagePromptBlocks(
  List<String> paths, {
  required bool supported,
  required String notSentMessage,
}) async {
  final images = paths
      .where((path) => mimeFromPath(path).startsWith('image/'))
      .toList();
  if (images.isEmpty) return const [];
  final blocks = <Map<String, Object?>>[];
  var missing = !supported;
  if (supported) {
    for (final path in images) {
      final encoded = await tryEncodeBase64File(path, withPrefix: true);
      if (encoded == null) {
        missing = true;
        continue;
      }
      blocks.add({
        'type': 'image',
        'mimeType': mimeFromDataUrl(encoded),
        'data': encoded.substring(encoded.indexOf(',') + 1),
      });
    }
  }
  if (missing) blocks.add({'type': 'text', 'text': notSentMessage});
  return blocks;
}
