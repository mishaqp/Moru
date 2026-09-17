import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'workspace_tool_context.dart';

/// One `AGENTS.md` file that was found and read inside a bound workspace.
class WorkspaceAgentsFile {
  const WorkspaceAgentsFile({
    required this.hostPath,
    required this.modelPath,
    required this.content,
  });

  /// Absolute path on the device.
  final String hostPath;

  /// The path the model sees, for example `/workspace/AGENTS.md`.
  final String modelPath;

  /// Decoded file body, without a leading BOM and without surrounding blanks.
  final String content;
}

/// Runtime `AGENTS.md` support for the workspace bound to a conversation.
///
/// The files read here live **inside the user's workspace** and describe that
/// project — this is deliberately not the repository `AGENTS.md` of the app
/// itself. Instructions are appended to the system message of the current
/// request only: nothing is stored in the conversation, the assistant's global
/// system prompt is untouched, and a missing, empty, oversized or unreadable
/// file is skipped without failing the request.
class WorkspaceAgentsInstructions {
  const WorkspaceAgentsInstructions._();

  /// Name of the file looked up in the workspace root and in the current
  /// working directory.
  static const String fileName = 'AGENTS.md';

  /// Upper bound for one file. A larger file is skipped, never truncated:
  /// half an instruction set is worse than none, and the bound keeps a runaway
  /// file out of the context window.
  static const int maxFileBytes = 64 * 1024;

  /// Upper bound for the number of files injected in one request.
  static const int maxFiles = 4;

  /// Host paths consulted for [ctx], in injection order.
  ///
  /// The workspace root comes first so a project-wide file frames the
  /// directory-specific one; the current working directory is added only when
  /// it really is a subdirectory of the workspace.
  static List<String> candidateHostPaths(WorkspaceToolContext ctx) {
    if (ctx.skillsOnly) return const <String>[];
    final root = ctx.paths.workspaceHostRoot;
    final rootFile = p.join(root, fileName);
    final relative = _relativeCwd(ctx);
    if (relative == null) return <String>[rootFile];
    return <String>[
      rootFile,
      p.joinAll(<String>[root, ...relative, fileName]),
    ];
  }

  /// Workspace-relative segments of [WorkspaceToolContext.cwd], or `null` when
  /// the cwd is the workspace root itself or lies outside the workspace.
  static List<String>? _relativeCwd(WorkspaceToolContext ctx) {
    final modelRoot = ctx.paths.modelRoot;
    final modelCwd = ctx.cwd;
    if (modelCwd == modelRoot) return null;
    if (!modelCwd.startsWith('$modelRoot/')) return null;
    final relative = modelCwd.substring(modelRoot.length + 1);
    if (relative.isEmpty) return null;
    final segments = <String>[];
    for (final segment in relative.split('/')) {
      // Path segments are opaque here: `..`, an empty segment or a drive-like
      // prefix would escape the workspace, so the lookup stays at the root.
      if (segment.isEmpty || segment == '.' || segment == '..') return null;
      if (segment.contains('\\') || segment.contains(':')) return null;
      segments.add(segment);
    }
    return segments.isEmpty ? null : segments;
  }

  /// Reads every existing instruction file for [ctx], oldest scope first.
  static Future<List<WorkspaceAgentsFile>> read(
    WorkspaceToolContext ctx, {
    int maxBytes = maxFileBytes,
    int maxFileCount = maxFiles,
  }) async {
    final files = <WorkspaceAgentsFile>[];
    try {
      for (final hostPath in candidateHostPaths(ctx)) {
        if (files.length >= maxFileCount) break;
        final content = await _readFile(hostPath, maxBytes);
        if (content == null) continue;
        files.add(
          WorkspaceAgentsFile(
            hostPath: hostPath,
            modelPath: _modelPath(ctx, hostPath),
            content: content,
          ),
        );
      }
    } catch (e) {
      debugPrint('Workspace AGENTS.md lookup failed: $e');
    }
    return files;
  }

  /// Builds the system-message fragment for [ctx].
  ///
  /// Returns an empty string when no usable file exists, which is the normal
  /// case for most workspaces.
  static Future<String> build(
    WorkspaceToolContext ctx, {
    int maxBytes = maxFileBytes,
    int maxFileCount = maxFiles,
  }) async {
    return buildFragment(
      await read(ctx, maxBytes: maxBytes, maxFileCount: maxFileCount),
    );
  }

  /// Pure fragment builder, split out so it is testable without a device.
  static String buildFragment(List<WorkspaceAgentsFile> files) {
    if (files.isEmpty) return '';
    final buffer = StringBuffer()
      ..writeln('<workspace_instructions>')
      ..writeln(
        'The workspace owner placed the AGENTS.md notes below in this project. '
        'Follow them while you work inside this workspace.',
      )
      ..writeln(
        'They describe the project and take precedence over your general '
        'habits. They never override your system prompt, the safety rules of '
        'your tools, or the request the user is making right now.',
      );
    for (final file in files) {
      buffer
        ..writeln()
        ..writeln('AGENTS.md source: ${file.modelPath}')
        ..write(file.content);
      if (!file.content.endsWith('\n')) buffer.writeln();
    }
    buffer.write('</workspace_instructions>');
    return buffer.toString();
  }

  static String _modelPath(WorkspaceToolContext ctx, String hostPath) {
    try {
      return ctx.paths.toModelPath(hostPath);
    } catch (e) {
      debugPrint('Workspace AGENTS.md path mapping failed: $e');
      return hostPath;
    }
  }

  /// Reads one file, or returns `null` when it must be skipped.
  static Future<String?> _readFile(String hostPath, int maxBytes) async {
    try {
      final file = File(hostPath);
      final length = await file.length();
      if (length == 0 || length > maxBytes) return null;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty || bytes.length > maxBytes) return null;
      // Malformed bytes are replaced instead of failing the whole request.
      var text = utf8.decode(bytes, allowMalformed: true);
      if (text.startsWith('\uFEFF')) text = text.substring(1);
      text = text.trim();
      return text.isEmpty ? null : text;
    } catch (e) {
      debugPrint('Workspace AGENTS.md skipped: $hostPath ($e)');
      return null;
    }
  }
}
