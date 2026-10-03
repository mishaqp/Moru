import 'dart:convert';

import 'package:flutter/widgets.dart' show IconData;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../../../core/services/acp/acp_secret_redactor.dart';
import '../../../core/services/api/tool_display_redaction.dart';
import '../../../core/services/logging/log_redactor.dart';
import '../../../core/services/workspace/output_buffer.dart' show utf16SafeCut;
import '../../../core/services/workspace/task_plan.dart';
import '../../../core/services/workspace/tool_run_registry.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../utils/authentication_uri.dart';
import '../../../utils/mcp_structured_image.dart';
import '../widgets/timeline_visibility.dart' show parseToolResultImages;

enum ComputerStepKind { browser, command, file, image, tool }

final _authenticationRedactor = AcpSecretRedactor(
  const [],
  protectAuthentication: true,
);

/// A safe display copy. The original execution input is never modified.
String sanitizeComputerDisplayText(String value) =>
    _safeText(value, ToolDisplayRedaction.current);

Object? sanitizeComputerDisplayValue(Object? value) =>
    _safeValue(value, ToolDisplayRedaction.current);

String _safeText(String value, ToolDisplayRedaction? filter) {
  final launchSafe = filter?.text(value) ?? value;
  return LogRedactor.redactText(
    LogRedactor.redactBody(_authenticationRedactor.text(launchSafe)),
  );
}

Object? _safeValue(Object? value, ToolDisplayRedaction? filter) {
  final authSafe = _authenticationRedactor.value(filter?.value(value) ?? value);
  Object? copy(Object? node) => switch (node) {
    String() => _safeText(node, null),
    Map() => Map<String, dynamic>.unmodifiable({
      for (final entry in node.entries)
        _safeText(entry.key.toString(), null): copy(entry.value),
    }),
    List() => List<Object?>.unmodifiable(node.map(copy)),
    _ => node,
  };
  // Reuse the existing field-name rules for passwords, API keys and headers.
  try {
    return copy(jsonDecode(LogRedactor.redactBody(jsonEncode(authSafe))));
  } on Object {
    return copy(authSafe);
  }
}

/// Only an unchanged public HTTP address is suitable for a browser action.
/// Authentication URLs follow the existing browser-library exclusion rules.
Uri? computerActionUri(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final raw = value.trim();
  final uri = Uri.tryParse(raw);
  if (uri == null ||
      (!uri.isScheme('http') && !uri.isScheme('https')) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      isAuthenticationUri(uri) ||
      sanitizeComputerDisplayText(raw) != raw ||
      _hasRedaction(raw)) {
    return null;
  }
  return uri;
}

bool _hasRedaction(String value) =>
    value.contains('[REDACTED]') || value.contains('***(len=');

/// A tool snapshot plus its live command run, shared by the strip and sheet.
/// All public text/parameters are filtered copies. [run] retains execution
/// state for cancellation and listeners; UI must read [result] for its output.
class ComputerStep {
  ComputerStep({
    required this.id,
    required String toolName,
    Map<String, dynamic> arguments = const {},
    String? content,
    Map<String, dynamic>? metadata,
    this.loading = false,
    this.run,
  }) : _displayFilter = _runDisplayFilter(ToolDisplayRedaction.current, run),
       _toolKey = _normalizedToolName(toolName) {
    this.toolName = _text(toolName);
    this.arguments =
        _safeValue(arguments, _displayFilter) as Map<String, dynamic>;
    this.content = content == null ? null : _text(content);
    this.metadata = metadata == null
        ? null
        : _safeValue(metadata, _displayFilter) as Map<String, dynamic>;
    final rawBrowser = metadata?['browser'];
    _browserPageKey = _safeBrowserPageKey(
      rawBrowser is Map ? rawBrowser['pageKey'] : null,
    );
    final rawWorkspace = metadata?['workspace'];
    final rawPath = _firstText([
      if (rawWorkspace is Map) rawWorkspace['path'],
      arguments['path'],
      arguments['file_path'],
      arguments['filePath'],
    ]);
    actionPath =
        rawPath != null && _text(rawPath) == rawPath && !_hasRedaction(rawPath)
        ? rawPath
        : null;
    final pageUrls = [
      arguments['url'],
      _decodeMap(_resultBody(content, metadata))['url'],
    ];
    allowsBrowserPreview = pageUrls.every(
      (value) =>
          value is! String || value.isEmpty || canPreviewBrowserPage(value),
    );
  }

