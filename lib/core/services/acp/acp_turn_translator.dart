import 'dart:convert';

import '../api/stream/stream_chunk.dart';
import '../workspace/task_plan.dart';
import '../workspace/unified_diff.dart';
import '../workspace/workspace_tool_metadata.dart';

/// Turns one prompt's ACP `session/update` payloads into the chunks the chat
/// already understands, so an agent's answer is stored and drawn like any
/// model's: text, thoughts, tool cards (with diffs), images.
///
/// Tools run inside the agent, so they are reported as server tools: the
/// card appears when the agent announces the call and fills in when it
/// finishes. File reads, edits and commands use the workspace tool names,
/// which gives them the same cards as Moru's own workspace tools.
class AcpTurnTranslator {
  AcpTurnTranslator({this.onPlan});

  /// The agent's checklist, for the plan strip above the composer.
  final void Function(TaskPlan plan)? onPlan;

  int _seq = 0;
  String? _textId;
  String? _reasoningId;
  final Map<String, _AcpTool> _tools = {};

  /// What the agent said this turn, for a notification or a title.
  final StringBuffer text = StringBuffer();

  List<StreamChunk> translate(Map<String, Object?> update) {
    final kind = update['sessionUpdate'];
    switch (kind) {
      case 'agent_message_chunk':
        return _content(update['content'], reasoning: false);
      case 'agent_thought_chunk':
        return _content(update['content'], reasoning: true);
      case 'tool_call':
      case 'tool_call_update':
        return _tool(update);
      case 'plan':
        final plan = _plan(update['entries']);
        if (plan != null) onPlan?.call(plan);
        return const [];
      default:
        // user_message_chunk echoes, available commands, mode changes and
        // unknown extensions carry nothing the message shows.
        return const [];
    }
  }

  /// Closes what is still open; tools that never finished end as cancelled
  /// when the turn was stopped, failed otherwise.
  List<StreamChunk> finish(String? stopReason) {
    final chunks = <StreamChunk>[..._closeText(), ..._closeReasoning()];
    for (final tool in _tools.values) {
      if (tool.reported) continue;
      tool.status = stopReason == 'cancelled' ? 'cancelled' : 'failed';
      chunks.addAll(_end(tool));
    }
    chunks.add(Finish(finishReason: _finishReason(stopReason)));
    return chunks;
  }

  static String _finishReason(String? stopReason) => switch (stopReason) {
    'max_tokens' => 'length',
    'refusal' => 'content_filter',
    'cancelled' => 'cancelled',
    _ => 'stop',
  };

  List<StreamChunk> _content(Object? content, {required bool reasoning}) {
    if (content is! Map) return const [];
    final type = content['type'];
    if (type == 'image') {
      final data = (content['data'] ?? '').toString();
      if (data.isEmpty) return const [];
      final mime = (content['mimeType'] ?? 'image/png').toString();
      final id = 'acp-image-${_seq++}';
      return [
        ..._closeText(),
        ..._closeReasoning(),
        ImageStart(id: id, mimeType: mime),
        ImageSnapshot(
          id: id,
          data: completeRenderableImageUri(data, mimeType: mime),
        ),
        ImageEnd(id),
      ];
    }
    final value = _contentText(content);
    if (value.isEmpty) return const [];
    if (reasoning) {
      final chunks = <StreamChunk>[..._closeText()];
      final id = _reasoningId ??= 'acp-reasoning-${_seq++}';
      if (_started.add(id)) chunks.add(ReasoningStart(id: id));
      chunks.add(ReasoningDelta(id: id, text: value));
      return chunks;
    }
    text.write(value);
    final chunks = <StreamChunk>[..._closeReasoning()];
    final id = _textId ??= 'acp-text-${_seq++}';
    if (_started.add(id)) chunks.add(TextStart(id));
    chunks.add(TextDelta(id: id, text: value));
    return chunks;
  }

  final Set<String> _started = {};

