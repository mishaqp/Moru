/// Durable display state for a tool whose generation was stopped before its
/// result arrived. It is separate from execution arguments and model output.
bool toolCallWasStopped(Map<String, dynamic>? metadata) {
  final computer = metadata?['computer'];
  return computer is Map && computer['status'] == 'stopped';
}

bool toolCallResponseWasStopped(Map<String, dynamic>? metadata) {
  final computer = metadata?['computer'];
  return computer is Map && computer['responseStopped'] == true;
}

String? toolCallBackgroundRuntimeId(Map<String, dynamic>? metadata) {
  final computer = metadata?['computer'];
  return computer is Map ? computer['runtimeRunId']?.toString() : null;
}

Map<String, dynamic> stoppedResponseToolMetadata(
  Map<String, dynamic>? metadata, {
  required bool stopped,
}) {
  final computer = metadata?['computer'];
  return {
    ...?metadata,
    'computer': {
      if (computer is Map) ...Map<String, dynamic>.from(computer),
      'responseStopped': true,
      if (stopped) 'status': 'stopped',
    },
  };
}
