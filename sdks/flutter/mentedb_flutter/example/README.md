# MenteDB Memory Demo

Native Flutter example for comparing an OpenAI-compatible response with and
without context recalled from a local MenteDB database.

The app opens MenteDB through Flutter Rust Bridge, stores the editable memory
text as real `MemoryNode` records, optionally runs sleep maintenance, recalls a
bounded context for the user prompt, then sends two chat completion requests:

1. No memory context.
2. Retrieved MenteDB memory context.

The default connection is OpenRouter:

- Endpoint: `https://openrouter.ai/api/v1`
- Model: `~openai/gpt-latest`
- Headers: `HTTP-Referer` and `X-OpenRouter-Title` are sent when the endpoint
  host is OpenRouter.

Run on desktop:

```bash
flutter run -d macos
```

Run on a connected mobile device:

```bash
flutter run -d android
flutter run -d ios
```

Run the native bridge smoke test on macOS:

```bash
flutter test integration_test/native_memory_store_test.dart -d macos
```