  ComputerStep._withRun(ComputerStep step, this.run)
    : id = step.id,
      loading = step.loading,
      _toolKey = step._toolKey,
      _displayFilter = _runDisplayFilter(step._displayFilter, run) {
    toolName = _text(step.toolName);
    arguments =
        _safeValue(step.arguments, _displayFilter) as Map<String, dynamic>;
    content = step.content == null ? null : _text(step.content!);
    metadata = step.metadata == null
        ? null
        : _safeValue(step.metadata, _displayFilter) as Map<String, dynamic>;
    _browserPageKey = _safeBrowserPageKey(step._browserPageKey);
    final originalPath = step.actionPath;
    actionPath = originalPath != null && _text(originalPath) == originalPath
        ? originalPath
        : null;
    allowsBrowserPreview =
        step.allowsBrowserPreview &&
        [
          step.arguments['url'],
          _decodeMap(_resultBody(step.content, step.metadata))['url'],
        ].every(
          (value) =>
              value is! String ||
              (_text(value) == value && !_hasRedaction(value)),
        );
  }

  /// Attaches live state while retaining display filters and denied actions.
  /// It never reconstructs an open-file target from a redacted display path.
  ComputerStep withRun(ToolRun? run) => ComputerStep._withRun(this, run);

  final String id;
  late final String toolName;
  late final Map<String, dynamic> arguments;
  late final String? content;
  late final Map<String, dynamic>? metadata;
  final bool loading;
  final ToolRun? run;
  final ToolDisplayRedaction? _displayFilter;
  final String _toolKey;
  late final String? _browserPageKey;

  /// Original file reference only when it survived display filtering intact.
  /// Opening or reading it still requires the workspace file-access boundary.
  late final String? actionPath;

  /// An auth-page step must not fall back to an older public screenshot.
  late final bool allowsBrowserPreview;

  String _text(String value) => _safeText(value, _displayFilter);

  String? _safeBrowserPageKey(Object? value) =>
      value is String &&
          RegExp(r'^[0-9a-f]{64}$').hasMatch(value) &&
          _text(value) == value
      ? value
      : null;

  Map get _workspace => switch (metadata?['workspace']) {
    Map workspace => workspace,
    _ => const {},
  };

  late final String _resultText = _resultBody(content, metadata);
  late final Map _decodedResult = _decodeMap(_resultText);
  late final (String, List<String>) _images = parseToolResultImages(
    content,
    metadata: metadata,
  );

  ComputerStepKind get kind {
    if (_toolKey == 'browser' || _toolKey.startsWith('browser_')) {
      return ComputerStepKind.browser;
    }
    if (_commandTools.contains(_toolKey)) return ComputerStepKind.command;
    if (_fileTools.contains(_toolKey)) return ComputerStepKind.file;
    if (imagePath != null || _imageTools.contains(_toolKey)) {
      return ComputerStepKind.image;
    }
    return ComputerStepKind.tool;
  }

  bool get isRunning {
    if (isStopped) return false;
    if (run != null) return run!.status == ToolRunStatus.running;
    return loading ||
        _workspace['status'] == 'running' ||
        _decodedResult['status'] == 'running';
  }

  /// Cancellation belongs to the response even if a completed/background
  /// step itself retains its original outcome.
  bool get responseStopped =>
      metadata?['computer'] is Map &&
      (metadata!['computer'] as Map)['responseStopped'] == true;

