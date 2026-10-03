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
  final bool isEditing;

  const QueuedChatInput({
    required this.id,
    required this.conversationId,
    required this.input,
    this.isEditing = false,
  });

  QueuedChatInput withInput(ChatInputData input) =>
      QueuedChatInput(id: id, conversationId: conversationId, input: input);

  QueuedChatInput withEditing(bool editing) => QueuedChatInput(
    id: id,
    conversationId: conversationId,
    input: input,
    isEditing: editing,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'conversationId': conversationId,
    'editing': isEditing,
    'text': input.text,
    'imagePaths': input.imagePaths,
    'documents': [
      for (final document in input.documents)
        {
          'path': document.path,
          'fileName': document.fileName,
          'mime': document.mime,
        },
    ],
    'allowImagesApiRouting': input.allowImagesApiRouting,
  };

  factory QueuedChatInput.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    final conversationId = json['conversationId'] as String;
    if (id.isEmpty || conversationId.isEmpty) {
      throw const FormatException('invalid_queued_input_identity');
    }
    return QueuedChatInput(
      id: id,
      conversationId: conversationId,
      isEditing: json['editing'] as bool? ?? false,
      input: ChatInputData(
        text: json['text'] as String,
        imagePaths: (json['imagePaths'] as List).cast<String>(),
        documents: [
          for (final value in json['documents'] as List)
            DocumentAttachment(
              path: (value as Map)['path'] as String,
              fileName: value['fileName'] as String,
              mime: value['mime'] as String,
            ),
        ],
        allowImagesApiRouting: json['allowImagesApiRouting'] as bool? ?? true,
      ),
    );
  }
}
