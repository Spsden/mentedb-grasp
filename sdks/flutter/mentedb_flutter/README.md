# MenteDB Flutter

This package embeds MenteDB in native Flutter apps through Flutter Rust Bridge.
It does not target Flutter web.

The native bridge lives in `rust/` and is bundled with Cargokit for Android,
iOS, macOS, Linux, and Windows. The public Dart entrypoint is
`RustMenteDbMemoryStore`, which opens a local MenteDB directory and exposes:

1. Text memory bank ingest as real `MemoryNode` records.
2. Hybrid recall for prompt context.
3. Leased sleep maintenance for background jobs.
4. Explicit close and flush behavior through the Rust facade.

The bridge uses MenteDB's deterministic hash embedder for local demo recall so
the example can run without an embedding API key. Production apps should swap
that Rust provider for the app's selected local or remote embedding provider.

Regenerate bindings after changing Rust bridge types:

```bash
flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml
```

The runnable example under `example/` compares an OpenAI-compatible chat
completion with no memory against one that receives context recalled from the
native MenteDB database.
