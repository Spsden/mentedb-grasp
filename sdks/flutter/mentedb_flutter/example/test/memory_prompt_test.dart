import 'package:flutter_test/flutter_test.dart';
import 'package:mentedb_memory_demo/src/memory_prompt.dart';

void main() {
  test('buildChatMessages omits memory when absent', () {
    final messages = buildChatMessages(
      systemPrompt: 'System',
      userPrompt: 'Question',
      memoryBank: null,
    );

    expect(messages, hasLength(2));
    expect(messages[0].role, 'system');
    expect(messages[1].role, 'user');
    expect(
      messages.any((message) => message.content.contains('memory bank')),
      isFalse,
    );
  });

  test('buildChatMessages inserts memory as separate system context', () {
    final messages = buildChatMessages(
      systemPrompt: 'System',
      userPrompt: 'Question',
      memoryBank: 'Alex avoids peanuts.',
    );

    expect(messages, hasLength(3));
    expect(messages[1].role, 'system');
    expect(messages[1].content, contains('Relevant memory bank'));
    expect(messages[1].content, contains('Alex avoids peanuts.'));
  });
}