  /// Text of a content block: plain text, or a link for a resource.
  static String _contentText(Map content) {
    switch (content['type']) {
      case 'text':
        return (content['text'] ?? '').toString();
      case 'resource_link':
        final uri = (content['uri'] ?? '').toString();
        if (uri.isEmpty) return '';
        final name = (content['title'] ?? content['name'] ?? uri).toString();
        return '[$name]($uri)';
      case 'resource':
        final resource = content['resource'];
        if (resource is Map && resource['text'] is String) {
          return resource['text'] as String;
        }
        return '';
      default:
        return '';
    }
  }

  List<StreamChunk> _closeText() {
    final id = _textId;
    if (id == null) return const [];
    _textId = null;
    return [TextEnd(id)];
  }

  List<StreamChunk> _closeReasoning() {
    final id = _reasoningId;
    if (id == null) return const [];
    _reasoningId = null;
    return [ReasoningEnd(id: id)];
  }

  List<StreamChunk> _tool(Map<String, Object?> update) {
    final id = (update['toolCallId'] ?? '').toString();
    if (id.isEmpty) return const [];
    final chunks = <StreamChunk>[];
    var tool = _tools[id];
    if (tool == null) {
      // A new card starts a new text block after it, keeping the order the
      // agent spoke in.
      chunks
        ..addAll(_closeText())
        ..addAll(_closeReasoning());
      tool = _tools[id] = _AcpTool('acp-tool-$id');
      tool.merge(update);
      tool.announcedName = tool.name;
      chunks.add(
        ServerToolStart(
          id: tool.chunkId,
          toolName: tool.name,
          input: tool.arguments,
        ),
      );
    } else {
      tool.merge(update);
    }
    if (!tool.reported && tool.isFinal) chunks.addAll(_end(tool));
    return chunks;
  }

  List<StreamChunk> _end(_AcpTool tool) {
    tool.reported = true;
    final name = tool.name;
    return [
      // Agents often name the file or command only after announcing the
      // call; the card then takes the kind it turned out to be.
      if (name != tool.announcedName)
        ServerToolStart(id: tool.chunkId, toolName: name),
      ServerToolEnd(
        id: tool.chunkId,
        input: tool.arguments,
        output: tool.output,
        status: tool.status == 'completed'
            ? ServerToolStatus.completed
            : ServerToolStatus.failed,
        metadata: tool.metadata,
      ),
    ];
  }

  static TaskPlan? _plan(Object? entries) {
    if (entries is! List) return null;
    final steps = <PlanStep>[];
    for (final entry in entries) {
      if (entry is! Map) continue;
      final text = (entry['content'] ?? '').toString().trim();
      if (text.isEmpty) continue;
      steps.add(
        PlanStep(text, switch (entry['status']) {
          'completed' => PlanStepStatus.completed,
          'in_progress' => PlanStepStatus.inProgress,
          _ => PlanStepStatus.pending,
        }),
      );
    }
    return steps.isEmpty ? null : TaskPlan(List.unmodifiable(steps));
  }
}

/// One tool call as the agent has described it so far.
class _AcpTool {
  _AcpTool(this.chunkId);

  final String chunkId;
  String title = '';
  String kind = 'other';
  String status = 'pending';
  Object? rawInput;
  Object? rawOutput;
  List<Map> content = const [];
  List<String> locations = const [];
  bool reported = false;
  String announcedName = '';

  bool get isFinal => status == 'completed' || status == 'failed';

  void merge(Map<String, Object?> update) {
    if (update['title'] is String) title = update['title'] as String;
    if (update['kind'] is String) kind = update['kind'] as String;
    if (update['status'] is String) status = update['status'] as String;
    if (update.containsKey('rawInput')) rawInput = update['rawInput'];
    if (update.containsKey('rawOutput')) rawOutput = update['rawOutput'];
    if (update['content'] is List) {
      content = [
        for (final item in update['content'] as List)
          if (item is Map) item,
      ];
    }
    if (update['locations'] is List) {
      locations = [
        for (final item in update['locations'] as List)
          if (item is Map && item['path'] is String) item['path'] as String,
      ];
    }
  }

  Map? get _diff {
    for (final item in content) {
      if (item['type'] == 'diff' && item['path'] is String) return item;
    }
    return null;
  }

