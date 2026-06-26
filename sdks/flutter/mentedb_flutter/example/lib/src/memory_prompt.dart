import 'openai_compatible_client.dart';

const defaultSystemPrompt =
    'You are a concise assistant. Answer directly and mention uncertainty when needed.';

const sampleUserPrompt =
    'What should I remember when planning dinner for Alex next week?';

const sampleMemoryBank = '''
Alex avoids peanuts and cashews.
Alex prefers vegetarian meals on weekdays.
Alex likes Thai basil, mushrooms, and sparkling water.
The last dinner plan failed because it included a peanut sauce.
''';

List<ChatMessage> buildChatMessages({
  required String systemPrompt,
  required String userPrompt,
  required String? memoryBank,
}) {
  final messages = <ChatMessage>[];
  final trimmedSystem = systemPrompt.trim();
  if (trimmedSystem.isNotEmpty) {
    messages.add(ChatMessage(role: 'system', content: trimmedSystem));
  }

  final trimmedMemory = memoryBank?.trim();
  if (trimmedMemory != null && trimmedMemory.isNotEmpty) {
    messages.add(
      ChatMessage(
        role: 'system',
        content:
            'Relevant memory bank:\n$trimmedMemory\n\nUse the memory bank when it is relevant. Do not claim it exists when it is not relevant.',
      ),
    );
  }

  messages.add(ChatMessage(role: 'user', content: userPrompt.trim()));
  return messages;
}