  bool get isStopped =>
      run?.status == ToolRunStatus.cancelled ||
      (metadata?['computer'] is Map &&
          (metadata!['computer'] as Map)['status'] == 'stopped') ||
      _workspace['cancelled'] == true ||
      const {
        'stopped',
        'cancelled',
        'canceled',
      }.contains(_workspace['status'] ?? _decodedResult['status']);

  bool get isBackground =>
      run?.background == true ||
      arguments['background'] == true ||
      _decodedResult['background'] == true ||
      (_commandTools.contains(_toolKey) &&
          (arguments['job_id'] != null || _decodedResult['job_id'] != null));

  bool get isPlan => _toolKey == 'update_plan';

  TaskPlan? get plan => isPlan ? TaskPlan.fromArguments(arguments) : null;

  /// Validates a live page against this step's captured launch display filter.
  bool canPreviewBrowserPage(String? value) {
    if (value == null || value.isEmpty) return false;
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.isScheme('http') || uri.isScheme('https')) &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        !isAuthenticationUri(uri) &&
        _text(value) == value &&
        !_hasRedaction(value);
  }

  /// Cached sources must also survive this step's captured launch filter.
  bool canPreviewBrowserSource(String value) =>
      value.trim().isNotEmpty && _text(value) == value && !_hasRedaction(value);

  String? get browserPageUrl {
    if (kind != ComputerStepKind.browser || !allowsBrowserPreview) return null;
    for (final value in [_decodedResult['url'], arguments['url']]) {
      if (value is String && canPreviewBrowserPage(value)) return value;
    }
    return null;
  }

  Map get _browser => switch (metadata?['browser']) {
    Map browser => browser,
    _ => const {},
  };

  String? get browserPageKey {
    if (kind != ComputerStepKind.browser || !allowsBrowserPreview) return null;
    return _browserPageKey;
  }

  /// Historical steps without a captured time cannot borrow newer previews.
  DateTime? get browserStartedAt {
    if (kind != ComputerStepKind.browser) return null;
    final value = _browser['startedAt'];
    return (value is DateTime
            ? value
            : value is String
            ? DateTime.tryParse(value)
            : null) ??
        run?.startedAt;
  }

  String? get browserDomain {
    final value = browserPageUrl;
    return value == null ? null : Uri.parse(value).host;
  }

  /// Display-only page context from preceding steps of this response.
  /// This does not authorize borrowing their snapshots or navigation targets.
  String? browserDomainInResponse(List<ComputerStep> responseSteps) {
    if (kind != ComputerStepKind.browser || !allowsBrowserPreview) return null;
    final ownDomain = browserDomain;
    if (ownDomain != null) return ownDomain;
    final index = responseSteps.indexOf(this);
    if (index < 0) return null;
    for (var i = index - 1; i >= 0; i--) {
      final previous = responseSteps[i];
      if (previous.kind != ComputerStepKind.browser) continue;
      if (!previous.allowsBrowserPreview) return null;
      final url = previous.browserPageUrl;
      if (url == null) continue;
      if (!canPreviewBrowserPage(url)) return null;
      final domain = Uri.parse(url).host;
      return _text(domain) == domain ? domain : null;
    }
    return null;
  }

  bool get isError {
    if (isStopped) return false;
    if (run != null) {
      return run!.status == ToolRunStatus.failed ||
          run!.status == ToolRunStatus.timedOut;
    }
    final status = _workspace['status'] ?? _decodedResult['status'];
    final exitCode = _workspace['exitCode'] ?? _decodedResult['exit_code'];
    return const {
          'error',
          'failed',
          'timed_out',
          'timedOut',
        }.contains(status) ||
        (exitCode is num && exitCode != 0) ||
        _decodedResult['ok'] == false ||
        _decodedResult['isError'] == true ||
        metadata?['isError'] == true;
  }

  String? get command => _firstText([
    _workspace['command'],
    if (run?.command != null) _text(run!.command!),
    arguments['command'],
    arguments['cmd'],
    arguments['command_line'],
    _decodedResult['command'],
  ]);

  String? get path => _firstText([
    _workspace['path'],
    arguments['path'],
    arguments['file_path'],
    arguments['filePath'],
    _decodedResult['path'],
  ]);

  String get result {
    if (run case final ToolRun active) {
      // Detail/copy use both bounded stream buffers, not the 200-line live
      // thumbnail window. The run's captured launch filter remains applied.
      final stdout = active.stdoutSoFar;
      final stderr = active.stderrSoFar;
      if (stdout.isNotEmpty || stderr.isNotEmpty) {
        final separator =
            stdout.isNotEmpty && stderr.isNotEmpty && !stdout.endsWith('\n')
            ? '\n'
            : '';
        return _text('$stdout$separator$stderr');
      }
    }
    if (_commandTools.contains(_toolKey)) {
      final output = _firstText([
        _workspace['stdoutPreview'],
        _decodedResult['stdout'],
      ]);
      final error = _firstText([
        _workspace['stderrPreview'],
        _decodedResult['stderr'],
      ]);
      if (output != null || error != null) {
        return [
          if (output != null) output,
          if (error != null) error,
        ].join('\n');
      }
      if (_isResultMap) {
        return _firstText([
              _decodedResult['message'],
              _decodedResult['error'],
            ]) ??
            '';
      }
    }
    return _resultText;
  }

  String get parameters =>
      const JsonEncoder.withIndent('  ').convert(arguments);

  /// Short text used in thumbnails; file contents start at the first line,
  /// while command output follows the most recent progress.
  String get preview {
    final text = _fileTools.contains(_toolKey)
        ? _firstText([
                arguments['content'],
                _decodedResult['content'],
                _decodedResult['text'],
                _workspace['stdoutPreview'],
                if (!_isResultMap) result,
              ]) ??
              ''
        : run != null && run!.tailLines.isNotEmpty
        ? _text(run!.tailLines.join('\n'))
        : result;
    final lines = const LineSplitter().convert(text);
    if (_commandTools.contains(_toolKey)) {
      if (text.trim().isEmpty) {
        final value = command;
        return value == null ? '' : '\$ $value';
      }
      return utf16SafeCut(
        lines.skip((lines.length - 4).clamp(0, lines.length)).join('\n'),
        512,
        keepTail: true,
      );
    }
    return utf16SafeCut(lines.take(3).join('\n'), 1024);
  }

  bool get _isResultMap {
    try {
      return jsonDecode(_resultText) is Map;
    } on FormatException {
      return false;
    }
  }

  /// A filtered reference, never a grant to read an arbitrary host file.
  String? get imagePath {
    if (_toolKey.startsWith('browser_') && !allowsBrowserPreview) return null;
    final candidates = [
      ..._images.$2,
      if (_toolKey.startsWith('browser_')) _decodedResult['screenshot'],
      if (_fileTools.contains(_toolKey) && _isImagePath(path)) path,
    ];
    for (final candidate in candidates) {
      if (candidate is! String ||
          candidate.isEmpty ||
          candidate == 'attached' ||
          _hasRedaction(candidate)) {
        continue;
      }
      if (_text(candidate) != candidate) continue;
      final uri = Uri.tryParse(candidate);
      if (uri != null &&
          (uri.isScheme('http') || uri.isScheme('https')) &&
          computerActionUri(candidate) == null) {
        continue;
      }
      return candidate;
    }
    return null;
  }

  String title(AppLocalizations l10n) {
    if (kind == ComputerStepKind.browser) {
      final domain = browserDomain;
      return domain == null
          ? l10n.settingsPageBrowser
          : l10n.computerBrowserStep(domain);
    }
    if (plan case final TaskPlan checklist) {
      return l10n.computerPlanProgress(
        checklist.completed,
        checklist.steps.length,
      );
    }
    if (_toolKey == 'shell_output') return l10n.computerBackgroundOutput;
    if (kind == ComputerStepKind.command && command != null) {
      return command!.trim().split('\n').first;
    }
    if (kind == ComputerStepKind.file) {
      final filePath = path;
      if (filePath != null) {
        final label = l10n.computerFileStep(
          actionLabel(l10n),
          p.basename(filePath),
        );
        final content = arguments['content'];
        if ((_toolKey == 'write' || _toolKey == 'write_file') &&
            content is String &&
            content.isNotEmpty) {
          return '$label ${l10n.computerAddedLines(const LineSplitter().convert(content).length)}';
        }
        return label;
      }
    }
    if (kind == ComputerStepKind.image) {
      final filePath = path ?? imagePath;
      if (filePath != null) return p.basename(filePath);
    }
    return switch (_toolKey) {
      'shell' => l10n.workspaceToolTitleShell,
      'shell_output' => l10n.workspaceToolTitleShellOutput,
      'read_file' || 'read' => l10n.workspaceToolTitleReadFile,
      'write_file' || 'write' => l10n.workspaceToolTitleWriteFile,
      'edit_file' || 'edit' || 'apply_patch' => l10n.workspaceToolTitleEditFile,
      'list_dir' || 'ls' => l10n.workspaceToolTitleListDir,
      'glob' => l10n.workspaceToolTitleGlob,
      'grep' => l10n.workspaceToolTitleGrep,
      'update_plan' => l10n.workspaceToolTitleUpdatePlan,
      _ => kind == ComputerStepKind.command ? l10n.terminalTitle : toolName,
    };
  }

  String actionLabel(AppLocalizations l10n) {
    if (isPlan) return l10n.computerActionPlan;
    if (kind == ComputerStepKind.command) return l10n.computerActionCommand;
    if (kind == ComputerStepKind.browser) {
      return switch (arguments['action']) {
        'navigate' || 'open' || 'new_tab' => l10n.computerActionOpen,
        'click' || 'tap' => l10n.computerActionClick,
        'type' || 'fill' => l10n.computerActionType,
        'screenshot' => l10n.computerActionScreenshot,
        'read' => l10n.computerActionRead,
        'done' => l10n.computerActionSummary,
        _ => l10n.computerBrowserAction((arguments['action'] ?? '').toString()),
      };
    }
    return switch (_toolKey) {
      'read_file' || 'read' => l10n.computerActionRead,
      'write_file' || 'write' => l10n.computerActionWrite,
      'edit_file' ||
      'edit' ||
      'multiedit' ||
      'apply_patch' => l10n.computerActionEdit,
      'list_dir' || 'ls' || 'glob' || 'grep' => l10n.computerActionList,
      _ => toolName,
    };
  }

  String subtitle(AppLocalizations l10n) {
    if (isStopped) return l10n.computerStopped;
    if (isError && kind != ComputerStepKind.command) return l10n.computerError;
    if (_toolKey == 'shell_output' && command != null) return command!;
    if (isPlan) return plan?.current?.text ?? l10n.computerDone;
    if (kind == ComputerStepKind.browser) {
      if (!isRunning && arguments['action'] == 'done') return l10n.computerDone;
      if (!isRunning) return actionLabel(l10n);
      return switch (arguments['action']) {
        'navigate' || 'open' || 'new_tab' => l10n.computerBrowserOpening,
        'click' || 'tap' => l10n.computerBrowserClicking,
        'type' || 'fill' => l10n.computerBrowserTyping,
        'screenshot' => l10n.computerActionScreenshot,
        'read' || 'observe' || 'outline' => l10n.computerBrowserReading,
        _ => actionLabel(l10n),
      };
    }
    if (kind == ComputerStepKind.command) {
      if (isRunning && isBackground) return l10n.computerBackground;
      final elapsed = _elapsed;
      if (isRunning) {
        final seconds = elapsed.inSeconds;
        return l10n.computerRunningElapsed(
          '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}',
        );
      }
      final code =
          run?.exitCode ??
          _workspace['exitCode'] ??
          _decodedResult['exit_code'];
      if (code is num) {
        return l10n.computerExitElapsed(
          code.toInt(),
          NumberFormat(
            '0.0',
            l10n.localeName,
          ).format(elapsed.inMilliseconds / 1000),
        );
      }
    }
    return isRunning
        ? l10n.computerWorking
        : isError
        ? l10n.computerError
        : l10n.computerDone;
  }

  Duration get _elapsed {
    final milliseconds = _workspace['durationMs'];
    if (milliseconds is num) {
      return Duration(milliseconds: milliseconds.toInt());
    }
    final seconds = _decodedResult['elapsed_seconds'];
    if (seconds is num) return Duration(milliseconds: (seconds * 1000).round());
    final active = run;
    if (active == null) return Duration.zero;
    return (active.finishedAt ?? DateTime.now()).difference(active.startedAt);
  }

  IconData get icon => isPlan
      ? Lucide.ListChecks
      : switch (kind) {
          ComputerStepKind.browser => Lucide.Globe,
          ComputerStepKind.command => Lucide.Terminal,
          ComputerStepKind.file => Lucide.FileText,
          ComputerStepKind.image => Lucide.Image,
          ComputerStepKind.tool => Lucide.Wrench,
        };
}

