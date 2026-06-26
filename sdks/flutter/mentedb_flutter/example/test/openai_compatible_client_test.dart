import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mentedb_memory_demo/src/openai_compatible_client.dart';

void main() {
  test('resolveChatCompletionsUri appends chat completions path', () {
    final uri = resolveChatCompletionsUri('http://localhost:11434/v1');

    expect(uri.toString(), 'http://localhost:11434/v1/chat/completions');
  });

  test('resolveChatCompletionsUri keeps full chat completions path', () {
    final uri = resolveChatCompletionsUri(
      'https://api.example.test/v1/chat/completions',
    );

    expect(uri.toString(), 'https://api.example.test/v1/chat/completions');
  });

  test('chat message encodes OpenAI-compatible shape', () {
    const message = ChatMessage(role: 'user', content: 'Hello');
    final encoded = jsonEncode(message.toJson());

    expect(encoded, '{"role":"user","content":"Hello"}');
  });
}
