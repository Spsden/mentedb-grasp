# MenteDB Memory Demo

Native Flutter example for comparing an OpenAI-compatible response with and
without a memory bank injected into the request.

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
