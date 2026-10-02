import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/chat_message.dart';
import '../../../core/models/message_part.dart';
import '../../../core/models/tool_call_status.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/workspace/tool_run_registry.dart';
import '../models/computer_step.dart';
import 'computer_sheet.dart';

/// A view over the existing message/tool state. Streaming tool events refresh
/// only Computer surfaces; token updates do not rebuild the composer or page.
class ComputerToolSource extends InheritedWidget {
  const ComputerToolSource({
    super.key,
    required this.readMessages,
    required this.readSteps,
    required this.updates,
    required super.child,
  });

  final List<ChatMessage> Function() readMessages;
  final List<ComputerStep> Function(String responseId) readSteps;
  final Listenable updates;

  static ComputerToolSource? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ComputerToolSource>();

  @override
  bool updateShouldNotify(ComputerToolSource oldWidget) => true;
}

String? latestComputerResponseId(List<ChatMessage> messages) {
  for (final message in messages.reversed) {
    if (message.role == 'user') return null;
    if (message.role == 'assistant') return message.id;
  }
  return null;
}

/// Missing legacy call IDs need the same identity in the source and its card.
String computerToolStepId(Object? id, String toolName, int ordinal) {
  final value = id?.toString().trim() ?? '';
  return value.isNotEmpty
      ? value
      : '${toolName.isEmpty ? 'tool' : toolName}-$ordinal';
}

List<ComputerStep> computerStepsFromEvents(
  List<Map<String, dynamic>> events, {
  bool streaming = false,
}) => [
  for (var i = 0; i < events.length; i++)
    ComputerStep(
      id: computerToolStepId(
        events[i]['id'],
        (events[i]['name'] ?? '').toString(),
        i,
      ),
      toolName: (events[i]['name'] ?? '').toString(),
      arguments: events[i]['arguments'] is Map
          ? Map<String, dynamic>.from(events[i]['arguments'] as Map)
          : const {},
      content: events[i]['content']?.toString(),
      metadata: events[i]['metadata'] is Map
          ? Map<String, dynamic>.from(events[i]['metadata'] as Map)
          : null,
      loading:
          streaming &&
          events[i]['content'] == null &&
          !toolCallWasStopped(
            events[i]['metadata'] is Map
                ? Map<String, dynamic>.from(events[i]['metadata'] as Map)
                : null,
          ) &&
          !toolCallResponseWasStopped(
            events[i]['metadata'] is Map
                ? Map<String, dynamic>.from(events[i]['metadata'] as Map)
                : null,
          ),
    ),
];

List<ComputerStep> computerStepsFromMessage(ChatMessage message) {
  final events = <Map<String, dynamic>>[];
  for (final part in message.parts.whereType<ToolCallPart>()) {
    try {
      final event = jsonDecode(part.payloadJson);
      if (event is Map) events.add(Map<String, dynamic>.from(event));
    } on FormatException {
      // Invalid legacy payloads cannot prevent other steps opening.
    }
  }
  return computerStepsFromEvents(events, streaming: message.isStreaming);
}

ToolRunRegistry? _registry(BuildContext context) {
  try {
    return context.read<ToolRunRegistry>();
  } on ProviderNotFoundException {
    return null;
  }
}

List<ComputerStep> withComputerRuns(
  List<ComputerStep> steps,
  ToolRunRegistry? registry,
  String? conversationId, {
  String? responseId,
}) => [
  for (final step in steps)
    _withRun(step, registry, conversationId, responseId),
];

ComputerStep _withRun(
  ComputerStep step,
  ToolRunRegistry? registry,
  String? conversationId,
  String? responseId,
) {
  String? jobId = step.arguments['job_id']?.toString();
  if (jobId == null && step.content != null) {
    try {
      final result = jsonDecode(step.content!);
      if (result is Map) jobId = result['job_id']?.toString();
    } on FormatException {
      // Plain text is also a valid tool result.
    }
  }
  jobId ??= toolCallBackgroundRuntimeId(step.metadata);
  var run = jobId == null
      ? step.run ?? registry?.of(step.id, conversationId: conversationId)
      : registry?.byRuntimeRunId(jobId, conversationId: conversationId) ??
            (step.run?.runtimeRunId == jobId ? step.run : null);
  if (jobId == null &&
      responseId != null &&
      run?.responseId != null &&
      run!.responseId != responseId) {
    run = null;
  }
  if (identical(run, step.run)) return step;
  return step.withRun(run);
}

/// Identifies the response of a tapped card, including persisted/older cards.
class ComputerResponseScope extends InheritedWidget {
  const ComputerResponseScope({
    super.key,
    required this.responseId,
    required this.conversationId,
    required this.steps,
    required super.child,
  });

  final String responseId;
  final String? conversationId;
  final List<ComputerStep> steps;

  @override
  bool updateShouldNotify(ComputerResponseScope oldWidget) =>
      responseId != oldWidget.responseId ||
      conversationId != oldWidget.conversationId ||
      !identical(steps, oldWidget.steps);

  static Future<void> showForStep(
    BuildContext context,
    ComputerStep selected, {
    String? conversationId,
  }) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<ComputerResponseScope>();
    final source = ComputerToolSource.maybeOf(context);
    final id = scope?.conversationId ?? conversationId;
    final registry = _registry(context);
    final fallback = scope?.steps ?? [selected];
    // Capture dependencies at launch. A dismissed card's BuildContext need not
    // remain mounted for a live sheet to receive later tool results.
    ChatService? chat;
    try {
      chat = context.read<ChatService>();
    } on ProviderNotFoundException {
      chat = null;
    }
    var retainedSteps = <ComputerStep>[];
    List<ComputerStep> read() {
      var steps = scope == null
          ? fallback
          : source?.readSteps(scope.responseId) ?? const <ComputerStep>[];
      if (steps.isEmpty && scope != null) {
        steps = computerStepsFromEvents(
          chat?.getToolEvents(scope.responseId) ?? const [],
        );
      }
      if (steps.isEmpty) steps = fallback;
      if (!steps.any((step) => step.id == selected.id)) {
        steps = [...steps, selected];
      }
      steps = [
        for (final step in steps)
          step.run == null
              ? step.withRun(
                  retainedSteps
                      .where((prior) => prior.id == step.id)
                      .firstOrNull
                      ?.run,
                )
              : step,
      ];
      retainedSteps = withComputerRuns(
        steps,
        registry,
        id,
        responseId: scope?.responseId,
      );
      return retainedSteps;
    }

    bool readResponseRunning() {
      final responseId = scope?.responseId;
      if (responseId == null) {
        return read().any((step) => step.isRunning && !step.isBackground);
      }
      final messages =
          source?.readMessages() ??
          chat?.getMessages(id ?? '') ??
          const <ChatMessage>[];
      final response = messages
          .where(
            (message) =>
                message.id == responseId && message.conversationId == id,
          )
          .firstOrNull;
      return response?.isStreaming ?? false;
    }

    return showComputerSheet(
      context,
      steps: read(),
      conversationId: id,
      initialStepId: selected.id,
      updates: Listenable.merge([
        if (source != null) source.updates,
        if (registry != null) registry,
        if (chat != null) chat,
      ]),
      readSteps: read,
      readResponseRunning: readResponseRunning,
    );
  }
}