  String? get path =>
      _diff?['path'] as String? ??
      (locations.isEmpty ? null : locations.first) ??
      _inputString(const ['path', 'file_path', 'filePath', 'abs_path']);

  String? get command =>
      _inputString(const ['command', 'cmd']) ??
      (rawInput is Map && (rawInput as Map)['command'] is List
          ? ((rawInput as Map)['command'] as List).join(' ')
          : null);

  String? _inputString(List<String> keys) {
    final input = rawInput;
    if (input is! Map) return null;
    for (final key in keys) {
      final value = input[key];
      if (value is String && value.isNotEmpty) return value;
    }
    return null;
  }

  /// A workspace tool name when the call is one, else the agent's title.
  String get name {
    switch (kind) {
      case 'execute':
        return 'shell';
      case 'read':
        return path == null ? _titleName : 'read_file';
      case 'edit':
      case 'delete':
      case 'move':
        if (path == null) return _titleName;
        final diff = _diff;
        return diff != null && (diff['oldText'] ?? '').toString().isEmpty
            ? 'write_file'
            : 'edit_file';
      case 'search':
        return 'grep';
      default:
        return _titleName;
    }
  }

  String get _titleName => title.trim().isEmpty ? 'agent_tool' : title.trim();

  Map<String, dynamic> get arguments => {
    if (title.isNotEmpty) 'title': title,
    if (path != null) 'path': path,
    if (kind == 'execute' && (command ?? title).isNotEmpty)
      'command': command ?? title,
    if (kind == 'search' && title.isNotEmpty) 'pattern': title,
    if (rawInput is Map) 'input': rawInput,
  };

  /// Text of what the tool gave back, for the card and the copy button.
  String get output {
    final parts = <String>[];
    for (final item in content) {
      if (item['type'] == 'content' && item['content'] is Map) {
        final text = AcpTurnTranslator._contentText(item['content'] as Map);
        if (text.isNotEmpty) parts.add(text);
      } else if (item['type'] == 'diff') {
        final diff = _unifiedDiff(item);
        if (diff != null) parts.add(diff.text);
      }
    }
    if (parts.isEmpty && rawOutput != null) {
      final raw = rawOutput;
      parts.add(raw is String ? raw : jsonEncode(raw));
    }
    if (parts.isEmpty) parts.add(status);
    return parts.join('\n');
  }

  static UnifiedDiff? _unifiedDiff(Map item) {
    final path = item['path'];
    if (path is! String) return null;
    return UnifiedDiff.compute(
      (item['oldText'] ?? '').toString(),
      (item['newText'] ?? '').toString(),
      path: path,
    );
  }

  /// Workspace card data for reads, edits and commands.
  Map<String, dynamic>? get metadata {
    final tool = name;
    final ok = status == 'completed';
    switch (tool) {
      case 'shell':
        return WorkspaceToolMetadata(
          tool: tool,
          status: ok ? 'ok' : 'error',
          command: command ?? title,
          cancelled: status == 'cancelled' ? true : null,
          stdoutPreview: output,
        ).toJson();
      case 'read_file':
        return WorkspaceToolMetadata(
          tool: tool,
          status: ok ? 'ok' : 'error',
          path: path,
          files: [WorkspaceToolFile(path: path!)],
        ).toJson();
      case 'write_file':
      case 'edit_file':
        final item = _diff;
        final diff = item == null ? null : _unifiedDiff(item);
        return WorkspaceToolMetadata(
          tool: tool,
          status: ok ? 'ok' : 'error',
          path: path,
          files: [
            WorkspaceToolFile(
              path: path!,
              // A failed edit changed nothing; keep it out of the summary.
              role: !ok
                  ? WorkspaceFileRole.referenced
                  : tool == 'write_file'
                  ? WorkspaceFileRole.created
                  : WorkspaceFileRole.modified,
            ),
          ],
          diff: diff?.text,
          added: diff?.added,
          removed: diff?.removed,
          diffTruncated: diff?.truncated,
          created: tool == 'write_file' ? true : null,
        ).toJson();
      default:
        return null;
    }
  }
}
