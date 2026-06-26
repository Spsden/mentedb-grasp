import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mentedb_memory_demo/src/openai_compatible_client.dart';

void main() {
  test('resolveChatCompletionsUri appends chat completions path', () {
    final uri = resolveChatCompletionsUri(defaultOpenRouterEndpoint);

    expect(uri.toString(), 'https://openrouter.ai/api/v1/chat/completions');
  });

  test('buildOpenRouterAttributionHeaders adds OpenRouter metadata', () {
    final headers = buildOpenRouterAttributionHeaders(
      endpoint: resolveChatCompletionsUri(defaultOpenRouterEndpoint),
      referer: 'https://example.test',
      title: 'Example App',
    );

    expect(headers['HTTP-Referer'], 'https://example.test');
    expect(headers['X-OpenRouter-Title'], 'Example App');
  });

  test('buildOpenRouterAttributionHeaders skips non OpenRouter endpoints', () {
    final headers = buildOpenRouterAttributionHeaders(
      endpoint: resolveChatCompletionsUri('http://localhost:11434/v1'),
      referer: 'https://example.test',
      title: 'Example App',
    );

    expect(headers, isEmpty);
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
