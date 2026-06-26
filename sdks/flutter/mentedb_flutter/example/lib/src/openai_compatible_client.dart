import 'dart:async';
import 'dart:convert';
import 'dart:io';

final class ChatMessage {
  const ChatMessage({required this.role, required this.content});

  final String role;
  final String content;

  Map<String, Object?> toJson() {
    return <String, Object?>{'role': role, 'content': content};
  }
}

final class ChatCompletionResult {
  const ChatCompletionResult({
    required this.content,
    required this.latency,
    this.model,
    this.finishReason,
    this.promptTokens,
    this.completionTokens,
    this.totalTokens,
  });

  final String content;
  final Duration latency;
  final String? model;
  final String? finishReason;
  final int? promptTokens;
  final int? completionTokens;
  final int? totalTokens;
}

final class OpenAiCompatibleChatClient {
  OpenAiCompatibleChatClient({
    HttpClient? httpClient,
    this.timeout = const Duration(seconds: 90),
  }) : _httpClient = httpClient ?? HttpClient();

  final HttpClient _httpClient;
  final Duration timeout;

  Future<ChatCompletionResult> complete({
    required Uri endpoint,
    required String? apiKey,
    required String model,
    required double temperature,
    required List<ChatMessage> messages,
  }) async {
    final startedAt = DateTime.now();
    final request = await _httpClient.postUrl(endpoint).timeout(timeout);
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
    if (apiKey != null && apiKey.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
    }

    final payload = jsonEncode(<String, Object?>{
      'model': model,
      'temperature': temperature,
      'messages': messages.map((message) => message.toJson()).toList(),
    });
    request.write(payload);

    final response = await request.close().timeout(timeout);
    final responseBody =
        await response.transform(utf8.decoder).join().timeout(timeout);
    final latency = DateTime.now().difference(startedAt);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ChatCompletionException(
        'HTTP ${response.statusCode}: ${_trimForError(responseBody)}',
      );
    }

    final decoded = jsonDecode(responseBody);
    if (decoded is! Map<String, Object?>) {
      throw const ChatCompletionException('Response was not a JSON object.');
    }

    return _parseChatCompletion(decoded, latency);
  }

  void close() {
    _httpClient.close(force: true);
  }
}

Uri resolveChatCompletionsUri(String endpoint) {
  final trimmed = endpoint.trim();
  if (trimmed.isEmpty) {
    throw const FormatException('Endpoint is empty.');
  }

  final uri = Uri.parse(trimmed);
  if (!uri.hasScheme || uri.host.isEmpty) {
    throw FormatException('Endpoint must include scheme and host: $endpoint');
  }

  final normalizedPath = uri.path.endsWith('/')
      ? uri.path.substring(0, uri.path.length - 1)
      : uri.path;
  if (normalizedPath.endsWith('/chat/completions')) {
    return uri;
  }

  final path = normalizedPath.isEmpty
      ? '/chat/completions'
      : '$normalizedPath/chat/completions';
  return uri.replace(path: path);
}

ChatCompletionResult _parseChatCompletion(
  Map<String, Object?> json,
  Duration latency,
) {
  final choices = json['choices'];
  if (choices is! List<Object?> || choices.isEmpty) {
    throw const ChatCompletionException('Response did not include choices.');
  }

  final firstChoice = choices.first;
  if (firstChoice is! Map<String, Object?>) {
    throw const ChatCompletionException('First choice was not a JSON object.');
  }

  final content = _readChoiceContent(firstChoice);
  final usage = json['usage'];
  final usageJson = usage is Map<String, Object?> ? usage : null;

  return ChatCompletionResult(
    content: content,
    latency: latency,
    model: json['model'] as String?,
    finishReason: firstChoice['finish_reason'] as String?,
    promptTokens: _readInt(usageJson, 'prompt_tokens'),
    completionTokens: _readInt(usageJson, 'completion_tokens'),
    totalTokens: _readInt(usageJson, 'total_tokens'),
  );
}

String _readChoiceContent(Map<String, Object?> choice) {
  final message = choice['message'];
  if (message is Map<String, Object?>) {
    final content = message['content'];
    if (content is String) {
      return content;
    }
    if (content is List<Object?>) {
      return content
          .map((part) {
            if (part is Map<String, Object?> && part['text'] is String) {
              return part['text'] as String;
            }
            return '';
          })
          .where((part) => part.isNotEmpty)
          .join('\n');
    }
  }

  final text = choice['text'];
  if (text is String) {
    return text;
  }

  throw const ChatCompletionException('Choice did not include text content.');
}

int? _readInt(Map<String, Object?>? json, String key) {
  final value = json?[key];
  return value is int ? value : null;
}

String _trimForError(String text) {
  const maxChars = 600;
  if (text.length <= maxChars) {
    return text;
  }
  return text.substring(0, maxChars);
}

final class ChatCompletionException implements Exception {
  const ChatCompletionException(this.message);

  final String message;

  @override
  String toString() => message;
}
