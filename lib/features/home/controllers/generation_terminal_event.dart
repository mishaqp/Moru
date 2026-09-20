import '../../../core/database/generation_run.dart';
import '../../../core/models/chat_message.dart';

/// Fired exactly once per generation run, at the same point
/// `ChatActions._finalizeStreamingCheckpoint` durably persists that run's
/// terminal state (`completed`/`failed`/`cancelled`/`interrupted`).
///
/// [message] is the real, finalized [ChatMessage] at that terminal point --
/// never the empty placeholder a caller like `ChatActions.sendMessage`
/// returns the moment generation *starts* -- so a listener never needs a
/// second read to learn the final content. Never emitted when the terminal
/// write itself fails (a listener would otherwise wait forever, since a
/// failed write is retried through a later error path that reaches this
/// same choke point once it actually commits).
class GenerationTerminalEvent {
  const GenerationTerminalEvent({
    required this.conversationId,
    required this.assistantMessageId,
    required this.generationRunId,
    required this.terminalState,
    required this.message,
    this.errorCode,
  });

  final String conversationId;
  final String assistantMessageId;

  /// Null when the run never reached the `preparing` -> `requesting`
  /// transition that assigns a run id (mirrors
  /// `ChatActions._createStreamingCheckpoint`'s own null case).
  final String? generationRunId;
  final GenerationRunState terminalState;
  final ChatMessage message;

  /// Set when [terminalState] is `failed` or `interrupted`.
  final String? errorCode;

  bool get succeeded => terminalState == GenerationRunState.completed;

  bool get cancelled =>
      terminalState == GenerationRunState.cancelled ||
      terminalState == GenerationRunState.interrupted;
}
