class DocumentAttachment {
  final String path; // absolute file path
  final String fileName;
  final String mime; // e.g. application/pdf, text/plain

  const DocumentAttachment({
    required this.path,
    required this.fileName,
    required this.mime,
  });
}

class ChatInputData {
  final String text;
  final List<String> imagePaths; // absolute file paths or data URLs
  final List<DocumentAttachment> documents; // selected files
  final bool allowImagesApiRouting;

  const ChatInputData({
    required this.text,
    this.imagePaths = const [],
    this.documents = const [],
    this.allowImagesApiRouting = true,
  });
}

enum ChatInputSubmissionResult { sent, queued, rejected }

/// One message the user submitted while the conversation was still generating.
///
/// Items live in a per-conversation FIFO and are sent one after another, each
/// only once the previous generation has finished. [id] is stable for the whole
/// lifetime of the item so the UI can edit or delete it before it is sent.
class QueuedChatInput {
  final String id;
  final String conversationId;
  final ChatInputData input;

  const QueuedChatInput({
    required this.id,
    required this.conversationId,
    required this.input,
  });

  QueuedChatInput withInput(ChatInputData input) =>
      QueuedChatInput(id: id, conversationId: conversationId, input: input);
}
