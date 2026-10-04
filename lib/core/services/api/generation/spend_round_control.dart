import '../../../models/token_usage.dart';
import '../stream/stream_chunk.dart';

/// Separate paid usage across requests from the latest context-window snapshot.
class SpendRoundControl {
  SpendRoundControl({
    required Future<String?> Function(TokenUsage, int) beforeRequest,
    this.initialWarning,
    this.onRoundCompleted,
    // Callback and async method deliberately share the public name.
    // ignore: prefer_initializing_formals
  }) : _beforeRequest = beforeRequest;

  final Future<String?> Function(TokenUsage, int) _beforeRequest;
  final String? initialWarning;
  final void Function()? onRoundCompleted;
  String? _warning;
  TokenUsage completedUsage = const TokenUsage();
  TokenUsage lastUsage = const TokenUsage();
  TokenUsage? pendingUsage;
  int completedRounds = 0;

  Future<void> beforeRequest() async {
    _warning = await _beforeRequest(completedUsage, completedRounds);
  }

  void recordInitialUsage(TokenUsage? usage) {
    if (usage == null) return;
    pendingUsage = null;
    lastUsage = const TokenUsage().merge(usage);
    completedUsage = TokenUsage(
      promptTokens: completedUsage.promptTokens + lastUsage.promptTokens,
      completionTokens:
          completedUsage.completionTokens + lastUsage.completionTokens,
      cachedTokens: completedUsage.cachedTokens + lastUsage.cachedTokens,
      totalTokens: completedUsage.totalTokens + lastUsage.totalTokens,
    );
    completedRounds++;
    onRoundCompleted?.call();
  }

  Stream<StreamChunk> trackRound(Stream<StreamChunk> round) async* {
    TokenUsage? usage;
    pendingUsage = null;
    await for (final chunk in round) {
      if (chunk is RetryAttemptStart) {
        usage = null;
        pendingUsage = null;
      }
      if (chunk is Usage) {
        usage = (usage ?? const TokenUsage()).merge(chunk.usage);
        pendingUsage = usage;
      }
      yield chunk;
    }
    recordInitialUsage(usage);
  }

  /// Copy only the system part at the transport boundary, never the transcript.
  Map<String, dynamic> decorateRequest(
    Map<String, dynamic> body, {
    String? systemField,
  }) {
    if (initialWarning == null && _warning == null) return body;
    final copy = Map<String, dynamic>.from(body);
    String removeInitial(String text) => initialWarning == null
        ? text
        : text
              .split('\n\n')
              .where((part) => part != initialWarning)
              .join('\n\n');
    String replace(String original) {
      final text = removeInitial(original);
      return _warning == null
          ? text
          : text.isEmpty
          ? _warning!
          : '$text\n\n$_warning';
    }

    Object replaceBlocks(Object? value) {
      if (value is String) return replace(value);
      final blocks = value is List
          ? [
              for (final block in value)
                if (block is Map) Map<String, dynamic>.from(block),
            ]
          : <Map<String, dynamic>>[];
      if (blocks.isEmpty) blocks.add({'type': 'text', 'text': ''});
      final index = blocks.indexWhere(
        (b) => b['type'] == 'text' || b.containsKey('text'),
      );
      if (index < 0) {
        if (_warning != null) blocks.add({'type': 'text', 'text': _warning});
      } else {
        // The prepared warning is appended to the final text block by some providers.
        for (final block in blocks) {
          final text = block['text'];
          if (text is String) block['text'] = removeInitial(text);
        }
        final text = blocks[index]['text'] as String? ?? '';
        if (_warning != null) {
          blocks[index]['text'] = text.isEmpty
              ? _warning
              : '$text\n\n$_warning';
        }
      }
      return blocks;
    }

    if (body.containsKey('instructions')) {
      copy['instructions'] = replaceBlocks(body['instructions']);
    } else if (systemField == 'system' || body.containsKey('system')) {
      copy['system'] = replaceBlocks(body['system'] ?? '');
    } else if (body.containsKey('systemInstruction')) {
      final system = Map<String, dynamic>.from(
        body['systemInstruction'] as Map,
      );
      system['parts'] = replaceBlocks(system['parts']);
      copy['systemInstruction'] = system;
    } else if (body['messages'] is List) {
      final messages = [
        for (final message in body['messages'] as List)
          Map<String, dynamic>.from(message as Map),
      ];
      final index = messages.indexWhere(
        (m) => m['role'] == 'system' || m['role'] == 'developer',
      );
      if (index < 0) {
        if (_warning != null) {
          messages.insert(0, {'role': 'system', 'content': _warning});
        }
      } else {
        messages[index]['content'] = replaceBlocks(messages[index]['content']);
      }
      copy['messages'] = messages;
    } else if (_warning != null) {
      // Responses and Gemini may omit their system field when it is empty.
      if (body.containsKey('input')) {
        copy['instructions'] = _warning;
      } else if (body.containsKey('contents')) {
        copy['systemInstruction'] = {
          'parts': [
            {'text': _warning},
          ],
        };
      }
    }
    return copy;
  }
}

class SpendLimitExceeded implements Exception {
  const SpendLimitExceeded(this.message);
  final String message;
  @override
  String toString() => message;
}
