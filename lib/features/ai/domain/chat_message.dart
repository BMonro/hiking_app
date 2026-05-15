class ChatMessage {
  final String role;
  final String content;
  final DateTime sentAt;

  const ChatMessage({
    required this.role,
    required this.content,
    required this.sentAt,
  });

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';

  Map<String, String> toApiPayload() => {
        'role': role,
        'content': content,
      };
}