ToolDisplayRedaction? _runDisplayFilter(
  ToolDisplayRedaction? snapshotFilter,
  ToolRun? run,
) {
  if (run == null) return snapshotFilter;
  return ToolDisplayRedaction(
    text: (text) {
      final runSafe = run.displayText(text);
      return snapshotFilter?.text(runSafe) ?? runSafe;
    },
    value: (value) {
      final runSafe = run.displayValue(value);
      return snapshotFilter?.value(runSafe) ?? runSafe;
    },
  );
}

const _commandTools = {
  'shell',
  'shell_output',
  'root_shell',
  'bash',
  'exec_command',
  'write_stdin',
  'bash_code_execution',
  'code_execution',
  'code_interpreter',
};
const _fileTools = {
  'read_file',
  'write_file',
  'edit_file',
  'list_dir',
  'glob',
  'grep',
  'read',
  'write',
  'edit',
  'multiedit',
  'ls',
  'apply_patch',
};
const _imageTools = {
  'generate_image',
  'image_generation',
  'imagegen',
  'image_gen',
};
const _imageExtensions = {
  '.png',
  '.jpg',
  '.jpeg',
  '.webp',
  '.gif',
  '.bmp',
  '.svg',
};

String _normalizedToolName(String name) =>
    name.toLowerCase().split('__').last.split('.').last.split('/').last;

String? _firstText(Iterable<Object?> values) {
  for (final value in values) {
    if (value is String && value.trim().isNotEmpty) return value;
  }
  return null;
}

bool _isImagePath(String? path) =>
    path != null &&
    _imageExtensions.contains(p.extension(path.split('?').first).toLowerCase());

String _resultBody(String? content, Map<String, dynamic>? metadata) {
  // Decode old saved bodies before typed metadata, which otherwise takes
  // precedence and leaves a legacy envelope nested around the URL/result.
  final legacy = content == null
      ? null
      : tryDecodeLegacyMcpToolResultEnvelope(content);
  return legacy == null
      ? parseToolResultImages(content, metadata: metadata).$1
      : parseToolResultImages(legacy.legacyBody ?? legacy.markdown).$1;
}

Map _decodeMap(String? value) {
  if (value == null || value.isEmpty) return const {};
  try {
    final decoded = jsonDecode(value);
    return decoded is Map ? decoded : const {};
  } on FormatException {
    return const {};
  }
}
